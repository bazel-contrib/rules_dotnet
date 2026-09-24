"""Unit tests of the layout decisions, on hand-built providers."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
    "NuGetInfo",
    "NuGetPackInfo",
    "StaticWebAssetsInfo",
)
load(
    "//dotnet/private/rules/nuget_pack:layout.bzl",
    "analyzer_layout",
    "framework_reference_group",
    "index_dep_packages",
    "is_analyzer",
    "is_valid_package_id",
    "library_layout",
    "plan_library_contents",
    "static_web_assets_layout",
    "static_web_assets_props",
)

def _file(path, is_source = False):
    """Stands in for a File: only the fields the layout reads."""
    return struct(
        path = path,
        basename = path.split("/")[-1],
        dirname = "/".join(path.split("/")[:-1]),
        is_source = is_source,
    )

# A -> B -> C, A and B -> Newtonsoft.Json (a diamond), A -> E (mapped) -> F.
#
# Everything a provider holds is declared at module level so that it is frozen
# by the time a test builds the providers: a depset only takes elements whose
# every field is immutable, and a list made inside a test body is not.
_VERSIONS = {
    "A": "1.2.3",
    "B": "1.0.0",
    "C": "3.0.0",
    "E": "5.0.0",
    "F": "6.0.0",
    "Newtonsoft.Json": "13.0.3",
}
_DIRECT_DEPS = {
    "A": ["B", "Newtonsoft.Json", "E"],
    "B": ["C", "Newtonsoft.Json"],
    "C": [],
    "E": ["F"],
    "F": [],
    "Newtonsoft.Json": [],
}
_LIBS = {name: [_file("out/{}/{}.dll".format(name, name))] for name in _VERSIONS.keys()}
_PDBS = {name: [_file("out/{}/{}.pdb".format(name, name))] for name in _VERSIONS.keys()}
_XML_DOCS = {name: [_file("out/{}/{}.xml".format(name, name))] for name in _VERSIONS.keys()}
_FRAGMENTS = {name: {dep: _VERSIONS[dep] for dep in deps} for (name, deps) in _DIRECT_DEPS.items()}
_NOTHING = []
_NUGET_INFO = NuGetInfo(targeting_pack_overrides = {}, framework_list = {}, sha512 = "", nupkg = None)
_A_REFS = [_file("out/A/ref/A.dll")]

def _assembly(name, built):
    """A DotnetAssemblyRuntimeInfo with the fields the walk and the layout read.

    Args:
      name: The assembly name.
      built: The assemblies built so far, by name; the direct deps must be among them.

    Returns:
      The provider, also recorded in `built`.
    """
    deps = [built[dep] for dep in _DIRECT_DEPS[name]]
    built[name] = DotnetAssemblyRuntimeInfo(
        name = name,
        version = _VERSIONS[name],
        libs = _LIBS[name],
        pdbs = _PDBS[name],
        xml_docs = _XML_DOCS[name],
        native = _NOTHING,
        data = _NOTHING,
        resource_assemblies = _NOTHING,
        appsetting_files = depset(),
        nuget_info = _NUGET_INFO if name == "Newtonsoft.Json" else None,
        deps = depset(deps, transitive = [dep.deps for dep in deps]),
        direct_deps_depsjson_fragment = _FRAGMENTS[name],
    )
    return built[name]

def _graph():
    built = {}
    for name in ["Newtonsoft.Json", "C", "F", "B", "E", "A"]:
        _assembly(name, built)
    return struct(**built)

def _package(id, version, bundled):
    return NuGetPackInfo(
        label = Label("//pkg:" + id),
        package_id = id,
        version = version,
        version_file = None,
        nupkg = None,
        snupkg = None,
        target_frameworks = ["netstandard2.0"],
        bundled_assemblies = bundled,
        is_tool = False,
    )

def _compile_info(refs, analyzers = [], analyzers_csharp = []):
    return DotnetAssemblyCompileInfo(
        name = "A",
        version = "1.2.3",
        project_sdk = "default",
        target_framework = "net9.0",
        refs = refs,
        irefs = [],
        analyzers = analyzers,
        analyzers_csharp = analyzers_csharp,
        analyzers_fsharp = [],
        analyzers_vb = [],
        internals_visible_to = [],
        compile_data = [],
        exports = [],
        transitive_refs = depset(),
        transitive_compile_data = depset(),
        transitive_analyzers = depset(),
        transitive_analyzers_csharp = depset(),
        transitive_analyzers_fsharp = depset(),
        transitive_analyzers_vb = depset(),
    )

_LABEL = Label("//pkg:pack")

# An analyzer is handed its own assembly, the first-party one it loads and, from
# a NuGet package, the Roslyn assemblies it was compiled against.
_ANALYZER_FILES = [
    _file("out/A/A.dll"),
    _file("out/Helper/Helper.dll"),
    _file("external/nuget.roslyn/lib/netstandard2.0/Microsoft.CodeAnalysis.dll", is_source = True),
]

# A library serving two of its own files and reached through one that serves its own.
_STATIC_WEB_ASSETS = [
    struct(file = _file("out/A/wwwroot/css/site.css"), serving_path = "_content/A/css/site.css", scoped_css_bundle = False),
    struct(file = _file("out/A/A.bundle.scp.css"), serving_path = "_content/A/A.bundle.scp.css", scoped_css_bundle = True),
    struct(file = _file("out/B/wwwroot/b.js"), serving_path = "_content/B/b.js", scoped_css_bundle = False),
]

def _e_package():
    return _package("Company.E", "5.0.0", ["E", "F"])

def _ids(plan):
    return [(dependency.id, dependency.version) for dependency in plan.dependencies]

def _names(plan):
    return [info.name for info in plan.bundled]

def _reference_mode_test_impl(ctx):
    env = unittest.begin(ctx)
    graph = _graph()
    e_package = _e_package()
    by_assembly = index_dep_packages([e_package], ["netstandard2.0"], _LABEL)
    plan = plan_library_contents(graph.A, by_assembly, [e_package], "reference", _LABEL)

    # Direct deps only, sorted by id: B and the NuGet package as themselves, E as its package; C and F are B's and E's business.
    asserts.equals(env, [("B", "1.0.0"), ("Company.E", "5.0.0"), ("Newtonsoft.Json", "13.0.3")], _ids(plan))
    asserts.equals(env, [], _names(plan))
    return unittest.end(env)

def _bundle_mode_test_impl(ctx):
    env = unittest.begin(ctx)
    graph = _graph()
    e_package = _e_package()
    by_assembly = index_dep_packages([e_package], ["netstandard2.0"], _LABEL)
    plan = plan_library_contents(graph.A, by_assembly, [e_package], "bundle", _LABEL)

    # B and C are copied in; B's NuGet dependency is declared once for the diamond; E's subtree stops at the package.
    asserts.equals(env, [("Company.E", "5.0.0"), ("Newtonsoft.Json", "13.0.3")], _ids(plan))
    asserts.equals(env, ["B", "C"], _names(plan))
    return unittest.end(env)

def _dep_package_always_declared_test_impl(ctx):
    env = unittest.begin(ctx)
    unrelated = _package("Company.Unrelated", "9.0.0", ["Z"])
    plan = plan_library_contents(_graph().A, index_dep_packages([unrelated], ["netstandard2.0"], _LABEL), [unrelated], "bundle", _LABEL)
    asserts.true(env, ("Company.Unrelated", "9.0.0") in _ids(plan))
    return unittest.end(env)

def _index_assemblies_test_impl(ctx):
    env = unittest.begin(ctx)
    one = _package("One", "1.0.0", ["Shared"])

    # One package listed twice is one entry. Two packages claiming one assembly
    # is a failure, which `two_packages_one_assembly_test` covers.
    asserts.equals(env, {"Shared": one}, index_dep_packages([one, one], ["netstandard2.0"], _LABEL))
    return unittest.end(env)

def _library_layout_test_impl(ctx):
    env = unittest.begin(ctx)
    graph = _graph()
    compile_info = _compile_info(_A_REFS)

    layout = library_layout("net9.0", None, compile_info, graph.A, [graph.B], "snupkg", reference_assemblies = True, emit_portable = True)
    asserts.equals(env, [
        "lib/net9.0/A.dll",
        "lib/net9.0/A.xml",
        "lib/net9.0/B.dll",
        "lib/net9.0/B.xml",
        "ref/net9.0/A.dll",
        "ref/net9.0/B.dll",
    ], sorted([path for (path, _) in layout.files]))
    asserts.equals(env, ["lib/net9.0/A.pdb", "lib/net9.0/B.pdb"], sorted([path for (path, _) in layout.symbol_files]))

    # No reference assemblies wanted: lib/ alone.
    layout = library_layout("net9.0", None, compile_info, graph.A, [], "embedded", reference_assemblies = False, emit_portable = True)
    asserts.equals(env, ["lib/net9.0/A.dll", "lib/net9.0/A.pdb", "lib/net9.0/A.xml"], sorted([path for (path, _) in layout.files]))

    # F# without --refout: the reference assembly is the implementation, so ref/ is left out.
    same = _compile_info(graph.A.libs)
    layout = library_layout("net9.0", None, same, graph.A, [], "none", reference_assemblies = True, emit_portable = True)
    asserts.equals(env, ["lib/net9.0/A.dll", "lib/net9.0/A.xml"], sorted([path for (path, _) in layout.files]))

    # RID-specific: runtimes/ per split, ref/ and docs from the first split only.
    first = library_layout("net9.0", "linux-x64", same, graph.A, [], "none", reference_assemblies = True, emit_portable = True)
    asserts.equals(env, ["ref/net9.0/A.dll", "ref/net9.0/A.xml", "runtimes/linux-x64/lib/net9.0/A.dll"], sorted([path for (path, _) in first.files]))
    second = library_layout("net9.0", "win-x64", same, graph.A, [], "none", reference_assemblies = True, emit_portable = False)
    asserts.equals(env, ["runtimes/win-x64/lib/net9.0/A.dll"], sorted([path for (path, _) in second.files]))
    return unittest.end(env)

def _analyzer_layout_test_impl(ctx):
    env = unittest.begin(ctx)
    graph = _graph()

    asserts.false(env, is_analyzer(_compile_info(_A_REFS)))
    asserts.true(env, is_analyzer(_compile_info([], analyzers_csharp = _ANALYZER_FILES)))
    asserts.true(env, is_analyzer(_compile_info([], analyzers = _ANALYZER_FILES)))

    # Language-specific: a language folder, and the Roslyn assemblies that came
    # out of a package are left behind.
    layout = analyzer_layout(_compile_info([], analyzers_csharp = _ANALYZER_FILES), graph.A, "embedded")
    asserts.equals(env, [
        "analyzers/dotnet/cs/A.dll",
        "analyzers/dotnet/cs/A.pdb",
        "analyzers/dotnet/cs/Helper.dll",
    ], sorted([path for (path, _) in layout.files]))
    asserts.equals(env, [], layout.symbol_files)

    # Not language-specific: the folder above it. The pdb follows `symbols`.
    layout = analyzer_layout(_compile_info([], analyzers = _ANALYZER_FILES), graph.A, "snupkg")
    asserts.equals(env, [
        "analyzers/dotnet/A.dll",
        "analyzers/dotnet/Helper.dll",
    ], sorted([path for (path, _) in layout.files]))
    asserts.equals(env, ["analyzers/dotnet/A.pdb"], [path for (path, _) in layout.symbol_files])

    layout = analyzer_layout(_compile_info([], analyzers = _ANALYZER_FILES), graph.A, "none")
    asserts.equals(env, [], layout.symbol_files)
    asserts.equals(env, 2, len(layout.files))
    return unittest.end(env)

def _static_web_assets_test_impl(ctx):
    env = unittest.begin(ctx)
    assets = StaticWebAssetsInfo(assets = depset(_STATIC_WEB_ASSETS))

    # Only what this library serves: B ships its own files in its own package.
    layout = static_web_assets_layout(assets, "A", [], _LABEL)
    asserts.equals(env, [
        "staticwebassets/A.bundle.scp.css",
        "staticwebassets/css/site.css",
    ], [path for (path, _) in layout.files])
    asserts.equals(env, ["A.bundle.scp.css", "css/site.css"], layout.paths)

    # A library that serves nothing of its own contributes nothing.
    asserts.equals(env, [], static_web_assets_layout(assets, "C", [], _LABEL).files)

    props = static_web_assets_props("Company.A", layout.paths)
    asserts.true(env, "<BasePath>_content/Company.A</BasePath>" in props, props)
    asserts.true(env, "<RelativePath>css/site.css</RelativePath>" in props, props)
    asserts.true(env, "<ContentRoot>$(MSBuildThisFileDirectory)../staticwebassets/</ContentRoot>" in props, props)
    asserts.equals(env, 2, props.count("<StaticWebAsset "), props)
    return unittest.end(env)

def _framework_reference_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, None, framework_reference_group("net9.0", "default"))
    asserts.equals(env, None, framework_reference_group("netstandard2.0", "web"))
    asserts.equals(env, None, framework_reference_group("netcoreapp2.1", "web"))
    asserts.equals(env, ["Microsoft.AspNetCore.App"], framework_reference_group("netcoreapp3.1", "web").frameworkReferences)
    asserts.equals(env, "net9.0", framework_reference_group("net9.0", "razor").targetFramework)
    return unittest.end(env)

def _package_id_test_impl(ctx):
    env = unittest.begin(ctx)
    for valid in ["A", "Foo.Bar", "foo-bar_baz", "a1.b2", "_x", "x_", "a__b"]:
        asserts.true(env, is_valid_package_id(valid), valid)
    for invalid in ["", ".Foo", "Foo.", "Foo..Bar", "Foo-.Bar", "Foo Bar", "Foo/Bar", "Foo+Bar", "x" * 101]:
        asserts.false(env, is_valid_package_id(invalid), invalid)
    return unittest.end(env)

reference_mode_test = unittest.make(_reference_mode_test_impl)
bundle_mode_test = unittest.make(_bundle_mode_test_impl)
dep_package_always_declared_test = unittest.make(_dep_package_always_declared_test_impl)
index_assemblies_test = unittest.make(_index_assemblies_test_impl)
library_layout_test = unittest.make(_library_layout_test_impl)
analyzer_layout_test = unittest.make(_analyzer_layout_test_impl)
static_web_assets_test = unittest.make(_static_web_assets_test_impl)
framework_reference_test = unittest.make(_framework_reference_test_impl)
package_id_test = unittest.make(_package_id_test_impl)

def layout_test_suite(name):
    unittest.suite(
        name,
        reference_mode_test,
        bundle_mode_test,
        dep_package_always_declared_test,
        index_assemblies_test,
        library_layout_test,
        analyzer_layout_test,
        static_web_assets_test,
        framework_reference_test,
        package_id_test,
    )
