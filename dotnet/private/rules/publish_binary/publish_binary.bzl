"""
Rule for assembling the publish output of a .NET binary.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("//dotnet/private:common.bzl", "generate_depsjson", "generate_runtimeconfig", "runtime_target_path")
load("//dotnet/private:providers.bzl", "DotnetApphostPackInfo", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo", "DotnetBinaryInfo", "DotnetCrossgen2PackInfo", "DotnetRuntimePackInfo")
load("//dotnet/private/sdk/apphost_packs:apphost_pack_transition.bzl", "apphost_pack_transition")
load("//dotnet/private/sdk/runtime_packs:runtime_pack_transition.bzl", "runtime_pack_default_transition", "runtime_pack_web_transition")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

# How many sources one `cp` invocation takes. A self-contained publish copies
# several hundred files into one directory, and the point of batching is lost if
# the command line grows long enough to risk the execve argument limit.
_COPY_BATCH = 128

def _render_copy_script(copies, is_windows):
    """The script that puts every published file in its place.

    A self-contained publish copies the whole runtime pack, so one process per
    file - and a second one to create its directory - dominates the action.
    Each directory is created once instead, and the files that keep their name
    are copied in batches.

    Args:
        copies: The (source, destination) pairs to copy, one pair per destination.
        is_windows: Whether the script is a batch file rather than a shell script.

    Returns:
        A list of script lines.
    """
    script_body = ["@echo off"] if is_windows else ["#! /usr/bin/env bash", "set -eou pipefail"]

    # Grouped by destination directory, in first-seen order. A file published
    # under a different name cannot join a batch, but its directory is still
    # created along with the rest.
    same_name = {}
    renamed = []

    for (src, dst) in copies:
        same_name.setdefault(dst.dirname, [])
        if src.basename == dst.basename:
            same_name[dst.dirname].append(src)
        else:
            renamed.append((src, dst))

    for (directory, sources) in same_name.items():
        if is_windows:
            script_body.append("if not exist \"{dir}\" @mkdir \"{dir}\" >NUL".format(dir = directory.replace("/", "\\")))

            # `copy` concatenates when handed several sources, so only the
            # directory creation is shared on Windows.
            for src in sources:
                script_body.append("@copy /Y \"{src}\" \"{dir}\" >NUL".format(
                    src = src.path.replace("/", "\\"),
                    dir = directory.replace("/", "\\"),
                ))
            continue

        script_body.append("mkdir -p {dir}".format(dir = shell.quote(directory)))

        for start in range(0, len(sources), _COPY_BATCH):
            script_body.append("cp -f {srcs} {dir}".format(
                srcs = " ".join([shell.quote(src.path) for src in sources[start:start + _COPY_BATCH]]),
                dir = shell.quote(directory),
            ))

    for (src, dst) in renamed:
        if is_windows:
            script_body.append("@copy /Y \"{src}\" \"{dst}\" >NUL".format(
                src = src.path.replace("/", "\\"),
                dst = dst.path.replace("/", "\\"),
            ))
        else:
            script_body.append("cp -f {src} {dst}".format(src = shell.quote(src.path), dst = shell.quote(dst.path)))

    return script_body

_NO_READY_TO_RUN = struct(replace = {}, extra = [])

def _crossgen2_target(runtime_identifier):
    """Splits a runtime identifier into crossgen2's --targetos/--targetarch.
    """
    parts = runtime_identifier.split("-")

    if len(parts) < 2 or parts[0] not in ("linux", "osx", "win"):
        fail("Cannot target {} with ReadyToRun".format(runtime_identifier))

    return ("windows" if parts[0] == "win" else parts[0], parts[-1])

def _runtime_pack_files(runtime_pack, deps_json_struct):
    """The runtime pack files that reach the publish.

    A user dependency that overrides a runtime pack DLL drops it from the
    pack's deps.json target, and then the pack's copy is not published.
    """
    libs = []
    native = []
    target = deps_json_struct["targets"].values()[0].get("runtimepack.{}/{}".format(
        runtime_pack.name,
        runtime_pack.version,
    ))

    if target:
        for file in runtime_pack.native:
            if file.basename in target.get("native", {}):
                native.append(file)
        for file in runtime_pack.libs:
            if file.basename in target.get("runtime", {}):
                libs.append(file)

    return struct(libs = libs, native = native)

def _ready_to_run_images(ctx, binary_info, assembly_files, deps_json_struct, runtime_identifier):
    """Compiles the published assemblies to ReadyToRun.

    crossgen2 cross-compiles, so the tool comes from the pack for the execution
    platform while the target platform and the references come from the target.
    """
    crossgen2_info = ctx.attr._crossgen2_pack[DotnetCrossgen2PackInfo]
    (target_os, target_arch) = _crossgen2_target(runtime_identifier)

    framework = [
        lib
        for runtime_pack in binary_info.runtime_pack_info.assembly_runtime_infos
        for lib in runtime_pack.libs
    ]

    # Runtime pack assemblies already ship as ReadyToRun images, so only a
    # composite image, which has to cover the framework, recompiles them.
    # Either way the framework is there for crossgen2 to resolve against.
    compiled = [binary_info.dll] + assembly_files.libs
    if ctx.attr.ready_to_run_composite:
        for runtime_pack in binary_info.runtime_pack_info.assembly_runtime_infos:
            compiled.extend(_runtime_pack_files(runtime_pack, deps_json_struct).libs)

    assemblies = {assembly.path: assembly for assembly in compiled}.values()
    references = {reference.path: reference for reference in framework + assemblies}.values()

    common = ctx.actions.args()
    common.add("--targetos:" + target_os)
    common.add("--targetarch:" + target_arch)
    common.add("-O")
    common.add_all(references, format_each = "-r:%s")
    common.set_param_file_format("multiline")

    response_file = ctx.actions.declare_file("{}/r2r/{}/crossgen2.rsp".format(
        ctx.label.name,
        runtime_identifier,
    ))
    ctx.actions.write(response_file, common)

    tool_files = depset(references + [response_file], transitive = [crossgen2_info.files])
    rsp = "@" + response_file.path

    if ctx.attr.ready_to_run_composite:
        image = ctx.actions.declare_file("{}/r2r/{}/composite/{}.r2r.dll".format(
            ctx.label.name,
            runtime_identifier,
            ctx.attr.binary[0][DotnetAssemblyRuntimeInfo].name,
        ))

        components = {}
        outputs = [image]

        for assembly in assemblies:
            component = ctx.actions.declare_file("{}/r2r/{}/composite/{}".format(
                ctx.label.name,
                runtime_identifier,
                assembly.basename,
            ))
            components[assembly.path] = component
            outputs.append(component)

        ctx.actions.run(
            executable = crossgen2_info.crossgen2,
            arguments = [rsp, "--composite", "--out:" + image.path] + [a.path for a in assemblies],
            inputs = tool_files,
            outputs = outputs,
            mnemonic = "Crossgen2Composite",
            progress_message = "Compiling composite ReadyToRun image for %{label}",
        )

        return struct(replace = components, extra = [image])

    images = {}
    for assembly in assemblies:
        image = ctx.actions.declare_file("{}/r2r/{}/{}".format(
            ctx.label.name,
            runtime_identifier,
            assembly.basename,
        ))

        ctx.actions.run(
            executable = crossgen2_info.crossgen2,
            arguments = [rsp, "--out:" + image.path, assembly.path],
            inputs = tool_files,
            outputs = [image],
            mnemonic = "Crossgen2",
            progress_message = "Compiling %{input} to ReadyToRun",
        )

        images[assembly.path] = image

    return struct(replace = images, extra = [])

def _get_assembly_files(assembly_info, transitive_runtime_deps, deps_json_struct):
    """The files a publish copies, gathered from the target and its deps."""
    libs = list(assembly_info.libs)
    resource_assemblies = list(assembly_info.resource_assemblies)
    native = list(assembly_info.native)
    data = list(assembly_info.data)
    targets = deps_json_struct["targets"].values()[0]

    for dep in transitive_runtime_deps:
        # A file missing from the deps.json is not published: the runtime pack
        # may be providing it instead of the dependency.
        target = targets.get("{}/{}".format(dep.name, dep.version))

        if target:
            dep_native = target.get("native", {})
            runtime_targets = target.get("runtimeTargets", {})
            runtime = target.get("runtime", {})

            # `native` is keyed by basename, `runtimeTargets` by the path the
            # asset takes inside the publish.
            for file in dep.native:
                if file.basename in dep_native or runtime_targets.get(runtime_target_path(file), {}).get("assetType") == "native":
                    native.append(file)

            for file in dep.libs:
                if file.basename in runtime:
                    libs.append(file)

        data += dep.data
        resource_assemblies += dep.resource_assemblies

    return struct(
        libs = libs,
        resource_assemblies = resource_assemblies,
        native = native,
        data = data,
        appsetting_files = assembly_info.appsetting_files.to_list(),
    )

def _copy_to_publish(ctx, runtime_identifier, runtime_pack_info, binary_info, assembly_files, deps_json_struct, is_self_contained, ready_to_run = _NO_READY_TO_RUN):
    is_windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo])
    main_dll_source = ready_to_run.replace.get(binary_info.dll.path, binary_info.dll)
    main_dll_copy = ctx.actions.declare_file(
        "{}/publish/{}/{}".format(ctx.label.name, runtime_identifier, binary_info.dll.basename),
    )

    # (source, destination) pairs, which are also the action's inputs and outputs.
    copies = [(main_dll_source, main_dll_copy)]

    for file in ready_to_run.extra:
        copies.append((file, ctx.actions.declare_file(file.basename, sibling = main_dll_copy)))

    # All managed DLLs are copied next to the app host in the publish directory
    for file in assembly_files.libs:
        output = ctx.actions.declare_file(
            "{}/publish/{}/{}".format(ctx.label.name, runtime_identifier, file.basename),
        )
        copies.append((ready_to_run.replace.get(file.path, file), output))

    # Resource assemblies are copied next to the app host in the publish directory in a folder
    # that has the same name as the locale of the resource assembly.
    # Example: `de/MyAssembly.resources.dll`
    for file in assembly_files.resource_assemblies:
        locale = file.dirname.split("/")[-1]
        output = ctx.actions.declare_file(
            "{}/publish/{}/{}/{}".format(ctx.label.name, runtime_identifier, locale, file.basename),
        )
        copies.append((file, output))

    for file in assembly_files.native:
        if is_self_contained:
            # A self-contained publish carries native DLLs next to the main DLL.
            output_path = "{}/publish/{}/{}".format(ctx.label.name, runtime_identifier, file.basename)
        else:
            # Everything else goes under runtimes/{rid}/native/. A native
            # library from a NuGet package carries its RID in its path; one we
            # built ourselves does not, but is by definition built for our RID.
            # Files inside a NuGet package are modelled as source files, which
            # is what tells the two apart.
            rid = file.dirname.split("/")[-2] if file.is_source else runtime_identifier
            output_path = "{}/publish/{}/runtimes/{}/native/{}".format(ctx.label.name, runtime_identifier, rid, file.basename)

        copies.append((file, ctx.actions.declare_file(output_path)))

    # Data files reach the publish as runfiles, not as files at a relative path:
    # end users have to resolve them with the runfiles library, and to package
    # them with a rule that carries runfiles along (`include_runfiles` on
    # rules_pkg's `pkg_tar`, for one).
    runfiles = list(assembly_files.data)

    for file in assembly_files.appsetting_files:
        output = ctx.actions.declare_file(
            "{}/publish/{}/{}".format(ctx.label.name, runtime_identifier, file.basename),
        )
        copies.append((file, output))

    # A self-contained publish carries the runtime pack at the root of the
    # publish folder.
    if runtime_pack_info:
        for runtime_pack in runtime_pack_info.assembly_runtime_infos:
            files = _runtime_pack_files(runtime_pack, deps_json_struct)

            for file in files.libs + files.native + runtime_pack.data:
                output = ctx.actions.declare_file(file.basename, sibling = main_dll_copy)
                copies.append((ready_to_run.replace.get(file.path, file), output))

    # The binary's own assembly arrives twice, as the main DLL and again in the
    # list of assemblies to publish. Keep the last source named for a destination.
    copies = {dst.path: (src, dst) for (src, dst) in copies}.values()
    outputs = [dst for (_, dst) in copies]

    script_body = _render_copy_script(copies, is_windows)
    copy_script = ctx.actions.declare_file(ctx.label.name + ".copy.bat" if is_windows else ctx.label.name + ".copy.sh")
    ctx.actions.write(
        output = copy_script,
        content = "\r\n".join(script_body) if is_windows else "\n".join(script_body),
        is_executable = True,
    )

    ctx.actions.run(
        mnemonic = "DotnetPublishCopy",
        progress_message = "Assembling publish output for %{label}",
        outputs = outputs,
        inputs = depset([src for (src, _) in copies]),
        executable = copy_script,
        tools = [copy_script],
    )

    return (main_dll_copy, outputs, runfiles)

def _create_shim_exe(ctx, apphost_pack_info, dll, runtime_identifier):
    windows_constraint = ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]

    apphost = apphost_pack_info.apphost
    output = ctx.actions.declare_file(paths.replace_extension(dll.basename, ".exe" if ctx.target_platform_has_constraint(windows_constraint) else ""), sibling = dll)

    ctx.actions.run(
        mnemonic = "DotnetApphostShim",
        progress_message = "Creating apphost shim for %{label}",
        executable = ctx.attr._apphost_shimmer.files_to_run,
        arguments = [apphost.path, dll.path, output.path, runtime_identifier],
        inputs = depset([apphost, dll], transitive = [ctx.attr._apphost_shimmer.default_runfiles.files]),
        tools = [ctx.attr._apphost_shimmer.files, ctx.attr._apphost_shimmer.default_runfiles.files],
        outputs = [output],
    )

    return output

def _generate_runtimeconfig(ctx, output, target_framework, project_sdk, is_self_contained, roll_forward_behavior, runtime_pack_info):
    runtimeconfig_struct = generate_runtimeconfig(target_framework, project_sdk, is_self_contained, roll_forward_behavior, runtime_pack_info)

    ctx.actions.write(
        output = output,
        content = json.encode(runtimeconfig_struct),
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
        content = json.encode(depsjson_struct),
    )

    return depsjson_struct

def _publish_binary_impl(ctx):
    assembly_compile_info = ctx.attr.binary[0][DotnetAssemblyCompileInfo]
    assembly_runtime_info = ctx.attr.binary[0][DotnetAssemblyRuntimeInfo]
    binary_info = ctx.attr.binary[0][DotnetBinaryInfo]
    transitive_runtime_deps = binary_info.transitive_runtime_deps
    target_framework = ctx.attr.target_framework
    is_self_contained = ctx.attr.self_contained

    if ctx.attr.ready_to_run_composite and not (ctx.attr.ready_to_run and is_self_contained):
        fail("ready_to_run_composite requires ready_to_run and self_contained")
    assembly_name = assembly_runtime_info.name
    selected_runtime_pack = ctx.attr._runtime_pack_web if assembly_compile_info.project_sdk == "web" else ctx.attr._runtime_pack_default
    selected_runtime_pack_info = selected_runtime_pack[0][DotnetRuntimePackInfo]
    runtime_pack_info = selected_runtime_pack_info if is_self_contained else None
    runtime_identifier = ctx.attr.runtime_identifier if ctx.attr.runtime_identifier else selected_runtime_pack_info.runtime_identifier
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

    assembly_files = _get_assembly_files(assembly_runtime_info, transitive_runtime_deps, depsjson_struct)
    ready_to_run = _NO_READY_TO_RUN

    if ctx.attr.ready_to_run:
        ready_to_run = _ready_to_run_images(
            ctx,
            binary_info,
            assembly_files,
            depsjson_struct,
            runtime_identifier,
        )

    (main_dll, outputs, runfiles) = _copy_to_publish(
        ctx,
        runtime_identifier,
        runtime_pack_info,
        binary_info,
        assembly_files,
        depsjson_struct,
        is_self_contained,
        ready_to_run,
    )

    apphost_shim = _create_shim_exe(ctx, ctx.attr._apphost_pack[0][DotnetApphostPackInfo], main_dll, runtime_identifier)

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
_publish_binary = rule(
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
        "ready_to_run": attr.bool(
            doc = """Compile the published assemblies to ReadyToRun.

