"""Tests that a library reached in two configurations is loaded and published once."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _shared_runtime(env, deps_json_name):
    """The `runtime` assets of `Shared` in the deps.json the target writes."""
    writes = [
        action
        for action in analysistest.target_actions(env)
        if action.mnemonic == "FileWrite" and action.outputs.to_list()[0].basename == deps_json_name
    ]
    asserts.equals(env, 1, len(writes), "deps.json writes")
    if len(writes) != 1:
        return None

    deps_json = json.decode(writes[0].content)
    return deps_json["targets"].values()[0]["Shared/1.0.0"]["runtime"].keys()

def _binary_loads_netstandard_test_impl(ctx):
    env = analysistest.begin(ctx)

    runtime = _shared_runtime(env, "app.deps.json")
    if runtime != None:
        asserts.equals(env, 1, len(runtime), "Shared assets: {}".format(runtime))
        asserts.true(env, all(["/shared/netstandard2.0/Shared.dll" in path for path in runtime]), "loads {}".format(runtime))

    return analysistest.end(env)

binary_loads_netstandard_test = analysistest.make(
    _binary_loads_netstandard_test_impl,
    doc = "Asserts that the binary's deps.json lists the configuration a .NET application picks.",
)

def _publish_copies_netstandard_test_impl(ctx):
    env = analysistest.begin(ctx)

    runtime = _shared_runtime(env, "app.deps.json")
    if runtime != None:
        asserts.equals(env, ["Shared.dll"], runtime)

    copies = [action for action in analysistest.target_actions(env) if action.mnemonic == "DotnetPublishCopy"]
    asserts.equals(env, 1, len(copies), "copy actions")
    if len(copies) != 1:
        return analysistest.end(env)

    shared = [file.short_path for file in copies[0].inputs.to_list() if file.basename == "Shared.dll"]
    asserts.equals(env, 1, len(shared), "copies {}".format(shared))
    asserts.true(env, shared and "/shared/netstandard2.0/" in shared[0], "copies {}".format(shared))

    return analysistest.end(env)

publish_copies_netstandard_test = analysistest.make(
    _publish_copies_netstandard_test_impl,
    doc = "Asserts that the publish copies the configuration its deps.json lists, and no other.",
)
