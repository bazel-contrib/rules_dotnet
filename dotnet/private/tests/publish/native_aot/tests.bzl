"""Asserts how a NativeAOT publish drives ilc and the linker."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")

def _argv(target, mnemonic):
    return [action for action in target[TestingAspectInfo].actions if action.mnemonic == mnemonic][0].argv

def _matches_the_sdk_test(name):
    analysis_test(
        name = name,
        impl = _matches_the_sdk_test_impl,
        target = ":native_aot",
    )

def _matches_the_sdk_test_impl(env, target):
    compile = env.expect.that_collection(_argv(target, "Ilc"))
    link = env.expect.that_collection(_argv(target, "IlcLink"))

    if not target[DefaultInfo].files_to_run.executable.basename.endswith(".exe"):
        compile.contains("--dehydrate")
        return

    # The SDK only dehydrates a Windows image when asked to optimise for size.
    compile.not_contains("--dehydrate")
    compile.contains("--export-dynamic-symbol:DotNetRuntimeDebugHeader,DATA")

    # The list of Windows APIs to bind directly comes with the compiler.
    lists = [arg for arg in _argv(target, "Ilc") if arg.startswith("--directpinvokelist:")]
    env.expect.that_collection(lists).has_size(1)
    env.expect.that_str(lists[0]).contains("/build/WindowsAPIs.txt")

    # The runtime is built for the static release C runtime, whichever one the
    # toolchain would link for the compilation mode, and ships without symbols.
    link.contains_at_least([
        "/NODEFAULTLIB:msvcrt.lib",
        "/NODEFAULTLIB:msvcrtd.lib",
        "/NODEFAULTLIB:libcmtd.lib",
        "/NODEFAULTLIB:libucrt.lib",
        "/DEFAULTLIB:ucrt.lib",
        "/DEBUG:NONE",
    ])

def native_aot_test_suite(name):
    test_suite(
        name = name,
        tests = [_matches_the_sdk_test],
    )
