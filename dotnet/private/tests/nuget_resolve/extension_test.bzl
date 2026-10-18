"""Tests for the nuget module extension helpers."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//dotnet/private/nuget_resolve:extension.bzl",
    "claim",
    "resolve_repositories",
)

def _repositories_test_impl(ctx):
    env = unittest.begin(ctx)

    tag = struct(name = "nuget", frameworks = ["net8.0", "net10.0"])

    asserts.equals(
        env,
        ["unpinned_nuget", "nuget.net8.0", "nuget.net10.0"],
        resolve_repositories(tag),
        "one resolve repository plus one hub per framework",
    )

    return unittest.end(env)

_repositories_test = unittest.make(_repositories_test_impl)

def _claim_test_impl(ctx):
    env = unittest.begin(ctx)

    claimed = {}
    asserts.equals(env, None, claim(claimed, "nuget.net10.0", "module 'a'"))
    asserts.equals(env, None, claim(claimed, "nuget.net8.0", "module 'a'"))

    error = claim(claimed, "nuget.net10.0", "module 'b'")
    asserts.true(env, error != None, "a double claim is an error")
    asserts.true(env, error.find("nuget.net10.0") != -1, "the error names the repository: %s" % error)
    asserts.true(env, error.find("module 'a'") != -1, "the error names the first claimant: %s" % error)
    asserts.true(env, error.find("name") != -1, "the error advises picking a different name: %s" % error)

    return unittest.end(env)

_claim_test = unittest.make(_claim_test_impl)

def extension_test_suite(name):
    unittest.suite(
        name,
        _repositories_test,
        _claim_test,
    )
