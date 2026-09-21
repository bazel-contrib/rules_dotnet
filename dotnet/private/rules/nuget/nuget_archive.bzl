"NuGet Archive"

load(
    "@bazel_tools//tools/build_defs/repo:utils.bzl",
    "read_netrc",
    "read_user_netrc",
    "use_netrc",
)
load(
    "//dotnet/private:common.bzl",
    "COR_FRAMEWORKS",
    "FRAMEWORK_COMPATIBILITY",
    "NET_FRAMEWORKS",
    "STD_FRAMEWORKS",
    "get_nearest_compatible_target_framework",
)
load("//dotnet/private:portable_rids.bzl", "rids_by_preference", "to_portable_rid")
load(
    "//dotnet/private/rules/nuget:dotnet_tool.bzl",
    "DotnetToolInfo",
)
load(
    "//dotnet/private/rules/nuget:package_metadata.bzl",
    "parse_dotnet_tool_settings",
    "parse_framework_list",
    "parse_nuspec",
    "parse_package_overrides",
)
load(
    "//dotnet/private/sdk:rids.bzl",
    "RUNTIME_GRAPH",
)

def _is_windows(repository_ctx):
    """Returns true if the host operating system is windows."""
    os_name = repository_ctx.os.name.lower()
    if os_name.find("windows") != -1:
        return True
    return False

def _read_dir(repository_ctx, src_dir):
    """Returns a string with all files in a directory.

    Finds all files inside a directory, traversing subfolders and following
    symlinks. The returned string contains the full path of all files
    separated by line breaks.
    """
    if _is_windows(repository_ctx):
        src_dir = src_dir.replace("/", "\\")
        nuget_directory = repository_ctx.execute(["cmd.exe", "/c", "echo|set", "/p=%cd%"])
        find_result = repository_ctx.execute(["cmd.exe", "/c", "dir", src_dir, "/b", "/s", "/a-d"])

        # The output from the find command includes absolute paths so we strip the
        # current working directory from the paths
        result = find_result.stdout.replace(nuget_directory.stdout + "\\", "")

        # src_files will be used in genrule.outs where the paths must
        # use forward slashes.
        result = result.replace("\\", "/")
    else:
        find_result = repository_ctx.execute(["find", src_dir, "-follow", "-type", "f"])
        result = find_result.stdout
    return result

def _file_dict(group):
    """Renders a group as the Starlark dict literal the BUILD file passes on.

    `_._` placeholders are dropped. They say the package brings nothing under a
    key, which the key being present at all already records.
    """
    entries = [
        ' "%s": [%s],\n' % (
            key,
            ",".join(["\n   \"%s\"" % file for file in files if not file.endswith("_._")]),
        )
        for (key, files) in group.items()
    ]

    return "{\n%s}" % "".join(entries)

def _create_rid_tfm_select(name, tfms, rid_tfms):
    if not tfms and not rid_tfms:
        return None

    rids = [
        ' "%s": %s,\n' % (rid, _file_dict(files_by_tfm))
        for (rid, files_by_tfm) in rid_tfms.items()
    ]

    return "rid_tfm_filegroup(\"%s\", %s, {\n%s})" % (name, _file_dict(tfms), "".join(rids))

def _with_empty_entries(tfms, extra):
    """Adds frameworks the package supports but ships no assemblies for.

    Only widens a group that already has entries. A package with no `lib` or
    `ref` folders at all -- one that ships only MSBuild assets -- has nothing to
    be incompatible with, so it must stay a group that resolves to nothing.
    """
    if not tfms:
        return tfms

    result = dict(tfms)

    for tfm in extra:
        if tfm not in result:
            result[tfm] = []

    return result

def _create_ref_select(name, ref_tfms, lib_tfms, default_to_empty):
    if not ref_tfms and not lib_tfms:
        return None

    return "ref_tfm_filegroup(\"%s\", %s, %s, %s)" % (
        name,
        default_to_empty,
        _file_dict(ref_tfms),
        _file_dict(lib_tfms),
    )

def _create_group(name, package, build_tfms, unsupported):
    """Emits the compile or runtime group, unioning in any `build` assemblies."""
    parts = []
    srcs = []

    if package:
        parts.append(package)
        srcs.append(":%s_package" % name)
    elif unsupported:
        # The package ships assemblies, just not for a framework rules_dotnet
        # can target. That is an incompatible package, not one that brings
        # nothing.
        parts.append("unsupported_frameworks(\"%s_package\", [%s])" % (
            name,
            ",".join(["\n  \"%s\"" % tfm for tfm in sorted(unsupported)]),
        ))
        srcs.append(":%s_package" % name)

    if build_tfms:
        parts.append("tfm_filegroup(\"%s_build\", True, %s)" % (name, _file_dict(build_tfms)))
        srcs.append(":%s_build" % name)

    parts.append("filegroup(name = \"%s\", srcs = [%s])" % (
        name,
        ",".join(["\n  \"%s\"" % src for src in srcs]),
    ))

    return "\n".join(parts)

