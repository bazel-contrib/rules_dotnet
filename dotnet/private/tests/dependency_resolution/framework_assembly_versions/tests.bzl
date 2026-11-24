"""Asserts which copy of a framework assembly wins over a dependency whose version is not three-part SemVer.

A dependency named like one of the framework's assemblies supersedes the
framework's copy only when it is newer in NuGet's order. One that sets no
version is never newer, and a version of two or four components is compared as
NuGet compares it. Neither fails analysis.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("//dotnet:defs.bzl", "csharp_binary", "csharp_library", "import_dll", "publish_binary")

_TFM = "net10.0"

_DLL = "System.Text.Json.dll"

def _pack_copy(description, repository):
    return matching.custom(
        description,
        lambda file: file.basename == _DLL and repository in file.path,
    )

# Not any copy out of the SDK: the compiler runs on the SDK's own runtime, so
# its System.Text.Json.dll is an input of every compile.
_TARGETING_PACK_COPY = _pack_copy("the targeting pack's " + _DLL, "nuget.microsoft.netcore.app.ref.")
_RUNTIME_PACK_COPY = _pack_copy("the runtime pack's " + _DLL, "nuget.microsoft.netcore.app.runtime.")

_DEPENDENCY_COPY = matching.custom(
    "the import_dll's " + _DLL,
    lambda file: file.basename == _DLL and not file.is_source,
)

def _framework_assembly(name, version):
    """An `import_dll` named like the framework's System.Text.Json.

    Its DLL is an empty placeholder, which is all analysis needs.
    """
    write_file(
        name = name + "_dll",
        out = "{}/{}".format(name, _DLL),
        content = [],
        tags = ["manual"],
    )

    import_dll(
        name = name,
        dll = name + "_dll",
        tags = ["manual"],
        version = version,
    )

def _compile_test(name, version, impl):
    _framework_assembly(name + "_dependency", version)

    csharp_library(
        name = name + "_library",
        srcs = ["Main.cs"],
        # Analysis is all the test needs.
        tags = ["manual"],
        target_frameworks = [_TFM],
        deps = [name + "_dependency"],
    )

    analysis_test(name = name, impl = impl, target = name + "_library")

def _publish_test(name, version, impl):
    _framework_assembly(name + "_dependency", version)

    csharp_binary(
        name = name + "_binary",
        srcs = ["Main.cs"],
        tags = ["manual"],
        target_frameworks = [_TFM],
        deps = [name + "_dependency"],
    )

    publish_binary(
        name = name + "_publish",
        binary = name + "_binary",
        self_contained = True,
        tags = ["manual"],
        target_framework = _TFM,
    )

    analysis_test(name = name, impl = impl, target = name + "_publish")

def _expect_only(env, target, mnemonic, kept, dropped):
    inputs = env.expect.that_target(target).action_named(mnemonic).inputs()
    inputs.contains_predicate(kept)
    inputs.not_contains_predicate(dropped)

def _framework_compiled_impl(env, target):
    _expect_only(env, target, "CSharpCompile", _TARGETING_PACK_COPY, _DEPENDENCY_COPY)

def _dependency_compiled_impl(env, target):
    _expect_only(env, target, "CSharpCompile", _DEPENDENCY_COPY, _TARGETING_PACK_COPY)

def _framework_published_impl(env, target):
    _expect_only(env, target, "DotnetPublishCopy", _RUNTIME_PACK_COPY, _DEPENDENCY_COPY)

def _dependency_published_impl(env, target):
    _expect_only(env, target, "DotnetPublishCopy", _DEPENDENCY_COPY, _RUNTIME_PACK_COPY)

def _unversioned_compile_test(name):
    _compile_test(name, None, _framework_compiled_impl)

def _older_two_components_compile_test(name):
    _compile_test(name, "4.5", _framework_compiled_impl)

def _newer_four_components_compile_test(name):
    _compile_test(name, "99.0.0.1", _dependency_compiled_impl)

def _unversioned_publish_test(name):
    _publish_test(name, None, _framework_published_impl)

def _older_four_components_publish_test(name):
    _publish_test(name, "1.2.3.4", _framework_published_impl)

def _newer_two_components_publish_test(name):
    _publish_test(name, "99.0", _dependency_published_impl)

def framework_assembly_versions_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _unversioned_compile_test,
            _older_two_components_compile_test,
            _newer_four_components_compile_test,
            _unversioned_publish_test,
            _older_four_components_publish_test,
            _newer_two_components_publish_test,
        ],
    )
