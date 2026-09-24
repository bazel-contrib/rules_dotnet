"""Analysis-time checks of `nuget_pack` and the `version` attribute.

What the rule declares and asks the packer for, without running it: output
names, the request, and the errors it raises.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load(
    "//dotnet:defs.bzl",
    "csharp_binary",
    "csharp_library",
    "fsharp_library",
    "nuget_pack",
)

_FRAMEWORKS = ["netstandard2.0", "net9.0"]

def _request(target):
    """The decoded request the pack action reads."""
    for action in target.actions:
        if action.mnemonic == "FileWrite" and action.outputs.to_list()[0].basename == "nuget_pack_request.json":
            return json.decode(action.content)
    fail("no request written for {}".format(target.label))

# --- Outputs and request ---------------------------------------------------------

def _library_package(name):
    csharp_library(
        name = name + "_lib",
        srcs = ["Simple.cs"],
        target_frameworks = _FRAMEWORKS,
        version = "1.2.3-beta.1+sha",
        deps = ["@paket.rules_dotnet_dev_nuget_packages//system.memory"],
    )

    nuget_pack(
        name = name + "_target_under_test",
        authors = ["a"],
        description = "d",
        library = name + "_lib",
        package_id = "Foo.Bar",
        symbols = "snupkg",
        target_frameworks = _FRAMEWORKS,
    )

    analysis_test(
        name = name,
        impl = _library_package_impl,
        target = name + "_target_under_test",
    )

def _library_package_impl(env, target):
    prefix = "{}/{}/".format(target.label.package, target.label.name)

    # Named after the id and the normalized version: no metadata in the name.
    env.expect.that_target(target).default_outputs().contains_exactly([
        prefix + "Foo.Bar.1.2.3-beta.1.nupkg",
        prefix + "Foo.Bar.1.2.3-beta.1.snupkg",
    ])

    action = env.expect.that_target(target).action_generating(prefix + "Foo.Bar.1.2.3-beta.1.nupkg")
    action.mnemonic().equals("NuGetPack")
    action.inputs().contains_at_least_predicates([
        matching.file_basename_equals("nuget_pack_request.json"),
        matching.file_basename_equals(target.label.name.replace("_target_under_test", "_lib") + ".dll"),
    ])

    request = _request(target)
    env.expect.that_str(request["metadata"]["id"]).equals("Foo.Bar")
    env.expect.that_str(request["metadata"]["version"]).equals("1.2.3-beta.1+sha")
    env.expect.that_collection(request["packageTypes"]).contains_exactly([])
    env.expect.that_collection([group["targetFramework"] for group in request["dependencyGroups"]]).contains_exactly([".NETStandard2.0", "net9.0"])
    for group in request["dependencyGroups"]:
        env.expect.that_collection([dependency["id"] for dependency in group["dependencies"]]).contains_exactly(["System.Memory"])

    lib = target.label.name.replace("_target_under_test", "_lib")
    env.expect.that_collection([entry["target"] for entry in request["files"]]).contains_at_least([
        "lib/netstandard2.0/{}.dll".format(lib),
        "lib/net9.0/{}.dll".format(lib),
        "ref/netstandard2.0/{}.dll".format(lib),
        "ref/net9.0/{}.dll".format(lib),
    ])
    env.expect.that_collection([entry["target"] for entry in request["symbolFiles"]]).contains_exactly([
        "lib/net9.0/{}.pdb".format(lib),
        "lib/netstandard2.0/{}.pdb".format(lib),
    ])
    env.expect.that_str(request["output"]).contains("/Foo.Bar.1.2.3-beta.1.nupkg")

def _tool_package(name):
    csharp_binary(
        name = name + "_bin",
        srcs = ["SimpleMain.cs"],
        target_frameworks = ["net9.0"],
        version = "0.1.0",
    )

    nuget_pack(
        name = name + "_target_under_test",
        authors = ["a"],
        binary = name + "_bin",
        command_name = "simple",
        description = "d",
        target_frameworks = ["net9.0"],
    )

    analysis_test(
        name = name,
        impl = _tool_package_impl,
        target = name + "_target_under_test",
    )

def _tool_package_impl(env, target):
    bin = target.label.name.replace("_target_under_test", "_bin")
    request = _request(target)
    env.expect.that_str(request["metadata"]["id"]).equals(bin)
    env.expect.that_collection(request["packageTypes"]).contains_exactly(["DotnetTool"])
    env.expect.that_str(request["toolSettings"]["commandName"]).equals("simple")
    env.expect.that_str(request["toolSettings"]["entryPoint"]).equals(bin + ".dll")
    env.expect.that_collection(request["toolSettings"]["directories"]).contains_exactly(["tools/net9.0/any"])
    env.expect.that_collection([entry["target"] for entry in request["files"]]).contains_at_least([
        "tools/net9.0/any/{}.dll".format(bin),
        "tools/net9.0/any/{}.deps.json".format(bin),
        "tools/net9.0/any/{}.runtimeconfig.json".format(bin),
    ])

# --- The version attribute -------------------------------------------------------

def _versioned_csharp(name):
    csharp_library(
        name = name + "_target_under_test",
        srcs = ["Simple.cs"],
        target_frameworks = ["net9.0"],
        version = "1.0.0",
    )
    analysis_test(name = name, impl = _versioned_csharp_impl, target = name + "_target_under_test")

def _versioned_csharp_impl(env, target):
    env.expect.that_target(target).action_named("CSharpCompile").inputs().contains_predicate(matching.file_basename_equals("assemblyinfo.cs"))

def _unversioned_csharp(name):
    csharp_library(
        name = name + "_target_under_test",
        srcs = ["Simple.cs"],
        target_frameworks = ["net9.0"],
    )
    analysis_test(name = name, impl = _unversioned_csharp_impl, target = name + "_target_under_test")

def _unversioned_csharp_impl(env, target):
    env.expect.that_target(target).action_named("CSharpCompile").inputs().not_contains_predicate(matching.file_basename_equals("assemblyinfo.cs"))

def _versioned_fsharp(name):
    fsharp_library(
        name = name + "_target_under_test",
        srcs = ["Simple.fs"],
        target_frameworks = ["net9.0"],
        version = "1.0.0",
        deps = ["@paket.rules_dotnet_dev_nuget_packages//fsharp.core"],
    )
    analysis_test(name = name, impl = _versioned_fsharp_impl, target = name + "_target_under_test")

def _versioned_fsharp_impl(env, target):
    env.expect.that_target(target).action_named("FSharpCompile").inputs().contains_predicate(matching.file_basename_equals("assemblyinfo.fs"))

# --- Failures ----------------------------------------------------------------------

def _fails_with_impl(ctx):
    env = analysistest.begin(ctx)
    for fragment in ctx.attr.expected_message_fragments:
        asserts.expect_failure(env, fragment)
    return analysistest.end(env)

fails_with_test = analysistest.make(
    _fails_with_impl,
    doc = "Asserts that the target under test fails to analyse with a message containing every fragment.",
    expect_failure = True,
    attrs = {
        "expected_message_fragments": attr.string_list(mandatory = True),
    },
)

def nuget_pack_analysis_test_suite(name):
    """The rules_testing suite.

    Args:
      name: The name of the suite.
    """
    test_suite(
        name = name,
        tests = [
            _library_package,
            _tool_package,
            _versioned_csharp,
            _unversioned_csharp,
            _versioned_fsharp,
        ],
    )
