"""Exact tests for the fixed .NET 10 implicit-using namespace sets."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//dotnet/private/rules/csharp/actions:implicit_usings.bzl",
    "implicit_usings_namespaces",
)

_BASE = [
    "System",
    "System.Collections.Generic",
    "System.IO",
    "System.Linq",
    "System.Net.Http",
    "System.Threading",
    "System.Threading.Tasks",
]

_BASE_NET_FRAMEWORK = [
    "System",
    "System.Collections.Generic",
    "System.IO",
    "System.Linq",
    "System.Threading",
    "System.Threading.Tasks",
]

_WEB = _BASE + [
    "System.Net.Http.Json",
    "Microsoft.AspNetCore.Builder",
    "Microsoft.AspNetCore.Hosting",
    "Microsoft.AspNetCore.Http",
    "Microsoft.AspNetCore.Routing",
    "Microsoft.Extensions.Configuration",
    "Microsoft.Extensions.DependencyInjection",
    "Microsoft.Extensions.Hosting",
    "Microsoft.Extensions.Logging",
]

_WEB_NET_FRAMEWORK = _BASE_NET_FRAMEWORK + [
    "System.Net.Http.Json",
    "Microsoft.AspNetCore.Builder",
    "Microsoft.AspNetCore.Hosting",
    "Microsoft.AspNetCore.Http",
    "Microsoft.AspNetCore.Routing",
    "Microsoft.Extensions.Configuration",
    "Microsoft.Extensions.DependencyInjection",
    "Microsoft.Extensions.Hosting",
    "Microsoft.Extensions.Logging",
]

_BLAZORWASM = _BASE + [
    "Microsoft.Extensions.Configuration",
    "Microsoft.Extensions.DependencyInjection",
    "Microsoft.Extensions.Logging",
]

_BLAZORWASM_NET_FRAMEWORK = _BASE_NET_FRAMEWORK + [
    "Microsoft.Extensions.Configuration",
    "Microsoft.Extensions.DependencyInjection",
    "Microsoft.Extensions.Logging",
]

_CASES = [
    ("default", "net10.0", _BASE),
    ("razor", "net10.0", _BASE),
    ("web", "net10.0", _WEB),
    ("blazorwasm", "net10.0", _BLAZORWASM),
    ("default", "net48", _BASE_NET_FRAMEWORK),
    ("razor", "net48", _BASE_NET_FRAMEWORK),
    ("web", "net48", _WEB_NET_FRAMEWORK),
    ("blazorwasm", "net48", _BLAZORWASM_NET_FRAMEWORK),
    ("default", "netstandard2.0", _BASE),
]

def _namespaces_test_impl(ctx):
    env = unittest.begin(ctx)
    for project_sdk, target_framework, expected in _CASES:
        actual = implicit_usings_namespaces(project_sdk, target_framework)
        asserts.equals(
            env,
            expected,
            actual,
            "implicit usings for %s/%s" % (project_sdk, target_framework),
        )
    return unittest.end(env)

namespaces_test = unittest.make(_namespaces_test_impl)

def implicit_usings_test_suite(name):
    unittest.suite(name, namespaces_test)
