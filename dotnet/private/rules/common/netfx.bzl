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

def _stem(basename):
    return basename.rsplit(".", 1)[0].lower()

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

def _select(state, kind, group, pdb_path):
    """Has netfx_config copy the highest version of `group` into the output directory.

    Returns:
        The File it writes.
    """
    output = state.ctx.actions.declare_file("{}/{}".format(state.out_dir, group.path))
    pdb_output = state.ctx.actions.declare_file("{}/{}".format(state.out_dir, pdb_path)) if pdb_path else None
    state.args.add_all(["--select", kind, output, pdb_output or "-", str(len(group.candidates))])
    for candidate in group.candidates:
        state.args.add_all([candidate.file, candidate.pdb or "-"])
        state.inputs.append(candidate.file)
        if candidate.pdb:
            state.inputs.append(candidate.pdb)

    state.selected.append(output)
    state.files.append(output)
    if pdb_output:
        state.selected.append(pdb_output)
        state.files.append(pdb_output)

    return output

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
            which say what the framework itself provides.
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
        for lib in dep.libs:
            _add(libs, lib.basename, struct(file = lib, pdb = pdbs.get(_stem(lib.basename)), owner = dep.name))
        for resource in dep.resource_assemblies:
            # A satellite assembly lives in a directory named after its culture.
            path = "{}/{}".format(resource.dirname.split("/")[-1], resource.basename)
            _add(resources, path, struct(file = resource, pdb = None, owner = dep.name))
        for native in dep.native:
            _add(natives, native.basename, struct(file = native, pdb = None, owner = dep.name))

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

    for group in libs.values():
        _claim(label, taken, group.path, "the assembly {} of `{}`".format(group.path, group.candidates[0].owner))
        pdb_path = _pdb_path(taken, group)

        if len(group.candidates) == 1:
            candidate = group.candidates[0]
            _stage(state, group.path, candidate.file)
            publish_layout.append((group.path, candidate.file))
            args.add("--assembly", candidate.file)
            state.inputs.append(candidate.file)
            if pdb_path:
                _stage(state, pdb_path, candidate.pdb)
        else:
            output = _select(state, "lib", group, pdb_path)
            publish_layout.append((group.path, output))

    for group in resources.values():
        _claim(label, taken, group.path, "the satellite assembly {} of `{}`".format(group.path, group.candidates[0].owner))

        if len(group.candidates) == 1:
            candidate = group.candidates[0]
            _stage(state, group.path, candidate.file)
            publish_layout.append((group.path, candidate.file))
        else:
            output = _select(state, "resource", group, None)
            publish_layout.append((group.path, output))

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

    transitive_inputs = []
    if auto_generate_binding_redirects:
        args.add_all(framework_files, before_each = "--framework")
        transitive_inputs.append(framework_files)
    else:
        args.add("--no-binding-redirects")

    ctx.actions.run(
        mnemonic = "DotnetNetFxConfig",
        progress_message = "Generating {} for %{{label}}".format(config_name),
        executable = ctx.attr._netfx_config_tool.files_to_run,
        arguments = [args],
        inputs = depset(state.inputs, transitive = transitive_inputs),
        outputs = [config] + state.selected,
    )

    state.files.append(config)
    publish_layout.append((config_name, config))

    return struct(files = state.files, publish_layout = publish_layout)
