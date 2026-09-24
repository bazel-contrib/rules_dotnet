"""What goes into a package, and where: pure functions over providers and strings."""

load(
    "//dotnet/private:common.bzl",
    "get_nearest_compatible_target_framework",
    "is_core_framework",
    "is_greater_or_equal_framework",
    "tfm_to_nuget_framework",
)
load("//dotnet/private:nuget_version.bzl", "nuget_version")
load("//dotnet/private/rules/common:publish_layout.bzl", "publish_layout")
load(
    "//dotnet/private/rules/common:static_web_assets.bzl",
    "PACKAGE_CONTENT_ROOT",
    "base_path",
)
load("//dotnet/private/sdk:packs.bzl", "WEB_SDK", "normalize_project_sdk")

# `dotnet pack`'s default for every dependency: the consumer takes its
# assemblies but not its build logic or analyzers.
DEPENDENCY_EXCLUDE = ["Build", "Analyzers"]

# What becomes of a first-party assembly that no package in `deps` ships.
FIRST_PARTY_REFERENCE = "reference"
FIRST_PARTY_BUNDLE = "bundle"
FIRST_PARTY_ERROR = "error"
FIRST_PARTY_DEPS = [FIRST_PARTY_REFERENCE, FIRST_PARTY_BUNDLE, FIRST_PARTY_ERROR]

# The shared framework a web project compiles against, from .NET Core 3.0 on.
_ASPNETCORE_FRAMEWORK_REFERENCE = "Microsoft.AspNetCore.App"
_FIRST_FRAMEWORK_REFERENCE_TFM = "netcoreapp3.0"

# Where NuGet looks for analyzers and source generators: `analyzers/dotnet` for
# one that applies to any language, and a language folder below it for one that
# applies to a single language.
_ANALYZER_DIR = "analyzers/dotnet"
_CSHARP_ANALYZER_DIR = _ANALYZER_DIR + "/cs"

# Tells a consuming MSBuild project what the package serves. The SDK writes one
# of the same name when it packs a Razor class library.
STATIC_WEB_ASSETS_PROPS = "build/Microsoft.AspNetCore.StaticWebAssets.props"

_CONTENT_FILES_DIR = "contentFiles"

def _dependency(id, version, version_file = None):
    return struct(id = id, version = version, version_file = version_file, exclude = DEPENDENCY_EXCLUDE)

def _pdb_entries(directory, pdbs, symbols):
    """Where the pdbs of one assembly go.

    Args:
      directory: The in-package folder its assemblies took.
      pdbs: The pdb `File`s.
      symbols: "none", "embedded" (beside the assemblies) or "snupkg".

    Returns:
      A `(files, symbol_files)` pair of `(path, File)` lists.
    """
    entries = [("{}/{}".format(directory, pdb.basename), pdb) for pdb in pdbs]

    if symbols == "embedded":
        return (entries, [])
    if symbols == "snupkg":
        return ([], entries)
    return ([], [])

def is_valid_package_id(id):
    """Whether `id` is a package id NuGet accepts: `^\\w+([_.-]\\w+)*$`, at most 100 characters.

    Args:
      id: The candidate id.

    Returns:
      True when it is valid.
    """
    if not id or len(id) > 100:
        return False

    previous_was_separator = True
    for char in id.elems():
        if char.isalnum() or char == "_":
            previous_was_separator = False
        elif char in ".-" and not previous_was_separator:
            previous_was_separator = True
        else:
            return False

    return not previous_was_separator

def index_dep_packages(packages, target_frameworks, label):
    """Maps every assembly the packages in `deps` ship to its package.

    Args:
      packages: The `NuGetPackInfo`s of `deps`.
      target_frameworks: The frameworks this package ships.
      label: This package's label, for messages.

    Returns:
      A dict of assembly name to `NuGetPackInfo`.
    """
    by_assembly = {}

    for pack in packages:
        if pack.is_tool:
            fail("{}: {} is a tool package; nothing can depend on a tool".format(label, pack.label))

        for tfm in target_frameworks:
            if get_nearest_compatible_target_framework(tfm, pack.target_frameworks) == None:
                fail("{}: {} ships nothing a {} consumer can use (it targets {})".format(
                    label,
                    pack.label,
                    tfm,
                    ", ".join(pack.target_frameworks),
                ))

        for name in pack.bundled_assemblies:
            other = by_assembly.get(name)
            if other != None and other.label != pack.label:
                fail("{}: {} and {} both ship the assembly {}".format(label, other.label, pack.label, name))
            by_assembly[name] = pack

    return by_assembly

