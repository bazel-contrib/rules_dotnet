"""The shape of a resolution test.

A declaration that states something the test cannot assert is a silent hole, so
every combination that would be ignored is rejected here instead.
"""

_DEFAULT_TFM = "net8.0"
_DEFAULT_RID = "linux-x64"

def _reject_unchecked(name, reason, reads, stated):
    """Rejects a declaration that states an expectation nothing will look at."""
    ignored = [field for field in stated if field not in reads]

    if ignored:
        fail("{}: {}, so {} would never be checked".format(name, reason, ", ".join(ignored)))

def nuget_resolution_test(
        name,
        files,
        target_framework = None,
        runtime_identifier = None,
        contents = {},
        expected_refs = [],
        expected_libs = [],
        expected_native = [],
        expected_analyzers = [],
        expected_analyzers_csharp = [],
        expected_analyzers_fsharp = [],
        expected_analyzers_vb = [],
        expected_resource_assemblies = [],
        expected_content_files = [],
        expected_tools = {},
        expected_framework_list = {},
        expected_targeting_pack_overrides = {},
        expected_runtime_targets = {},
        expect_incompatible = False,
        default_configuration = False,
        portable = False):
    """One package layout and what a build gets out of it.

    Stating no expectations at all is how a test says the package resolves to
    nothing, which is different from it being incompatible.

    Args:
      name: What the test asserts, as a sentence.
      files: Every file the package ships.
      target_framework: The framework being built. Defaults to net8.0.
      runtime_identifier: The RID being built. Defaults to linux-x64.
      contents: Contents for the files that are parsed rather than listed.
      expected_refs: The assemblies the compiler references.
      expected_libs: The assemblies that end up next to the binary.
      expected_native: The native libraries that end up next to the binary.
      expected_analyzers: Language agnostic analyzers.
      expected_analyzers_csharp: C# analyzers.
      expected_analyzers_fsharp: F# analyzers.
      expected_analyzers_vb: VB analyzers.
      expected_resource_assemblies: Localized satellite assemblies.
      expected_content_files: The `contentFiles` a package ships. They are not
        resolved per framework, so a test asserting on them asserts nothing else.
      expected_tools: The files a package offers `dotnet tool`, keyed by the
        framework they sit under. Read straight off the archive, so a test
        asserting on them asserts nothing else.
      expected_framework_list: Assembly versions a targeting pack declares.
      expected_targeting_pack_overrides: Packages a targeting pack supersedes.
      expected_runtime_targets: Every runtime's assets an app that runs on any
        runtime takes, by their path in the package, to `<rid> native` or
        `<rid> runtime`. Read by a `portable` test alone.
      expect_incompatible: The package supports nothing that can be built here,
        which is an error rather than a package that brings nothing. Asserts
        only that, so no other expectation can be stated alongside it.
      default_configuration: Resolve without a framework transition in front,
        the way anything reaching the package from outside the .NET rules does.
        There is no framework or RID to name, and only `expected_libs` is read.
      portable: Resolve what an app that runs on any runtime takes, as a .NET
        tool package does: `expected_libs` are then its RID-agnostic
        assemblies, `expected_runtime_targets` every runtime's assets, and
        nothing else is read. There is no RID to name.

    Returns:
      The test declaration.
    """
    stated = [
        field
        for (field, value) in [
            ("expected_refs", expected_refs),
            ("expected_libs", expected_libs),
            ("expected_native", expected_native),
            ("expected_analyzers", expected_analyzers),
            ("expected_analyzers_csharp", expected_analyzers_csharp),
            ("expected_analyzers_fsharp", expected_analyzers_fsharp),
            ("expected_analyzers_vb", expected_analyzers_vb),
            ("expected_resource_assemblies", expected_resource_assemblies),
            ("expected_content_files", expected_content_files),
            ("expected_tools", expected_tools),
            ("expected_framework_list", expected_framework_list),
            ("expected_targeting_pack_overrides", expected_targeting_pack_overrides),
            ("expected_runtime_targets", expected_runtime_targets),
        ]
        if value
    ]

    if not files:
        fail("{}: a test needs a package layout to resolve".format(name))

    shipped = {file: True for file in files}

    for file in contents:
        if file not in shipped:
            fail("{}: contents names `{}`, which the package does not ship".format(name, file))

    if expect_incompatible:
        if default_configuration:
            fail(
                ("{}: a package that cannot be resolved has nothing to resolve in " +
                 "the default configuration either; state one or the other").format(name),
            )

        _reject_unchecked(name, "expect_incompatible asserts only that resolution fails", [], stated)

    if expected_content_files:
        if expect_incompatible or default_configuration:
            fail("{}: content files are asserted on their own".format(name))

        _reject_unchecked(
            name,
            "content files are not resolved per framework, so a test asserting on them asserts nothing else",
            ["expected_content_files"],
            stated,
        )

    if expected_tools:
        if expect_incompatible or default_configuration:
            fail("{}: tools are asserted on their own".format(name))

        _reject_unchecked(
            name,
            "a tools test reads the archive's tools group directly",
            ["expected_tools"],
            stated,
        )

    if default_configuration:
        if target_framework or runtime_identifier:
            fail(
                ("{}: a default configuration test resolves without a transition, so it " +
                 "cannot name a target_framework or a runtime_identifier").format(name),
            )

        _reject_unchecked(
            name,
            "a default configuration test reads expected_libs only",
            ["expected_libs"],
            stated,
        )

    if portable:
        if expect_incompatible or default_configuration:
            fail("{}: a portable test is asserted on its own".format(name))

        if runtime_identifier:
            fail("{}: a portable test takes every runtime, so it cannot name a runtime_identifier".format(name))

        _reject_unchecked(
            name,
            "a portable test reads expected_libs and expected_runtime_targets only",
            ["expected_libs", "expected_runtime_targets"],
            stated,
        )
    elif expected_runtime_targets:
        fail("{}: only a portable test reads expected_runtime_targets".format(name))

    return struct(
        name = name,
        files = files,
        target_framework = target_framework or _DEFAULT_TFM,
        runtime_identifier = runtime_identifier or _DEFAULT_RID,
        contents = contents,
        expected_refs = expected_refs,
        expected_libs = expected_libs,
        expected_native = expected_native,
        expected_analyzers = expected_analyzers,
        expected_analyzers_csharp = expected_analyzers_csharp,
        expected_analyzers_fsharp = expected_analyzers_fsharp,
        expected_analyzers_vb = expected_analyzers_vb,
        expected_resource_assemblies = expected_resource_assemblies,
        expected_content_files = expected_content_files,
        expected_tools = expected_tools,
        expected_framework_list = expected_framework_list,
        expected_targeting_pack_overrides = expected_targeting_pack_overrides,
        expected_runtime_targets = expected_runtime_targets,
        expect_incompatible = expect_incompatible,
        default_configuration = default_configuration,
        portable = portable,
    )
