"""Tests for publish-owned entry assemblies and dependency assets."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _values(action, flag):
    return [action.argv[index + 1] for index, argument in enumerate(action.argv) if argument == flag]

def _publish_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    actions = {action.mnemonic: action for action in analysistest.target_actions(env)}
    compile_action = actions["CSharpCompile"]
    publish_action = actions["BlazorPublish"]
    entry_assembly = target[OutputGroupInfo].entry_assembly.to_list()[0]

    asserts.true(env, "/target:exe" in compile_action.argv)
    asserts.false(env, "/target:library" in compile_action.argv)
    for symbol in ["NET", "NETCOREAPP", "NET10_0", "BROWSER", "BROWSER1_0", "BROWSER1_0_OR_GREATER"]:
        asserts.true(env, "/d:" + symbol in compile_action.argv)
    asserts.false(env, "/d:NETSTANDARD2_0_OR_GREATER" in compile_action.argv)
    asserts.false(env, any([argument.endswith("/Microsoft.AspNetCore.App.Analyzers.dll") for argument in compile_action.argv]))
    asserts.false(env, any([argument.endswith("/Microsoft.AspNetCore.Server.Kestrel.Core.dll") for argument in compile_action.argv]))
    asserts.true(env, any([argument.startswith("/out:") and argument.endswith("/" + entry_assembly.short_path) for argument in compile_action.argv]))
    asserts.true(env, all([path.endswith("/" + entry_assembly.short_path) for path in _values(publish_action, "--entry-assembly")]))
    asserts.equals(env, ["basic_two"], _values(publish_action, "--assembly-name"))

    references = [path.split("/")[-1] for path in _values(publish_action, "--reference")]
    asserts.true(env, "basic.dll" in references)
    asserts.true(env, "plain.dll" in references)
    asserts.false(env, "basic_two.dll" in references)

    assets = [mapping.split("|")[1] for mapping in _values(publish_action, "--asset")]
    for path in [
        "wwwroot/app.css",
        "wwwroot/app.js",
        "wwwroot/basic_two.styles.css",
        "wwwroot/_content/basic/app.css",
        "wwwroot/_content/basic/app.js",
        "wwwroot/_content/basic/basic.styles.css",
        "wwwroot/_content/example/app.js",
    ]:
        asserts.equals(env, 1, len([asset for asset in assets if asset == path]), "Expected one published asset at " + path)
    asserts.false(env, "wwwroot/_content/basic_two/app.css" in assets)
    asserts.false(env, "wwwroot/basic.styles.css" in assets)

    return analysistest.end(env)

publish_test = analysistest.make(_publish_test_impl)