def _create_rid_native_select(name, group):
    if not group:
        return None

    return "rid_filegroup(\"%s\", %s)" % (name, _file_dict(group))

def _create_tools_select(tools):
    if not tools:
        return None

    return "tool_filegroup(\"tools\", %s)" % _file_dict(tools)

def _sanitize_path(file_path):
    # On linux the relative file path starts with ./
    if file_path.startswith("./"):
        return file_path[2:]

    return file_path

# Spellings some packages ship in place of the canonical moniker.
_NON_STANDARD_TFMS = {
    "netstandard20": "netstandard2.0",
    "netstandard21": "netstandard2.1",
}

def _normalize_tfm(folder):
    """Maps a package folder name onto the target framework it names.

    NuGet matches these folders case insensitively, and packages do ship
    `lib/Net45` or `lib/NetCore45`.

    Args:
      folder: The folder name as it appears in the package.

    Returns:
      The target framework, or None when it is not one rules_dotnet configures on.
    """
    tfm = folder.lower()
    tfm = _NON_STANDARD_TFMS.get(tfm, tfm)

    return tfm if tfm in FRAMEWORK_COMPATIBILITY else None

# `lib/<tfm>/<assembly>.dll` and `ref/<tfm>/<assembly>.dll`.
def _process_group_with_tfm(groups, group_name, file):
    parts = file.split("/")

    # A file sitting directly under the group folder names no framework.
    if len(parts) < 3:
        return

    folder = parts[1]
    tfm = _normalize_tfm(folder)

    if tfm == None:
        # A framework rules_dotnet cannot configure on: a platform specific TFM
        # such as `net8.0-windows`, a portable profile, a Xamarin target. A
        # package whose every folder lands here supports nothing we can build,
        # which is an incompatible package.
        groups["unsupported_tfms"][folder] = True
        return

    # Registered before the file is looked at, so that a `_._` placeholder still
    # claims the framework: it says the package brings nothing for it, not that
    # it does not support it.
    group = groups[group_name].setdefault(tfm, [])

    if file.endswith("_._"):
        return

    # lib/<tfm>/<locale>/<assembly>.resources.dll
    if group_name == "lib" and file.endswith(".resources.dll"):
        groups["resource_assemblies"].setdefault(tfm, []).append(file)
        return

    if file.endswith(".dll"):
        group.append(file)

# A package supports a framework when it brings anything for it, assemblies or
# not. MSBuild props and targets named after the package count, and one that
# resolves through those simply brings no assemblies.
def _record_build_compatibility(groups, id, file):
    parts = file.split("/")

    if parts[-1].lower() not in ["%s.props" % id.lower(), "%s.targets" % id.lower()]:
        return

    if len(parts) == 2:
        groups["build_compat"]["any"] = True
    elif len(parts) == 3:
        tfm = _normalize_tfm(parts[1])
        if tfm != None:
            groups["build_compat"]["tfms"][tfm] = True

# `build/<tfm>/<ref|lib>/<assembly>.dll`.
def _process_build_file(groups, file):
    parts = file.split("/")

    if len(parts) < 3:
        return

    if parts[1].lower() == ".netframework":
        # `build/.NETFramework/<version>/<assembly>.dll`: no `ref`/`lib`
        # segment, and the assemblies are references.
        tfm = _normalize_tfm(parts[2].replace("v", "net").replace(".", ""))
        file_type = "ref"
    else:
        tfm = _normalize_tfm(parts[1])
        file_type = parts[2]

    if tfm == None or file_type not in ["lib", "ref"]:
        return

    # See https://github.com/bazel-contrib/rules_dotnet/issues/405
    if not file.endswith(".dll") or file.endswith(".resources.dll"):
        return

    groups["build"].setdefault(tfm, {"lib": [], "ref": []})[file_type].append(file)

def _process_typeprovider_file(groups, file):
    if not file.endswith(".dll"):
        return

    parts = file.split("/")

    if len(parts) < 3:
        return

    tfm = _normalize_tfm(parts[2])

    if tfm == None:
        return

    groups["typeproviders"].setdefault(tfm, []).append(file)

# See https://learn.microsoft.com/en-us/nuget/guides/analyzers-conventions.
# `dotnet` is the only framework name the convention defines.
#
#   analyzers/dotnet/<assembly>.dll
#   analyzers/dotnet/<language>/<assembly>.dll
#   analyzers/dotnet/roslyn<version>/<language>/<assembly>.dll
def _process_analyzer_file(groups, file):
    if (not file.endswith(".dll")) or file.endswith("resources.dll"):
        return

    parts = file.split("/")

    if len(parts) == 3:
        groups["analyzers"]["dotnet"].append(file)
    elif len(parts) == 4:
        _add_language_analyzer(groups, parts[2], file)
    elif len(parts) == 5:
        groups["analyzers_by_roslyn"].setdefault(parts[3], {}).setdefault(parts[2], []).append(file)

