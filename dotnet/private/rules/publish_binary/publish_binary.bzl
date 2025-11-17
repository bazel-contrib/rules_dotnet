"""
Rules for compiling F# binaries.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("//dotnet/private:common.bzl", "generate_depsjson", "generate_runtimeconfig")
load("//dotnet/private:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo", "DotnetBinaryInfo")
load("//dotnet/private/transitions:default_transition.bzl", "default_transition")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _copy_file(script_body, src, dst, is_windows):
    if is_windows:
        script_body.append("if not exist \"{dir}\" @mkdir \"{dir}\" >NUL".format(dir = dst.dirname.replace("/", "\\")))
        script_body.append("@copy /Y \"{src}\" \"{dst}\" >NUL".format(src = src.path.replace("/", "\\"), dst = dst.path.replace("/", "\\")))
    else:
        script_body.append("mkdir -p {dir} && cp -f {src} {dst}".format(dir = shell.quote(dst.dirname), src = shell.quote(src.path), dst = shell.quote(dst.path)))

def _get_assembly_files(assembly_info, transitive_runtime_deps, deps_json_struct):
    libs = [] + assembly_info.libs
    resource_assemblies = [] + assembly_info.resource_assemblies
    native = [] + assembly_info.native
    data = [] + assembly_info.data
    appsetting_files = assembly_info.appsetting_files.to_list()
    for dep in transitive_runtime_deps:
        # For each dependency we need to check in the deps.json struct if the files should be copied.
        # If the file is to be copied it will be in the `native`, `runtimeTargets` or `runtime` attribute of the `target` for the dependency.
        # A reason for the file not being in the deps.json is that the runtime pack might provide the file instead of the dependency.
        target = deps_json_struct["targets"].items()[0][1].get("{}/{}".format(dep.name, dep.version))
        if target:
            if "native" in target:
                for file in dep.native:
                    if file.basename in target["native"]:
                        native.append(file)

            if "runtimeTargets" in target:
                for file in dep.native:
                    if file.basename in target["runtimeTargets"].keys() and target["runtimeTargets"][file.basename]["assetType"] == "native":
                        native.append(file)

            if "runtime" in target:
                for file in dep.libs:
                    if file.basename in target["runtime"]:
                        libs.append(file)

        data += dep.data
        resource_assemblies += dep.resource_assemblies
    return (libs, resource_assemblies, native, data, appsetting_files)

def _copy_to_publish(ctx, runtime_identifier, runtime_pack_info, binary_info, assembly_info, transitive_runtime_deps, deps_json_struct, is_self_contained):
    is_windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo])
    inputs = [binary_info.dll]
    main_dll_copy = ctx.actions.declare_file(
        "{}/publish/{}/{}".format(ctx.label.name, runtime_identifier, binary_info.dll.basename),
    )
    outputs = [main_dll_copy]
    script_body = ["@echo off"] if is_windows else ["#! /usr/bin/env bash", "set -eou pipefail"]

    _copy_file(script_body, binary_info.dll, main_dll_copy, is_windows = is_windows)

    (libs, resource_assemblies, native, data, appsetting_files) = _get_assembly_files(assembly_info, transitive_runtime_deps, deps_json_struct)

    # All managed DLLs are copied next to the app host in the publish directory
    for file in libs:
        output = ctx.actions.declare_file(
            "{}/publish/{}/{}".format(ctx.label.name, runtime_identifier, file.basename),
        )
        outputs.append(output)
        inputs.append(file)
        _copy_file(script_body, file, output, is_windows = is_windows)

    # Resource assemblies are copied next to the app host in the publish directory in a folder
    # that has the same name as the locale of the resource assembly.
    # Example: `de/MyAssembly.resources.dll`
    for file in resource_assemblies:
        locale = file.dirname.split("/")[-1]
        output_dir = "{}/publish/{}/{}/{}".format(ctx.label.name, runtime_identifier, locale, file.basename)
        output = ctx.actions.declare_file(output_dir)
        outputs.append(output)
        inputs.append(file)
        _copy_file(script_body, file, output, is_windows = is_windows)

    for file in native:
        # If the publish is not self-contained we need to copy the native
        # DLLs into the runtimes/{rid}/native/ folder structure
        output_path = "{}/publish/{}/runtimes/{}/native/{}".format(ctx.label.name, runtime_identifier, file.dirname.split("/")[-2], file.basename)

        # If the publish is self-contained we need to copy the native DLLs
        # next to the main DLL in the publish folder
        if is_self_contained:
            output_path = "{}/publish/{}/{}".format(ctx.label.name, runtime_identifier, file.basename)
        output = ctx.actions.declare_file(
            output_path,
        )
        inputs.append(file)
        outputs.append(output)
        _copy_file(script_body, file, output, is_windows = is_windows)

    # The data files put into the publish folder in a structure that works with
    # the runfiles lib. End users should not expect files in the `data` attribute
    # to be resolvable by relative paths. They need to use the runfiles lib.
    #
    # The end-user will have to use rules that also pull the runfiles. For examples if
    # they use rules_pkg they have to use `include_runfiles` on the pkt_tar rule.
    #
    # The runfiles library follows the spec and tries to find a `<DLL>.runfiles` directory
    # next to the the DLL based on argv0 of the running process if
    # RUNFILES_DIR/RUNFILES_MANIFEST_FILE/RUNFILES_MANIFEST_ONLY is not set).
    runfiles = []
    for file in data:
        runfiles.append(file)

    for file in appsetting_files:
        inputs.append(file)
        output = ctx.actions.declare_file(
            "{}/publish/{}/{}".format(ctx.label.name, runtime_identifier, file.basename),
        )
        outputs.append(output)
        _copy_file(script_body, file, output, is_windows = is_windows)

    # In case the publish is self-contained there needs to be a runtime pack available
    # with the runtime dependencies that are required for the targeted runtime.
    # The runtime pack contents should always be copied to the root of the publish folder
    if runtime_pack_info:
        for runtime_pack in runtime_pack_info.assembly_runtime_infos:
            # We need to go through the deps.json struct to determine which files should be copied.
            # If a user provided dependency is overriding a DLL that is in the runtime pack then the
            # DLL is omitted from the target for the runtime pack in the deps.json.
            libs = []
            native = []
            target = deps_json_struct["targets"].items()[0][1].get("runtimepack.{}/{}".format(runtime_pack.name, runtime_pack.version))
            if target:
                if "native" in target:
                    for file in runtime_pack.native:
                        if file.basename in target["native"]:
                            native.append(file)
                if "runtime" in target:
                    for file in runtime_pack.libs:
                        if file.basename in target["runtime"]:
                            libs.append(file)

            runtime_pack_files = depset(
                libs +
                native +
                runtime_pack.data,
            )
            for file in runtime_pack_files.to_list():
                output = ctx.actions.declare_file(file.basename, sibling = main_dll_copy)
                outputs.append(output)
                inputs.append(file)
                _copy_file(script_body, file, output, is_windows = is_windows)

    copy_script = ctx.actions.declare_file(ctx.label.name + ".copy.bat" if is_windows else ctx.label.name + ".copy.sh")
    ctx.actions.write(
        output = copy_script,
        content = "\r\n".join(script_body) if is_windows else "\n".join(script_body),
        is_executable = True,
    )

    ctx.actions.run(
        outputs = outputs,
        inputs = inputs,
        executable = copy_script,
        tools = [copy_script],
    )

    return (main_dll_copy, outputs, runfiles)

def _create_shim_exe(ctx, apphost_pack_info, dll, runtime_identifier):
    windows_constraint = ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]

    apphost = apphost_pack_info.apphost
    output = ctx.actions.declare_file(paths.replace_extension(dll.basename, ".exe" if ctx.target_platform_has_constraint(windows_constraint) else ""), sibling = dll)

    ctx.actions.run(
        executable = ctx.attr._apphost_shimmer[0].files_to_run,
        arguments = [apphost.path, dll.path, output.path, runtime_identifier],
        inputs = depset([apphost, dll], transitive = [ctx.attr._apphost_shimmer[0].default_runfiles.files]),
        tools = [ctx.attr._apphost_shimmer[0].files, ctx.attr._apphost_shimmer[0].default_runfiles.files],
        outputs = [output],
    )

    return output

def _generate_runtimeconfig(ctx, output, target_framework, project_sdk, is_self_contained, roll_forward_behavior, runtime_pack_info):
    runtimeconfig_struct = generate_runtimeconfig(target_framework, project_sdk, is_self_contained, roll_forward_behavior, runtime_pack_info)

    ctx.actions.write(
        output = output,
        content = json.encode_indent(runtimeconfig_struct),
    )

def _generate_depsjson(
        ctx,
        output,
        target_framework,
        is_self_contained,
        assembly_info,
        transitive_runtime_deps,
        runtime_pack_info):
    depsjson_struct = generate_depsjson(ctx, target_framework, is_self_contained, assembly_info, transitive_runtime_deps, runtime_pack_info)

    ctx.actions.write(
        output = output,
        content = json.encode_indent(depsjson_struct),
    )

    return depsjson_struct

def _publish_binary_impl(ctx):
    assembly_compile_info = ctx.attr.binary[0][DotnetAssemblyCompileInfo]
    assembly_runtime_info = ctx.attr.binary[0][DotnetAssemblyRuntimeInfo]
    binary_info = ctx.attr.binary[0][DotnetBinaryInfo]
    transitive_runtime_deps = binary_info.transitive_runtime_deps
    target_framework = ctx.attr.target_framework
    is_self_contained = ctx.attr.self_contained
    assembly_name = assembly_runtime_info.name
    runtime_pack_info = binary_info.runtime_pack_info if is_self_contained else None
    runtime_identifier = ctx.attr.runtime_identifier if ctx.attr.runtime_identifier else binary_info.runtime_pack_info.runtime_identifier
    roll_forward_behavior = ctx.attr.roll_forward_behavior

    depsjson = ctx.actions.declare_file("{}/publish/{}/{}.deps.json".format(ctx.label.name, runtime_identifier, assembly_name))
    depsjson_struct = _generate_depsjson(
        ctx,
        depsjson,
        target_framework,
        is_self_contained,
        assembly_runtime_info,
        transitive_runtime_deps,
        runtime_pack_info,
    )

    runtimeconfig = ctx.actions.declare_file("{}/publish/{}/{}.runtimeconfig.json".format(
        ctx.label.name,
        runtime_identifier,
        assembly_name,
    ))

    _generate_runtimeconfig(
        ctx,
        runtimeconfig,
        target_framework,
        assembly_compile_info.project_sdk,
        is_self_contained,
        roll_forward_behavior,
        runtime_pack_info,
    )

    (main_dll, outputs, runfiles) = _copy_to_publish(
        ctx,
        runtime_identifier,
        runtime_pack_info,
        binary_info,
        assembly_runtime_info,
        transitive_runtime_deps,
        depsjson_struct,
        is_self_contained,
    )

    apphost_shim = _create_shim_exe(ctx, binary_info.apphost_pack_info, main_dll, runtime_identifier)

    return [
        DefaultInfo(
            executable = apphost_shim,
            files = depset([apphost_shim, main_dll, runtimeconfig, depsjson] + outputs),
            runfiles = ctx.runfiles(files = runfiles),
        ),
    ]

# This wrapper is only needed so that we can turn the incoming transition in `publish_binary`
# into an outgoing transition in the wrapper. This allows us to select on the runtime_identifier
# and runtime_packs attributes. We also need to have all the file copying in the wrapper rule
# because Bazel does not allow forwarding executable files as they have to be created by the wrapper rule.
publish_binary = rule(
    _publish_binary_impl,
    doc = """Publish a .Net binary""",
    attrs = {
        "binary": attr.label(
            doc = "The .Net binary that is being published",
            providers = [DotnetBinaryInfo],
            cfg = tfm_transition,
            mandatory = True,
        ),
        "self_contained": attr.bool(
            doc = """
            Whether the binary should be self-contained.
            
            If true, the binary will be published as a self-contained but you need to provide
            a runtime pack in the `runtime_packs` attribute. At some point the rules might
            resolve the runtime pack automatically.

            If false, the binary will be published as a non-self-contained. That means that to be
            able to run the binary you need to have a .Net runtime installed on the host system.
            """,
            default = False,
        ),
        "target_framework": attr.string(
            doc = "The target framework that should be published",
            mandatory = True,
        ),
        "runtime_identifier": attr.string(
            doc = "The runtime identifier that is being targeted. " +
                  "See https://docs.microsoft.com/en-us/dotnet/core/rid-catalog",
            mandatory = False,
        ),
        "roll_forward_behavior": attr.string(
            doc = "The roll forward behavior that should be used: https://learn.microsoft.com/en-us/dotnet/core/versions/selection#control-roll-forward-behavior",
            default = "Minor",
            values = ["Minor", "Major", "LatestPatch", "LatestMinor", "LatestMajor", "Disable"],
        ),
        "_apphost_shimmer": attr.label(
            providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo],
            executable = True,
            default = "//dotnet/private/tools/apphost_shimmer:apphost_shimmer",
            cfg = default_transition,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
        "_windows_constraint": attr.label(default = "@platforms//os:windows"),
    },
    toolchains = [
        "//dotnet:toolchain_type",
    ],
    executable = True,
    cfg = tfm_transition,
)
