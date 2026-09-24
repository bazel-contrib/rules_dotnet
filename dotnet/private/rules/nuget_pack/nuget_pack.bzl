"""Builds a NuGet package from a library, or a .NET tool package from a binary."""

load(
    "//dotnet/private:common.bzl",
    "generate_depsjson",
    "generate_runtimeconfig",
    "is_core_framework",
)
load("//dotnet/private:nuget_version.bzl", "nuget_version")
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
    "DotnetBinaryInfo",
    "NuGetPackInfo",
    "StaticWebAssetsInfo",
)
load(
    "//dotnet/private/rules/common:publish_layout.bzl",
    "collect_assembly_files",
    "reject_conflicting_paths",
)
load("//dotnet/private/transitions:default_transition.bzl", "default_transition")
load(
    ":layout.bzl",
    "FIRST_PARTY_DEPS",
    "FIRST_PARTY_REFERENCE",
    "STATIC_WEB_ASSETS_PROPS",
    "analyzer_layout",
    "content_files_layout",
    "dependency_group",
    "extra_files_layout",
    "framework_reference_group",
    "index_dep_packages",
    "is_analyzer",
    "is_valid_package_id",
    "library_layout",
    "plan_library_contents",
    "static_web_assets_layout",
    "static_web_assets_props",
    "tool_directory",
    "tool_layout",
)
load(":transitions.bzl", "nuget_pack_transition", "parse_split_key", "split_key")

_SYMBOLS = ["none", "embedded", "snupkg"]
_CONTENT_BUILD_ACTIONS = ["Content", "None", "EmbeddedResource", "Compile"]
_ROLL_FORWARD_BEHAVIORS = ["Minor", "Major", "LatestPatch", "LatestMinor", "LatestMajor", "Disable"]
_DOTNET_TOOL_PACKAGE_TYPE = "DotnetTool"

def _fail_wrong_framework(label, target_label, tfm, builds):
    """Reports that the packed target does not build `tfm`, but `builds` instead."""
    fail(("{}: asks {} for {}, but that target builds {}: the highest of its target_frameworks " +
          "that {} can use. Add {} to its target_frameworks, or drop it from this package's.").format(
        label,
        target_label,
        tfm,
        builds,
        tfm,
        tfm,
    ))

def _split_targets(ctx):
    """The configured targets to pack, keyed by split, and whether they make a tool."""
    has_library = bool(ctx.attr.library)
    has_binary = bool(ctx.attr.binary)

    if has_library == has_binary:
        fail("{}: set exactly one of `library` (a package) or `binary` (a .NET tool package)".format(ctx.label))

    packed = ctx.attr.binary if has_binary else ctx.attr.library
    split = ctx.split_attr.binary if has_binary else ctx.split_attr.library
    targets = {key: target for (key, target) in split.items() if target != None}

    # Two branches of the split that end up in the same configuration are one
    # dependency to Bazel, and only one of their keys survives. That happens
    # when the target does not build a requested framework and its own
    # transition falls back to the same lower one for both, so a missing key
    # means a framework the target does not build.
    for tfm in ctx.attr.target_frameworks:
        for rid in ctx.attr.runtime_identifiers or [None]:
            if split_key(tfm, rid) not in targets:
                _fail_wrong_framework(
                    ctx.label,
                    packed[0].label,
                    tfm,
                    "the same assembly for it as for another framework of this package",
                )

    return (has_binary, targets)

def _check_attrs(ctx, is_tool):
    if ctx.attr.version and ctx.file.version_file:
        fail("{}: set `version` or `version_file`, not both".format(ctx.label))

    if ctx.attr.license_expression and ctx.file.license_file:
        fail("{}: set `license_expression` or `license_file`, not both".format(ctx.label))

    if is_tool:
        if ctx.attr.runtime_identifiers:
            fail("{}: a tool package is not RID-specific; drop `runtime_identifiers`".format(ctx.label))
        if ctx.attr.deps:
            fail("{}: a tool package ships its whole closure and depends on nothing; drop `deps`".format(ctx.label))
    elif ctx.attr.command_name:
        fail("{}: `command_name` names a tool's command; it needs `binary`".format(ctx.label))

