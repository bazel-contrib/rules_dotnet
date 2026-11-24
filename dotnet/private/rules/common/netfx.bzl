"""The output directory of a .NET Framework application.

.NET Framework has no `deps.json` and no probing paths outside the
application's own directory: the CLR loads an assembly from the GAC or from
beside the executable. So, as MSBuild's copy-local does, everything the
application loads is laid out next to it, with the `<exe>.config` that holds
its binding redirects.
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
    """Where a satellite assembly goes: a directory named after its culture.

    Args:
        file: The satellite assembly, which lives in such a directory already.

    Returns:
        Its path relative to the application's directory.
    """
    return "{}/{}".format(file.dirname.split("/")[-1], file.basename)

def _stem(basename):
    return basename.rsplit(".", 1)[0].lower()

_SATELLITE_SUFFIX = ".resources.dll"

def _add(groups, path, candidate):
    """Adds a candidate for `path`, once per distinct source file."""
    group = groups.setdefault(path.lower(), struct(path = path, candidates = []))
    for existing in group.candidates:
        if existing.file.path == candidate.file.path:
            return
    group.candidates.append(candidate)

def _claim(label, taken, path, owner):
    """Takes `path` in the output directory for `owner`, failing if something else has it."""
    previous = taken.get(path.lower())
    if previous != None:
        fail(("{}: {} would be staged as {} next to the executable, but that is already {}. " +
              ".NET Framework loads assemblies from the executable's own directory, so only " +
              "one file can take that name.").format(label, owner, path, previous))
    taken[path.lower()] = owner

def _stage(state, path, source):
    """Symlinks `source` into the output directory at `path`."""
    staged = state.ctx.actions.declare_file("{}/{}".format(state.out_dir, path))
    state.ctx.actions.symlink(output = staged, target_file = source)
    state.files.append(staged)

def _declare_selected(state, path):
    output = state.ctx.actions.declare_file("{}/{}".format(state.out_dir, path))
    state.selected.append(output)
    state.files.append(output)
    return output

def _select(state, kind, group, pdb_path, satellite_paths):
    """Has netfx_config copy the highest version of `group` into the output directory.

    Its PDB and satellite assemblies come from the same copy. Which copy that
    is is only known once the action runs, so each satellite assembly any copy
    has gets a directory of its name, `de/Foo.resources/`, which .NET
    Framework probes for it after `de/Foo.resources.dll`. The chosen copy's
    goes in it; for a culture that copy has none of, it stays empty and the
    assembly's own resources serve instead.

    Returns:
        A list of the (path, File) pairs it writes, the assembly's first.
    """
    output = _declare_selected(state, group.path)
    pdb_output = _declare_selected(state, pdb_path) if pdb_path else None
    satellite_directories = [satellite_path.removesuffix(".dll") for satellite_path in satellite_paths]
    satellite_outputs = []
    for path in satellite_directories:
        directory = state.ctx.actions.declare_directory("{}/{}".format(state.out_dir, path))
        state.selected.append(directory)
        state.files.append(directory)
        satellite_outputs.append(directory)

    state.args.add_all(["--select", kind, output, pdb_output or "-", str(len(satellite_outputs))])
    state.args.add_all(satellite_outputs, expand_directories = False)
    state.args.add(str(len(group.candidates)))
    for candidate in group.candidates:
        satellites = [candidate.satellites.get(path.lower()) for path in satellite_paths]
        state.args.add_all([candidate.file, candidate.pdb or "-"] + [satellite or "-" for satellite in satellites])
        state.inputs.extend([candidate.file] + [satellite for satellite in satellites if satellite])
        if candidate.pdb:
            state.inputs.append(candidate.pdb)

    return [(group.path, output)] + [(path, satellite_outputs[i]) for (i, path) in enumerate(satellite_directories)]

def _pdb_path(taken, group):
    """Where the PDB of an assembly goes, or None to leave it out.

    The PDB follows its assembly, and only where every copy of it has one.
    """
    if not all([candidate.pdb for candidate in group.candidates]):
        return None

    path = group.candidates[0].pdb.basename
    if path.lower() in taken:
        return None

    taken[path.lower()] = "the PDB of `{}`".format(group.candidates[0].owner)
    return path

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
    """Stages a .NET Framework application's dependencies and writes its `<exe>.config`.

    Each assembly, satellite assembly, native library and PDB of the
    dependencies goes beside the executable. Where several dependencies ship
    the same assembly, the `netfx_config` tool keeps the highest version, as
    MSBuild's ResolveAssemblyReference does. It also writes the configuration
    file: the user's `app_config` if there is one, with `<supportedRuntime>` and
    a binding redirect for each strong-named assembly that is referenced at a
    version other than the one shipped.

    Args:
        ctx: The rule context.
        executable: The application's `.exe`.
        out_dir: The output directory the executable is in, relative to the package.
        target_framework: The .NET Framework target framework, such as `net48`.
        transitive_runtime_deps: The `DotnetAssemblyRuntimeInfo`s of its dependencies.
        reserved: The paths, relative to `out_dir`, that the binary writes there
            itself, each with a description of what it is, for error messages.
        framework_files: A depset of the targeting pack's reference assemblies,
            which say what the framework itself provides, and at which version.
        app_config: The user's `App.config`, or None.
        auto_generate_binding_redirects: Whether to write binding redirects.

    Returns:
        A struct of `files`, everything staged including the configuration file,
        and `publish_layout`, the `(path, File)` pairs a publish copies: the
        same files less the PDBs, each pointing at its source where it is a
        symlink.
    """
    label = ctx.label
    config_name = executable.basename + ".config"
    taken = {path.lower(): owner for (path, owner) in reserved.items()}

    if config_name.lower() in taken:
        fail(("{}: {} would be staged as {}, which is the application's configuration file. " +
              "Pass it as `app_config` instead, so that the build can add its binding " +
              "redirects to it.").format(label, taken[config_name.lower()], config_name))
    taken[config_name.lower()] = "the application's configuration file"

    libs = {}
    resources = {}
    natives = {}
    for dep in transitive_runtime_deps:
        pdbs = {_stem(pdb.basename): pdb for pdb in dep.pdbs}

        # A satellite assembly belongs to the assembly of its name in the same
        # dependency, and travels with it.
        satellites = {}
        for resource in dep.resource_assemblies:
            stem = resource.basename[:-len(_SATELLITE_SUFFIX)].lower() if resource.basename.lower().endswith(_SATELLITE_SUFFIX) else None
            satellites.setdefault(stem, {})[satellite_path(resource).lower()] = resource

        for lib in dep.libs:
            _add(libs, lib.basename, struct(
                file = lib,
                pdb = pdbs.get(_stem(lib.basename)),
                satellites = satellites.pop(_stem(lib.basename), {}),
                owner = dep.name,
            ))

        # Satellite assemblies of no assembly here are shipped on their own.
        for orphans in satellites.values():
            for resource in orphans.values():
                _add(resources, satellite_path(resource), struct(file = resource, pdb = None, satellites = {}, owner = dep.name))

        for native in dep.native:
            _add(natives, native.basename, struct(file = native, pdb = None, satellites = {}, owner = dep.name))

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)
    args.add("--label", str(label))

    # What the loops below build up: the staged files, the netfx_config
    # arguments and inputs, and the outputs it writes.
    state = struct(
        ctx = ctx,
        out_dir = out_dir,
        args = args,
        files = [],
        inputs = [executable],
        selected = [],
    )
    publish_layout = []

    # The satellite assemblies that ship with their assembly.
    with_assembly = {}

    for group in libs.values():
        owner = group.candidates[0].owner
        _claim(label, taken, group.path, "the assembly {} of `{}`".format(group.path, owner))
        pdb_path = _pdb_path(taken, group)

        if len(group.candidates) == 1:
            candidate = group.candidates[0]
            _stage(state, group.path, candidate.file)
            publish_layout.append((group.path, candidate.file))
            args.add("--assembly", candidate.file)
            state.inputs.append(candidate.file)
            if pdb_path:
                _stage(state, pdb_path, candidate.pdb)
            for satellite in candidate.satellites.values():
                path = satellite_path(satellite)
                _claim(label, taken, path, "the satellite assembly {} of `{}`".format(path, owner))
                with_assembly[path.lower()] = True
                _stage(state, path, satellite)
                publish_layout.append((path, satellite))
        else:
            # Only the chosen copy's satellite assemblies match it: every
            # culture any copy has is made room for. See _select.
            satellite_paths = {}
            for candidate in group.candidates:
                for satellite in candidate.satellites.values():
                    satellite_paths.setdefault(satellite_path(satellite).lower(), satellite_path(satellite))
            for path in satellite_paths.values():
                _claim(label, taken, path, "the satellite assembly {} of `{}`".format(path, owner))
                _claim(label, taken, path.removesuffix(".dll"), "the satellite assemblies of `{}`".format(owner))
                with_assembly[path.lower()] = True
            publish_layout.extend(_select(state, "lib", group, pdb_path, satellite_paths.values()))

    for group in resources.values():
        # A language pack's satellite assembly gives way to the one that
        # ships with the assembly itself, which matches its version.
        if group.path.lower() in with_assembly:
            continue

        _claim(label, taken, group.path, "the satellite assembly {} of `{}`".format(group.path, group.candidates[0].owner))

        if len(group.candidates) == 1:
            candidate = group.candidates[0]
            _stage(state, group.path, candidate.file)
            publish_layout.append((group.path, candidate.file))
        else:
            publish_layout.extend(_select(state, "resource", group, None, []))

    for group in natives.values():
        if len(group.candidates) > 1:
            fail(("{}: `{}` and `{}` both ship a native library named {}, from {} and {}. " +
                  ".NET Framework loads native libraries from beside the executable, so only " +
                  "one of them can be there.").format(
                label,
                group.candidates[0].owner,
                group.candidates[1].owner,
                group.path,
                group.candidates[0].file.short_path,
                group.candidates[1].file.short_path,
            ))

        candidate = group.candidates[0]
        _claim(label, taken, group.path, "the native library {} of `{}`".format(group.path, candidate.owner))
        _stage(state, group.path, candidate.file)
        publish_layout.append((group.path, candidate.file))

    config = ctx.actions.declare_file("{}/{}".format(out_dir, config_name))
    args.add("--output", config)
    args.add("--main", executable)

    if app_config:
        args.add("--app-config", app_config)
        state.inputs.append(app_config)

    (runtime_version, sku) = netfx_supported_runtime(target_framework)
    args.add_all(["--supported-runtime", runtime_version, sku or "-"])

    if auto_generate_binding_redirects:
        # Only the framework's copies of assemblies the application ships
        # matter, so the tool reads those rather than the whole targeting pack,
        # which is a few hundred files.
        framework_by_name = {file.basename.lower(): file for file in framework_files.to_list()}
        for name in libs:
            if name in framework_by_name:
                args.add("--framework", framework_by_name[name])
                state.inputs.append(framework_by_name[name])
    else:
        args.add("--no-binding-redirects")

    ctx.actions.run(
        mnemonic = "DotnetNetFxConfig",
        progress_message = "Generating {} for %{{label}}".format(config_name),
        executable = ctx.attr._netfx_config_tool.files_to_run,
        arguments = [args],
        inputs = depset(state.inputs),
        outputs = [config] + state.selected,
    )

    state.files.append(config)
    publish_layout.append((config_name, config))

    return struct(files = state.files, publish_layout = publish_layout)
