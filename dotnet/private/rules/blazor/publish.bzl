"""Rule for publishing Blazor applications."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:common.bzl",
    "get_toolchain",
)
load(
    "//dotnet/private:providers.bzl",
    "BlazorLibraryInfo",
    "DotnetAssemblyRuntimeInfo",
)
load("//dotnet/private/rules/csharp/actions:csharp_assembly.bzl", "AssemblyAction")
load("//dotnet/private/transitions:default_transition.bzl", "default_transition")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _normalize_entry_path(path):
    return path.strip("/")

def _add_entry(entries, file, entry_path):
    entry_path = _normalize_entry_path(entry_path)
    if not entry_path:
        fail("Invalid empty publish entry path for {}".format(file.path))
    if entry_path not in entries:
        entries[entry_path] = file

def _collect_runtime_entries(entries, packages, runtime_info, entry_assembly):
    for lib in runtime_info.libs:
        if lib != entry_assembly:
            entries[lib.path] = lib
    if runtime_info.nuget_info != None:
        package = runtime_info.nuget_info.nupkg
        packages[package.path] = package

def _bool(value):
    return "true" if value else "false"

def _blazor_publish_impl(ctx):
    if ctx.attr.mode != "wasm":
        fail("blazor_publish currently supports mode = \"wasm\" only.")
    if len(ctx.attr.target_frameworks) != 1:
        fail("blazor_publish requires exactly one target framework.")

    toolchain = get_toolchain(ctx)
    entry_info = ctx.attr.main[0][BlazorLibraryInfo]
    entry_runtime_info = entry_info.assembly_runtime_info
    if len(entry_runtime_info.libs) != 1:
        fail("The main Blazor library must provide exactly one assembly.")

    platform_info = ctx.actions.declare_file(ctx.attr.name + "/entry/BrowserAssemblyInfo.g.cs")
    ctx.actions.write(platform_info, "\n".join([
        '[assembly: System.Runtime.Versioning.TargetPlatform("browser1.0")]',
        '[assembly: System.Runtime.Versioning.SupportedOSPlatform("browser1.0")]',
        "",
    ]))
    _, entry_runtime_info = AssemblyAction(ctx.actions, **dicts.add(entry_info.compilation, {
        "defines": entry_info.compilation["defines"] + ["BROWSER", "BROWSER1_0", "BROWSER1_0_OR_GREATER"],
        "out": entry_runtime_info.name,
        "srcs": entry_info.compilation["srcs"] + [platform_info],
        "target": "exe",
        "target_name": ctx.attr.name + "/entry",
    }))
    entry_assembly = entry_runtime_info.libs[0]

    references = {}
    packages = {}
    _collect_runtime_entries(references, packages, entry_runtime_info, entry_assembly)
    for runtime_info in entry_runtime_info.deps.to_list():
        _collect_runtime_entries(references, packages, runtime_info, entry_assembly)
    for dep in ctx.attr.deps:
        runtime_info = dep[DotnetAssemblyRuntimeInfo]
        _collect_runtime_entries(references, packages, runtime_info, entry_assembly)
        for dep_runtime_info in runtime_info.deps.to_list():
            _collect_runtime_entries(references, packages, dep_runtime_info, entry_assembly)

    assets = {}
    for library in ctx.attr.main + ctx.attr.deps:
        if BlazorLibraryInfo not in library:
            continue
        for asset in library[BlazorLibraryInfo].transitive_static_web_assets:
            prefix = "" if asset.source_name == entry_runtime_info.name else "_content/{}/".format(asset.source_name)
            _add_entry(assets, asset.file, "wwwroot/" + prefix + asset.relative_path)

    if len(ctx.attr.nuget_assets) != len(ctx.attr.nuget_asset_paths):
        fail("nuget_assets and nuget_asset_paths must have the same length.")

    for i, target in enumerate(ctx.attr.nuget_assets):
        files = target[DefaultInfo].files.to_list()
        if len(files) != 1:
            fail("nuget_assets keys must resolve to exactly one file: {} resolved to {} files".format(target.label, len(files)))
        _add_entry(assets, files[0], ctx.attr.nuget_asset_paths[i])

    wasm_workload_files = getattr(toolchain, "wasm_workload_files", []) + ctx.files._wasm_workload_files
    if len(wasm_workload_files) == 0:
        fail("The selected .NET toolchain does not provide wasm-tools workload files. For host toolchains, install wasm-tools into the host SDK. External toolchains should install it during repository setup.")

    illink_task = None
    for file in ctx.files._illink_host_files:
        if file.path.endswith("/tools/net/ILLink.Tasks.dll"):
            illink_task = file
            break
    if illink_task == None:
        fail("Microsoft.NET.ILLink.Tasks must provide tools/net/ILLink.Tasks.dll.")

    output = ctx.actions.declare_file(ctx.attr.name + ".zip")
    args = ctx.actions.args()
    args.add("publish")
    args.add("--mode", ctx.attr.mode)
    args.add("--output", output)
    args.add("--dotnet", ctx.file._wasm_dotnet)
    args.add("--target-framework", ctx.attr.target_frameworks[0] + "-browser")
    args.add("--assembly-name", entry_runtime_info.name)
    args.add("--entry-assembly", entry_assembly)
    args.add("--illink-task", illink_task)
    for _, reference in sorted(references.items()):
        args.add("--reference", reference)
    for _, package in sorted(packages.items()):
        args.add("--package", package)
    for entry_path, asset in sorted(assets.items()):
        args.add("--asset", asset.path + "|" + entry_path)
    args.add("--property", "PublishTrimmed=" + _bool(ctx.attr.publish_trimmed))
    args.add("--property", "TrimMode=" + ctx.attr.trim_mode)
    args.add("--property", "WasmEmitSymbolMap=" + _bool(ctx.attr.wasm_emit_symbol_map))
    args.add("--property", "WasmNativeStrip=" + _bool(ctx.attr.wasm_native_strip))
    args.add("--property", "WasmEmitSourceMap=" + _bool(ctx.attr.wasm_emit_source_map))
    args.add("--property", "CompressionEnabled=" + _bool(ctx.attr.compression_enabled))

    inputs = depset(
        direct = [entry_assembly, ctx.file._wasm_dotnet] + references.values() + assets.values() + packages.values() + wasm_workload_files + ctx.files._illink_host_files,
        transitive = [toolchain.runtime.default_runfiles.files],
    )

    ctx.actions.run(
        mnemonic = "BlazorPublish",
        progress_message = "Publishing Blazor application " + ctx.attr.name,
        executable = ctx.attr._blazor_helper[DefaultInfo].files_to_run,
        inputs = inputs,
        outputs = [output],
        arguments = [args],
    )

    return [
        DefaultInfo(files = depset([output])),
        OutputGroupInfo(entry_assembly = depset([entry_assembly])),
    ]

blazor_publish = rule(
    _blazor_publish_impl,
    doc = "Publish a Blazor application's wwwroot contents as a ZIP, excluding duplicate precompressed variants.",
    attrs = {
        "main": attr.label(
            doc = "Blazor library whose sources are compiled as the executable entry assembly during publishing. Its static assets are published at the web root.",
            providers = [BlazorLibraryInfo, DotnetAssemblyRuntimeInfo],
            cfg = tfm_transition,
            mandatory = True,
        ),
        "deps": attr.label_list(
            doc = "Additional assemblies to publish alongside main and its transitive dependencies. Blazor dependency assets are published under _content/<assembly name>/.",
            providers = [DotnetAssemblyRuntimeInfo],
            cfg = tfm_transition,
        ),
        "mode": attr.string(
            doc = "Blazor publishing mode. Only wasm is supported initially.",
            default = "wasm",
            values = ["wasm"],
        ),
        "target_frameworks": attr.string_list(
            doc = "Target framework monikers supported by this publish target.",
            mandatory = True,
            allow_empty = False,
        ),
        "runtime_identifier": attr.string(
            doc = "Runtime identifier used to resolve application dependencies.",
            default = "browser-wasm",
            values = ["browser-wasm"],
        ),
        "publish_trimmed": attr.bool(default = True),
        "trim_mode": attr.string(default = "partial", values = ["copyused", "link", "partial"]),
        "wasm_emit_symbol_map": attr.bool(default = False),
        "wasm_native_strip": attr.bool(default = True),
        "wasm_emit_source_map": attr.bool(default = False),
        "compression_enabled": attr.bool(default = True),
        "nuget_assets": attr.label_list(
            doc = "Explicit external or NuGet asset files to publish.",
            allow_files = True,
            cfg = default_transition,
        ),
        "nuget_asset_paths": attr.string_list(
            doc = "Publish-relative paths for nuget_assets, in the same order. Only wwwroot/ contents are archived, with that prefix removed.",
        ),
        "_blazor_helper": attr.label(
            default = "//tools/blazor",
            executable = True,
            cfg = "exec",
        ),
        "_illink_host_files": attr.label(
            default = "@paket.blazor_dependencies//microsoft.net.illink.tasks:files",
            allow_files = True,
            cfg = "exec",
        ),
        "_wasm_workload_files": attr.label(
            default = "@dotnet_wasm_workload//:wasm_workload_files",
            allow_files = True,
            cfg = "exec",
        ),
        "_wasm_dotnet": attr.label(
            default = "@dotnet_wasm_workload//:dotnet",
            allow_single_file = True,
            cfg = "exec",
        ),
    },
    toolchains = ["//dotnet:toolchain_type"],
)
