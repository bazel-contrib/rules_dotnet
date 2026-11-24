"""The output directory of a .NET Framework application.

The CLR only loads assemblies from the GAC or from beside the executable, so
dependencies are staged next to it, as MSBuild's copy-local does.
"""

def netfx_supported_runtime(target_framework):
    """The `<supportedRuntime>` a .NET Framework application asks for.

    Args:
        target_framework: A .NET Framework target framework, such as `net48`.

    Returns:
        A `(version, sku)` pair. The CLR 2.0 frameworks have no SKU.
    """
    digits = target_framework.removeprefix("net")
    if digits in ["20", "30", "35"]:
        return ("v2.0.50727", None)

    return ("v4.0", ".NETFramework,Version=v" + ".".join(digits.elems()))

def satellite_path(file):
    """The path of a satellite assembly in an application directory: `<culture>/<name>`.

    Args:
        file: The satellite assembly, in a directory named after its culture.

    Returns:
        Its path relative to the application's directory.
    """
    return "{}/{}".format(file.dirname.split("/")[-1], file.basename)

def _stem(basename):
    return basename.rsplit(".", 1)[0].lower()

_SATELLITE_SUFFIX = ".resources.dll"

def _add(groups, path, candidate):
    """Adds a candidate for `path`, once per distinct source file."""
    group = groups.setdefault(path.lower(), struct(path = path, candidates = [], sources = {}))
    if candidate.file.path not in group.sources:
        group.sources[candidate.file.path] = True
        group.candidates.append(candidate)

def _candidate(file, owner, pdb = None, satellites = {}):
    return struct(file = file, owner = owner, pdb = pdb, satellites = satellites)

def _collect_candidates(transitive_runtime_deps):
    """Groups the dependencies' files by the path each would take beside the executable.

    Returns:
        A struct of `libs`, `orphan_satellites` (satellite assemblies without
        an assembly of their name, e.g. a language pack's) and `natives`, each
        a dict of lower-cased path to a struct of the `path` and the
        `candidates` for it, in dependency order.
    """
    libs = {}
    orphan_satellites = {}
    natives = {}
    for dep in transitive_runtime_deps:
        pdbs = {_stem(pdb.basename): pdb for pdb in dep.pdbs}

        # Satellite assemblies go with the assembly of their name.
        satellites = {}
        for resource in dep.resource_assemblies:
            stem = resource.basename[:-len(_SATELLITE_SUFFIX)].lower() if resource.basename.lower().endswith(_SATELLITE_SUFFIX) else None
            satellites.setdefault(stem, {})[satellite_path(resource).lower()] = resource

        for lib in dep.libs:
            stem = _stem(lib.basename)
            _add(libs, lib.basename, _candidate(lib, dep.name, pdbs.get(stem), satellites.pop(stem, {})))

        for orphans in satellites.values():
            for resource in orphans.values():
                _add(orphan_satellites, satellite_path(resource), _candidate(resource, dep.name))

        for native in dep.native:
            _add(natives, native.basename, _candidate(native, dep.name))

    return struct(libs = libs, orphan_satellites = orphan_satellites, natives = natives)

def _claim(state, path, owner):
    """Takes `path` in the output directory for `owner`, failing if something else has it."""
    previous = state.taken.get(path.lower())
    if previous != None:
        fail(("{}: {} would be staged as {} next to the executable, but that is already {}. " +
              ".NET Framework loads assemblies from the executable's own directory, so only " +
              "one file can take that name.").format(state.ctx.label, owner, path, previous))
    state.taken[path.lower()] = owner

def _stage(state, path, source, publish = True):
    """Symlinks `source` into the output directory at `path`."""
    staged = state.ctx.actions.declare_file("{}/{}".format(state.out_dir, path))
    state.ctx.actions.symlink(output = staged, target_file = source)
    state.files.append(staged)
    if publish:
        state.publish_layout.append((path, source))

def _declare_selected(state, path, declare):
    output = declare("{}/{}".format(state.out_dir, path))
    state.selected.append(output)
    state.files.append(output)
    return output

