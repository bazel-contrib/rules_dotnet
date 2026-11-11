"Tests of the compiler workers."

load("//dotnet/private/tests:utils.bzl", "runs_with_settings_test")

runs_with_pruning_test = runs_with_settings_test({
    str(Label("//dotnet/settings:use_compiler_worker")): True,
    str(Label("//dotnet/settings:prune_unused_references")): True,
})
