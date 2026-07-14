"Tests for the `excluded_analyzers` attribute on the C# rules."

load("//dotnet:defs.bzl", "csharp_binary", "csharp_library")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def test_excluded_analyzers():
    csharp_library(
        name = "common_analyzer_to_exclude",
        srcs = ["ExcludedAnalyzer.cs"],
        out = "CommonAnalyzerToExclude",
        is_analyzer = True,
        target_frameworks = ["netstandard2.0"],
        tags = ["manual"],
    )

    csharp_library(
        name = "common_analyzer_to_keep",
        srcs = ["KeptAnalyzer.cs"],
        out = "CommonAnalyzerToKeep",
        is_analyzer = True,
        target_frameworks = ["netstandard2.0"],
        tags = ["manual"],
    )

    csharp_library(
        name = "csharp_analyzer_to_exclude",
        srcs = ["ExcludedAnalyzer.cs"],
        out = "CSharpAnalyzerToExclude",
        is_analyzer = True,
        is_language_specific_analyzer = True,
        target_frameworks = ["netstandard2.0"],
        tags = ["manual"],
    )

    csharp_library(
        name = "csharp_analyzer_to_keep",
        srcs = ["KeptAnalyzer.cs"],
        out = "CSharpAnalyzerToKeep",
        is_analyzer = True,
        is_language_specific_analyzer = True,
        target_frameworks = ["netstandard2.0"],
        tags = ["manual"],
    )

    analyzer_deps = [
        ":common_analyzer_to_exclude",
        ":common_analyzer_to_keep",
        ":csharp_analyzer_to_exclude",
        ":csharp_analyzer_to_keep",
    ]

    csharp_library(
        name = "consumer_control",
        srcs = ["Consumer.cs"],
        out = "ConsumerControl",
        target_frameworks = ["net8.0"],
        deps = analyzer_deps,
        tags = ["manual"],
    )

    action_args_test(
        name = "consumer_control_test",
        target_under_test = ":consumer_control",
        action_mnemonic = "CSharpCompile",
        expected_args_containing = [
            "/analyzer:",
            "CommonAnalyzerToExclude.dll",
            "CommonAnalyzerToKeep.dll",
            "CSharpAnalyzerToExclude.dll",
            "CSharpAnalyzerToKeep.dll",
        ],
    )

    csharp_library(
        name = "consumer_excluded",
        srcs = ["Consumer.cs"],
        out = "ConsumerExcluded",
        target_frameworks = ["net8.0"],
        deps = analyzer_deps,
        excluded_analyzers = [
            "CommonAnalyzerToExclude.dll",
            "CSharpAnalyzerToExclude.dll",
        ],
        tags = ["manual"],
    )

    action_args_test(
        name = "consumer_excluded_test",
        target_under_test = ":consumer_excluded",
        action_mnemonic = "CSharpCompile",
        expected_args_containing = [
            "CommonAnalyzerToKeep.dll",
            "CSharpAnalyzerToKeep.dll",
        ],
        expected_args_not_containing = [
            "CommonAnalyzerToExclude.dll",
            "CSharpAnalyzerToExclude.dll",
        ],
    )

    csharp_binary(
        name = "binary_consumer_excluded",
        srcs = ["Consumer.cs"],
        out = "BinaryConsumerExcluded",
        target_frameworks = ["net8.0"],
        deps = analyzer_deps,
        excluded_analyzers = [
            "CommonAnalyzerToExclude.dll",
            "CSharpAnalyzerToExclude.dll",
        ],
        tags = ["manual"],
    )

    action_args_test(
        name = "binary_consumer_excluded_test",
        target_under_test = ":binary_consumer_excluded",
        action_mnemonic = "CSharpCompile",
        expected_args_containing = [
            "CommonAnalyzerToKeep.dll",
            "CSharpAnalyzerToKeep.dll",
        ],
        expected_args_not_containing = [
            "CommonAnalyzerToExclude.dll",
            "CSharpAnalyzerToExclude.dll",
        ],
    )