def _select(state, kind, group, pdb_path, satellite_paths):
    """Has netfx_config copy the highest version of `group`, with its PDB and satellite assemblies.

    The chosen copy is only known when the action runs, so its satellite
    assemblies go in `<culture>/<name>.resources/` directories, which .NET
    Framework also probes. A culture the chosen copy lacks stays empty.
    """
    declare_file = state.ctx.actions.declare_file
    output = _declare_selected(state, group.path, declare_file)
    pdb_output = _declare_selected(state, pdb_path, declare_file) if pdb_path else None
    satellite_directories = [path.removesuffix(".dll") for path in satellite_paths]
    satellite_outputs = [
        _declare_selected(state, path, state.ctx.actions.declare_directory)
        for path in satellite_directories
    ]

    args = state.args
    args.add_all(["--select", kind, output, pdb_output or "-", str(len(satellite_outputs))])
    args.add_all(satellite_outputs, expand_directories = False)
    args.add(str(len(group.candidates)))
    for candidate in group.candidates:
        satellites = [candidate.satellites.get(path.lower()) for path in satellite_paths]
        args.add_all([candidate.file, candidate.pdb or "-"] + [satellite or "-" for satellite in satellites])
        state.inputs.extend([candidate.file] + [satellite for satellite in satellites if satellite])
        if candidate.pdb:
            state.inputs.append(candidate.pdb)

    state.publish_layout.append((group.path, output))
    state.publish_layout.extend(zip(satellite_directories, satellite_outputs))

def _pdb_path(taken, group):
    """Where the PDB of `group` goes, or None unless every copy has one."""
    if not all([candidate.pdb for candidate in group.candidates]):
        return None

    path = group.candidates[0].pdb.basename
    if path.lower() in taken:
        return None

    taken[path.lower()] = "the PDB of `{}`".format(group.candidates[0].owner)
    return path

def _stage_libs(state, libs):
    """Stages each assembly with its PDB and satellite assemblies.

    Returns:
        The lower-cased paths of the satellite assemblies staged with an assembly.
    """
    with_assembly = {}
    for group in libs.values():
        owner = group.candidates[0].owner
        _claim(state, group.path, "the assembly {} of `{}`".format(group.path, owner))
        pdb_path = _pdb_path(state.taken, group)

        # Every culture any copy has.
        satellite_paths = {}
        for candidate in group.candidates:
            for satellite in candidate.satellites.values():
                satellite_paths.setdefault(satellite_path(satellite).lower(), satellite_path(satellite))
        for path in satellite_paths.values():
            _claim(state, path, "the satellite assembly {} of `{}`".format(path, owner))
            with_assembly[path.lower()] = True

        if len(group.candidates) == 1:
            candidate = group.candidates[0]
            _stage(state, group.path, candidate.file)
            state.shipped.append(candidate.file)
            if pdb_path:
                _stage(state, pdb_path, candidate.pdb, publish = False)
            for satellite in candidate.satellites.values():
                _stage(state, satellite_path(satellite), satellite)
        else:
            for path in satellite_paths.values():
                _claim(state, path.removesuffix(".dll"), "the satellite assemblies of `{}`".format(owner))
            _select(state, "lib", group, pdb_path, satellite_paths.values())

    return with_assembly

def _stage_orphan_satellites(state, orphan_satellites, with_assembly):
    for group in orphan_satellites.values():
        # The assembly's own satellite wins, as it matches its version.
        if group.path.lower() in with_assembly:
            continue

        _claim(state, group.path, "the satellite assembly {} of `{}`".format(group.path, group.candidates[0].owner))
        if len(group.candidates) == 1:
            _stage(state, group.path, group.candidates[0].file)
        else:
            _select(state, "resource", group, None, [])

def _stage_natives(state, natives):
    for group in natives.values():
        if len(group.candidates) > 1:
            fail(("{}: `{}` and `{}` both ship a native library named {}, from {} and {}. " +
                  ".NET Framework loads native libraries from beside the executable, so only " +
                  "one of them can be there.").format(
                state.ctx.label,
                group.candidates[0].owner,
                group.candidates[1].owner,
                group.path,
                group.candidates[0].file.short_path,
                group.candidates[1].file.short_path,
            ))

        candidate = group.candidates[0]
        _claim(state, group.path, "the native library {} of `{}`".format(group.path, candidate.owner))
        _stage(state, group.path, candidate.file)

