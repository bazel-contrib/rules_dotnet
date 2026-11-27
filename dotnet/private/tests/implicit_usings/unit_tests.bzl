"""Unit tests for reading the SDK's `Using` items and evaluating their MSBuild conditions."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private:msbuild_condition.bzl", "evaluate_condition")
load("//dotnet/private/sdk:implicit_usings.bzl", "extract_using_items")

_PROPERTIES = {
    "implicitusings": "enable",
    "language": "C#",
    "targetframeworkidentifier": ".NETCoreApp",
    "targetframeworkversion": "v10.0",
    "usewpf": "true",
}

def _expect(env, condition, expected, properties = _PROPERTIES):
    result, error = evaluate_condition(condition, properties)
    asserts.equals(env, None, error, "error evaluating " + condition)
    asserts.equals(env, expected, result, condition)

def _expect_error(env, condition, message):
    result, error = evaluate_condition(condition, _PROPERTIES)
    asserts.equals(env, None, result, condition)
    asserts.true(env, error != None and message in error, "expected {} in {}".format(repr(message), repr(error)))

def _conditions_test_impl(ctx):
    env = unittest.begin(ctx)

    # As written in the SDK 11 props.
    _expect(env, "'$(ImplicitUsings)' == 'true' Or '$(ImplicitUsings)' == 'enable'", True)
    _expect(env, "'$(Language)' == 'C#' AND ('$(ImplicitUsings)' == 'true' or '$(ImplicitUsings)' == 'enable')", True)
    _expect(env, "'$(TargetFrameworkIdentifier)' != '.NETFramework'", True)
    _expect(env, "'$(UseWPF)' == 'true' and ('$(ImplicitUsings)' == 'true' or '$(ImplicitUsings)' == 'enable')", True)
    _expect(env, "'$(UseWindowsForms)' == 'true' and ('$(ImplicitUsings)' == 'true' or '$(ImplicitUsings)' == 'enable')", False)
    net11 = "'$(TargetFrameworkIdentifier)' == '.NETCoreApp' And $([MSBuild]::VersionGreaterThanOrEquals('$(TargetFrameworkVersion)', '11.0'))"
    _expect(env, net11, False)
    _expect(env, net11, True, dict(_PROPERTIES, targetframeworkversion = "v11.0"))
    _expect(env, net11, True, dict(_PROPERTIES, targetframeworkversion = "v12.0"))

    # Comparisons ignore case, and an undefined property is empty.
    _expect(env, "'$(Language)' == 'c#'", True)
    _expect(env, "'$(Undefined)' == ''", True)

    # `and` binds tighter than `or`, and `!` tighter than both.
    _expect(env, "'a' == 'a' or 'a' == 'b' and 'a' == 'b'", True)
    _expect(env, "('a' == 'a' or 'a' == 'b') and 'a' == 'b'", False)
    _expect(env, "!('a' == 'b') and !false", True)
    _expect(env, "$([MSBuild]::VersionLessThan('4.8', '4.8.1'))", True)
    _expect(env, "true", True)

    # What the SDK does not use is reported rather than guessed.
    _expect_error(env, "Exists('foo')", "unsupported syntax")
    _expect_error(env, "$([System.String]::Copy('a')) == 'a'", "unsupported property function")
    _expect_error(env, "'@(Using)' != ''", "unsupported expression")
    _expect_error(env, "'1' < '2'", "unsupported syntax")
    _expect_error(env, "('a' == 'a'", "unbalanced parentheses")
    _expect_error(env, "'maybe'", "is not a boolean")

    return unittest.end(env)

_conditions_test = unittest.make(_conditions_test_impl)

_PROPS = """<Project>
  <!-- A comment with a <Using Include="Not.Read" /> inside. -->
  <ItemGroup Condition="'$(ImplicitUsings)' == 'enable'">
    <Using Include="System" />
    <Using Include="System.Net.Http" Condition="'$(TargetFrameworkIdentifier)' != '.NETFramework'"/>
    <Using Include="A;B" />
  </ItemGroup>
  <ItemGroup>
    <Using Remove="System.IO" />
  </ItemGroup>
  <Target Name="AddedAsTheBuildRuns">
    <ItemGroup>
      <Using Include="Not.Read" />
    </ItemGroup>
  </Target>
</Project>
"""

def _extract_test_impl(ctx):
    env = unittest.begin(ctx)

    implicit = ["'$(ImplicitUsings)' == 'enable'"]
    asserts.equals(env, {
        "items": [
            {"conditions": implicit, "namespace": "System", "op": "include"},
            {"conditions": implicit + ["'$(TargetFrameworkIdentifier)' != '.NETFramework'"], "namespace": "System.Net.Http", "op": "include"},
            {"conditions": implicit, "namespace": "A", "op": "include"},
            {"conditions": implicit, "namespace": "B", "op": "include"},
            {"conditions": [], "namespace": "System.IO", "op": "remove"},
        ],
        "unsupported": "",
    }, extract_using_items(_PROPS))

    # Items rules_dotnet cannot represent are reported, so that the targets
    # using them fail instead of silently missing a namespace.
    unsupported = extract_using_items("""<Project>
  <ItemGroup><Using Include="System.Math" Static="true" /></ItemGroup>
  <Choose><When Condition="true"><ItemGroup><Using Include="X" /></ItemGroup></When></Choose>
</Project>""")
    asserts.equals(env, [], unsupported["items"])
    asserts.true(env, "Static=\"true\"" in unsupported["unsupported"], unsupported["unsupported"])
    asserts.true(env, "a Using item under Project/Choose/When/ItemGroup" in unsupported["unsupported"], unsupported["unsupported"])

    return unittest.end(env)

_extract_test = unittest.make(_extract_test_impl)

def implicit_usings_unit_test_suite(name):
    unittest.suite(
        name,
        _conditions_test,
        _extract_test,
    )