def _add_language_analyzer(groups, language, file):
    group = groups["analyzers"].get("dotnet/%s" % language)

    # A folder naming something other than a language rules_dotnet compiles.
    if group != None:
        group.append(file)

def _roslyn_order(folder):
    """Orders a `roslyn<major>.<minor>` folder by version rather than by name.

    Args:
      folder: The folder name as it appears under `analyzers/dotnet`.

    Returns:
      A sort key. Folders that do not name a Roslyn version order after every
      one that does, so they are only reached when nothing else is on offer.
    """
    if not folder.startswith("roslyn"):
        return [1]

    order = [0]

    for part in folder[len("roslyn"):].split("."):
        if not part.isdigit():
            return [1]

        order.append(int(part))

    return order

# The Roslyn an analyzer was built against. The SDK takes the newest version the
# running compiler can load; rules_dotnet does not know that version, so it takes
# the lowest, which every compiler can load.
# See https://github.com/dotnet/sdk/issues/20355.
def _resolve_roslyn_analyzers(groups):
    for (language, by_version) in groups["analyzers_by_roslyn"].items():
        lowest = sorted(by_version.keys(), key = _roslyn_order)[0]

        for file in by_version[lowest]:
            _add_language_analyzer(groups, language, file)

def _process_content_file(groups, file):
    groups["contentFiles"]["any"].append(file)

def _process_runtimes_file(groups, file):
    parts = file.split("/")

    if len(parts) < 3:
        return

    # A package can ship assets under a version-qualified RID such as
    # `ubuntu.16.04-x64`. rules_dotnet configures only on portable RIDs, so fold
    # those onto the nearest portable ancestor.
    source_rid = parts[1]

    if source_rid not in RUNTIME_GRAPH:
        return

    rid = to_portable_rid(source_rid)

    group = groups["runtimes"]
    entry = group.get(rid)

    if entry != None and entry["rid"] != source_rid:
        # Several version-qualified RIDs can fold onto the same portable one, and
        # only one set of assets can sit there. Order by fallback chain length,
        # then by name, so the winner does not depend on the order of the archive.
        if (len(RUNTIME_GRAPH[source_rid]), source_rid) <= (len(RUNTIME_GRAPH[entry["rid"]]), entry["rid"]):
            return
        entry = None

    if entry == None:
        entry = {
            "rid": source_rid,
            "native": [],
            "lib": {},
        }
        group[rid] = entry

    if parts[2] == "native":
        entry["native"].append(file)

    if parts[2] == "lib":
        if len(parts) < 5:
            return

        tfm = _normalize_tfm(parts[3])

        if tfm == None:
            return

        # Registered before the file is looked at, so that a `_._` placeholder
        # still claims the RID/TFM combination: it says the package brings
        # nothing here, not that it says nothing about the RID.
        files = entry["lib"].setdefault(tfm, [])

        if file.endswith(".dll") and not file.endswith(".resources.dll"):
            files.append(file)

# `tools/<TFM>/any/...`
def _process_tools_file(groups, file):
    parts = file.split("/")

    if len(parts) < 4 or parts[2] != "any":
        return

    # Keyed by the framework the folder names rather than by the folder itself,
    # so that a tool is looked up the same way every other group is.
    tfm = _normalize_tfm(parts[1])

    if tfm != None:
        groups["tools"].setdefault(tfm, []).append(file)

def _process_key_and_file(groups, key, file):
    if key == "lib" or key == "ref":
        _process_group_with_tfm(groups, key, file)
    elif key == "analyzers":
        _process_analyzer_file(groups, file)
    elif key == "contentFiles":
        _process_content_file(groups, file)
    elif key == "staticwebassets":
        groups["staticwebassets"].append(file)
    elif key == "typeproviders":
        _process_typeprovider_file(groups, file)
    elif key == "runtimes":
        _process_runtimes_file(groups, file)
    elif key == "build":
        _process_build_file(groups, file)
    elif key == "tools":
        _process_tools_file(groups, file)