def plan_library_contents(root, packages_by_assembly, dep_packages, first_party_deps, label):
    """Decides which dependencies the package declares and which assemblies it bundles.

    Only the direct dependencies of the packed library, and of every assembly
    bundled into the package, are declared: NuGet resolves the rest from them.

    Args:
      root: The `DotnetAssemblyRuntimeInfo` of the packed library, for one framework.
      packages_by_assembly: What `index_dep_packages` returned.
      dep_packages: The `NuGetPackInfo`s of `deps`; every one is declared.
      first_party_deps: One of `FIRST_PARTY_DEPS`.
      label: This package's label, for messages.

    Returns:
      A struct of `dependencies` (structs of `id`, `version`, `version_file`,
      `exclude`, sorted by id) and `bundled` (`DotnetAssemblyRuntimeInfo`s,
      sorted by name).
    """
    if root.name in packages_by_assembly:
        fail("{}: {} already ships the assembly {}".format(label, packages_by_assembly[root.name].label, root.name))

    # `deps` is flat: the direct and transitive closure together. The names of
    # the direct ones are what the deps.json fragment records.
    by_name = {}
    for dep in root.deps.to_list():
        by_name.setdefault(dep.name, dep)

    dependencies = {}
    bundled = {}
    visited = {root.name: True}
    stack = [root]

    # Starlark has no `while`. Every assembly is pushed at most once, on top of
    # the root, so this many passes always empty the stack.
    for _ in range(len(by_name) + 1):
        if not stack:
            break

        current = stack.pop()
        for name in sorted(current.direct_deps_depsjson_fragment.keys()):
            dep = by_name.get(name)
            if dep == None or name in visited:
                continue
            visited[name] = True

            if dep.nuget_info != None:
                # A NuGet package: its id is the assembly info's name, in the
                # casing the package declares, and a bare version means at least.
                dependencies[name.lower()] = _dependency(name, dep.version)
            elif name in packages_by_assembly:
                # Shipped by a package in `deps`, which owns everything below it.
                pack = packages_by_assembly[name]
                dependencies[pack.package_id.lower()] = _dependency(pack.package_id, pack.version, pack.version_file)
            elif first_party_deps == FIRST_PARTY_REFERENCE:
                # Its own `nuget_pack` would default to this id and version.
                dependencies[name.lower()] = _dependency(name, nuget_version.normalize(dep.version))
            elif first_party_deps == FIRST_PARTY_BUNDLE:
                if not dep.libs:
                    # Nothing under `lib/` means an analyzer, whose assemblies
                    # belong under `analyzers/` in a package of its own.
                    fail(("{}: {} (a dependency of {}) ships no assembly to copy into this " +
                          "package. An analyzer or source generator is its own package; list " +
                          "its nuget_pack in `deps`.").format(label, name, current.name))
                bundled[name] = dep
                stack.append(dep)
            else:
                fail(("{}: {} (a dependency of {}) is not shipped by any package in `deps`. " +
                      "List its nuget_pack in `deps`, or set first_party_deps = \"{}\" to declare " +
                      "a dependency on a package named after it, or \"{}\" to copy it into this package.").format(
                    label,
                    name,
                    current.name,
                    FIRST_PARTY_REFERENCE,
                    FIRST_PARTY_BUNDLE,
                ))

    # A package in `deps` is a dependency whether or not anything resolved to it,
    # as a PackageReference is.
    for pack in dep_packages:
        dependencies.setdefault(pack.package_id.lower(), _dependency(pack.package_id, pack.version, pack.version_file))

    return struct(
        dependencies = [dependencies[key] for key in sorted(dependencies.keys())],
        bundled = [bundled[name] for name in sorted(bundled.keys())],
    )

