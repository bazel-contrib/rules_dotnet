"""Asserts which copy of an assembly a Blazor WebAssembly site ships when a dependency and the runtime pack both carry it.

The newer copy, as MSBuild resolves the conflict. The applications are only
analysed, never built.
"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("//dotnet:defs.bzl", "csharp_binary", "csharp_library", "import_library", "publish_binary")

_PACKAGES = "@paket.rules_dotnet_static_web_assets_tests//"

# Where the runtime pack's files are, and where each package's are.
_RUNTIME_PACK = "runtime.mono.browser-wasm"

def _file(description, where, basename):
    return matching.custom(
        description,
        lambda file: file.basename == basename and where in file.path,
    )

def _app(name, deps):
    csharp_binary(
        name = name,
        srcs = [
            "App.razor",
            "Program.cs",
            "_Imports.razor",
        ],
        project_sdk = "blazorwasm",
        root_namespace = "BlazorApp",
        tags = ["manual"],
        target_frameworks = ["net10.0"],
        deps = [_PACKAGES + "microsoft.aspnetcore.components.webassembly"] + deps,
    )

def _publish(name, deps):
    _app(name + "_app", deps)
    publish_binary(
        name = name + "_publish",
        binary = name + "_app",
        tags = ["manual"],
        target_framework = "net10.0",
        wasm = True,
    )
    return name + "_publish"

def _imported(name, basename, version = None):
    """An imported library shipping a DLL named `basename`, with `version` if any."""
    native.genrule(
        name = name + "_dll",
        outs = [name + "/" + basename],
        cmd = "touch $@",
        tags = ["manual"],
    )
    import_library(
        name = name,
        library_name = name,
        libs = [name + "_dll"],
        tags = ["manual"],
        **({"version": version} if version else {})
    )
    return name

def _assembled(env, target):
    return env.expect.that_target(target).action_named("BlazorWasmAssemble").inputs()

def _older_package_loses_test(name):
    analysis_test(
        name = name,
        impl = _older_package_loses_test_impl,
        target = _publish(name, [_PACKAGES + "system.text.json"]),
    )

def _older_package_loses_test_impl(env, target):
    # 8.0.5, against the pack's 10.0: the framework's own assemblies are built
    # against the pack's copy and would fail to load the older one.
    inputs = _assembled(env, target)
    inputs.contains_predicate(_file("the runtime pack's System.Text.Json.dll", _RUNTIME_PACK, "System.Text.Json.dll"))
    inputs.not_contains_predicate(_file("the package's System.Text.Json.dll", "nuget.system.text.json.", "System.Text.Json.dll"))

def _newer_package_wins_test(name):
    analysis_test(
        name = name,
        impl = _newer_package_wins_test_impl,
        target = _publish(name, [_PACKAGES + "system.collections.immutable"]),
    )

def _newer_package_wins_test_impl(env, target):
    # 11.0, against the pack's 10.0.
    inputs = _assembled(env, target)
    inputs.contains_predicate(_file("the package's System.Collections.Immutable.dll", "nuget.system.collections.immutable.", "System.Collections.Immutable.dll"))
    inputs.not_contains_predicate(_file("the runtime pack's System.Collections.Immutable.dll", _RUNTIME_PACK, "System.Collections.Immutable.dll"))

def _unversioned_import_loses_test(name):
    analysis_test(
        name = name,
        impl = _unversioned_import_loses_test_impl,
        target = _publish(name, [_imported(name + "_import", "System.Formats.Asn1.dll")]),
    )

def _unversioned_import_loses_test_impl(env, target):
    # An import that sets no version cannot be shown to be the newer.
    inputs = _assembled(env, target)
    inputs.contains_predicate(_file("the runtime pack's System.Formats.Asn1.dll", _RUNTIME_PACK, "System.Formats.Asn1.dll"))
    inputs.not_contains_predicate(_file("the import's System.Formats.Asn1.dll", "_import/", "System.Formats.Asn1.dll"))

def _newest_of_two_test(name, import_first):
    imported = _imported(name + "_import", "System.Collections.Immutable.dll", version = "10.9.0")
    package = _PACKAGES + "system.collections.immutable"
    analysis_test(
        name = name,
        impl = _newest_of_two_test_impl,
        target = _publish(name, [imported, package] if import_first else [package, imported]),
    )

def _newest_of_two_test_impl(env, target):
    # Both are newer than the pack's 10.0, but the package's 11.0 is the newest.
    inputs = _assembled(env, target)
    inputs.contains_predicate(_file("the package's System.Collections.Immutable.dll", "nuget.system.collections.immutable.", "System.Collections.Immutable.dll"))
    inputs.not_contains_predicate(_file("the import's System.Collections.Immutable.dll", "_import/", "System.Collections.Immutable.dll"))

def _newest_of_two_import_first_test(name):
    _newest_of_two_test(name, import_first = True)

def _newest_of_two_import_last_test(name):
    _newest_of_two_test(name, import_first = False)

def _symbols_of_shipped_assemblies_test(name):
    csharp_library(
        name = name + "_older",
        srcs = ["Reflected.cs"],
        out = "System.Text.Json",
        tags = ["manual"],
        target_frameworks = ["net10.0"],
    )
    csharp_library(
        name = name + "_newer",
        srcs = ["Reflected.cs"],
        out = "System.Collections.Immutable",
        tags = ["manual"],
        target_frameworks = ["net10.0"],
        version = "99.0.0",
    )
    _app(name + "_app", [name + "_older", name + "_newer"])

    # The development build, which ships symbols.
    analysis_test(
        name = name,
        impl = _symbols_of_shipped_assemblies_test_impl,
        target = name + "_app",
    )

def _symbols_of_shipped_assemblies_test_impl(env, target):
    # A debugger would match a symbol file against the assembly the site ships,
    # so one whose assembly lost to the pack's copy does not go with it.
    inputs = _assembled(env, target)
    inputs.contains_predicate(_file("the newer library's symbols", "_newer/", "System.Collections.Immutable.pdb"))
    inputs.not_contains_predicate(_file("the older library's symbols", "_older/", "System.Text.Json.pdb"))

def blazor_wasm_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _older_package_loses_test,
            _newer_package_wins_test,
            _unversioned_import_loses_test,
            _newest_of_two_import_first_test,
            _newest_of_two_import_last_test,
            _symbols_of_shipped_assemblies_test,
        ],
    )
