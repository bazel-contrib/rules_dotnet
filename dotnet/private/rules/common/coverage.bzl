"""Code coverage for `bazel coverage`.

Every C# and F# library and binary that `--instrumentation_filter` selects lists
its assembly in `DotnetCoverageInfo`, and a test gathers the lists of its
dependencies. Under `bazel coverage` the test's launcher hands that list to the
coverage tool (`//dotnet/settings:coverage_tool`), which instruments those
assemblies, runs the test and writes LCOV where Bazel's coverage merger reads
it. Under `bazel test` none of this is analysed, so the tool is never fetched.
"""

load("//dotnet/private:common.bzl", "to_rlocation_path")
load("//dotnet/private:providers.bzl", "DotnetCoverageInfo")

# The attributes a test rule needs for `bazel coverage`.
TEST_COVERAGE_ATTRS = {
    "_coverage_tool": attr.label(
        doc = "The coverage tool, or an empty filegroup outside `bazel coverage`.",
        default = "//dotnet/private/coverage:test_coverage_tool",
    ),
    "_lcov_merger": attr.label(
        default = configuration_field(fragment = "coverage", name = "output_generator"),
        executable = True,
        cfg = "exec",
    ),
}

# Runs the test through the coverage tool when Bazel asks for coverage. The
# tool is handed the runtime, the test assembly and the file listing the
# assemblies to instrument, then the test's own arguments.
_COVERAGE_BLOCK_SH = """\
if [[ -n "${{COVERAGE:-}}" ]]; then
  exec "$(rlocation {tool})" "$(rlocation {dotnet})" "$(rlocation {executable})" "$(rlocation {assemblies})" "$@"
fi"""

def coverage_providers(ctx, runtime_provider, dependency_attributes):
    """The coverage providers of a library or binary.

    Args:
        ctx: The rule context.
        runtime_provider: The target's DotnetAssemblyRuntimeInfo.
        dependency_attributes: The attributes holding the target's dependencies.

    Returns:
        A list of DotnetCoverageInfo and InstrumentedFilesInfo.
    """

    deps = [dep for attr in dependency_attributes for dep in getattr(ctx.attr, attr, [])]

    # An assembly without a PDB cannot be mapped to its sources, so it is not
    # instrumented whatever the filter says.
    own = runtime_provider.libs if ctx.coverage_instrumented() and runtime_provider.pdbs else []

    return [
        DotnetCoverageInfo(assemblies = depset(
            own,
            transitive = [dep[DotnetCoverageInfo].assemblies for dep in deps if DotnetCoverageInfo in dep],
        )),
        coverage_common.instrumented_files_info(
            ctx,
            source_attributes = ["srcs"],
            dependency_attributes = dependency_attributes,
        ),
    ]

def coverage_launcher(ctx, coverage_info, executable, toolchain, is_windows):
    """What a test launcher needs to run under the coverage tool.

    Args:
        ctx: The rule context of a test.
        coverage_info: The test's DotnetCoverageInfo.
        executable: The test assembly.
        toolchain: The .Net toolchain the test runs with.
        is_windows: Whether the test runs on Windows.

    Returns:
        A (launcher substitution, runfiles) tuple. Both are empty outside
        `bazel coverage`, for a rule that is not a test, and on Windows, where
        the coverage tool does not run.
    """

    tool = getattr(ctx.attr, "_coverage_tool", None)
    if not ctx.configuration.coverage_enabled or tool == None or is_windows:
        return ("", ctx.runfiles())

    tool_executable = tool[DefaultInfo].files_to_run.executable
    if tool_executable == None:
        return ("", ctx.runfiles())

    assemblies = ctx.actions.declare_file("{}.coverage_assemblies".format(executable.basename), sibling = executable)
    ctx.actions.write(
        output = assemblies,
        content = "".join([to_rlocation_path(ctx, dll) + "\n" for dll in coverage_info.assemblies.to_list()]),
    )

    block = _COVERAGE_BLOCK_SH.format(
        tool = to_rlocation_path(ctx, tool_executable),
        dotnet = to_rlocation_path(ctx, toolchain.runtime.files_to_run.executable),
        executable = to_rlocation_path(ctx, executable),
        assemblies = to_rlocation_path(ctx, assemblies),
    )
    runfiles = ctx.runfiles(files = [assemblies, tool_executable]).merge(tool[DefaultInfo].default_runfiles)
    return (block, runfiles)
