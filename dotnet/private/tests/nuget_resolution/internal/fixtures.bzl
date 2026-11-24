"""The packages the resolution tests run against, declared in code.

`nuget_archive` fetches a `.nupkg`, unpacks it and turns the file layout into
targets. This skips the fetching: every test's layout is given as a list of
paths, the files are created empty, and the same code produces the same
targets, one package per test.
"""

# buildifier: disable=bzl-visibility
load(
    "//dotnet/private/rules/nuget:nuget_archive.bzl",
    "write_repository_for_testing",
)
load("//dotnet/private/tests/nuget_resolution:tests.bzl", "TESTS")

_NUSPEC = """<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
  <metadata>
    <id>{id}</id>
    <version>{version}</version>
    <description>fixture</description>
    <authors>fixture</authors>
  </metadata>
</package>
"""

def _nuget_fixtures_impl(ctx):
    ctx.file("BUILD.bazel", "")

    for test in TESTS:
        id = "fixture.%s" % test.name

        # Upper case, like some pre-release labels: the package has to find
        # its `.nupkg` under the lower cased name `nuget_archive` downloads to.
        version = "Fixture_%s" % test.name
        nuspec = "%s.nuspec" % id
        nupkg = ("%s.%s.nupkg" % (id, version)).lower()
        prefix = "%s/" % test.name

        ctx.file(prefix + nuspec, _NUSPEC.format(id = id, version = version))
        ctx.file(prefix + nupkg, "")

        for file in test.files:
            ctx.file(prefix + file, test.contents.get(file, ""))

        write_repository_for_testing(
            ctx,
            id,
            nupkg,
            sorted(test.files + [nuspec, nupkg]),
            prefix,
        )

_nuget_fixtures_repo = repository_rule(
    _nuget_fixtures_impl,
    doc = "One package per test, laid out from the list of paths it declares.",
)

def _extension_impl(_ctx):
    _nuget_fixtures_repo(name = "nuget_fixtures")

nuget_fixtures = module_extension(implementation = _extension_impl)
