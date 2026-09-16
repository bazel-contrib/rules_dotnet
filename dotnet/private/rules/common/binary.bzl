"""
Base rule for building .Net binaries
"""

load("@bazel_lib//lib:expand_make_vars.bzl", "expand_locations", "expand_variables")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//dotnet/private:common.bzl",
    "collect_transitive_runfiles",
    "generate_depsjson",
    "generate_runtimeconfig",
    "get_toolchain",
    "is_core_framework",
    "is_standard_framework",
    "to_rlocation_path",
)
load("//dotnet/private:providers.bzl", "DotnetAssemblyRuntimeInfo", "DotnetBinaryInfo")

def _collect_native_dlls(assembly_runtime_info, deps):
    """Groups the native DLLs of a target and its dependencies by RID.

    Args:
        assembly_runtime_info: The DotnetAssemblyRuntimeInfo provider for the target.
        deps: Dependencies of the target.

    Returns:
        A dict of RID to the native DLL files built for it.
    """

    # A copy: this is the list the returned provider holds, so extending it in
    # place would leak the transitive closure into DotnetAssemblyRuntimeInfo.
    native_dlls = list(assembly_runtime_info.native)

    for dep in deps:
        native_dlls.extend(dep[DotnetAssemblyRuntimeInfo].native)

    closure = depset(transitive = [dep[DotnetAssemblyRuntimeInfo].deps for dep in deps])
    for transitive_dep in closure.to_list():
        native_dlls.extend(transitive_dep.native)

    result = {}
    for dll in native_dlls:
        result.setdefault(dll.dirname.split("/")[-2], []).append(dll)

    return result

def _create_launcher(ctx, executable):
    is_windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo])
    launcher = ctx.actions.declare_file("{}.{}".format(executable.basename, "bat" if is_windows else "sh"), sibling = executable)

    ctx.actions.expand_template(
        template = ctx.file._launcher_bat if is_windows else ctx.file._launcher_sh,
        output = launcher,
        substitutions = {
            "TEMPLATED_dotnet": to_rlocation_path(ctx, get_toolchain(ctx).runtime.files_to_run.executable),
            "TEMPLATED_executable": to_rlocation_path(ctx, executable),
        },
        is_executable = True,
    )

    return launcher

def build_binary(ctx, compile_action):
    """Builds a .Net binary from a compilation action

    Args:
        ctx: Bazel build ctx.
        compile_action: A compilation function
            Args:
                ctx: Bazel build ctx.
                tfm: Target framework string
            Returns:
                An DotnetAssemblyInfo provider
    Returns:
        A collection of the references, runfiles and native dlls.
    """
    tfm = ctx.attr._target_framework[BuildSettingInfo].value

    if is_standard_framework(tfm):
        fail("It doesn't make sense to build an executable for " + tfm)

    (compile_provider, runtime_provider) = compile_action(ctx, tfm)
    dll = runtime_provider.libs[0]
    appsetting_files = runtime_provider.appsetting_files.to_list()
    default_info_files = [dll] + runtime_provider.xml_docs + appsetting_files

    launcher = _create_launcher(ctx, dll)

    additional_runfiles = list(appsetting_files)

    runtimeconfig = None
    depsjson = None
    transitive_runtime_deps = runtime_provider.deps.to_list()

    if is_core_framework(tfm):
        runtimeconfig = ctx.actions.declare_file("%s/%s/%s.runtimeconfig.json" % (ctx.label.name, tfm, ctx.attr.out or ctx.attr.name))
        runtimeconfig_struct = generate_runtimeconfig(
            target_framework = tfm,
            project_sdk = ctx.attr.project_sdk,
            is_self_contained = False,
            roll_forward_behavior = ctx.attr.roll_forward_behavior,
        )

        # Add additional lookup paths so that we can avoid copying all DLLs
        # into the output directory. The deps.json file will then contain
        # paths that are relative to the workspace root
        runtimeconfig_struct["runtimeOptions"]["additionalProbingPaths"] = [
            "./",
            "./external",
            "../",
            "../external",
            # This one is for when the binary target is used as an tool in e.g. a custom rule
            "{}.runfiles".format(launcher.path),
        ]
        ctx.actions.write(
            output = runtimeconfig,
            content = json.encode(runtimeconfig_struct),
        )

        depsjson = ctx.actions.declare_file("%s/%s/%s.deps.json" % (ctx.label.name, tfm, ctx.attr.out or ctx.attr.name))
        depsjson_struct = generate_depsjson(
            ctx,
            target_framework = tfm,
            is_self_contained = False,
            target_assembly_runtime_info = runtime_provider,
            transitive_runtime_deps = transitive_runtime_deps,
            use_relative_paths = True,
        )

        ctx.actions.write(
            output = depsjson,
            content = json.encode(depsjson_struct),
        )

    if runtimeconfig != None:
        additional_runfiles.append(runtimeconfig)

    if depsjson != None:
        additional_runfiles.append(depsjson)

    runfiles = collect_transitive_runfiles(ctx, runtime_provider, ctx.attr.deps).merge(
        ctx.runfiles(
            files = additional_runfiles,
            transitive_files = get_toolchain(ctx).dotnetinfo.runtime_files,
        ),
    )

    # The apphost shimmer loads Microsoft.NET.HostModel.dll at run time.
    # `include_host_model_dll` makes it a compile dependency; the runtime needs
    # it staged as well. Only csharp_binary carries the attribute.
    if getattr(ctx.attr, "include_host_model_dll", False):
        runfiles = runfiles.merge(ctx.runfiles(files = get_toolchain(ctx).host_model[DotnetAssemblyRuntimeInfo].libs))

    # Due to how the .Net runtime loads native DLLs we need make the native
    # DLLs available in the application root directory with the folder structure:
    # runtimes/{rid}/native/{dlls}
    native_dlls = _collect_native_dlls(runtime_provider, ctx.attr.deps)
    native_symlinks = []
    for (rid, native_files) in native_dlls.items():
        for file in native_files:
            output_path = "{}/{}/runtimes/{}/native/{}".format(ctx.label.name, tfm, rid, file.basename)
            output = ctx.actions.declare_file(output_path)
            ctx.actions.symlink(
                output = output,
                target_file = file,
            )
            default_info_files.append(output)
            native_symlinks.append(output)

    if native_symlinks:
        runfiles = runfiles.merge(ctx.runfiles(files = native_symlinks))

    if not ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]):
        runfiles = runfiles.merge(ctx.attr._bash_runfiles[DefaultInfo].default_runfiles)
    default_info = DefaultInfo(
        executable = launcher,
        runfiles = runfiles,
        files = depset(default_info_files),
    )

    toolchain = get_toolchain(ctx)

    dotnet_binary_info = DotnetBinaryInfo(
        dll = dll,
        transitive_runtime_deps = transitive_runtime_deps,
        runtime_pack_info = toolchain.dotnetinfo.runtime_pack_infos[ctx.attr.project_sdk],
    )

    return [default_info, dotnet_binary_info, compile_provider, runtime_provider, RunEnvironmentInfo(environment = {key: expand_variables(ctx, expand_locations(ctx, value, ctx.attr.data)) for key, value in ctx.attr.envs.items()}, inherited_environment = ctx.attr.env_inherit)]
