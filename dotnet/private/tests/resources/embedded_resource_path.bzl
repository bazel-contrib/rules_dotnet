"Tests for embedded resources of `csharp_*` and `fsharp_*` rules."

load("//dotnet:defs.bzl", "csharp_library", "fsharp_library")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

# buildifier: disable=unnamed-macro
def test_embedded_resource_path_csharp():
    csharp_library(
        name = "csharp_lib",
        out = "EmbeddedResource.Library",
        srcs = ["EmbeddedResource.cs"],
        resources = ["nested/path/to/resource.txt"],
        target_frameworks = ["net9.0"],
    )

    action_args_test(
        name = "csharp_action_args_test",
        target_under_test = ":csharp_lib",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = ["/resource:dotnet/private/tests/resources/nested/path/to/resource.txt,EmbeddedResource.Library.nested.path.to.resource.txt"],
    )

# buildifier: disable=unnamed-macro
def test_embedded_resource_path_fsharp():
    fsharp_library(
        name = "fsharp_lib",
        out = "EmbeddedResource.Library",
        srcs = ["EmbeddedResource.fs"],
        resources = ["nested/path/to/resource.txt"],
        target_frameworks = ["net9.0"],
    )

    action_args_test(
        name = "fsharp_action_args_test",
        target_under_test = ":fsharp_lib",
        action_mnemonic = "FSharpCompile",
        expected_partial_args = ["--resource:dotnet/private/tests/resources/nested/path/to/resource.txt,EmbeddedResource.Library.nested.path.to.resource.txt"],
    )

# buildifier: disable=unnamed-macro
def test_path_from_other_repo_should_stay_as_basename():
    csharp_library(
        name = "path_from_other_repo_csharp_lib",
        out = "EmbeddedResource.Library",
        srcs = ["EmbeddedResource.cs"],
        resources = ["@dotnet_test_resources_other_repo//:file.txt"],
        target_frameworks = ["net9.0"],
    )

    external_workspace_root = Label("@dotnet_test_resources_other_repo//:file.txt").workspace_root

    action_args_test(
        name = "path_from_other_repo_csharp_action_args_test",
        target_under_test = ":path_from_other_repo_csharp_lib",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [
            "/resource:{}/file.txt,EmbeddedResource.Library.file.txt".format(external_workspace_root),
        ],
    )

# buildifier: disable=unnamed-macro
def test_path_from_parent_package_should_stay_as_basename():
    action_args_test(
        name = "path_from_parent_package_csharp_action_args_test",
        target_under_test = "//dotnet/private/tests/resources/subdir:parent_lib",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = ["/resource:dotnet/private/tests/resources/file.txt,EmbeddedResource.Library.file.txt"],
    )

def test_path_from_unrelated_package_should_stay_as_basename():
    action_args_test(
        name = "path_from_unrelated_package_csharp_action_args_test",
        target_under_test = "//dotnet/private/tests/resources/subdir:unrelated_lib",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = ["/resource:dotnet/private/tests/resources/other_dir/file.txt,EmbeddedResource.Library.file.txt"],
    )
