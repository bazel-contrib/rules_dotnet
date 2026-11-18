"""Compiles `.resx` resources and names them as MSBuild does.

Neutral resources are embedded; culture ones (`Strings.fr.resx`) go into
satellite assemblies. Cultures are recognised from `cultures.bzl`.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:common.bzl", "add_resx_resource_args", "format_ref_arg", "get_csharp_compiler_worker")
load("//dotnet/private:nuget_version.bzl", "nuget_version")
load("//dotnet/private:providers.bzl", "DotnetResxInfo")
load("//dotnet/private/icu:settings.bzl", "globalization_env", "icu_wrapper_arguments")
load("//dotnet/private/rules/common:cultures.bzl", "CULTURES")

_TASKS_ASSEMBLY = "Microsoft.Build.Tasks.Core.dll"

# The references the SDK compiles a satellite assembly against.
_SATELLITE_REFERENCES = ["mscorlib.dll", "netstandard.dll", "System.Runtime.dll"]

# Invalid identifier characters; anything else, non-ASCII included, counts as a letter.
_NOT_IDENTIFIER = " !\"#$%&'()*+,-./:;<=>?@[\\]^`{|}~"
_DIGITS = "0123456789"

def _everett_part(name):
    # MSBuild's `MakeValidEverettSubFolderIdentifier`.
    if not name:
        return name

    first = name[0]
    result = []
    if first not in _NOT_IDENTIFIER and first not in _DIGITS:
        result.append(first)
    else:
        result.append("_")
        if first in _DIGITS:
            result.append(first)

    for character in name.elems()[1:]:
        result.append("_" if character in _NOT_IDENTIFIER else character)

    return "".join(result)

def everett_identifier(directory):
    """MSBuild's `MakeValidEverettIdentifier`: `My Res/2024` -> `My_Res._2024`.

    Args:
        directory: A `/`-separated relative directory.

    Returns:
        The directory as it appears in a manifest resource name.
    """
    folders = []
    for folder in directory.split("/"):
        converted = ".".join([_everett_part(part) for part in folder.split(".")])
        folders.append("__" if converted == "_" else converted)
    return ".".join(folders)

def _split_culture(stem):
    # MSBuild's `Culture.GetItemCultureInfo`: `Strings.fr` -> ("Strings", "fr").
    (name, dot, suffix) = stem.rpartition(".")
    if dot and suffix and suffix.lower() in CULTURES:
        return (name, suffix)
    return (stem, None)

def _relative_path(file, label):
    # Like MSBuild, falls back to the file name outside the project (package).
    if file.owner != None and file.owner.repo_name != label.repo_name:
        return file.basename

    prefix = label.package + "/" if label.package else ""
    if not file.short_path.startswith(prefix):
        return file.basename

    return file.short_path[len(prefix):]

def _resource(file, path, culture, logical_name):
    """A `.resx` to compile.

    Args:
        file: The `.resx`.
        path: Its package-relative path.
        culture: A culture, `""` for neutral, or None to infer it from the name.
        logical_name: A resource name without `.resources`, or None.

    Returns:
        A struct of `file`, `culture` (None if neutral), `neutral_path` and `logical_name`.
    """
    (directory, slash, file_name) = path.rpartition("/")
    stem = file_name.rpartition(".")[0]

    if culture == None:
        (stem, culture) = _split_culture(stem)
    elif culture == "":
        culture = None
    elif stem.lower().endswith("." + culture.lower()):
        stem = stem[:-len(culture) - 1]

    return struct(
        file = file,
        culture = culture,
        neutral_path = directory + slash + stem,
        logical_name = logical_name,
    )

def _manifest_name(root_namespace, resource):
    # MSBuild's `CreateCSharpManifestResourceName`, which the F# SDK also uses.
    if resource.logical_name:
        name = resource.logical_name
    else:
        (directory, _, stem) = resource.neutral_path.rpartition("/")
        parts = [root_namespace] if root_namespace else []
        if directory:
            parts.append(everett_identifier(directory))
        parts.append(stem)
        name = ".".join(parts)

    if resource.culture:
        name = "{}.{}".format(name, resource.culture)

    return name + ".resources"

def _check_culture(culture, what):
    for character in culture.elems():
        if not (character.isalnum() or character == "-"):
            fail("{} is not a culture name: {}".format(repr(culture), what))

def split_resources(ctx):
    """Splits a target's `resources` into plain files and `.resx` files.

    Args:
        ctx: The context of a C# or F# binary, library or test.

    Returns:
        A struct of `files` and `resx` (None, or the input of `resx_compile`).
    """
    files = []
    resources = []
    data = []
    for target in ctx.attr.resources:
        if DotnetResxInfo in target:
            resources.extend(target[DotnetResxInfo].resources)
            data.append(target[DotnetResxInfo].data)
            continue

        for file in target.files.to_list():
            if file.extension.lower() == "resx":
                resources.append(_resource(file, _relative_path(file, ctx.label), None, None))
            else:
                files.append(file)

    if not resources:
        return struct(files = files, resx = None)

    # MSBuild's default `RootNamespace`.
    root_namespace = ctx.attr.root_namespace or ctx.attr.name.replace(" ", "_")

    named = []
    seen = {}
    for resource in resources:
        manifest_name = _manifest_name(root_namespace, resource)
        if manifest_name in seen:
            fail("{}: {} and {} would both be embedded as {}. Rename one, or give it a `logical_names` entry in a `resx_resource`.".format(
                ctx.label,
                seen[manifest_name].short_path,
                resource.file.short_path,
                manifest_name,
            ))
        seen[manifest_name] = resource.file
        named.append(struct(
            file = resource.file,
            culture = resource.culture,
            manifest_name = manifest_name,
        ))

    return struct(
        files = files,
        resx = struct(
            resources = named,
            data = depset(transitive = data),
            tool = ctx.attr._resx_tool,
            # Satellites are built with csc, even for F#.
            compiler_worker = get_csharp_compiler_worker(ctx),
        ),
    )

def _tasks_assembly(toolchain, label):
    for file in toolchain.msbuild_tasks.files.to_list() if toolchain.msbuild_tasks else []:
        if file.basename == _TASKS_ASSEMBLY:
            return file

    fail(
        "the resolved .NET toolchain provides no {}, so {} cannot compile its `.resx` resources.\n".format(_TASKS_ASSEMBLY, label) +
        "The SDK is expected to carry it in its own directory.",
    )

def _output_name(manifest_name):
    return "".join([c if c.isalnum() or c in "._-" else "_" for c in manifest_name.elems()])

def _satellite_attributes(culture, version):
    lines = [
        "// Generated by rules_dotnet for a satellite assembly.",
        "[assembly: System.Reflection.AssemblyCulture(\"%s\")]" % culture,
    ]
    if version:
        numeric = nuget_version.assembly_version(version)
        lines += [
            "[assembly: System.Reflection.AssemblyVersion(\"%s\")]" % numeric,
            "[assembly: System.Reflection.AssemblyFileVersion(\"%s\")]" % numeric,
            "[assembly: System.Reflection.AssemblyInformationalVersion(\"%s\")]" % version,
        ]
    return "\n".join(lines) + "\n"

def resx_compile(
        actions,
        label,
        resx,
        out_dir,
        assembly_name,
        toolchain,
        compiler_wrapper,
        references,
        framework_files,
        keyfile,
        version):
    """Compiles `.resx` resources and builds satellite assemblies.

    Args:
        actions: The rule's `ctx.actions`.
        label: The label of the target.
        resx: The `resx` of `split_resources`, or None.
        out_dir: The target's output directory, `<target>/<tfm>`.
        assembly_name: The name of the target's assembly.
        toolchain: The resolved .NET toolchain.
        compiler_wrapper: The compiler wrapper, used without a C# worker.
        references: A depset of what the target compiles against.
        framework_files: A depset of the targeting pack's reference assemblies.
        keyfile: The strong name key of the assembly, or None.
        version: The target's `version`, or "".

    Returns:
        `(File, manifest name)` pairs to embed, and the satellite assemblies.
    """
    if resx == None:
        return [], []

    tasks = _tasks_assembly(toolchain, label)

    # Non-string resources need this reference, as in MSBuild.
    extensions = [
        ref
        for ref in references.to_list()
        if ref.basename.lower() == "system.resources.extensions.dll"
    ]

    neutral = []
    cultures = {}
    requests = []
    outputs = []
    for resource in resx.resources:
        output = actions.declare_file("{}/resx/{}".format(out_dir, _output_name(resource.manifest_name)))
        outputs.append(output)
        requests.append(struct(source = resource.file.path, output = output.path))

        if resource.culture:
            # One satellite per culture, case-insensitively.
            cultures.setdefault(resource.culture.lower(), []).append((resource.culture, output, resource.manifest_name))
        else:
            neutral.append((output, resource.manifest_name))

    request = actions.declare_file("{}/resx/request.json".format(out_dir))
    actions.write(
        output = request,
        content = json.encode(struct(
            tasksAssembly = tasks.path,
            references = [ref.path for ref in extensions],
            resources = requests,
        )),
    )

    actions.run(
        mnemonic = "ResxCompile",
        progress_message = "Compiling .resx resources of %{label}",
        executable = resx.tool.files_to_run,
        arguments = [request.path],
        inputs = depset(
            direct = [request] + [resource.file for resource in resx.resources] + extensions,
            transitive = [resx.data, toolchain.msbuild_tasks.files],
        ),
        outputs = outputs,
    )

    satellites = []
    if cultures:
        satellite_references = depset([
            file
            for file in framework_files.to_list()
            if file.basename in _SATELLITE_REFERENCES
        ])
        for key in sorted(cultures.keys()):
            entries = cultures[key]
            culture = sorted([entry[0] for entry in entries])[0]
            satellites.append(_satellite_assembly(
                actions,
                culture = culture,
                resources = [(entry[1], entry[2]) for entry in entries],
                out_dir = out_dir,
                assembly_name = assembly_name,
                toolchain = toolchain,
                compiler_wrapper = compiler_wrapper,
                compiler_worker = resx.compiler_worker,
                references = satellite_references,
                keyfile = keyfile,
                version = version,
            ))

    return neutral, satellites

def _satellite_assembly(
        actions,
        culture,
        resources,
        out_dir,
        assembly_name,
        toolchain,
        compiler_wrapper,
        compiler_worker,
        references,
        keyfile,
        version):
    # The SDK's `CoreGenerateSatelliteAssemblies`.
    attributes = actions.declare_file("{}/resx/{}/{}.resources.cs".format(out_dir, culture, assembly_name))
    actions.write(output = attributes, content = _satellite_attributes(culture, version))

    satellite = actions.declare_file("{}/{}/{}.resources.dll".format(out_dir, culture, assembly_name))

    args = actions.args()
    args.add("/nostdlib+")
    args.add("/utf8output")
    args.add("/deterministic+")
    args.add("/filealign:512")
    args.add("/nologo")
    args.add("/target:library")
    args.add(satellite, format = "/out:\"%s\"")
    format_ref_arg(args, references, quote = True)
    add_resx_resource_args(args, resources, "csharp")
    if keyfile != None:
        args.add(keyfile, format = "/keyfile:\"%s\"")
    args.add(attributes, format = "\"%s\"")
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    icu_arguments, icu_tools = [], []
    if compiler_worker:
        executable = compiler_worker.executable
        extra_tools = []
        execution_requirements = {
            "requires-worker-protocol": "json",
            "supports-path-mapping": "1",
            "supports-workers": "1",
        }
    else:
        executable = compiler_wrapper
        extra_tools = [compiler_wrapper]
        execution_requirements = {"supports-path-mapping": "1"}
        icu_arguments, icu_tools = icu_wrapper_arguments(actions, toolchain)

    actions.run(
        mnemonic = "ResxSatellite",
        progress_message = "Building the %s satellite assembly of %%{label}" % culture,
        executable = executable,
        arguments = icu_arguments + [
            toolchain.compiler_host.files_to_run.executable.path,
            toolchain.csharp_compiler.files_to_run.executable.path,
            args,
        ],
        inputs = depset(
            direct = [attributes] + [file for (file, _) in resources] + ([keyfile] if keyfile else []),
            transitive = [references],
        ),
        tools = depset(
            direct = extra_tools + [
                toolchain.compiler_host.files_to_run.executable,
                toolchain.csharp_compiler.files_to_run.executable,
            ],
            transitive = icu_tools + [
                toolchain.compiler_host.default_runfiles.files,
                toolchain.csharp_compiler.default_runfiles.files,
            ],
        ),
        outputs = [satellite],
        env = dicts.add(
            {"DOTNET_CLI_HOME": toolchain.compiler_host.files_to_run.executable.dirname},
            globalization_env(toolchain),
        ),
        execution_requirements = execution_requirements,
    )

    return satellite

def _resx_resource_impl(ctx):
    sources = {_relative_path(src, ctx.label): src for src in ctx.files.srcs}

    for path, culture in ctx.attr.cultures.items():
        if path not in sources:
            fail("{}: `cultures` names {}, which is not in `srcs`.".format(ctx.label, path))
        if culture:
            _check_culture(culture, "`cultures` of {}".format(ctx.label))

    resources = [
        _resource(src, path, ctx.attr.cultures.get(path), None)
        for path, src in sources.items()
    ]

    # Cultures take their neutral resource's logical name.
    logical_names = {}
    names = {}
    for path, logical_name in ctx.attr.logical_names.items():
        if path not in sources:
            fail("{}: `logical_names` names {}, which is not in `srcs`.".format(ctx.label, path))
        if logical_name.endswith(".resources"):
            fail("{}: the `logical_names` entry {} ends in `.resources`, which is added to it.".format(ctx.label, logical_name))
        resource = [r for r in resources if r.file == sources[path]][0]
        if resource.culture:
            fail("{}: `logical_names` names {}, which is a {} resource. Name the neutral resource it translates, whose name it takes.".format(ctx.label, path, resource.culture))
        if logical_name in names:
            fail("{}: {} and {} have the same logical name, {}.".format(ctx.label, names[logical_name], path, logical_name))
        names[logical_name] = path
        logical_names[resource.neutral_path] = logical_name

    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        DotnetResxInfo(
            resources = [
                struct(
                    file = r.file,
                    culture = r.culture,
                    neutral_path = r.neutral_path,
                    logical_name = logical_names.get(r.neutral_path),
                )
                for r in resources
            ],
            data = depset(ctx.files.data),
        ),
    ]

resx_resource = rule(
    implementation = _resx_resource_impl,
    doc = """Sets a logical name or culture on `.resx` files, or gives them the files they reference.

Pass it in `resources`. Paths are relative to this package.

```starlark
resx_resource(
    name = "messages",
    srcs = ["Messages.resx", "Messages.fr.resx"],
    logical_names = {"Messages.resx": "MyApp.Messages"},
)
```
""",
    attrs = {
        "srcs": attr.label_list(
            doc = "The `.resx` files.",
            allow_files = [".resx"],
            mandatory = True,
            allow_empty = False,
        ),
        "data": attr.label_list(
            doc = "Files referenced by `ResXFileRef` entries, relative to the `.resx`.",
            allow_files = True,
        ),
        "logical_names": attr.string_dict(
            doc = "Neutral `.resx` to the `ResourceManager` base name to use. Its cultures follow it.",
        ),
        "cultures": attr.string_dict(
            doc = "`.resx` to its culture, or `\"\"` for neutral. Overrides the culture in the file name.",
        ),
    },
)
