def _fake_executable_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = out,
        content = "#!/usr/bin/env bash\nexit 0\n",
        is_executable = True,
    )
    return [DefaultInfo(executable = out, files = depset([out]))]

fake_executable = rule(
    implementation = _fake_executable_impl,
    executable = True,
)

def _windows_platform_transition_impl(_settings, _attr):
    return {
        "//command_line_option:platforms": "//dotnet/private/tests/target_runtime:windows_x64",
    }

_windows_platform_transition = transition(
    implementation = _windows_platform_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _target_runtime_test_impl(ctx):
    toolchain_under_test = ctx.attr.toolchain_under_test
    if type(toolchain_under_test) == "list":
        toolchain_under_test = toolchain_under_test[0]
    toolchain = toolchain_under_test[platform_common.ToolchainInfo]
    return _assert_windows_runtime(ctx, toolchain)

def _resolved_target_runtime_test_impl(ctx):
    toolchain = ctx.toolchains["//dotnet:toolchain_type"]
    return _assert_windows_runtime(ctx, toolchain)

def _assert_windows_runtime(ctx, toolchain):
    target_runtime_files = [
        file.basename
        for file in toolchain.dotnetinfo.target_runtime_files
    ]

    if "runtime_windows.sh" not in target_runtime_files:
        fail("Expected target runtime files to contain runtime_windows.sh, got: {}".format(target_runtime_files))

    out = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = out,
        content = "#!/usr/bin/env bash\nexit 0\n",
        is_executable = True,
    )
    return [DefaultInfo(executable = out)]

target_runtime_test = rule(
    implementation = _target_runtime_test_impl,
    attrs = {
        "toolchain_under_test": attr.label(
            cfg = _windows_platform_transition,
            providers = [platform_common.ToolchainInfo],
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    test = True,
)

resolved_target_runtime_test = rule(
    implementation = _resolved_target_runtime_test_impl,
    test = True,
    toolchains = ["//dotnet:toolchain_type"],
)
