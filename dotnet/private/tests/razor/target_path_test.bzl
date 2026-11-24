"""Tests the path a Razor component is named after.

`TargetPath` is the source's path relative to the package that compiles it,
base64-encoded. The generator decodes it and derives a component's namespace
and a Razor Page's route from it, so both halves are a contract with MSBuild
rather than an internal detail.
"""

load("@bazel_lib//lib:base64.bzl", "base64")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//dotnet/private/rules/csharp/actions:razor.bzl", "escape_section_name", "razor_lang_version", "target_path")

# `target_path` reads only these two fields off the label.
def _label(package, repo_name = ""):
    return struct(package = package, repo_name = repo_name)

_CASES = [
    # (short_path, label, expected target path)
    ("Widget.razor", _label(""), "Widget.razor"),
    ("ui/Widget.razor", _label("ui"), "Widget.razor"),
    ("ui/Pages/Index.cshtml", _label("ui"), "Pages/Index.cshtml"),
    ("ui/web/Views/Home/Index.cshtml", _label("ui/web"), "Views/Home/Index.cshtml"),
    ("ui/Some Folder/A b.razor", _label("ui"), "Some Folder/A b.razor"),
    ("../other_repo+/ui/Widget.razor", _label("ui", "other_repo+"), "Widget.razor"),
    ("../other_repo+/Widget.razor", _label("", "other_repo+"), "Widget.razor"),
]

# Derived from the target framework rather than tabulated, so a .NET release
# needs no change. net12.0 is here to prove that: it has no toolchain yet.
_LANG_VERSIONS = {
    "net5.0": "5.0",
    "net8.0": "8.0",
    "net10.0": "10.0",
    "net11.0": "11.0",
    "net12.0": "12.0",
}

def _lang_version_test_impl(ctx):
    env = unittest.begin(ctx)
    for tfm, expected in _LANG_VERSIONS.items():
        asserts.equals(env, expected, razor_lang_version(tfm), "RazorLangVersion for %s" % tfm)
    return unittest.end(env)

lang_version_test = unittest.make(_lang_version_test_impl)

def _target_path_test_impl(ctx):
    env = unittest.begin(ctx)
    for short_path, label, expected in _CASES:
        asserts.equals(env, expected, target_path(short_path, label), "target path of %r" % short_path)
    return unittest.end(env)

target_path_test = unittest.make(_target_path_test_impl)

_ENCODED_TARGET_PATHS = {
    "Widget.razor": "V2lkZ2V0LnJhem9y",
    "Pages/Index.cshtml": "UGFnZXMvSW5kZXguY3NodG1s",
    "_Imports.razor": "X0ltcG9ydHMucmF6b3I=",
    "Views/Home/Index.cshtml": "Vmlld3MvSG9tZS9JbmRleC5jc2h0bWw=",
    "Some Folder/A b.razor": "U29tZSBGb2xkZXIvQSBiLnJhem9y",
}

def _encoding_test_impl(ctx):
    env = unittest.begin(ctx)
    for path, encoded in _ENCODED_TARGET_PATHS.items():
        asserts.equals(env, encoded, base64.encode(path), "encoding of %r" % path)
    return unittest.end(env)

encoding_test = unittest.make(_encoding_test_impl)

# An editorconfig section name is a glob, and Roslyn only parses a section
# header holding `#` or `;` when they are escaped.
_SECTION_NAMES = {
    "Widget.razor": "Widget.razor",
    "Some Folder/A b.razor": "Some Folder/A b.razor",
    "C#/Widget.razor": "C\\#/Widget.razor",
    "a;b/Widget.razor": "a\\;b/Widget.razor",
    "[x]{y}*?.razor": "\\[x\\]\\{y\\}\\*\\?.razor",
    "a\\b.razor": "a\\\\b.razor",
}

def _section_name_test_impl(ctx):
    env = unittest.begin(ctx)
    for path, expected in _SECTION_NAMES.items():
        asserts.equals(env, expected, escape_section_name(path), "section name of %r" % path)
    return unittest.end(env)

section_name_test = unittest.make(_section_name_test_impl)

def _fails_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.expected_message)
    return analysistest.end(env)

# Asserts that the target under test fails analysis with `expected_message`.
fails_test = analysistest.make(
    _fails_test_impl,
    expect_failure = True,
    attrs = {"expected_message": attr.string(mandatory = True)},
)

def target_path_test_suite(name):
    unittest.suite(
        name,
        encoding_test,
        lang_version_test,
        section_name_test,
        target_path_test,
    )
