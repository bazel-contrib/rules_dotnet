"""The default coverage tool: coverlet.console behind a wrapper that fits Bazel."""

load("//dotnet/private:common.bzl", "to_rlocation_path")

def _coverlet_coverage_tool_impl(ctx):
    coverlet = ctx.attr.coverlet[DefaultInfo].files_to_run.executable
    wrapper = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._wrapper,
        output = wrapper,
        substitutions = {"TEMPLATED_coverlet": to_rlocation_path(ctx, coverlet)},
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [coverlet]).merge_all([
        ctx.attr.coverlet[DefaultInfo].default_runfiles,
        ctx.attr._bash_runfiles[DefaultInfo].default_runfiles,
    ])
    return [DefaultInfo(executable = wrapper, runfiles = runfiles)]

coverlet_coverage_tool = rule(
    implementation = _coverlet_coverage_tool_impl,
    executable = True,
    doc = """Runs a .NET test under coverlet.console for `bazel coverage`.

The test launcher calls the tool as

    <tool> <dotnet> <test.dll> <assemblies> [test arguments...]

where `<assemblies>` is a file listing, one per line, the runfiles paths of the
DLLs to instrument. A replacement coverage tool takes the same arguments, runs
the test and writes LCOV to a `*.dat` file under `$COVERAGE_DIR`.""",
    attrs = {
        "coverlet": attr.label(
            doc = "The coverlet.console executable.",
            executable = True,
            cfg = "target",
            mandatory = True,
        ),
        "_wrapper": attr.label(
            default = "//dotnet/private/coverage:coverlet.sh.tpl",
            allow_single_file = True,
        ),
        "_bash_runfiles": attr.label(default = "@rules_shell//shell/runfiles"),
    },
)
