"""Asserts how a NativeAOT publish drives ilc and the linker."""

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//dotnet:defs.bzl", "csharp_binary", "import_dll", "publish_binary")

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

def _compiles_in_shared_frameworks_test(name):
    analysis_test(
        name = name,
        impl = _compiles_in_shared_frameworks_test_impl,
        target = ":web_publish",
    )

def _compiles_in_shared_frameworks_test_impl(env, target):
    references = [arg.rpartition("/")[2] for arg in _argv(target, "Ilc") if arg.startswith("-r:")]

    # Microsoft.AspNetCore.App comes from its runtime pack, and Microsoft.NETCore.App
    # from the NativeAOT pack alone, not from its runtime pack as well.
    env.expect.that_collection(references).contains_at_least(["Microsoft.AspNetCore.dll", "System.Private.CoreLib.dll"])
    env.expect.that_int(len([ref for ref in references if ref == "System.Private.CoreLib.dll"])).equals(1)
    env.expect.that_int(len([ref for ref in references if ref == "System.Runtime.dll"])).equals(1)

# An assembly of Microsoft.AspNetCore.App that NuGet ships too.
_OVERRIDABLE_DLL = "Microsoft.Extensions.Logging.Abstractions.dll"

def _publish_with_dependency(name, version, impl):
    """A web app's NativeAOT publish, with a dependency named like one of ASP.NET Core's assemblies.

    The dependency's DLL is an empty placeholder, which is all analysis needs.
    """
    write_file(
        name = name + "_dll",
        out = "{}/{}".format(name, _OVERRIDABLE_DLL),
        content = [],
        tags = ["manual"],
    )

    import_dll(
        name = name + "_dependency",
        dll = name + "_dll",
        tags = ["manual"],
        version = version,
    )

    csharp_binary(
        name = name + "_binary",
        srcs = ["DependencyOverride.cs"],
        project_sdk = "web",
        tags = ["manual"],
        target_frameworks = ["net10.0"],
        deps = [name + "_dependency"],
    )

    publish_binary(
        name = name + "_publish",
        binary = name + "_binary",
        native_aot = True,
        self_contained = True,
        tags = ["manual"],
        target_framework = "net10.0",
    )

    analysis_test(
        name = name,
        impl = impl,
        target = name + "_publish",
    )

def _overridable_copies(target):
    """Which copies of the overridable assembly ilc is given."""
    dependency_copy = "{}/{}/{}".format(target.label.package, target.label.name.removesuffix("_publish"), _OVERRIDABLE_DLL)

    return [
        "dependency" if path.endswith(dependency_copy) else "runtime pack" if "microsoft.aspnetcore.app.runtime." in path.lower() else path
        for path in [arg.removeprefix("-r:") for arg in _argv(target, "Ilc") if arg.startswith("-r:")]
        if path.rpartition("/")[2] == _OVERRIDABLE_DLL
    ]

# ilc keeps the first reference of each name, so it is only ever given one: the
# newer, as in a self-contained publish.
def _newer_dependency_replaces_framework_test(name):
    _publish_with_dependency(name, "99.0", _newer_dependency_replaces_framework_test_impl)

def _newer_dependency_replaces_framework_test_impl(env, target):
    env.expect.that_collection(_overridable_copies(target)).contains_exactly(["dependency"])

def _older_dependency_does_not_replace_framework_test(name):
    _publish_with_dependency(name, "1.0", _older_dependency_does_not_replace_framework_test_impl)

def _older_dependency_does_not_replace_framework_test_impl(env, target):
    env.expect.that_collection(_overridable_copies(target)).contains_exactly(["runtime pack"])

def native_aot_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _matches_the_sdk_test,
            _compiles_in_shared_frameworks_test,
            _newer_dependency_replaces_framework_test,
            _older_dependency_does_not_replace_framework_test,
        ],
    )