def _get_package_urls(rctx, sources, auth, package_id, package_version):
    base_addresses = {}
    package_urls = []

    for source in sources:
        if base_addresses.get(source):
            continue

        # If the url ends with index.json we are dealing with a V3 NuGet feed
        # and the url schema for the package contents will be:
        # {base_address}/{lower_id}/{lower_version}/{lower_id}.{lower_version}.nupkg
        if source.endswith("index.json"):
            rctx.download(source, auth = auth, output = "index.json")
            index = json.decode(rctx.read("index.json"))
            rctx.delete("index.json")
            for resource in index["resources"]:
                if resource["@type"] == "PackageBaseAddress/3.0.0":
                    base_addresses[source] = resource["@id"]

                    package_urls.append(
                        "{base_address}{package_id}/{package_version}/{package_id}.{package_version}.nupkg".format(
                            base_address = resource["@id"] if resource["@id"].endswith("/") else resource["@id"] + "/",
                            package_id = package_id.lower(),
                            package_version = package_version.lower(),
                        ),
                    )
        else:
            # Else we expect the url to be a V2 NuGet feed and the url schema for the
            # package contents will be: {source}/package/{id}/{version}
            base_addresses[source] = source
            package_urls.append("{source}/package/{package_id}/{package_version}".format(source = source, package_id = package_id, package_version = package_version))

    return package_urls

def _get_auth_dict(ctx, urls):
    # A netrc declared on the package wins over the user's.
    netrc = read_netrc(ctx, ctx.attr.netrc) if ctx.attr.netrc else read_user_netrc(ctx)

    return use_netrc(netrc, urls, {
        "type": "basic",
        "login": "<login>",
        "password": "<password>",
    })

_PACKAGE_INFO_TEMPLATE = """\
"GENERATED"

DEPENDENCY_GROUPS = {dependency_groups}

FRAMEWORK_LIST = {framework_list}

TARGETING_PACK_OVERRIDES = {targeting_pack_overrides}

TOOLS = {tools}
"""

def _write_package_info(ctx, all_files, tool_files, prefix):
    """Extracts the package metadata that the hub repository needs.

    Reading it here keeps the work lazy: a package nothing depends on is never
    fetched, let alone parsed.
    """
    nuspec = None
    framework_list = {}
    targeting_pack_overrides = {}

    for file in all_files:
        file = _sanitize_path(file)
        lower = file.lower()

        if lower.endswith(".nuspec") and file.find("/") == -1:
            nuspec = file
        elif lower == "data/frameworklist.xml":
            framework_list = parse_framework_list(ctx.read(prefix + file))
        elif lower == "data/packageoverrides.txt":
            targeting_pack_overrides = parse_package_overrides(ctx.read(prefix + file))

    dependency_groups = {}
    is_dotnet_tool = False

    if nuspec != None:
        manifest = parse_nuspec(ctx.read(prefix + nuspec))
        dependency_groups = manifest.dependency_groups
        is_dotnet_tool = manifest.is_dotnet_tool

    # Tool name -> target framework -> entrypoint. Packages that are not
    # dotnet tools sometimes ship helper executables under `tools/`, which are
    # not meant to be run through `dotnet tool`.
    tools = {}
    if is_dotnet_tool:
        for (tfm, files) in tool_files.items():
            for file in files:
                if not file.endswith("DotnetToolSettings.xml"):
                    continue

                for command in parse_dotnet_tool_settings(ctx.read(prefix + file), file):
                    tools.setdefault(command["name"], {})[tfm] = {
                        "entrypoint": command["entrypoint"],
                        "runner": command["runner"],
                    }

    ctx.file(prefix + "package_info.bzl", _PACKAGE_INFO_TEMPLATE.format(
        dependency_groups = json.encode(dependency_groups),
        framework_list = json.encode(framework_list),
        targeting_pack_overrides = json.encode(targeting_pack_overrides),
        tools = json.encode(tools),
    ))

# Assemblies under `build` resolve through their own select and are unioned
# into the compile or runtime group: the SDK adds them alongside a package's own
# assemblies, not in place of them.
def _build_assemblies(build, kind):
    return {tfm: entry[kind] for (tfm, entry) in build.items() if entry[kind]}

