"Analysis tests for deps_json and runtimeconfig_json output groups and DotnetBinaryInfo fields."

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load(
    "//dotnet:defs.bzl",
    "csharp_binary",
    "csharp_test",
    "fsharp_binary",
    "fsharp_test",
)
load("//dotnet/private:providers.bzl", "DotnetBinaryInfo")
load("//dotnet/private/tests:utils.bzl", "get_target_tfm")

def _csharp_binary(name):
    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["App.cs"],
        out = "CustomOut",
        tags = ["manual"],
        target_frameworks = ["net8.0"],
    )

    analysis_test(
        name = name,
        impl = _custom_out_test_impl,
        target = name + "_target_under_test",
    )

def _csharp_test(name):
    csharp_test(
        name = name + "_target_under_test",
        srcs = ["App.cs"],
        tags = ["manual"],
        target_frameworks = ["net8.0"],
    )

    analysis_test(
        name = name,
        impl = _default_out_test_impl,
        target = name + "_target_under_test",
    )

def _fsharp_binary(name):
    fsharp_binary(
        name = name + "_target_under_test",
        srcs = ["App.fs"],
        tags = ["manual"],
        target_frameworks = ["net8.0"],
    )

    analysis_test(
        name = name,
        impl = _default_out_test_impl,
        target = name + "_target_under_test",
    )

def _fsharp_test(name):
    fsharp_test(
        name = name + "_target_under_test",
        srcs = ["App.fs"],
        tags = ["manual"],
        target_frameworks = ["net8.0"],
    )

    analysis_test(
        name = name,
        impl = _default_out_test_impl,
        target = name + "_target_under_test",
    )

def _blazor_wasm_binary(name):
    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["App.cs"],
        project_sdk = "blazorwasm",
        tags = ["manual"],
        target_frameworks = ["net10.0"],
    )

    analysis_test(
        name = name,
        impl = _blazor_wasm_test_impl,
        target = name + "_target_under_test",
    )

def _assert_json_outputs(env, target, target_dir_name, assembly_name, tfm):
    expected_deps = "{}/{}/{}/{}.deps.json".format(
        target.label.package,
        target_dir_name,
        tfm,
        assembly_name,
    )
    expected_rc = "{}/{}/{}/{}.runtimeconfig.json".format(
        target.label.package,
        target_dir_name,
        tfm,
        assembly_name,
    )

    env.expect.that_target(target).output_group("deps_json").contains_exactly([expected_deps])
    env.expect.that_target(target).output_group("runtimeconfig_json").contains_exactly([expected_rc])
    env.expect.that_str(target[DotnetBinaryInfo].deps_json.short_path).equals(expected_deps)
    env.expect.that_str(target[DotnetBinaryInfo].runtimeconfig_json.short_path).equals(expected_rc)

def _custom_out_test_impl(env, target):
    _assert_json_outputs(env, target, target.label.name, "CustomOut", get_target_tfm(target))

def _default_out_test_impl(env, target):
    _assert_json_outputs(env, target, target.label.name, target.label.name, get_target_tfm(target))

def _blazor_wasm_test_impl(env, target):
    _assert_json_outputs(env, target, target.label.name + ".app", target.label.name, "net10.0")

def deps_json_output_group_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _csharp_binary,
            _csharp_test,
            _fsharp_binary,
            _fsharp_test,
            _blazor_wasm_binary,
        ],
    )
