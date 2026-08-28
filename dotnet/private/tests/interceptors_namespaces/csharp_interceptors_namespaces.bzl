"Tests for the interceptors_namespaces attribute on the C# rules."

load("//dotnet:defs.bzl", "csharp_binary", "csharp_library", "csharp_test")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

_EXPECTED_FEATURE_ARG = "/features:InterceptorsNamespaces=My.First.Namespace;My.Second.Namespace"

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def csharp_interceptors_namespaces():
    csharp_library(
        name = "library_with_interceptors_namespaces",
        srcs = ["interceptors_namespaces.cs"],
        target_frameworks = ["net6.0"],
        interceptors_namespaces = ["My.First.Namespace", "My.Second.Namespace"],
        tags = ["manual"],
    )

    action_args_test(
        name = "library_with_interceptors_namespaces_test",
        target_under_test = ":library_with_interceptors_namespaces",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [_EXPECTED_FEATURE_ARG],
    )

    csharp_library(
        name = "library_without_interceptors_namespaces",
        srcs = ["interceptors_namespaces.cs"],
        target_frameworks = ["net6.0"],
        tags = ["manual"],
    )

    action_args_test(
        name = "library_without_interceptors_namespaces_test",
        target_under_test = ":library_without_interceptors_namespaces",
        action_mnemonic = "CSharpCompile",
        expected_nonexistent_partial_args = [_EXPECTED_FEATURE_ARG],
    )

    csharp_binary(
        name = "binary_with_interceptors_namespaces",
        srcs = ["interceptors_namespaces.cs"],
        target_frameworks = ["net6.0"],
        interceptors_namespaces = ["My.First.Namespace", "My.Second.Namespace"],
        tags = ["manual"],
    )

    action_args_test(
        name = "binary_with_interceptors_namespaces_test",
        target_under_test = ":binary_with_interceptors_namespaces",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [_EXPECTED_FEATURE_ARG],
    )

    csharp_test(
        name = "test_with_interceptors_namespaces",
        srcs = ["interceptors_namespaces.cs"],
        target_frameworks = ["net6.0"],
        interceptors_namespaces = ["My.First.Namespace", "My.Second.Namespace"],
        tags = ["manual"],
    )

    action_args_test(
        name = "test_with_interceptors_namespaces_test",
        target_under_test = ":test_with_interceptors_namespaces",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [_EXPECTED_FEATURE_ARG],
    )