def _group_package_files(id, all_files):
    """Sorts a package's files into the groups the BUILD file is generated from.

    Args:
      id: The package id, used to recognise its MSBuild props and targets.
      all_files: Every file in the extracted package.

    Returns:
      A struct of the groups, ready to be turned into targets.
    """

    # The NuGet package format
    groups = {
        # Format: analyzers/dotnet[/<roslyn version>][/<language>]/<assembly>.dll
        "analyzers": {
            "dotnet": [],
            "dotnet/cs": [],
            "dotnet/fs": [],
            "dotnet/vb": [],
        },
        # See: https://devblogs.microsoft.com/nuget/nuget-contentfiles-demystified/
        # NB: Only the any group is supported at the moment
        "contentFiles": {
            "any": [],
        },
        # Files the package serves, at their paths below the `_content/<id>`
        # base path. See the `build/Microsoft.AspNetCore.StaticWebAssets.props`
        # a Razor class library ships.
        "staticwebassets": [],
        # Format: lib/<TFM>/<assembly>.dll
        "lib": {},
        # Resource assemblies: https://learn.microsoft.com/en-us/nuget/create-packages/creating-localized-packages
        # Format: lib/<TFM>/<locale>/<assembly>.resources.<dll|xml>
        "resource_assemblies": {},
        # Format: ref/<TFM>/<assembly>.dll
        "ref": {},
        # See https://github.com/fsharp/fslang-design/blob/main/tooling/FST-1003-loading-type-provider-design-time-components.md
        # Format: typeproviders/<TFM>/<assembly>.dll
        "typeproviders": {},
        # See https://docs.microsoft.com/en-us/nuget/create-packages/supporting-multiple-target-frameworks#architecture-specific-folders
        # Format: runtimes/<RID>/native/<assembly>.dll OR runtimes/<RID>/lib/<TFM>/<assembly>.dll
        "runtimes": {},
        # See: https://learn.microsoft.com/en-us/nuget/concepts/msbuild-props-and-targets#framework-specific-build-folder
        # Format: build/<TFM>/ref/<assembly>.dll OR build/<TFM>/lib/<assembly>.dll
        # NB: Only the assemblies are picked up; the MSBuild props and targets
        #     that packages ship here are not run.
        "build": {},
        # See: https://github.com/dotnet/sdk/blob/master/documentation/general/tool-nuget-package-format.md
        # Format: tools/<TFM>/any/...
        # NB: Dotnet requires portable assemblies in the tools folder, so RID is always 'any'
        "tools": {},
        # Bookkeeping rather than assets: analyzers still keyed by the Roslyn
        # they were built against, the `lib`/`ref` folder names that do not name
        # a framework rules_dotnet can target, and the frameworks the package
        # supports through MSBuild assets rather than assemblies.
        "analyzers_by_roslyn": {},
        "unsupported_tfms": {},
        "build_compat": {
            "any": False,
            "tfms": {},
        },
    }

    for file in all_files:
        file = _sanitize_path(file)
        i = file.find("/")
        key = file[:i]

        _process_key_and_file(groups, key, file)

        if key == "build" or key == "buildTransitive":
            _record_build_compatibility(groups, id, file)

    _resolve_roslyn_analyzers(groups)

    # The runtime group comes from `lib` alone. `ref` never contributes to it,
    # and never constrains which `lib` entry is picked.
    libs = dict(groups["lib"])
    native = {}

    for (tfm, files) in groups["typeproviders"].items():
        if libs.get(tfm):
            libs[tfm] = libs[tfm] + files
        else:
            libs[tfm] = files

    # RID bound assemblies stand in for the whole lib group when one applies,
    # so they are kept apart and resolved first.
    rid_libs = {}

    for (rid, files_for_rid) in groups["runtimes"].items():
        native[rid] = files_for_rid["native"]
        if files_for_rid["lib"]:
            rid_libs[rid] = files_for_rid["lib"]

    # An F# type provider's designer assembly is never referenced, but the
    # compiler probes the package layout for it, so it has to be staged whatever
    # framework it was published for.
    typeproviders = [
        file
        for files in groups["typeproviders"].values()
        for file in files
    ]

    return struct(
        typeproviders = typeproviders,
        analyzers = groups["analyzers"],
        build_compat_tfms = groups["build_compat"]["tfms"].keys(),
        build_libs = _build_assemblies(groups["build"], "lib"),
        build_refs = _build_assemblies(groups["build"], "ref"),
        compatible_with_anything = (
            groups["build_compat"]["any"] or len(groups["contentFiles"]["any"]) > 0
        ),
        content_files = groups["contentFiles"]["any"],
        static_web_assets = groups["staticwebassets"],
        libs = libs,
        native = native,
        refs = groups["ref"],
        resource_assemblies = groups["resource_assemblies"],
        rid_libs = rid_libs,
        tools = groups["tools"],
        unsupported_tfms = groups["unsupported_tfms"].keys(),
    )

def _nuget_archive_impl(ctx):
    # First get the auth dict for the package sources since the sources can be different than the
    # package base url when using NuGet V3 feeds.
    auth = _get_auth_dict(ctx, ctx.attr.sources)
    urls = _get_package_urls(ctx, ctx.attr.sources, auth, ctx.attr.id, ctx.attr.version)

    # Then get the auth dict for the package base urls
    auth = _get_auth_dict(ctx, urls)

    # We download it as .zip because ctx.extract reads the file extension to determine the archive type
    file_name = "%s.zip" % ctx.name
    nupkg_name = "%s.%s.nupkg" % (ctx.attr.id, ctx.attr.version)

    ctx.download(urls, output = file_name, integrity = ctx.attr.sha512, auth = auth)
    ctx.extract(archive = file_name)
    ctx.symlink(file_name, nupkg_name)

    all_files = sorted(_read_dir(ctx, ".").replace(str(ctx.path(".")) + "/", "").splitlines())

    _write_repository(ctx, ctx.attr.id, nupkg_name, all_files)