def library_layout(tfm, rid, compile_info, runtime_info, bundled, symbols, reference_assemblies, emit_portable):
    """Where a library and the assemblies bundled with it go for one framework.

    Args:
      tfm: The target framework moniker.
      rid: The runtime identifier of this split, or None when the package is not RID-specific.
      compile_info: The `DotnetAssemblyCompileInfo` of the library.
      runtime_info: The `DotnetAssemblyRuntimeInfo` of the library.
      bundled: The `DotnetAssemblyRuntimeInfo`s to copy into the package beside it.
      symbols: "none", "embedded" (pdbs beside the dlls) or "snupkg" (pdbs into the symbol package).
      reference_assemblies: Whether to ship a `ref/` folder when there is a reference assembly.
      emit_portable: Whether this split also contributes the parts shared by every
        runtime identifier of the framework: the reference assemblies and the docs.

    Returns:
      A struct of `files` and `symbol_files`, each a list of `(path, File)` pairs.
    """
    lib_dir = "lib/" + tfm if rid == None else "runtimes/{}/lib/{}".format(rid, tfm)
    ref_dir = "ref/" + tfm

    # Docs travel with whichever folder a compile consults.
    doc_dir = lib_dir if rid == None else ref_dir

    files = []
    symbol_files = []

    for info in [runtime_info] + bundled:
        for dll in info.libs:
            files.append(("{}/{}".format(lib_dir, dll.basename), dll))

        # A satellite assembly sits in a folder named after its locale.
        for resource in info.resource_assemblies:
            files.append(("{}/{}/{}".format(lib_dir, resource.dirname.split("/")[-1], resource.basename), resource))

        (beside, apart) = _pdb_entries(lib_dir, info.pdbs, symbols)
        files += beside
        symbol_files += apart

        if info.native:
            if rid == None:
                fail("{} has native libraries, which a package can only ship for a runtime identifier. Set `runtime_identifiers`.".format(info.name))
            for native in info.native:
                files.append(("runtimes/{}/native/{}".format(rid, native.basename), native))

        if emit_portable:
            for xml in info.xml_docs:
                files.append(("{}/{}".format(doc_dir, xml.basename), xml))

    if emit_portable:
        implementation = runtime_info.libs[0]
        ref = compile_info.refs[0] if compile_info.refs else implementation

        # Without a reference assembly of its own - F# on an SDK that cannot
        # produce a deterministic one - a `ref/` folder would only repeat
        # `lib/`. A RID-specific package has no `lib/`, so it ships one anyway.
        if rid != None or (reference_assemblies and ref.path != implementation.path):
            files.append(("{}/{}".format(ref_dir, ref.basename), ref))

            # Once `ref/` exists a compile takes every assembly from it and
            # nothing from `lib/`, so the bundled ones have to be there too.
            for info in bundled:
                for dll in info.libs:
                    files.append(("{}/{}".format(ref_dir, dll.basename), dll))

    return struct(files = files, symbol_files = symbol_files)

def is_analyzer(compile_info):
    """Whether a library is an analyzer or a source generator rather than a reference.

    Args:
      compile_info: The `DotnetAssemblyCompileInfo` of the library.

    Returns:
      True when the compiler loads it instead of compiling against it.
    """
    return bool(compile_info.analyzers or compile_info.analyzers_csharp)

def analyzer_layout(compile_info, runtime_info, symbols):
    """Where an analyzer or source generator goes, with the assemblies it loads.

    Nothing goes under `lib/`: a consumer hands these to the compiler rather
    than compiling against them, and NuGet only does that for the ones under
    `analyzers/`.

    Args:
      compile_info: The `DotnetAssemblyCompileInfo` of the analyzer.
      runtime_info: The `DotnetAssemblyRuntimeInfo` of the analyzer.
      symbols: "none", "embedded" (the pdb beside the dll) or "snupkg".

    Returns:
      A struct of `files` and `symbol_files`, each a list of `(path, File)` pairs.
    """
    if compile_info.analyzers_csharp:
        (directory, analyzers) = (_CSHARP_ANALYZER_DIR, compile_info.analyzers_csharp)
    else:
        (directory, analyzers) = (_ANALYZER_DIR, compile_info.analyzers)

    # Exactly the assemblies the compiler was handed, minus the ones that came
    # out of a NuGet package: the compiler running the analyzer brings Roslyn
    # itself. A package's files are source files, which tells the two apart.
    files = [
        ("{}/{}".format(directory, dll.basename), dll)
        for dll in analyzers
        if not dll.is_source
    ]

    (beside, apart) = _pdb_entries(directory, runtime_info.pdbs, symbols)
    return struct(files = files + beside, symbol_files = apart)

