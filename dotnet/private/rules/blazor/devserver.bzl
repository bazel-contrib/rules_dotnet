"""Serving a Blazor WebAssembly application for development.

This runs the SDK's own `blazor-devserver`, from
`Microsoft.AspNetCore.Components.WebAssembly.DevServer`, rather than a static
file server of our own: the package carries a debug proxy that maps the
browser's debugger onto the application, so devtools show C# and F# rather than
WebAssembly.

The server addresses an application by its assembly, expecting the endpoint
manifest beside it and the served directory under the content root. Neither has
to be where the application was built, so this stages the two it needs.
"""

load("//dotnet/private:common.bzl", "get_toolchain", "targets_windows", "to_rlocation_path")
load("//dotnet/private:providers.bzl", "BlazorWasmSiteInfo")
load(":common.bzl", "only")

def devserver_launcher(ctx, site):
    """Builds the executable that serves an application.

    Args:
      ctx: The rule context, carrying `DEVSERVER_ATTRS`.
      site: The `BlazorWasmSiteInfo` to serve.

    Returns:
      A struct of the `launcher` and the `runfiles` it needs.
    """

    # The server reads the manifest from beside the assembly it is given, so
    # both are staged here rather than wherever they were built.
    staged = "{}/serve".format(ctx.label.name)
    application = ctx.actions.declare_file("{}/{}".format(staged, site.assembly.basename))
    ctx.actions.symlink(output = application, target_file = site.assembly)

    manifest = ctx.actions.declare_file("{}/{}".format(staged, site.manifest.basename))
    ctx.actions.symlink(output = manifest, target_file = site.manifest)

    # This pack ships one build rather than one per framework, so unlike the
    # publish tools it sits directly under `tools/`.
    devserver = only(ctx.files._devserver, "blazor-devserver.dll", "the development server")
    toolchain = get_toolchain(ctx)
    dotnet = toolchain.runtime.files_to_run.executable

    is_windows = targets_windows(ctx)
    launcher = ctx.actions.declare_file(
        "{}{}".format(ctx.label.name, ".bat" if is_windows else ".sh"),
    )
    ctx.actions.expand_template(
        template = ctx.file._devserver_bat if is_windows else ctx.file._devserver_sh,
        output = launcher,
        substitutions = {
            "TEMPLATED_dotnet": to_rlocation_path(ctx, dotnet),
            "TEMPLATED_devserver": to_rlocation_path(ctx, devserver),
            "TEMPLATED_application": to_rlocation_path(ctx, application),
            "TEMPLATED_wwwroot": to_rlocation_path(ctx, site.wwwroot),
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [site.wwwroot, manifest, application],
        transitive_files = depset(transitive = [
            ctx.attr._devserver.files,
            toolchain.runtime.files,
        ]),
    ).merge(
        # The launcher resolves its runfiles with Bazel's own bash library,
        # which is carried as runfiles rather than as files.
        ctx.attr._bash_runfiles[DefaultInfo].default_runfiles,
    )

    return struct(launcher = launcher, runfiles = runfiles)

DEVSERVER_ATTRS = {
    "_devserver": attr.label(
        default = "//dotnet/private:devserver",
        allow_files = True,
        cfg = "exec",
    ),
    "_devserver_sh": attr.label(
        default = "//dotnet/private:devserver.sh.tpl",
        allow_single_file = True,
    ),
    "_devserver_bat": attr.label(
        default = "//dotnet/private:devserver.bat.tpl",
        allow_single_file = True,
    ),
    "_bash_runfiles": attr.label(default = "@bazel_tools//tools/bash/runfiles"),
    "_windows_constraint": attr.label(default = "@platforms//os:windows"),
}

def _blazor_devserver_impl(ctx):
    served = devserver_launcher(ctx, ctx.attr.app[BlazorWasmSiteInfo])

    return [
        DefaultInfo(
            executable = served.launcher,
            runfiles = served.runfiles,
        ),
    ]

blazor_devserver = rule(
    _blazor_devserver_impl,
    doc = """Serve a Blazor WebAssembly application, with debugging.

Takes anything that produces one, so a publish can be served exactly as it will
be deployed:

```python
publish_binary(
    name = "publish",
    binary = ":app",
    target_framework = "net10.0",
    wasm = True,
)

blazor_devserver(
    name = "serve",
    app = ":publish",
)
```

`bazel run //path/to:serve` then serves it on `http://127.0.0.1:5000/`; pass
`--urls` to change the address.""",
    executable = True,
    attrs = dict(DEVSERVER_ATTRS, app = attr.label(
        doc = "The application to serve.",
        providers = [BlazorWasmSiteInfo],
        mandatory = True,
    )),
    toolchains = ["//dotnet:toolchain_type"],
)
