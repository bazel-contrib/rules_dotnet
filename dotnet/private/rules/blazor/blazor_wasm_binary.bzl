"""Running a Blazor WebAssembly application during development.

A WebAssembly application runs in the browser, so `bazel run` has nothing to
execute. MSBuild answers this by convention - the Blazor WebAssembly SDK
overrides `RunCommand` so that `dotnet run` starts a development server - and
this rule is that convention; `devserver.bzl` runs the server itself.

It wraps the ordinary binary rather than replacing it, forwarding everything
the binary provides, so a `publish_binary` or a dependent library sees no
difference. Wrapping also keeps the WebAssembly packs off every other target:
the runtime pack is selected on the target framework with no default branch, so
the rule that carries it cannot be the rule every C# and F# binary is built by.

Nothing is trimmed and symbols are shipped, as in `dotnet build`: trimming only
serves download size and would discard what a debugger needs.
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
    toolchains = ["//dotnet:toolchain_type"],
)