def static_web_assets_layout(assets_info, assembly_name, copied_names, label):
    """The files a Razor class library serves, and where they go in the package.

    Only the library's own: a package has one content root under one base path,
    so a dependency's files travel in that dependency's own package.

    Args:
      assets_info: The `StaticWebAssetsInfo` of the packed library.
      assembly_name: The library's assembly name, which prefixes its own assets.
      copied_names: The names of the assemblies copied into this package, whose
        files would otherwise be dropped without a word.
      label: This package's label, for messages.

    Returns:
      A struct of `files`, the `(path, File)` pairs sorted by path, and `paths`,
      the same paths relative to the package's content root.
    """
    own = base_path(assembly_name, is_application = False) + "/"
    copied = {base_path(name, is_application = False) + "/": name for name in copied_names}

    entries = []
    for asset in assets_info.assets.to_list():
        if asset.serving_path.startswith(own):
            entries.append((
                "{}/{}".format(PACKAGE_CONTENT_ROOT, asset.serving_path[len(own):]),
                asset.file,
            ))
            continue

        for (prefix, name) in copied.items():
            if asset.serving_path.startswith(prefix):
                fail(("{}: {} is copied into this package and serves {}, but a package serves " +
                      "the files of one assembly, under `_content/<package id>`. List its " +
                      "nuget_pack in `deps` rather than copying it in.").format(
                    label,
                    name,
                    asset.serving_path,
                ))

    files = sorted(entries, key = lambda entry: entry[0])
    return struct(
        files = files,
        paths = [path[len(PACKAGE_CONTENT_ROOT) + 1:] for (path, _) in files],
    )

def _xml_escape(value):
    return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

def static_web_assets_props(package_id, paths):
    """The MSBuild file that tells a consuming project what the package serves.

    Written into the package next to the files themselves, so that a project
    that is not built with Bazel finds them where the SDK would have put them.

    Args:
      package_id: The package id, which names the base path the files are served
        under, as it does for a package the SDK wrote.
      paths: The paths of the files, relative to the package's content root.

    Returns:
      The contents of the props file.
    """
    root = "$(MSBuildThisFileDirectory)../{}/".format(PACKAGE_CONTENT_ROOT)
    lines = [
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>",
        "<Project>",
        "  <ItemGroup>",
    ]

    for path in paths:
        escaped = _xml_escape(path)
        lines.extend([
            "    <StaticWebAsset Include=\"$([System.IO.Path]::GetFullPath('{}{}'))\">".format(root, escaped),
            "      <SourceType>Package</SourceType>",
            "      <SourceId>{}</SourceId>".format(_xml_escape(package_id)),
            "      <ContentRoot>{}</ContentRoot>".format(root),
            "      <BasePath>{}</BasePath>".format(_xml_escape(base_path(package_id, is_application = False))),
            "      <RelativePath>{}</RelativePath>".format(escaped),
            "    </StaticWebAsset>",
        ])

    lines.extend(["  </ItemGroup>", "</Project>", ""])
    return "\n".join(lines)

def tool_directory(tfm):
    """The in-package folder a tool's files take for a framework, without a trailing slash.

    Args:
      tfm: The target framework moniker.

    Returns:
      The folder.
    """
    return "tools/{}/any".format(tfm)