ReadyToRun embeds native code alongside the IL so the JIT has less to do at
startup. The published file set is unchanged: each assembly is replaced by its
compiled image.""",
            default = False,
        ),
        "ready_to_run_composite": attr.bool(
            doc = """Compile a single composite ReadyToRun image.

One image covers every assembly, which lets crossgen2 inline across assembly
boundaries. Requires `ready_to_run` and `self_contained`, because the framework
has to be part of the image.""",
            default = False,
        ),
        "_apphost_pack": attr.label(
            default = "//dotnet/private/sdk/apphost_packs:apphost_pack",
            providers = [DotnetApphostPackInfo],
            cfg = apphost_pack_transition,
        ),
        "_crossgen2_pack": attr.label(
            doc = """The crossgen2 pack to compile ReadyToRun images with.

Selected by the execution platform rather than the target: crossgen2
cross-compiles, so what matters is the machine it runs on.""",
            cfg = "exec",
            default = Label("//dotnet/private:crossgen2_pack"),
        ),
        "_apphost_shimmer": attr.label(
            providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo],
            executable = True,
            default = "//dotnet/private/tools/apphost_shimmer:apphost_shimmer",
            cfg = "exec",
        ),
        "_runtime_pack_default": attr.label(
            default = "//dotnet/private/sdk/runtime_packs:runtime_pack",
            providers = [DotnetRuntimePackInfo],
            cfg = runtime_pack_default_transition,
        ),
        "_runtime_pack_web": attr.label(
            default = "//dotnet/private/sdk/runtime_packs:runtime_pack",
            providers = [DotnetRuntimePackInfo],
            cfg = runtime_pack_web_transition,
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

def _publish_binary_macro_impl(name, **kwargs):
    # This macro is just a wrapper so that we can make the user experience for automatic
    # runtime identifier selection better. If the user does not provide a runtime identifier
    # we will use the target platform to determine the runtime identifier.
    # If the user provides a runtime identifier we will use that one. The wrapper macro
    # is needed because we don't have access to the target platform in the TFM/RID transition.

    rid = kwargs.get("runtime_identifier", None)
    if rid == None:
        kwargs["runtime_identifier"] = select({
            "@rules_dotnet//dotnet/private:linux-x64": "linux-x64",
            "@rules_dotnet//dotnet/private:osx-x64": "osx-x64",
            "@rules_dotnet//dotnet/private:windows-x64": "win-x64",
            "@rules_dotnet//dotnet/private:linux-arm64": "linux-arm64",
            "@rules_dotnet//dotnet/private:osx-arm64": "osx-arm64",
            "@rules_dotnet//dotnet/private:windows-arm64": "win-arm64",
        })

    _publish_binary(name = name, **kwargs)

publish_binary = macro(
    inherit_attrs = _publish_binary,
    implementation = _publish_binary_macro_impl,
)
