"""Running a Blazor WebAssembly application during development.

As `dotnet run` does for the Blazor WebAssembly SDK, `bazel run` starts a
development server. The rule wraps the ordinary binary and forwards its
providers, so `publish_binary` and dependents see no difference, while only
this rule carries the WebAssembly packs: the runtime pack is selected on the
target framework with no default, so it cannot sit on every binary.

As in `dotnet build`, nothing is trimmed and symbols are shipped.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:providers.bzl",
    "BlazorWasmInfo",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
    "DotnetBinaryInfo",
    "StaticWebAssetsInfo",
)
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")
load(":common.bzl", "APPLICATION_ENVIRONMENT_DOC", "ASSEMBLE_ATTRS", "assemble_site")
load(":devserver.bzl", "DEVSERVER_ATTRS", "devserver_launcher")

def _blazor_wasm_binary_impl(ctx):
    assembled = assemble_site(
        ctx,
        tfm = ctx.attr.target_framework,
        verb = "be built",
        debug = True,
        # Nothing is downloaded over a network, so the compressed variants would
        # cost the whole runtime's worth of Brotli on every edit and buy nothing.
        compress = False,
    )
    devserver = devserver_launcher(ctx, assembled.site)

    # Everything the wrapped binary provided, so that depending on this target
    # is the same as depending on the binary itself.
    forwarded = [
        BlazorWasmInfo(),
        assembled.binary[DotnetAssemblyCompileInfo],
        assembled.binary[DotnetAssemblyRuntimeInfo],
        assembled.binary[DotnetBinaryInfo],
        # Named rather than forwarded whole: the binary's other output groups
        # are Bazel's own, and the wrapper has its own of those.
        OutputGroupInfo(
            deps_json = assembled.binary[OutputGroupInfo].deps_json,
            runtimeconfig_json = assembled.binary[OutputGroupInfo].runtimeconfig_json,
        ),
    ]
    if StaticWebAssetsInfo in assembled.binary:
        forwarded.append(assembled.binary[StaticWebAssetsInfo])

    return forwarded + [
        assembled.site,
        DefaultInfo(
            executable = devserver.launcher,
            files = depset([assembled.site.wwwroot, assembled.site.manifest, devserver.launcher]),
            runfiles = devserver.runfiles,
        ),
    ]

blazor_wasm_binary = rule(
    _blazor_wasm_binary_impl,
    doc = """Serve a Blazor WebAssembly application for development.""",
    executable = True,
    attrs = dicts.add(ASSEMBLE_ATTRS, DEVSERVER_ATTRS, {
        "binary": attr.label(
            doc = "The Blazor WebAssembly application to serve.",
            providers = [DotnetBinaryInfo],
            cfg = tfm_transition,
            mandatory = True,
        ),
        "target_framework": attr.string(
            doc = "The target framework that should be served.",
            mandatory = True,
        ),
        # A development run is the one that `dotnet run` would start, so it
        # starts in the environment `dotnet run` uses.
        "application_environment": attr.string(
            doc = APPLICATION_ENVIRONMENT_DOC,
            default = "Development",
        ),
    }),
    toolchains = ["//dotnet/toolchain:toolchain_type"],
)
