"""Tests for the nuget.resolve input hash."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//dotnet/private/nuget_resolve:input_hash.bzl",
    "classify_input_hash",
    "compute_input_hash",
)

_PACKAGES = {"Newtonsoft.Json": "13.0.3", "Serilog": "4.0.*"}
_FRAMEWORKS = ["net10.0", "net8.0"]
_SOURCES = ["https://api.nuget.org/v3/index.json", "https://pkgs.example.com/v3/index.json"]

def _stable_test_impl(ctx):
    env = unittest.begin(ctx)

    first = compute_input_hash(_PACKAGES, _FRAMEWORKS, _SOURCES)
    second = compute_input_hash(_PACKAGES, _FRAMEWORKS, _SOURCES)

    asserts.equals(env, first, second, "the same inputs hash the same")
    asserts.true(env, first.isdigit(), "the hash is a decimal string: %s" % first)

    return unittest.end(env)

_stable_test = unittest.make(_stable_test_impl)

def _canonicalization_test_impl(ctx):
    env = unittest.begin(ctx)

    canonical = compute_input_hash(_PACKAGES, _FRAMEWORKS, _SOURCES)

    asserts.equals(
        env,
        canonical,
        compute_input_hash({"Serilog": "4.0.*", "Newtonsoft.Json": "13.0.3"}, _FRAMEWORKS, _SOURCES),
        "package dict order does not matter",
    )
    asserts.equals(
        env,
        canonical,
        compute_input_hash(_PACKAGES, ["net8.0", "net10.0"], _SOURCES),
        "framework order does not matter",
    )

    return unittest.end(env)

_canonicalization_test = unittest.make(_canonicalization_test_impl)

def _sensitivity_test_impl(ctx):
    env = unittest.begin(ctx)

    canonical = compute_input_hash(_PACKAGES, _FRAMEWORKS, _SOURCES)

    asserts.false(
        env,
        canonical == compute_input_hash(
            {"Newtonsoft.Json": "13.0.3", "Serilog": "4.0.0"},
            _FRAMEWORKS,
            _SOURCES,
        ),
        "a changed version range changes the hash",
    )
    asserts.false(
        env,
        canonical == compute_input_hash(_PACKAGES, ["net10.0"], _SOURCES),
        "a removed framework changes the hash",
    )
    asserts.false(
        env,
        canonical == compute_input_hash(
            _PACKAGES,
            _FRAMEWORKS,
            ["https://pkgs.example.com/v3/index.json", "https://api.nuget.org/v3/index.json"],
        ),
        "source order matters (lookup order is semantically significant)",
    )
    asserts.false(
        env,
        canonical == compute_input_hash(_PACKAGES, _FRAMEWORKS, _SOURCES[:1]),
        "a removed source changes the hash",
    )

    return unittest.end(env)

_sensitivity_test = unittest.make(_sensitivity_test_impl)

def _classify_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "current", classify_input_hash("123", "123"))
    asserts.equals(env, "mismatch", classify_input_hash("123", "456"))
    asserts.equals(
        env,
        "legacy",
        classify_input_hash("999", "456", legacy = ["999"]),
        "a hash from a superseded algorithm is recognised",
    )

    return unittest.end(env)

_classify_test = unittest.make(_classify_test_impl)

def input_hash_test_suite(name):
    unittest.suite(
        name,
        _stable_test,
        _canonicalization_test,
        _sensitivity_test,
        _classify_test,
    )
