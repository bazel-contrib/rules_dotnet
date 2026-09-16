"Analysis tests for csharp_proto_library."

load("@bazel_skylib//lib:unittest.bzl", "analysistest")
load("@com_google_protobuf//bazel:proto_library.bzl", "proto_library")
load("//proto:defs.bzl", "csharp_proto_library")

def _actions_by_mnemonic(env, mnemonic):
    return [action for action in analysistest.target_actions(env) if action.mnemonic == mnemonic]

def _csharp_proto_library_action_test_impl(ctx):
    env = analysistest.begin(ctx)

    proto_actions = _actions_by_mnemonic(env, "GenProto")
    if len(proto_actions) != 1:
        fail("Expected one GenProto action, got {}".format(len(proto_actions)))

    compile_actions = _actions_by_mnemonic(env, "CSharpCompile")
    if len(compile_actions) != 1:
        fail("Expected one CSharpCompile action, got {}".format(len(compile_actions)))

    compile_args = compile_actions[0].argv
    has_recurse_arg = False
    has_embed_src = False
    for arg in compile_args:
        if arg.startswith("/recurse:") and arg.endswith("/*.cs"):
            has_recurse_arg = True
        if arg.endswith("Embedded.cs"):
            has_embed_src = True

    if not has_recurse_arg:
        fail("Expected CSharpCompile action to recurse over generated C# sources: {}".format(compile_args))
    if not has_embed_src:
        fail("Expected CSharpCompile action to include embed_srcs: {}".format(compile_args))

    return analysistest.end(env)

csharp_proto_library_action_test = analysistest.make(_csharp_proto_library_action_test_impl)

def csharp_proto_library_test_suite(name):
    proto_library(
        name = "messages_proto",
        srcs = ["messages.proto"],
        tags = ["manual"],
    )

    csharp_proto_library(
        name = "messages_csharp_proto",
        embed_srcs = ["Embedded.cs"],
        protos = [":messages_proto"],
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    csharp_proto_library_action_test(
        name = name,
        target_under_test = ":messages_csharp_proto",
    )
