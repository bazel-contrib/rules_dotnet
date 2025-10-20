"""Rule that allows running .NET command-line tools hermetically within Bazel."""

load("//dotnet/private:common.bzl", "get_highest_compatible_target_framework", "to_rlocation_path")

DotnetToolInfo = provider(
    doc = "Provider for grouping .NET tools by target framework.",
    fields = {
        "files_by_tfm": "A dict mapping target frameworks to tool filegroups.",
    },
)

def _dotnet_tool_impl(ctx):
    windows_constraint = ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]
    if ctx.target_platform_has_constraint(windows_constraint):
        fail("The dotnet_tool rule currently does not support Windows targets.")

    toolchain = ctx.toolchains["//dotnet:toolchain_type"]
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

    repo_name = ctx.attr.deps.label.repo_name
    executable = "{}/tools/{}/any/{}".format(repo_name, framework, entrypoint)

    filegroup = ctx.attr.deps[DotnetToolInfo].files_by_tfm.get(framework)
    if filegroup == None:
        fail("Tool {} does not provide files for the target framework: {}".format(ctx.attr.name, framework))

    launcher = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._launcher_sh,
        output = launcher,
        substitutions = {
            "TEMPLATED_dotnet": to_rlocation_path(ctx, runtime.files_to_run.executable),
            "TEMPLATED_executable": executable,
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = filegroup[DefaultInfo].files.to_list() + dotnet_info.runtime_files)
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
You should instead add the tool as a dependency to your Paket dependencies, and
use paket2bazel to generate Bazel targets; any tools found within the Paket
dependencies will automatically be exposed as Bazel targets in the resulting
`nuget_repo` rule.
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
            default = "//dotnet/private:launcher.sh.tpl",
            allow_single_file = True,
        ),
        "_bash_runfiles": attr.label(default = "@rules_shell//shell/runfiles"),
        "_windows_constraint": attr.label(default = "@platforms//os:windows"),
    },
    toolchains = ["//dotnet:toolchain_type"],
)
