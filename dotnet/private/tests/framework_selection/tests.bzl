"""Tests which framework a target builds for, given what depends on it."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//dotnet/private:providers.bzl", "DotnetAssemblyCompileInfo")

def _framework(target):
    return target[DotnetAssemblyCompileInfo].target_framework

def _dependency_frameworks(target):
    return {dep.label.name: _framework(dep) for dep in target[TestingAspectInfo].attrs.deps}

# A compatible framework beats one of another family; with none, .NET falls
# back to .NET Framework, as NuGet's AssetTargetFallback does.
def _net8_consumer_test(name):
    analysis_test(name = name, impl = _net8_consumer_test_impl, target = ":net8_consumer")

def _net8_consumer_test_impl(env, target):
    env.expect.that_dict(_dependency_frameworks(target)).contains_exactly({
        "net48_and_netstandard": "netstandard2.0",
        "net48_only": "net48",
    })

def _net48_consumer_test(name):
    analysis_test(name = name, impl = _net48_consumer_test_impl, target = ":net48_consumer")

def _net48_consumer_test_impl(env, target):
    env.expect.that_dict(_dependency_frameworks(target)).contains_exactly({
        "net48_and_netstandard": "net48",
    })

# Built on its own, a target takes its newest framework, whatever the family.
def _built_on_its_own_test(name):
    analysis_test(name = name, impl = _built_on_its_own_test_impl, target = ":net48_and_netstandard")

def _built_on_its_own_test_impl(env, target):
    env.expect.that_str(_framework(target)).equals("net48")

def framework_selection_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _built_on_its_own_test,
            _net48_consumer_test,
            _net8_consumer_test,
        ],
    )
