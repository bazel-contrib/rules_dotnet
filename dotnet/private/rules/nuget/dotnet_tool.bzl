"""Rule that allows running .NET command-line tools hermetically within Bazel."""

load("//dotnet/private:common.bzl", "get_highest_compatible_target_framework", "get_toolchain", "to_rlocation_path")
load("//dotnet/private/icu:settings.bzl", "icu_files", "icu_launcher_environment")

DotnetToolInfo = provider(
    doc = "Provider for grouping .NET tools by target framework.",
    fields = {
        "files_by_tfm": "A dict mapping target frameworks to tool filegroups.",
    },
)

def _tool_executable(ctx, files, entrypoint):
    """Finds the assembly a tool's settings file names.

    `entrypoint` is a bare file name, resolved against the folder holding the
    `DotnetToolSettings.xml` that named it. The folder cannot be rebuilt from
    the framework: a package names it with whatever spelling of the framework it
    shipped, which is not always the one the tool resolved to.

    Args:
      ctx: The rule context.
      files: The files the package ships for the resolved framework.
      entrypoint: The file name the settings file names.

    Returns:
      The rlocation path of the entrypoint, or None when it is not shipped.
    """
    directory = None

    for file in files:
        if file.basename == "DotnetToolSettings.xml":
            directory = file.dirname
            break

    for file in files:
        if file.dirname == directory and file.basename == entrypoint:
            return to_rlocation_path(ctx, file)

    return None

def _dotnet_tool_impl(ctx):
    toolchain = get_toolchain(ctx)

    runtime = toolchain.runtime
    dotnet_info = toolchain.dotnetinfo

    framework = get_highest_compatible_target_framework(dotnet_info.runtime_tfm, ctx.attr.target_frameworks)
    if framework == None:
        fail("The current .NET runtime ({}) does not support any of the target frameworks specified for this tool: {}".format(dotnet_info.runtime_tfm, ctx.attr.target_frameworks))

    entrypoint = ctx.attr.entrypoint.get(framework)
    runner = ctx.attr.runner.get(framework)

    if entrypoint == None or runner == None:
        fail("The tool does not support the target framework: {}".format(framework))
    if runner != "dotnet":
        fail("Unsupported runner '{}' for target framework '{}'. Currently, only 'dotnet' is supported.".format(runner, framework))

    filegroup = ctx.attr.deps[DotnetToolInfo].files_by_tfm.get(framework)
    if filegroup == None:
        fail("Tool {} does not provide files for the target framework: {}".format(ctx.attr.name, framework))

    executable = _tool_executable(ctx, filegroup[DefaultInfo].files.to_list(), entrypoint)
    if executable == None:
        fail("Tool {} does not ship its entrypoint '{}' for the target framework: {}".format(ctx.attr.name, entrypoint, framework))

    is_windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo])
    launcher = ctx.actions.declare_file("{}.{}".format(ctx.label.name, "bat" if is_windows else "sh"))
    ctx.actions.expand_template(
        template = ctx.file._launcher_bat if is_windows else ctx.file._launcher_sh,
        output = launcher,
        substitutions = {
            "TEMPLATED_dotnet": to_rlocation_path(ctx, runtime.files_to_run.executable),
            "TEMPLATED_executable": executable,
            "TEMPLATED_environment": icu_launcher_environment(ctx, toolchain, is_windows),
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(transitive_files = depset(
        transitive = [filegroup[DefaultInfo].files, dotnet_info.runtime_files, icu_files(toolchain)],
    ))
    runfiles = runfiles.merge(ctx.attr._bash_runfiles[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            executable = launcher,
            runfiles = runfiles,
        ),
    ]

dotnet_tool = rule(
    implementation = _dotnet_tool_impl,
    executable = True,
    doc = """Run a .NET command-line tool hermetically via Bazel.

This rule allows you to run a pre-built .NET command-line tool that has been packaged
with NuGet. The tool is executed using the hermetic .NET runtime provided by `rules_dotnet`.

This is a lower-level API that requires a manual specification of tool details.
Prefer adding the tool to your `paket.dependencies`: every dotnet tool in a
dependency group is exposed automatically as `@<group>//<package>/tools:<tool>`.
""",
    attrs = {
        "target_frameworks": attr.string_list(
            doc = "The target frameworks this tool was built for.",
            mandatory = True,
        ),
        "entrypoint": attr.string_dict(
            mandatory = True,
            doc = "The entrypoint of the dotnet tool (the dll to execute), keyed by the target framework.",
        ),
        "runner": attr.string_dict(
            mandatory = True,
            doc = "The runner to use to execute the tool, keyed by the target framework. Currently, only 'dotnet' is supported.",
        ),
        "deps": attr.label(
            mandatory = True,
            providers = [DotnetToolInfo],
            doc = "The dependencies of the dotnet tool. Must include a DotnetToolInfo provider.",
        ),
        "_launcher_sh": attr.label(
            doc = "A template file for the launcher on Linux/MacOS",
            default = "//dotnet/private:tool_launcher.sh.tpl",
            allow_single_file = True,
        ),
        "_launcher_bat": attr.label(
            doc = "A template file for the launcher on Windows",
            default = "//dotnet/private:tool_launcher.bat.tpl",
            allow_single_file = True,
        ),
        "_bash_runfiles": attr.label(default = "@rules_shell//shell/runfiles"),
        "_windows_constraint": attr.label(default = "@platforms//os:windows"),
    },
    toolchains = ["//dotnet:toolchain_type"],
)