def _check_built_framework(ctx, target, compile_info, tfm):
    built = compile_info.target_framework

    if built == None:
        fail(("{}: {} is an imported assembly. `nuget_pack` packs a csharp_library, " +
              "fsharp_library, csharp_binary or fsharp_binary.").format(ctx.label, target.label))

    if built != tfm:
        _fail_wrong_framework(ctx.label, target.label, tfm, "{} for it".format(built))

def _pack_tool(ctx, tfm, target, compile_info, runtime_info):
    """The files of a tool package for one framework, and where they go."""
    if not is_core_framework(tfm):
        fail("{}: a .NET tool runs on .NET; {} is not a .NET framework".format(ctx.label, tfm))

    binary_info = target[DotnetBinaryInfo]
    transitive = binary_info.transitive_runtime_deps
    name = runtime_info.name

    # The binary's own deps.json and runtimeconfig.json describe the runfiles
    # tree it runs from under Bazel. A tool runs from its package folder, so it
    # gets the ones a publish would.
    depsjson_struct = generate_depsjson(
        ctx,
        target_framework = tfm,
        is_self_contained = False,
        target_assembly_runtime_info = runtime_info,
        transitive_runtime_deps = transitive,
    )
    depsjson = ctx.actions.declare_file("{}/{}/{}.deps.json".format(ctx.label.name, tfm, name))
    ctx.actions.write(depsjson, json.encode(depsjson_struct))

    runtimeconfig = ctx.actions.declare_file("{}/{}/{}.runtimeconfig.json".format(ctx.label.name, tfm, name))
    ctx.actions.write(runtimeconfig, json.encode(generate_runtimeconfig(
        target_framework = tfm,
        project_sdk = compile_info.project_sdk,
        is_self_contained = False,
        roll_forward_behavior = ctx.attr.roll_forward_behavior,
    )))

    assembly_files = collect_assembly_files(runtime_info, transitive, depsjson_struct)

    return tool_layout(
        tfm,
        binary_info,
        runtime_info,
        assembly_files,
        binary_info.runtime_pack_info.runtime_identifier,
        depsjson,
        runtimeconfig,
    )

def _pack_static_web_assets(ctx, target, assembly_name, package_id, copied_names):
    """The files a Razor class library serves, and the props file pointing at them.

    Every framework the package ships serves the same files, so they are taken
    from one split of the packed library: a second copy of them would only
    collide with the first.

    Args:
      ctx: The rule context.
      target: One configured packed library.
      assembly_name: Its assembly name, which prefixes its own served files.
      package_id: The package id, which prefixes them once they are in a package.
      copied_names: The names of the assemblies copied into this package.

    Returns:
      A list of `(path, File)` pairs, empty when the library serves nothing.
    """
    if StaticWebAssetsInfo not in target:
        return []

    layout = static_web_assets_layout(target[StaticWebAssetsInfo], assembly_name, copied_names, ctx.label)
    if not layout.files:
        return []

    # A library serves its files under its assembly name here and under the
    # package id everywhere else, so a component asking for `_content/<name>`
    # would come up empty once the package is installed.
    if package_id != assembly_name:
        fail(("{}: {} serves files under `_content/{}`, but out of a package they are served " +
              "under `_content/{}`, the package id. Set `package_id` to \"{}\", or `out` on " +
              "that library to \"{}\".").format(
            ctx.label,
            target.label,
            assembly_name,
            package_id,
            assembly_name,
            package_id,
        ))

    props = ctx.actions.declare_file("{}/{}".format(ctx.label.name, STATIC_WEB_ASSETS_PROPS))
    ctx.actions.write(props, static_web_assets_props(package_id, layout.paths))

    return layout.files + [(STATIC_WEB_ASSETS_PROPS, props)]