def _write_repository(ctx, id, nupkg_name, all_files, prefix = ""):
    """Turns an extracted package into the metadata and targets it is consumed through.

    Args:
      ctx: The repository context.
      id: The package id.
      nupkg_name: The name of the `.nupkg` in the repository.
      all_files: Every file in the package, relative to the package it is
        written into.
      prefix: The directory the targets are written into, empty for the
        repository root. Several packages can then share one repository.
    """
    groups = _group_package_files(id, all_files)

    _write_package_info(ctx, all_files, groups.tools, prefix)

    ctx.file(prefix + "BUILD.bazel", r"""package(default_visibility = ["//visibility:public"])
exports_files(glob(["**"]))
load("@rules_dotnet//dotnet/private/rules/nuget:nuget_archive.bzl", "tfm_filegroup", "rid_tfm_filegroup", "ref_tfm_filegroup", "rid_filegroup", "tool_filegroup", "unsupported_frameworks")
""" + "\n".join([
        _create_group(
            "libs",
            _create_rid_tfm_select("libs_package", groups.libs, groups.rid_libs),
            groups.build_libs,
            {},
        ),
        _create_group(
            "refs",
            _create_ref_select(
                "refs_package",
                groups.refs,
                _with_empty_entries(groups.libs, groups.build_compat_tfms),
                groups.compatible_with_anything,
            ),
            groups.build_refs,
            groups.unsupported_tfms,
        ),
        # A package can ship satellite assemblies for some of its frameworks and
        # not others, so this group falls back to empty rather than to an error.
        "tfm_filegroup(\"resource_assemblies\", True, %s)" % _file_dict(groups.resource_assemblies) if groups.resource_assemblies else "filegroup(name = \"resource_assemblies\", srcs = [])",
        "filegroup(name = \"analyzers\", srcs = [%s])" % ",".join(["\n  \"%s\"" % a for a in groups.analyzers["dotnet"]]),
        "filegroup(name = \"analyzers_csharp\", srcs = [%s])" % ",".join(["\n  \"%s\"" % a for a in groups.analyzers["dotnet/cs"]]),
        "filegroup(name = \"analyzers_fsharp\", srcs = [%s])" % ",".join(["\n  \"%s\"" % a for a in groups.analyzers["dotnet/fs"]]),
        "filegroup(name = \"analyzers_vb\", srcs = [%s])" % ",".join(["\n  \"%s\"" % a for a in groups.analyzers["dotnet/vb"]]),
        "filegroup(name = \"data\", srcs = [])",
        _create_rid_native_select("native", groups.native) or "filegroup(name = \"native\", srcs = [])",
        "filegroup(name = \"content_files\", srcs = [%s])" % ",".join(["\n  \"%s\"" % a for a in groups.content_files]),
        "filegroup(name = \"typeproviders\", srcs = [%s])" % ",".join(["\n  \"%s\"" % _sanitize_path(a) for a in groups.typeproviders]),
        "filegroup(name = \"static_web_assets\", srcs = [%s])" % ",".join(["\n  \"%s\"" % _sanitize_path(a) for a in groups.static_web_assets]),
        "filegroup(name = \"files\", srcs = [%s])" % ",".join(["\n  \"%s\"" % _sanitize_path(a) for a in all_files]),
        _create_tools_select(groups.tools) or "filegroup(name = \"tools\", srcs = [])",
        "exports_files([\"%s\"])" % nupkg_name,
    ]))

nuget_archive = repository_rule(
    _nuget_archive_impl,
    attrs = {
        "sources": attr.string_list(),
        "netrc": attr.label(),
        "id": attr.string(),
        "version": attr.string(),
        "sha512": attr.string(),
    },
)

