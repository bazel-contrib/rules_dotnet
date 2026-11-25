"""Unit tests for which copy of an assembly a .NET application loads and publishes."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private:common.bzl", "generate_depsjson", "select_runtime_variants")
load("//dotnet/private/rules/common:publish_layout.bzl", "collect_assembly_files")

def _file(path, owner = None):
    (dirname, _, basename) = path.rpartition("/")
    return struct(path = path, short_path = path, dirname = dirname, basename = basename, owner = owner or path, is_source = True)

def _runtime_info(name, version, libs, nuget = False):
    return struct(
        name = name,
        version = version,
        libs = libs,
        native = [],
        data = [],
        resource_assemblies = [],
        content_files = [],
        appsetting_files = depset(),
        direct_deps = [],
        deps = depset(),
        direct_deps_depsjson_fragment = {},
        nuget_info = struct(
            sha512 = "",
            nupkg = _file("external/{}.v{}/{}.nupkg".format(name.lower(), version, name.lower())),
            portable_assets = None,
        ) if nuget else None,
    )

def _package(name, version):
    return _runtime_info(name, version, [_file("external/{}.v{}/lib/net8.0/{}.dll".format(name.lower(), version, name))], nuget = True)

_APP = _runtime_info("App", "1.0.0", [_file("bazel-out/bin/app/net8.0/App.dll", owner = "//app")])

_RUNTIME_PACK = struct(
    runtime_identifier = "linux-x64",
    assembly_runtime_infos = [_runtime_info(
        "Microsoft.NETCore.App.Runtime.linux-x64",
        "8.0.0",
        [_file("external/runtime_pack/runtimes/linux-x64/lib/net8.0/System.Text.Json.dll")],
    )],
)

def _self_contained(deps):
    """The deps.json targets of a self-contained app, and the assemblies its publish copies."""
    deps_json = generate_depsjson(
        None,
        target_framework = "net8.0",
        is_self_contained = True,
        target_assembly_runtime_info = _APP,
        transitive_runtime_deps = deps,
        runtime_pack_info = _RUNTIME_PACK,
    )
    files = collect_assembly_files("//app", _APP, deps, deps_json)

    return struct(
        targets = deps_json["targets"][".NETCoreApp,Version=v8.0.0/linux-x64"],
        published = [file.path for file in files.libs if file.basename == "System.Text.Json.dll"],
    )

def _runtime(targets, library):
    return targets[library].get("runtime", {}).keys()

def _newest_dependency_wins_test_impl(ctx):
    """The pack's copy is in between, so the newer dependency replaces it and the older one."""
    env = unittest.begin(ctx)

    newer = _package("System.Text.Json", "9.0.0")
    app = _self_contained([_package("System.Text.Json", "7.0.0"), newer])

    asserts.equals(env, [], [dll for dll in _runtime(app.targets, "runtimepack.Microsoft.NETCore.App.Runtime.linux-x64/8.0.0") if dll == "System.Text.Json.dll"])
    asserts.equals(env, [], _runtime(app.targets, "System.Text.Json/7.0.0"))
    asserts.equals(env, ["System.Text.Json.dll"], _runtime(app.targets, "System.Text.Json/9.0.0"))
    asserts.equals(env, [newer.libs[0].path], app.published)

    return unittest.end(env)

_newest_dependency_wins_test = unittest.make(_newest_dependency_wins_test_impl)

def _pack_wins_a_tie_test_impl(ctx):
    """No dependency is newer than the pack, so only the pack's copy is published."""
    env = unittest.begin(ctx)

    app = _self_contained([_package("System.Text.Json", "7.0.0"), _package("System.Text.Json", "8.0.0")])

    asserts.equals(env, ["System.Text.Json.dll"], _runtime(app.targets, "runtimepack.Microsoft.NETCore.App.Runtime.linux-x64/8.0.0"))
    asserts.equals(env, [], _runtime(app.targets, "System.Text.Json/7.0.0"))
    asserts.equals(env, [], _runtime(app.targets, "System.Text.Json/8.0.0"))
    asserts.equals(env, [], app.published)

    return unittest.end(env)

_pack_wins_a_tie_test = unittest.make(_pack_wins_a_tie_test_impl)

def _shared(framework, owner = "//shared"):
    return _runtime_info("Shared", "1.0.0", [_file("bazel-out/{}/bin/shared/{}/Shared.dll".format(framework, framework), owner = owner)])

def _nearest_framework_is_kept_test_impl(ctx):
    """.NET Framework only when nothing else fits, whatever the order the graph gives."""
    env = unittest.begin(ctx)

    for (frameworks, kept) in [
        (["net48", "netstandard2.0"], "netstandard2.0"),
        (["netstandard2.0", "net48"], "netstandard2.0"),
        (["netstandard2.0", "net6.0", "netstandard2.1"], "net6.0"),
        (["net472", "net48"], "net472"),
    ]:
        selected = select_runtime_variants([_shared(framework) for framework in frameworks])
        asserts.equals(env, [kept], [dep.libs[0].dirname.rpartition("/")[2] for dep in selected], str(frameworks))

    return unittest.end(env)

_nearest_framework_is_kept_test = unittest.make(_nearest_framework_is_kept_test_impl)

def _other_targets_are_kept_test_impl(ctx):
    """Two targets building the same assembly are not configurations of one library."""
    env = unittest.begin(ctx)

    deps = [_shared("net48", owner = "//one"), _shared("netstandard2.0", owner = "//two")]
    asserts.equals(env, [dep.libs[0].path for dep in deps], [dep.libs[0].path for dep in select_runtime_variants(deps)])

    return unittest.end(env)

_other_targets_are_kept_test = unittest.make(_other_targets_are_kept_test_impl)

def runtime_variants_test_suite(name):
    unittest.suite(
        name,
        _newest_dependency_wins_test,
        _pack_wins_a_tie_test,
        _nearest_framework_is_kept_test,
        _other_targets_are_kept_test,
    )
