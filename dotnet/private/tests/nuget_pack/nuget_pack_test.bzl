"""The tests of `nuget_pack`: a package in, what it has to hold declared.

`nuget_pack_test` declares what one package holds. Short values are
attributes: the files in it, what its assemblies say they are, the warnings
`dotnet pack` would give and, for a tool, what it prints. Documents are files
beside the test, which `contents` and `symbol_contents` map to the entries of
the package and of its symbol package they must match.

What no package may get wrong fails the test outright, whatever it declares:
an unsorted or timestamped archive, a missing or dangling OPC part, a
framework NuGet cannot read, a symbol package that does not match its
package.

`fails_with_test` is the other half: a target in, the error it fails with out.
"""

load("@bazel_lib//lib:write_source_files.bzl", "write_source_files")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:select_file.bzl", "select_file")
load("//dotnet/private:providers.bzl", "NuGetPackInfo")

_ActualInfo = provider(
    doc = "What `_nuget_pack_actual` found in a package.",
    fields = {
        "json": "File: what the package holds, as far as the test asks.",
        "contents": "dict[string, File]: what the entries asked for hold, by their path in the package.",
        "symbol_contents": "dict[string, File]: the same for the symbol package.",
    },
)

def _check_path(path, attribute):
    for segment in path.split("/"):
        if segment in ["", ".", ".."]:
            fail("`{}`: \"{}\" is not a path in a package".format(attribute, path))

def _nuget_pack_actual_impl(ctx):
    pack = ctx.attr.package[NuGetPackInfo]
    output = ctx.actions.declare_file(ctx.label.name + "/actual.json")

    contents = {}
    for path in ctx.attr.contents:
        _check_path(path, "contents")
        contents[path] = ctx.actions.declare_file("{}/nupkg/{}".format(ctx.label.name, path))
    symbol_contents = {}
    for path in ctx.attr.symbol_contents:
        _check_path(path, "symbol_contents")
        symbol_contents[path] = ctx.actions.declare_file("{}/snupkg/{}".format(ctx.label.name, path))

    request = ctx.actions.declare_file(ctx.label.name + "/request.json")
    ctx.actions.write(request, json.encode(struct(
        nupkg = pack.nupkg.path,
        snupkg = pack.snupkg.path if pack.snupkg else None,
        # Otherwise the version comes from a file, and names nothing.
        versioned = pack.version != None,
        run = ctx.attr.run_arguments if ctx.attr.run else None,
        assemblies = ctx.attr.assemblies,
        contents = [struct(path = path, output = file.path) for (path, file) in contents.items()],
        symbolContents = [struct(path = path, output = file.path) for (path, file) in symbol_contents.items()],
        output = output.path,
    )))

    outputs = [output] + contents.values() + symbol_contents.values()
    ctx.actions.run(
        executable = ctx.executable._check,
        arguments = ["extract", request.path],
        inputs = [request, pack.nupkg] + ([pack.snupkg] if pack.snupkg else []),
        outputs = outputs,
        mnemonic = "NuGetPackExtract",
        progress_message = "Opening the package of %{label}",
    )

    return [
        DefaultInfo(files = depset(outputs)),
        _ActualInfo(json = output, contents = contents, symbol_contents = symbol_contents),
    ]

_nuget_pack_actual = rule(
    _nuget_pack_actual_impl,
    doc = "Opens a package and writes what it holds, failing on what no package may get wrong.",
    attrs = {
        "package": attr.label(providers = [NuGetPackInfo], mandatory = True),
        "run": attr.bool(doc = "Unpacks the tool package and runs its command with `run_arguments`."),
        "run_arguments": attr.string_list(),
        "assemblies": attr.string_list(doc = "The assemblies to say what they are."),
        "contents": attr.string_list(doc = "The entries of the package to write out."),
        "symbol_contents": attr.string_list(doc = "The entries of the symbol package to write out."),
        "_check": attr.label(
            default = "//dotnet/private/tests/nuget_pack/check",
            executable = True,
            cfg = "exec",
        ),
    },
)

def _expected_contents(contents, actual, existing):
    return [
        struct(
            path = path,
            actual = actual[path].path,
            expected = existing[expected].path if expected in existing else None,
            expectedName = expected,
        )
        for (expected, path) in contents.items()
    ]

def _nuget_pack_test_impl(ctx):
    actual = ctx.attr.actual[_ActualInfo]
    existing = {target.label.name: target.files.to_list()[0] for target in ctx.attr.expected_files}
    report = ctx.actions.declare_file(ctx.label.name + ".report.txt")
    request = ctx.actions.declare_file(ctx.label.name + ".request.json")

    # Written by the comparison with its verdict in it, so that nothing has to
    # be found when the test runs.
    is_windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo])
    script = ctx.actions.declare_file(ctx.label.name + (".bat" if is_windows else ".sh"))

    ctx.actions.write(request, json.encode(struct(
        label = "//{}:{}".format(ctx.label.package, ctx.label.name),
        update = "//{}:{}".format(ctx.label.package, ctx.attr.update) if ctx.attr.update else None,
        actual = actual.json.path,
        files = ctx.attr.files,
        symbolFiles = ctx.attr.symbol_files,
        warnings = ctx.attr.warnings,
        assemblies = ctx.attr.assemblies,
        output = ctx.attr.output if ctx.attr.check_output else None,
        contents = _expected_contents(ctx.attr.contents, actual.contents, existing),
        symbolContents = _expected_contents(ctx.attr.symbol_contents, actual.symbol_contents, existing),
        report = report.path,
        script = script.path,
        windows = is_windows,
    )))

    ctx.actions.run(
        executable = ctx.executable._check,
        arguments = ["compare", request.path],
        inputs = depset(
            [request, actual.json] + actual.contents.values() + actual.symbol_contents.values(),
            transitive = [target.files for target in ctx.attr.expected_files],
        ),
        outputs = [report, script],
        mnemonic = "NuGetPackCompare",
        progress_message = "Comparing %{label} with what it expects",
    )

    return [
        DefaultInfo(executable = script),
        OutputGroupInfo(report = depset([report])),
    ]