def _tfm_alias(name, targets_by_tfm, default_target):
    """Resolves a TFM keyed mapping through the `tfm_*` config settings.

    Args:
      name: The name of the alias to create.
      targets_by_tfm: The target each target framework resolves to.
      default_target: The target a configuration matching no TFM falls back to.

    Returns:
      The alias.
    """
    std = []
    net = []
    cor = []

    for (tfm, target) in targets_by_tfm.items():
        if tfm in COR_FRAMEWORKS:
            cor.append((tfm, target))
        elif tfm in STD_FRAMEWORKS:
            std.append((tfm, target))
        elif tfm in NET_FRAMEWORKS:
            net.append((tfm, target))
        else:
            fail("unknown framework %s" % tfm)

    # A netstandard candidate and a net/netcoreapp one can both be compatible
    # without either encapsulating the other. Splitting them into a filegroup
    # per family and choosing between those with an alias resolves the conflict.
    if std and (net or cor):
        native.alias(
            name = "%s_std" % name,
            actual = select(
                {"@rules_dotnet//dotnet:tfm_%s" % tfm: target for (tfm, target) in std} |
                {"//conditions:default": default_target},
            ),
            visibility = ["//visibility:public"],
        )

        if net:
            native.alias(
                name = "%s_net" % name,
                actual = select(
                    {"@rules_dotnet//dotnet:tfm_%s" % tfm: target for (tfm, target) in net} |
                    {"//conditions:default": ":%s_std" % name},
                ),
                visibility = ["//visibility:public"],
            )

        if cor:
            native.alias(
                name = "%s_cor" % name,
                actual = select(
                    {"@rules_dotnet//dotnet:tfm_%s" % tfm: target for (tfm, target) in cor} |
                    {"//conditions:default": ":%s_std" % name},
                ),
                visibility = ["//visibility:public"],
            )

        return native.alias(
            name = name,
            actual = select({
                # targeting net(core)
                "@rules_dotnet//dotnet:tfm_netcoreapp1.0": (":%s_cor" % name) if cor else (":%s_std" % name),
                # targeting netframework
                "@rules_dotnet//dotnet:tfm_net11": (":%s_net" % name) if net else (":%s_std" % name),
                # targeting netstandard
                "//conditions:default": (":%s_std" % name),
            }),
            visibility = ["//visibility:public"],
        )

    return native.alias(
        name = name,
        actual = select(
            {"@rules_dotnet//dotnet:tfm_%s" % tfm: target for (tfm, target) in targets_by_tfm.items()} |
            {"//conditions:default": default_target},
        ),
        visibility = ["//visibility:public"],
    )

def _empty_filegroup(name):
    native.filegroup(name = name, srcs = [], visibility = ["//visibility:public"])

    return ":%s" % name

# This function is public because it's used by the nuget_archive repository rule.
# buildifier: disable=function-docstring
def tfm_filegroup(name, default_to_empty, tfms):
    for (tfm, files) in tfms.items():
        native.filegroup(
            name = "%s_%s_files" % (name, tfm),
            srcs = files,
            visibility = ["//visibility:public"],
        )

    default_name = "%s_default" % name
    default_target = (
        _empty_filegroup(default_name) if default_to_empty else unsupported_frameworks(default_name, tfms.keys())
    )

    return _tfm_alias(name, {tfm: ":%s_%s_files" % (name, tfm) for tfm in tfms}, default_target)

def _rid_chain(name, targets_by_rid, fallback):
    """Resolves RID bound targets through a chain of single condition selects.

    Several of a package's RIDs can be compatible with the one being built --
    `linux-musl` and `linux-x64` both are when building `linux-musl-x64` -- and
    neither `rid_*` config setting is a specialisation of the other, so Bazel
    cannot pick between them. One condition per select states the order.

    Args:
      name: Prefix for the aliases to create.
      targets_by_rid: The target each runtime identifier resolves to.
      fallback: The target to resolve to when no RID matches.

    Returns:
      The label of the head of the chain.
    """
    ordered = rids_by_preference(targets_by_rid.keys())
    target = fallback

    for index in range(len(ordered) - 1, -1, -1):
        alias_name = "%s_%d" % (name, index)
        native.alias(
            name = alias_name,
            actual = select({
                "@rules_dotnet//dotnet:rid_%s" % ordered[index]: targets_by_rid[ordered[index]],
                "//conditions:default": target,
            }),
            visibility = ["//visibility:public"],
        )
        target = ":%s" % alias_name

    return target

# This function is public because it's used by the nuget_archive repository rule.
# buildifier: disable=function-docstring
def rid_tfm_filegroup(name, tfms, rid_tfms):
    # The runtime group never decides compatibility: a package that supports the
    # framework being built but ships no assembly for it brings nothing, which
    # is not an error. `refs` carries that check.
    lib_name = "%s_lib" % name

    if tfms:
        tfm_filegroup(lib_name, True, tfms)
    else:
        _empty_filegroup(lib_name)

    lib_target = ":%s" % lib_name

    if not rid_tfms:
        return native.alias(name = name, actual = lib_target, visibility = ["//visibility:public"])

    # NuGet picks the nearest TFM among the ones shipped under `runtimes` and
    # only then picks between the RIDs offering it.
    rids_by_tfm = {}

    for (rid, files_by_tfm) in rid_tfms.items():
        for (tfm, files) in files_by_tfm.items():
            native.filegroup(
                name = "%s_%s_%s_files" % (name, rid, tfm),
                srcs = files,
                visibility = ["//visibility:public"],
            )
            if tfm not in rids_by_tfm:
                rids_by_tfm[tfm] = {}
            rids_by_tfm[tfm][rid] = ":%s_%s_%s_files" % (name, rid, tfm)

    targets_by_tfm = {}

    for (tfm, targets_by_rid) in rids_by_tfm.items():
        # Falling through to the next TFM that has RID bound assemblies keeps
        # the search going across both dimensions: a package shipping
        # `runtimes/win/lib/net8.0` and `runtimes/linux/lib/netstandard2.0`
        # still resolves to the Linux assembly on Linux.
        next_tfm = get_nearest_compatible_target_framework(
            tfm,
            [candidate for candidate in rids_by_tfm.keys() if candidate != tfm],
        )

        native.alias(
            name = "%s_rid_%s" % (name, tfm),
            actual = _rid_chain(
                "%s_rid_%s_chain" % (name, tfm),
                targets_by_rid,
                ":%s_rid_%s" % (name, next_tfm) if next_tfm else lib_target,
            ),
            visibility = ["//visibility:public"],
        )
        targets_by_tfm[tfm] = ":%s_rid_%s" % (name, tfm)

    return _tfm_alias(name, targets_by_tfm, lib_target)