def tool_layout(tfm, binary_info, runtime_info, assembly_files, runtime_identifier, depsjson, runtimeconfig):
    """Where a tool's framework-dependent publish goes for one framework.

    Args:
      tfm: The target framework moniker.
      binary_info: The `DotnetBinaryInfo` of the binary.
      runtime_info: The `DotnetAssemblyRuntimeInfo` of the binary.
      assembly_files: What `collect_assembly_files` returned for it.
      runtime_identifier: The runtime identifier the binary was built for, which
        names the folder of any native library built alongside it.
      depsjson: The `deps.json` written for the package.
      runtimeconfig: The `runtimeconfig.json` written for the package.

    Returns:
      A list of `(path, File)` pairs.
    """
    prefix = tool_directory(tfm) + "/"

    entries = [
        (prefix + path, file)
        for (path, file) in publish_layout(runtime_identifier, binary_info, assembly_files, [], False)
    ]

    # A publish ships the symbols of what it built, so a tool package does too.
    for info in [runtime_info] + [dep for dep in binary_info.transitive_runtime_deps if dep.nuget_info == None]:
        for pdb in info.pdbs:
            entries.append((prefix + pdb.basename, pdb))

    entries.append((prefix + depsjson.basename, depsjson))
    entries.append((prefix + runtimeconfig.basename, runtimeconfig))

    return entries

def dependency_group(tfm, dependencies):
    """A dependency group of the manifest, as the packer wants it.

    Args:
      tfm: The target framework moniker the group is for.
      dependencies: The structs `plan_library_contents` returned; may be empty,
        which says the framework is supported and needs nothing.

    Returns:
      A struct for the request.
    """
    return struct(
        targetFramework = tfm_to_nuget_framework(tfm),
        dependencies = [
            struct(
                id = dependency.id,
                version = dependency.version or "",
                versionFile = dependency.version_file.path if dependency.version_file else None,
                exclude = dependency.exclude,
            )
            for dependency in dependencies
        ],
    )

def framework_reference_group(tfm, project_sdk):
    """The shared framework a web library's consumers need, if any.

    Args:
      tfm: The target framework moniker.
      project_sdk: The `project_sdk` the library was compiled with.

    Returns:
      A struct for the request, or None when the framework is implied.
    """
    if normalize_project_sdk(project_sdk) != WEB_SDK:
        return None

    if not is_core_framework(tfm) or not is_greater_or_equal_framework(tfm, _FIRST_FRAMEWORK_REFERENCE_TFM):
        return None

    return struct(
        targetFramework = tfm_to_nuget_framework(tfm),
        frameworkReferences = [_ASPNETCORE_FRAMEWORK_REFERENCE],
    )

def _check_package_path(path, label, target):
    for segment in path.split("/"):
        if segment in ["", ".", ".."]:
            fail("{}: the package path \"{}\" of {} must be relative, with no empty, `.` or `..` segments".format(label, path, target.label))
    if "\\" in path:
        fail("{}: the package path \"{}\" of {} must use forward slashes".format(label, path, target.label))

def extra_files_layout(files, label, prefix = ""):
    """Places arbitrary files in the package.

    Args:
      files: A dict of `Target` to in-package path. A path ending in `/` is a
        folder every file of the target goes into by its base name; otherwise the
        target must be exactly one file, which takes that path.
      label: This package's label, for messages.
      prefix: A folder to place everything under, with its trailing slash.

    Returns:
      A list of `(path, File)` pairs.
    """
    entries = []

    for (target, path) in files.items():
        target_files = target.files.to_list()

        if path.endswith("/"):
            _check_package_path(path[:-1], label, target)
            for file in target_files:
                entries.append((prefix + path + file.basename, file))
        else:
            _check_package_path(path, label, target)
            if len(target_files) != 1:
                fail("{}: {} is {} files, so its package path \"{}\" has to name a folder (end in `/`)".format(label, target.label, len(target_files), path))
            entries.append((prefix + path, target_files[0]))

    return entries

def content_files_layout(files, label):
    """Places files under `contentFiles/` and describes them for the manifest.

    Args:
      files: A dict of `Target` to `<language>/<framework>/<path>` under `contentFiles/`.
      label: This package's label, for messages.

    Returns:
      A struct of `entries` (`(path, File)` pairs) and `includes` (the paths
      relative to `contentFiles/`, for the `<contentFiles>` metadata).
    """
    entries = extra_files_layout(files, label, prefix = _CONTENT_FILES_DIR + "/")
    includes = [path[len(_CONTENT_FILES_DIR) + 1:] for (path, _) in entries]

    for include in includes:
        if len(include.split("/")) < 3:
            fail("{}: a content file's path must be `<language>/<framework>/<path>`, got \"{}\"".format(label, include))

    return struct(entries = entries, includes = includes)
