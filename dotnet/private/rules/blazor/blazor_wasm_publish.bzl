"""Publishing a Blazor WebAssembly application.

A browser cannot load a .NET assembly, so a publish rewrites the application
into something it can: the whole program is trimmed to what the entry point
reaches, every assembly that survives becomes a Webcil module, the Mono
runtime's own files are copied in beside them, and a boot configuration listing
all of it is merged into `dotnet.js`. The result is an ordinary static site,
served through the same static web asset machinery as any other web target.

Nothing here is specific to C#. The application arrives as compiled assemblies,
so an `fsharp_binary` publishes exactly the same way.

This is reached through `publish_binary(wasm = True)` rather than directly: a
browser publish produces a site rather than something to run, which is why it
cannot be the same rule, but it is the same public API.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:providers.bzl",
    "BlazorWasmInfo",
    "DotnetBinaryInfo",
)
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")
load(":common.bzl", "ASSEMBLE_ATTRS", "TRIM_MODES", "TRIM_MODE_DOC", "assemble_site")

def _blazor_wasm_publish_impl(ctx):
    binary = ctx.attr.binary[0]
    if BlazorWasmInfo not in binary:
        fail(
            "%s publishes %s for a browser, but that target is not a Blazor WebAssembly application.\n" % (ctx.label, binary.label) +
            "Set `project_sdk = \"blazorwasm\"` on it, the way MSBuild asks for " +
            "`Microsoft.NET.Sdk.BlazorWebAssembly` rather than `Microsoft.NET.Sdk.Web`.",
        )

    # Trimming removes whole assemblies, so the directory it leaves behind
    # cannot be described before the action runs.
    trimmed = ctx.actions.declare_directory("{}/trimmed".format(ctx.label.name))
    assembled = assemble_site(
        ctx,
        tfm = ctx.attr.target_framework,
        verb = "publish",
        trimmed = trimmed,
        trim_mode = ctx.attr.trim_mode,
    )

    files = [assembled.site.wwwroot, assembled.site.manifest]
    return [
        DefaultInfo(files = depset(files), runfiles = ctx.runfiles(files = files)),
        assembled.site,
    ]

blazor_wasm_publish = rule(
    _blazor_wasm_publish_impl,
    doc = """Publish a Blazor WebAssembly application as a static site.""",
    attrs = dicts.add(ASSEMBLE_ATTRS, {
        "binary": attr.label(
            doc = "The Blazor WebAssembly application to publish.",
            providers = [DotnetBinaryInfo],
            cfg = tfm_transition,
            mandatory = True,
        ),
        "target_framework": attr.string(
            doc = "The target framework that should be published.",
            mandatory = True,
        ),
        "trim_mode": attr.string(
            doc = TRIM_MODE_DOC,
            default = "full",
            values = TRIM_MODES,
        ),
        "_illink": attr.label(
            default = "//dotnet/private:illink",
            allow_files = True,
            cfg = "exec",
        ),
    }),
)