# This function is public because it's used by the nuget_archive repository rule.
# buildifier: disable=function-docstring
def ref_tfm_filegroup(name, default_to_empty, ref_tfms, lib_tfms):
    # `ref` is consulted as a group before `lib`, but is not the last word:
    # a package shipping only `ref/net8.0` still compiles against its
    # `lib/netstandard2.0` assembly on net6.0.
    lib_name = "%s_lib" % name

    if lib_tfms:
        tfm_filegroup(lib_name, default_to_empty, lib_tfms)
    elif default_to_empty or not ref_tfms:
        _empty_filegroup(lib_name)
    else:
        unsupported_frameworks(lib_name, ref_tfms.keys())

    if not ref_tfms:
        return native.alias(
            name = name,
            actual = ":%s" % lib_name,
            visibility = ["//visibility:public"],
        )

    for (tfm, files) in ref_tfms.items():
        native.filegroup(
            name = "%s_ref_%s_files" % (name, tfm),
            srcs = files,
            visibility = ["//visibility:public"],
        )

    return _tfm_alias(
        name,
        {tfm: ":%s_ref_%s_files" % (name, tfm) for tfm in ref_tfms},
        ":%s" % lib_name,
    )

def _unsupported_frameworks_impl(ctx):
    fail(ctx.attr.message)

_unsupported_frameworks_rule = rule(
    implementation = _unsupported_frameworks_impl,
    attrs = {"message": attr.string()},
)

# This function is public because it's used by the nuget_archive repository rule.
# buildifier: disable=function-docstring
def unsupported_frameworks(name, frameworks):
    # Tagged manual: the target exists only to be reached through a `select()`,
    # and a wildcard build must not fail on a package it is not resolving.
    _unsupported_frameworks_rule(
        name = name,
        tags = ["manual"],
        message = "{} does not support the target framework being built. It provides: [{}].".format(
            native.repository_name(),
            ", ".join(sorted(frameworks)),
        ),
        visibility = ["//visibility:public"],
    )

    return ":%s" % name

# This function is public because it's used by the nuget_archive repository rule.
# buildifier: disable=function-docstring
def rid_filegroup(name, files_per_rid):
    fallback = _empty_filegroup("%s_none" % name)
    targets_by_rid = {}

    for (rid, files) in files_per_rid.items():
        native.filegroup(
            name = "%s_%s_files" % (name, rid),
            srcs = files,
            visibility = ["//visibility:public"],
        )
        targets_by_rid[rid] = ":%s_%s_files" % (name, rid)

    return native.alias(
        name = name,
        actual = _rid_chain("%s_chain" % name, targets_by_rid, fallback),
        visibility = ["//visibility:public"],
    )

def _tool_filegroup_impl(ctx):
    return [
        DotnetToolInfo(
            files_by_tfm = ctx.attr.tfms,
        ),
    ]

_tool_filegroup_rule = rule(
    implementation = _tool_filegroup_impl,
    attrs = {
        "tfms": attr.string_keyed_label_dict(
            doc = "A mapping of target frameworks to tool filegroups.",
            mandatory = True,
        ),
    },
)

# This function is public because it's used by the nuget_archive repository rule.
# buildifier: disable=function-docstring
def tool_filegroup(name, tools_by_tfm):
    for tfm, files in tools_by_tfm.items():
        native.filegroup(
            name = "%s_%s" % (name, tfm),
            srcs = files,
            visibility = ["//visibility:public"],
        )

    return _tool_filegroup_rule(
        name = name,
        tfms = {tfm: ":%s_%s" % (name, tfm) for tfm in tools_by_tfm.keys()},
    )

# Exposed so a package's targets can be produced from a fixture rather than a
# download. See `//dotnet/private/tests/nuget_resolution`.
write_repository_for_testing = _write_repository
