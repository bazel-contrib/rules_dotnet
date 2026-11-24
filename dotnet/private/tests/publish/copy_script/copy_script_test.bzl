"""Tests for the scripts that copy a publish's files into place."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//dotnet/private/rules/publish_binary:copy_script.bzl", "render_copy_script")

def _file(path, is_directory = False):
    return struct(path = path, basename = path.rsplit("/", 1)[-1], is_directory = is_directory)

def _batch_escapes_percent_test_impl(ctx):
    """cmd.exe expands `%` even between quotes, so a batch file has to double it."""
    env = unittest.begin(ctx)

    lines = render_copy_script([(_file("pkg/100%/a%b.dll"), "out/50%/a%b.dll")], is_windows = True)

    asserts.equals(env, [
        "@echo off",
        "if not exist \"out\\50%%\" mkdir \"out\\50%%\" || exit /b 1",
        "copy /Y \"pkg\\100%%\\a%%b.dll\" \"out\\50%%\" >NUL || exit /b 1",
    ], lines)

    return unittest.end(env)

batch_escapes_percent_test = unittest.make(_batch_escapes_percent_test_impl)

def _batch_stops_on_failure_test_impl(ctx):
    """A batch file carries on past a failed command unless told to stop."""
    env = unittest.begin(ctx)

    lines = render_copy_script(
        [
            (_file("a/x.dll"), "out/x.dll"),
            (_file("a/y.txt"), "out/sub/renamed.txt"),
            (_file("a/tree", is_directory = True), "out/tree"),
        ],
        is_windows = True,
        directories = ["out/empty"],
    )

    # So that a script missing its commands cannot pass: four directories, for
    # `out/empty`, `out`, `out/sub` and the tree, and three copies.
    asserts.equals(env, 4, len([line for line in lines if "mkdir " in line]), "mkdir commands")
    asserts.equals(env, 3, len([line for line in lines if "copy /Y " in line]), "copy commands")

    for line in lines[1:]:
        asserts.true(env, line.endswith(" || exit /b 1"), "does not stop on failure: " + line)

    return unittest.end(env)

batch_stops_on_failure_test = unittest.make(_batch_stops_on_failure_test_impl)

def _shell_batches_by_directory_test_impl(ctx):
    """Files keeping their name share one `cp` per directory; renamed ones get their own."""
    env = unittest.begin(ctx)

    lines = render_copy_script(
        [
            (_file("a/x.dll"), "out/x.dll"),
            (_file("b/it's here.txt"), "out/sub/it's here.txt"),
            (_file("c/y.dll"), "out/y.dll"),
            (_file("d/z.txt"), "out/sub/renamed.txt"),
        ],
        is_windows = False,
        directories = ["out/empty"],
    )

    asserts.equals(env, [
        "#! /usr/bin/env bash",
        "set -eou pipefail",
        "mkdir -p 'out/empty'",
        "mkdir -p 'out'",
        "cp -f 'a/x.dll' 'c/y.dll' 'out'",
        "mkdir -p 'out/sub'",
        "cp -f 'b/it'\\''s here.txt' 'out/sub'",
        "cp -f 'd/z.txt' 'out/sub/renamed.txt'",
    ], lines)

    return unittest.end(env)

shell_batches_by_directory_test = unittest.make(_shell_batches_by_directory_test_impl)

def _directory_copies_its_contents_test_impl(ctx):
    """A tree artifact is copied as its contents, into the directory declared for it."""
    env = unittest.begin(ctx)

    asserts.equals(env, [
        "#! /usr/bin/env bash",
        "set -eou pipefail",
        "mkdir -p 'out/tree'",
        "cp -Rf 'a/tree'/. 'out/tree'",
    ], render_copy_script([(_file("a/tree", is_directory = True), "out/tree")], is_windows = False))

    asserts.equals(env, [
        "@echo off",
        "if not exist \"out\\tree\" mkdir \"out\\tree\" || exit /b 1",
        "for %%F in (\"a\\tree\\*\") do copy /Y \"%%F\" \"out\\tree\" >NUL || exit /b 1",
    ], render_copy_script([(_file("a/tree", is_directory = True), "out/tree")], is_windows = True))

    return unittest.end(env)

directory_copies_its_contents_test = unittest.make(_directory_copies_its_contents_test_impl)

def copy_script_test_suite(name):
    unittest.suite(
        name,
        batch_escapes_percent_test,
        batch_stops_on_failure_test,
        directory_copies_its_contents_test,
        shell_batches_by_directory_test,
    )