def _write_config(state, config_name, executable, target_framework, app_config, binding_redirects_against):
    """Runs netfx_config, which writes `<exe>.config` and the copies `_select` asked for.

    Args:
        state: The staging state.
        config_name: The name of the configuration file.
        executable: The application's `.exe`.
        target_framework: The .NET Framework target framework.
        app_config: The user's `App.config`, or None.
        binding_redirects_against: The framework's reference assemblies the
            application also ships, or None to write no binding redirects.
    """
    args = state.args
    config = state.ctx.actions.declare_file("{}/{}".format(state.out_dir, config_name))
    args.add("--output", config)

    if app_config:
        args.add("--app-config", app_config)
        state.inputs.append(app_config)

    (runtime_version, sku) = netfx_supported_runtime(target_framework)
    args.add_all(["--supported-runtime", runtime_version, sku or "-"])

    # Binding redirects follow the assembly references of the executable and
    # of what ships beside it.
    if binding_redirects_against == None:
        args.add("--no-binding-redirects")
    else:
        args.add("--main", executable)
        args.add_all(state.shipped, before_each = "--assembly")
        args.add_all(binding_redirects_against, before_each = "--framework")
        state.inputs.extend([executable] + state.shipped + binding_redirects_against)

    state.ctx.actions.run(
        mnemonic = "DotnetNetFxConfig",
        progress_message = "Generating {} for %{{label}}".format(config_name),
        executable = state.ctx.attr._netfx_config_tool.files_to_run,
        arguments = [args],
        inputs = depset(state.inputs),
        outputs = [config] + state.selected,
    )

    state.files.append(config)
    state.publish_layout.append((config_name, config))

def stage_netfx_application(
        ctx,
        executable,
        out_dir,
        target_framework,
        transitive_runtime_deps,
        reserved,
        framework_files,
        app_config,
        auto_generate_binding_redirects):
    """Stages a .NET Framework application's dependencies beside it and writes its `<exe>.config`.

    Args:
        ctx: The rule context.
        executable: The application's `.exe`.
        out_dir: The output directory the executable is in, relative to the package.
        target_framework: The .NET Framework target framework, such as `net48`.
        transitive_runtime_deps: The `DotnetAssemblyRuntimeInfo`s of its dependencies.
        reserved: The paths, relative to `out_dir`, that the binary writes there
            itself, each with a description of what it is, for error messages.
        framework_files: A depset of the targeting pack's reference assemblies.
        app_config: The user's `App.config`, or None.
        auto_generate_binding_redirects: Whether to write binding redirects.

    Returns:
        A struct of `files`, everything staged, and `publish_layout`, the
        `(path, File)` pairs to publish: the same, without PDBs, with symlinks
        replaced by their sources.
    """
    config_name = executable.basename + ".config"
    taken = {path.lower(): owner for (path, owner) in reserved.items()}
    if config_name.lower() in taken:
        fail(("{}: {} would be staged as {}, which is the application's configuration file. " +
              "Pass it as `app_config` instead, so that the build can add its binding " +
              "redirects to it.").format(ctx.label, taken[config_name.lower()], config_name))
    taken[config_name.lower()] = "the application's configuration file"

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)
    args.add("--label", str(ctx.label))

    state = struct(
        ctx = ctx,
        out_dir = out_dir,
        taken = taken,
        args = args,
        # What the binary stages, and the netfx_config outputs among them.
        files = [],
        selected = [],
        publish_layout = [],
        inputs = [],
        # The assemblies staged as they are, rather than selected.
        shipped = [],
    )

    candidates = _collect_candidates(transitive_runtime_deps)
    with_assembly = _stage_libs(state, candidates.libs)
    _stage_orphan_satellites(state, candidates.orphan_satellites, with_assembly)
    _stage_natives(state, candidates.natives)

    binding_redirects_against = None
    if auto_generate_binding_redirects:
        # Only the framework assemblies the application also ships matter.
        binding_redirects_against = [
            file
            for file in framework_files.to_list()
            if file.basename.lower() in candidates.libs
        ]
    _write_config(state, config_name, executable, target_framework, app_config, binding_redirects_against)

    return struct(files = state.files, publish_layout = state.publish_layout)