def _metadata(ctx, package_id, version):
    license = None
    if ctx.attr.license_expression:
        license = struct(type = "expression", value = ctx.attr.license_expression)
    elif ctx.file.license_file:
        license = struct(type = "file", value = ctx.file.license_file.basename)

    repository = None
    if ctx.attr.repository_url:
        repository = struct(
            type = ctx.attr.repository_type,
            url = ctx.attr.repository_url,
            branch = ctx.attr.repository_branch or None,
            commit = ctx.attr.repository_commit or None,
        )

    return struct(
        id = package_id,
        version = version or "",
        authors = ctx.attr.authors,
        description = ctx.attr.description,
        title = ctx.attr.title or None,
        copyright = ctx.attr.copyright or None,
        projectUrl = ctx.attr.project_url or None,
        releaseNotes = ctx.attr.release_notes or None,
        tags = ctx.attr.package_tags,
        requireLicenseAcceptance = ctx.attr.require_license_acceptance,
        developmentDependency = ctx.attr.development_dependency,
        license = license,
        icon = ctx.file.icon.basename if ctx.file.icon else None,
        readme = ctx.file.readme.basename if ctx.file.readme else None,
        repository = repository,
        minClientVersion = ctx.attr.min_client_version or None,
    )

def _nuget_pack_impl(ctx):
    (is_tool, split) = _split_targets(ctx)
    _check_attrs(ctx, is_tool)

    keys = sorted(split.keys())
    packs_analyzer = not is_tool and is_analyzer(split[keys[0]][DotnetAssemblyCompileInfo])
    if packs_analyzer and ctx.attr.runtime_identifiers:
        fail("{}: an analyzer runs inside the compiler, not on a runtime; drop `runtime_identifiers`".format(ctx.label))

    dep_packages = [dep[NuGetPackInfo] for dep in ctx.attr.deps]
    packages_by_assembly = index_dep_packages(dep_packages, ctx.attr.target_frameworks, ctx.label)

    entries = []
    symbol_entries = []
    groups = {}
    framework_references = []
    copied_names = {}
    tool_directories = []
    identity = None

    for key in keys:
        (tfm, rid) = parse_split_key(key)
        target = split[key]
        compile_info = target[DotnetAssemblyCompileInfo]
        runtime_info = target[DotnetAssemblyRuntimeInfo]

        _check_built_framework(ctx, target, compile_info, tfm)

        if not runtime_info.libs and not packs_analyzer:
            fail("{}: {} builds no assembly to ship".format(ctx.label, target.label))

        if identity == None:
            identity = struct(
                name = runtime_info.name,
                version = runtime_info.version,
                dll = runtime_info.libs[0].basename if runtime_info.libs else None,
            )
        elif identity.name != runtime_info.name or identity.version != runtime_info.version:
            fail(("{}: {} is {} {} for {} but {} {} for another framework; a package has " +
                  "one id and one version").format(ctx.label, target.label, runtime_info.name, runtime_info.version, tfm, identity.name, identity.version))

        if is_tool:
            entries += _pack_tool(ctx, tfm, target, compile_info, runtime_info)
            tool_directories.append(tool_directory(tfm))
            groups[tfm] = dependency_group(tfm, [])
            continue

        # The parts shared by every runtime identifier of a framework come from
        # its first split, and every later split must agree with it.
        first_of_tfm = tfm not in groups

        plan = plan_library_contents(runtime_info, packages_by_assembly, dep_packages, ctx.attr.first_party_deps, ctx.label)

        if packs_analyzer:
            # Nothing resolves to an analyzer, so `plan` contributes only the
            # packages listed in `deps`.
            layout = analyzer_layout(compile_info, runtime_info, ctx.attr.symbols)
        else:
            layout = library_layout(
                tfm,
                rid,
                compile_info,
                runtime_info,
                plan.bundled,
                ctx.attr.symbols,
                ctx.attr.reference_assemblies,
                emit_portable = first_of_tfm,
            )

        entries += layout.files
        symbol_entries += layout.symbol_files

        group = dependency_group(tfm, plan.dependencies)
        if first_of_tfm:
            groups[tfm] = group
            references = framework_reference_group(tfm, compile_info.project_sdk)
            if references != None:
                framework_references.append(references)
        elif groups[tfm] != group:
            fail(("{}: the dependencies of {} differ between runtime identifiers for {}; " +
                  "NuGet declares dependencies per framework, not per runtime identifier").format(ctx.label, target.label, tfm))

        for info in plan.bundled:
            copied_names[info.name] = True

    package_id = ctx.attr.package_id or identity.name
    if not is_valid_package_id(package_id):
        fail(("{}: \"{}\" is not a valid package id: letters, digits and `_`, separated by " +
              "single `.`, `-` or `_`, at most 100 characters.{}").format(
            ctx.label,
            package_id,
            "" if ctx.attr.package_id else " It is the assembly name; set `package_id`.",
        ))

    if not is_tool and not packs_analyzer:
        entries += _pack_static_web_assets(ctx, split[keys[0]], identity.name, package_id, sorted(copied_names.keys()))

    entries += extra_files_layout(ctx.attr.files, ctx.label)
    content = content_files_layout(ctx.attr.content_files, ctx.label)
    entries += content.entries

    for file in [ctx.file.readme, ctx.file.icon, ctx.file.license_file]:
        if file:
            entries.append((file.basename, file))

    reject_conflicting_paths(entries, ctx.label, what = "packed")

    # The same file under the same path more than once is one entry.
    by_path = {}
    for (path, file) in entries:
        by_path.setdefault(path, file)
    entries = sorted(by_path.items(), key = lambda entry: entry[0])
    symbol_entries = sorted(symbol_entries, key = lambda entry: entry[0])

    if ctx.file.version_file:
        version = None
        normalized = None
        stem = ctx.label.name
    else:
        version = ctx.attr.version or identity.version
        normalized = nuget_version.normalize(version)
        stem = "{}.{}".format(package_id, normalized)

    nupkg = ctx.actions.declare_file("{}/{}.nupkg".format(ctx.label.name, stem))
    nuspec = ctx.actions.declare_file("{}/{}.nuspec".format(ctx.label.name, stem))
    snupkg = ctx.actions.declare_file("{}/{}.snupkg".format(ctx.label.name, stem)) if ctx.attr.symbols == "snupkg" else None
    symbol_packages = [snupkg] if snupkg else []

    tool_settings = None
    if is_tool:
        tool_settings = struct(
            commandName = ctx.attr.command_name or identity.name,
            entryPoint = identity.dll,
            directories = tool_directories,
        )

    request = ctx.actions.declare_file("{}/nuget_pack_request.json".format(ctx.label.name))
    ctx.actions.write(request, json.encode(struct(
        output = nupkg.path,
        nuspecOutput = nuspec.path,
        symbolsOutput = snupkg.path if snupkg else None,
        versionFile = ctx.file.version_file.path if ctx.file.version_file else None,
        metadata = _metadata(ctx, package_id, version),
        packageTypes = [_DOTNET_TOOL_PACKAGE_TYPE] if is_tool else [],
        dependencyGroups = [groups[tfm] for tfm in sorted(groups.keys())],
        frameworkReferenceGroups = framework_references,
        contentFiles = [
            struct(
                include = include,
                buildAction = ctx.attr.content_files_build_action,
                copyToOutput = ctx.attr.content_files_copy_to_output,
                flatten = ctx.attr.content_files_flatten,
            )
            for include in content.includes
        ],
        files = [struct(source = file.path, target = path) for (path, file) in entries],
        symbolFiles = [struct(source = file.path, target = path) for (path, file) in symbol_entries],
        toolSettings = tool_settings,
    )))

    version_files = [pack.version_file for pack in dep_packages if pack.version_file]
    if ctx.file.version_file:
        version_files.append(ctx.file.version_file)

    ctx.actions.run(
        mnemonic = "NuGetPack",
        progress_message = "Packing NuGet package %{label}",
        executable = ctx.attr._packer[DefaultInfo].files_to_run,
        arguments = [request.path],
        inputs = depset([request] + version_files + [file for (_, file) in entries + symbol_entries]),
        outputs = [nupkg, nuspec] + symbol_packages,
    )

    return [
        DefaultInfo(files = depset([nupkg] + symbol_packages)),
        OutputGroupInfo(nuspec = depset([nuspec])),
        NuGetPackInfo(
            label = ctx.label,
            package_id = package_id,
            version = normalized,
            version_file = ctx.file.version_file,
            nupkg = nupkg,
            snupkg = snupkg,
            target_frameworks = sorted(groups.keys()),
            bundled_assemblies = [] if is_tool else sorted([identity.name] + copied_names.keys()),
            is_tool = is_tool,
        ),
    ]