_nuget_pack_test = rule(
    _nuget_pack_test_impl,
    test = True,
    doc = "Fails with what differs between a package and what the test expects.",
    attrs = {
        "actual": attr.label(providers = [_ActualInfo], mandatory = True),
        "files": attr.string_list(),
        "symbol_files": attr.string_list(),
        "warnings": attr.string_list(),
        "assemblies": attr.string_dict(),
        "check_output": attr.bool(),
        "output": attr.string(),
        "contents": attr.string_dict(doc = "Expected files, by name in this package, to the paths in the package they must match."),
        "symbol_contents": attr.string_dict(doc = "The same for the symbol package."),
        "expected_files": attr.label_list(
            doc = "The expected files that exist: one that does not yet is reported by the test.",
            allow_files = True,
        ),
        "update": attr.string(doc = "The target that rewrites the expected files, in this package."),
        "_check": attr.label(
            default = "//dotnet/private/tests/nuget_pack/check",
            executable = True,
            cfg = "exec",
        ),
        "_windows_constraint": attr.label(default = "@platforms//os:windows"),
    },
)

def nuget_pack_test(
        name,
        package,
        files,
        symbol_files = [],
        contents = {},
        symbol_contents = {},
        assemblies = {},
        warnings = [],
        run = None,
        output = None,
        **kwargs):
    """Checks what a package built by `nuget_pack` holds.

    `bazel run :<name>.update` rewrites the files `contents` and
    `symbol_contents` name from what the package holds, creating them if need
    be. A wrong attribute makes the test print the value to paste instead.

    Args:
      name: The name of the test.
      package: The `nuget_pack` target, in this package.
      files: Every path in the package, other than its manifest and the OPC
        parts every package has.
      symbol_files: Every such path in the symbol package, if there is one.
      contents: Files in this package, by their path relative to it, to the
        paths in the package whose contents must be theirs. JSON is laid out.
      symbol_contents: The same for the symbol package.
      assemblies: What some assemblies must say they are, by path: name and
        version, the versions their attributes carry, the core library they
        compile against and whether they are reference assemblies; or `same
        bytes as <path>` for a copy of one before it.
      warnings: The codes of every warning `dotnet pack` would give.
      run: Unpacks the tool package and runs its command with these arguments.
      output: What that command prints. Set with `run`.
      **kwargs: Passed on to the test, such as `tags` or `size`.
    """
    if (run == None) != (output == None):
        fail("{}: set `run` and `output` together".format(name))

    for expected in contents.keys() + symbol_contents.keys():
        if expected[0] in ":/@":
            fail("{}: \"{}\" has to be a file in this package, as a path relative to it".format(name, expected))
        if expected in contents and expected in symbol_contents:
            fail("{}: \"{}\" is in both `contents` and `symbol_contents`".format(name, expected))

    # An expected file that does not exist yet is reported by the test, not by
    # Bazel failing to find it, so that the update target can still create it.
    existing = native.glob(contents.keys() + symbol_contents.keys(), allow_empty = True)

    _nuget_pack_actual(
        name = name + "_actual",
        package = package,
        run = run != None,
        run_arguments = run or [],
        assemblies = sorted(assemblies.keys()),
        # One entry may be compared with more than one expected file.
        contents = sorted({path: None for path in contents.values()}.keys()),
        symbol_contents = sorted({path: None for path in symbol_contents.values()}.keys()),
        visibility = ["//visibility:private"],
    )

    updates = {}
    for (kind, expected_files) in [("nupkg", contents), ("snupkg", symbol_contents)]:
        for (index, (expected, path)) in enumerate(expected_files.items()):
            select_file(
                name = "{}_{}_{}".format(name, kind, index),
                srcs = name + "_actual",
                subpath = "/{}_actual/{}/{}".format(name, kind, path),
                visibility = ["//visibility:private"],
            )
            updates[expected] = "{}_{}_{}".format(name, kind, index)

    if updates:
        write_source_files(
            name = name + ".update",
            files = updates,
            diff_test = False,
            check_that_out_file_exists = False,
            visibility = ["//dotnet/private/tests/nuget_pack:__pkg__"],
        )

    _nuget_pack_test(
        name = name,
        actual = name + "_actual",
        files = files,
        symbol_files = symbol_files,
        warnings = warnings,
        assemblies = assemblies,
        check_output = run != None,
        output = output or "",
        contents = contents,
        symbol_contents = symbol_contents,
        expected_files = existing,
        update = name + ".update" if updates else "",
        **kwargs
    )

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
