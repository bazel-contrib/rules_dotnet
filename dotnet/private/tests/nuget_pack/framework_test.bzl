"Round trip between target framework monikers and how a nuspec spells them."

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private:common.bzl", "FRAMEWORK_COMPATIBILITY", "nuget_framework_to_tfm", "tfm_to_nuget_framework")

_SPELLINGS = {
    "net11": ".NETFramework1.1",
    "net20": ".NETFramework2.0",
    "net403": ".NETFramework4.0.3",
    "net472": ".NETFramework4.7.2",
    "net48": ".NETFramework4.8",
    "net481": ".NETFramework4.8.1",
    "net8.0": "net8.0",
    "netcoreapp3.1": ".NETCoreApp3.1",
    "netstandard": "netstandard",
    "netstandard2.0": ".NETStandard2.0",
    "netstandard2.1": ".NETStandard2.1",
}

def _spellings_test_impl(ctx):
    env = unittest.begin(ctx)
    for (tfm, spelling) in _SPELLINGS.items():
        asserts.equals(env, spelling, tfm_to_nuget_framework(tfm), tfm)
    return unittest.end(env)

def _round_trip_test_impl(ctx):
    env = unittest.begin(ctx)
    for tfm in FRAMEWORK_COMPATIBILITY.keys():
        asserts.equals(env, tfm, nuget_framework_to_tfm(tfm_to_nuget_framework(tfm)), tfm)
    return unittest.end(env)

spellings_test = unittest.make(_spellings_test_impl)
round_trip_test = unittest.make(_round_trip_test_impl)

def framework_test_suite(name):
    unittest.suite(
        name,
        spellings_test,
        round_trip_test,
    )