nuget_pack = rule(
    _nuget_pack_impl,
    doc = """Builds a NuGet package.

From a `library`, a package with the assembly under `lib/<tfm>/` for every
framework in `target_frameworks`, its reference assembly under `ref/<tfm>/`,
its documentation, and a dependency group per framework. From a `binary`, a
.NET tool package (`dotnet tool install`) with the binary's framework-dependent
publish under `tools/<tfm>/any/`.

A library built with `is_analyzer` packs as an analyzer package instead:
nothing goes under `lib/`, and the analyzer and the assemblies it loads go
under `analyzers/dotnet/`, in the language folder below it when it is
language-specific. A Razor class library ships the files it serves under
`staticwebassets/`, with the MSBuild file that points a consuming project at
them.

The package is `<name>/<package_id>.<version>.nupkg`, deterministic for the
same inputs, and `nuget_push` publishes it. The manifest it carries is also
written on its own, in the `nuspec` output group.

What a dependency of the library becomes:

  * a NuGet package is declared as a dependency;
  * an assembly shipped by a package in `deps` is declared as a dependency on
    that package;
  * any other library built in this workspace follows `first_party_deps`.

An analyzer resolves none of these: the assemblies the compiler was handed
travel with it, so only the packages listed in `deps` are declared.
""",
    attrs = {
        "library": attr.label(
            doc = """The library to pack: a package, or an analyzer package when the
            library sets `is_analyzer`. Set this or `binary`.""",
            providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo],
            cfg = nuget_pack_transition,
        ),
        "binary": attr.label(
            doc = "The binary to pack as a .NET tool. Set this or `library`.",
            providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo, DotnetBinaryInfo],
            cfg = nuget_pack_transition,
        ),
        "target_frameworks": attr.string_list(
            doc = """The frameworks the package ships. Each must be one the packed
            target lists in its own `target_frameworks`.""",
            mandatory = True,
            allow_empty = False,
        ),
        "runtime_identifiers": attr.string_list(
            doc = """Makes the package RID-specific: the library is built once per
            runtime identifier and shipped under `runtimes/<rid>/lib/<tfm>/`, with one
            reference assembly under `ref/<tfm>/` to compile against. Native libraries of
            the library and of the assemblies bundled with it go under
            `runtimes/<rid>/native/`. Each runtime identifier builds the library's whole
            dependency graph again, so use this only when the assembly differs per
            runtime identifier.""",
        ),
        "deps": attr.label_list(
            doc = """Other `nuget_pack` targets. A dependency on an assembly one of them
            ships is declared as a dependency on that package, and every listed package
            is declared as a dependency.""",
            providers = [NuGetPackInfo],
        ),
        "first_party_deps": attr.string(
            doc = """What becomes of a dependency built in this workspace that no package
            in `deps` ships. `reference` declares a dependency on a package named after
            the assembly, with the assembly's version, which is what a `nuget_pack` of
            it defaults to: a workspace that publishes every library as its own package
            needs no `deps`. `bundle` copies the assembly into this package and does the
            same for its dependencies. `error` fails, so that every such dependency has
            to be listed in `deps`.""",
            default = FIRST_PARTY_REFERENCE,
            values = FIRST_PARTY_DEPS,
        ),
        "package_id": attr.string(
            doc = "The package id. Defaults to the assembly name.",
        ),
        "version": attr.string(
            doc = "The package version. Defaults to the packed target's `version`.",
        ),
        "version_file": attr.label(
            doc = """A file whose first non-empty line is the package version, read when
            the package is built, for versions that come from a stamp. The package is then
            `<name>/<name>.nupkg`, as its version is not known until it is built. The
            packed assemblies keep the version they were compiled with.""",
            allow_single_file = True,
            cfg = default_transition,
        ),
        "authors": attr.string_list(
            doc = "The package authors.",
            mandatory = True,
            allow_empty = False,
        ),
        "description": attr.string(
            doc = "A description of the package.",
            mandatory = True,
        ),
        "title": attr.string(doc = "A human-friendly title."),
        "copyright": attr.string(doc = "Copyright details."),
        "project_url": attr.string(doc = "The URL of the project's home page."),
        "release_notes": attr.string(doc = "Release notes for this version."),
        "package_tags": attr.string_list(doc = "Tags for the package, for feeds to search by."),
        "license_expression": attr.string(
            doc = "An SPDX license expression, such as `MIT` or `Apache-2.0`. Set this or `license_file`.",
        ),
        "license_file": attr.label(
            doc = "A license file, packed at the root. Set this or `license_expression`.",
            allow_single_file = True,
            cfg = default_transition,
        ),
        "readme": attr.label(
            doc = "A Markdown readme, packed at the root.",
            allow_single_file = [".md"],
            cfg = default_transition,
        ),
        "icon": attr.label(
            doc = "An icon, packed at the root. PNG or JPEG, ideally 128x128.",
            allow_single_file = [".png", ".jpg", ".jpeg"],
            cfg = default_transition,
        ),
        "repository_type": attr.string(
            doc = "The kind of repository `repository_url` points at.",
            default = "git",
        ),
        "repository_url": attr.string(doc = "The URL of the source repository."),
        "repository_branch": attr.string(doc = "The branch the package was built from."),
        "repository_commit": attr.string(doc = "The commit the package was built from."),
        "require_license_acceptance": attr.bool(
            doc = "Whether a consumer has to accept the license before installing.",
            default = False,
        ),
        "development_dependency": attr.bool(
            doc = "Marks a package that is only needed at development time, such as an analyzer.",
            default = False,
        ),
        "min_client_version": attr.string(doc = "The lowest NuGet client version that can install the package."),
        "files": attr.label_keyed_string_dict(
            doc = """Further files, keyed by target and valued by their path in the package.
            A path ending in `/` is a folder that every file of the target goes into by
            name; otherwise the target has to be one file, which takes that path. Use this
            for `build/<tfm>/<package_id>.props`, `buildTransitive/`, and the like. An
            analyzer that needs an assembly out of a NuGet package ships it this way,
            under `analyzers/dotnet/cs/`.""",
            allow_files = True,
            cfg = default_transition,
        ),
        "content_files": attr.label_keyed_string_dict(
            doc = """Files a consuming project gets, keyed by target and valued by their
            path under `contentFiles/`, which is `<language>/<framework>/<path>`, such as
            `any/any/settings.json`. The path may end in `/` like in `files`. The
            `content_files_*` attributes say what a consumer does with them.""",
            allow_files = True,
            cfg = default_transition,
        ),
        "content_files_build_action": attr.string(
            doc = "The build action a consuming project gives the content files.",
            default = "Content",
            values = _CONTENT_BUILD_ACTIONS,
        ),
        "content_files_copy_to_output": attr.bool(
            doc = "Whether a consuming project copies the content files to its output.",
            default = False,
        ),
        "content_files_flatten": attr.bool(
            doc = "Whether copied content files lose their folders.",
            default = False,
        ),
        "symbols": attr.string(
            doc = """Where the symbols go: nowhere, `embedded` beside the assemblies in the
            package, or into a `.snupkg` symbol package next to the package, which
            `nuget_push` publishes along with it.""",
            default = "none",
            values = _SYMBOLS,
        ),
        "reference_assemblies": attr.bool(
            doc = """Whether to ship the reference assembly under `ref/<tfm>/`, so that
            consumers compile against the public surface alone. Always on for a
            RID-specific package, which has nothing under `lib/` to compile against.""",
            default = True,
        ),
        "command_name": attr.string(
            doc = "The command a tool package installs. Defaults to the assembly name. Only with `binary`.",
        ),
        "roll_forward_behavior": attr.string(
            doc = "The roll-forward policy of a tool package's runtime configuration.",
            default = "Major",
            values = _ROLL_FORWARD_BEHAVIORS,
        ),
        "_packer": attr.label(
            doc = "Writes the package.",
            default = "//dotnet/private/tools/nuget_pack",
            executable = True,
            cfg = "exec",
        ),
    },
)
