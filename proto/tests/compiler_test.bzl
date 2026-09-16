"""Tests for gRPC compiler selection across target and execution platforms."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//proto:defs.bzl", "CsharpProtoCompilerInfo", "csharp_grpc_proto_compiler", "grpc_csharp_plugin")

_PLATFORMS = {
    "linux_x86": ["@platforms//os:linux", "@platforms//cpu:x86_32"],
    "linux_x64": ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    "linux_arm64": ["@platforms//os:linux", "@platforms//cpu:arm64"],
    "macosx_x64": ["@platforms//os:macos", "@platforms//cpu:x86_64"],
    "macosx_arm64": ["@platforms//os:macos", "@platforms//cpu:arm64"],
    "windows_x86": ["@platforms//os:windows", "@platforms//cpu:x86_32"],
    "windows_x64": ["@platforms//os:windows", "@platforms//cpu:x86_64"],
    "windows_arm64": ["@platforms//os:windows", "@platforms//cpu:arm64"],
    "linux_arm": ["@platforms//os:linux", "@platforms//cpu:arm"],
}

_PACKAGED_PLATFORMS = ["linux_x86", "linux_x64", "linux_arm64", "macosx_x64", "windows_x86", "windows_x64"]

def _package_impl(ctx):
    files = []
    for platform in ctx.attr.platforms:
        filename = "grpc_csharp_plugin.exe" if platform.startswith("windows_") else "grpc_csharp_plugin"
        output = ctx.actions.declare_file("{}/tools/{}/{}".format(ctx.label.name, platform, filename))
        ctx.actions.write(output, "Analysis-only plugin fixture", is_executable = True)
        files.append(output)
    return [DefaultInfo(files = depset(files))]

_package = rule(
    implementation = _package_impl,
    attrs = {"platforms": attr.string_list()},
)

def _selection_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    executable = target[DefaultInfo].files_to_run.executable
    actions = [action for action in analysistest.target_actions(env) if executable in action.outputs.to_list()]
    filename = "grpc_csharp_plugin.exe" if ctx.attr.expected_platform.startswith("windows_") else "grpc_csharp_plugin"
    suffix = "/tools/{}/{}".format(ctx.attr.expected_platform, filename)
    asserts.equals(env, 1, len(actions))
    asserts.equals(env, 1, len([file for file in actions[0].inputs.to_list() if file.path.endswith(suffix)]))
    asserts.equals(env, ctx.attr.expected_platform.startswith("windows_"), executable.basename.endswith(".exe"))
    return analysistest.end(env)

def _make_selection_test(platform):
    return analysistest.make(
        _selection_test_impl,
        attrs = {"expected_platform": attr.string(mandatory = True)},
        config_settings = {"//command_line_option:platforms": str(Label("//proto/tests:" + platform))},
    )

_linux_x86_test = _make_selection_test("linux_x86")
_linux_x64_test = _make_selection_test("linux_x64")
_linux_arm64_test = _make_selection_test("linux_arm64")
_macosx_x64_test = _make_selection_test("macosx_x64")
_macosx_arm64_test = _make_selection_test("macosx_arm64")
_windows_x86_test = _make_selection_test("windows_x86")
_windows_x64_test = _make_selection_test("windows_x64")
_windows_arm64_test = _make_selection_test("windows_arm64")

def _failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.message)
    return analysistest.end(env)

_missing_test = analysistest.make(
    _failure_test_impl,
    expect_failure = True,
    attrs = {"message": attr.string()},
    config_settings = {"//command_line_option:platforms": str(Label("//proto/tests:linux_x64"))},
)

_unsupported_test = analysistest.make(
    _failure_test_impl,
    expect_failure = True,
    attrs = {"message": attr.string()},
    config_settings = {"//command_line_option:platforms": str(Label("//proto/tests:linux_arm"))},
)

_macos_arm64_missing_test = analysistest.make(
    _failure_test_impl,
    expect_failure = True,
    attrs = {"message": attr.string()},
    config_settings = {"//command_line_option:platforms": str(Label("//proto/tests:macosx_arm64"))},
)

_windows_arm64_missing_test = analysistest.make(
    _failure_test_impl,
    expect_failure = True,
    attrs = {"message": attr.string()},
    config_settings = {"//command_line_option:platforms": str(Label("//proto/tests:windows_arm64"))},
)

def _compiler_test_impl(ctx):
    env = analysistest.begin(ctx)
    compiler = analysistest.target_under_test(env)[CsharpProtoCompilerInfo].proto_lang_toolchain_info
    expected = ctx.attr.expected_plugin[DefaultInfo].files_to_run.executable
    asserts.equals(env, expected, compiler.plugin.executable)
    asserts.equals(env, "--grpc_out=no_server,internal_access:%s", compiler.out_replacement_format_flag)
    asserts.equals(env, "--plugin=protoc-gen-grpc=%s", compiler.plugin_format_flag)
    return analysistest.end(env)

_compiler_test = analysistest.make(
    _compiler_test_impl,
    attrs = {"expected_plugin": attr.label(executable = True, cfg = "exec", mandatory = True)},
    config_settings = {"//command_line_option:platforms": str(Label("//proto/tests:windows_arm64"))},
)

def compiler_tests(name):
    """Instantiate the platform matrix and compiler integration tests.

    Args:
        name: Name of the test suite.
    """
    for platform, constraints in _PLATFORMS.items():
        native.platform(name = platform, constraint_values = constraints)

    _package(name = "package", platforms = _PACKAGED_PLATFORMS)
    _package(name = "native_package", platforms = _PACKAGED_PLATFORMS + ["macosx_arm64", "windows_arm64"])
    _package(name = "universal_package", platforms = [platform for platform in _PACKAGED_PLATFORMS if platform != "macosx_x64"] + ["macosx_universal"])
    _package(name = "empty_package")
    _package(name = "duplicate_package", platforms = ["linux_x64"])
    native.filegroup(name = "duplicate_files", srcs = [":package", ":duplicate_package"])

    for plugin_name, package in [("plugin", "package"), ("native_plugin", "native_package"), ("universal_plugin", "universal_package"), ("missing_plugin", "empty_package"), ("duplicate_plugin", "duplicate_files")]:
        grpc_csharp_plugin(name = plugin_name, grpc_tools = ":" + package, tags = ["manual"])

    for platform, test in [
        ("linux_x86", _linux_x86_test),
        ("linux_x64", _linux_x64_test),
        ("linux_arm64", _linux_arm64_test),
        ("macosx_x64", _macosx_x64_test),
        ("macosx_arm64", _macosx_arm64_test),
        ("windows_x86", _windows_x86_test),
        ("windows_x64", _windows_x64_test),
        ("windows_arm64", _windows_arm64_test),
    ]:
        test(name = platform + "_test", target_under_test = ":native_plugin", expected_platform = platform, size = "small")

    _macosx_arm64_test(name = "macos_arm64_universal_test", target_under_test = ":universal_plugin", expected_platform = "macosx_universal", size = "small")
    _macosx_x64_test(name = "macos_x64_universal_test", target_under_test = ":universal_plugin", expected_platform = "macosx_universal", size = "small")
    _macos_arm64_missing_test(name = "macos_no_emulation_test", target_under_test = ":plugin", message = "does not provide a native grpc_csharp_plugin for macosx_arm64", size = "small")
    _windows_arm64_test(name = "windows_arm64_x64_test", target_under_test = ":universal_plugin", expected_platform = "windows_x64", size = "small")
    _windows_arm64_missing_test(name = "windows_missing_plugin_test", target_under_test = ":missing_plugin", message = "does not provide a native grpc_csharp_plugin.exe for windows_arm64", size = "small")
    _missing_test(name = "missing_plugin_test", target_under_test = ":missing_plugin", message = "Grpc.Tools does not provide", size = "small")
    _missing_test(name = "duplicate_plugin_test", target_under_test = ":duplicate_plugin", message = "Grpc.Tools contains multiple plugins", size = "small")
    _unsupported_test(name = "unsupported_platform_test", target_under_test = ":plugin", message = "Supply a source-built executable", size = "small")

    csharp_grpc_proto_compiler(
        name = "compiler",
        grpc_tools = ":universal_package",
        options = ["no_server", "internal_access"],
    )
    csharp_grpc_proto_compiler(
        name = "custom_compiler",
        plugin = ":native_plugin",
        options = ["no_server", "internal_access"],
    )
    _compiler_test(name = "execution_platform_test", target_under_test = ":compiler", expected_plugin = ":compiler_plugin", size = "small")
    _compiler_test(name = "custom_plugin_test", target_under_test = ":custom_compiler", expected_plugin = ":native_plugin", size = "small")

    native.test_suite(
        name = name,
        tests = [":" + platform + "_test" for platform in _PLATFORMS if platform != "linux_arm"] + [
            ":macos_arm64_universal_test",
            ":macos_x64_universal_test",
            ":macos_no_emulation_test",
            ":windows_arm64_x64_test",
            ":windows_missing_plugin_test",
            ":missing_plugin_test",
            ":duplicate_plugin_test",
            ":unsupported_platform_test",
            ":execution_platform_test",
            ":custom_plugin_test",
        ],
    )
