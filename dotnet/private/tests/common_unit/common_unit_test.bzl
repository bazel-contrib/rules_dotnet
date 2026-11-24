"""Unit tests for the deps.json and copy-script generation in common.bzl."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private:common.bzl", "copy_content_to_dir", "generate_depsjson")

def _file(path):
    (dirname, _, basename) = path.rpartition("/")
    return struct(path = path, short_path = path, dirname = dirname, basename = basename)

def _runtime_info(name, version, nuget_info = None):
    return struct(
        name = name,
        version = version,
        nuget_info = nuget_info,
        direct_deps_depsjson_fragment = {},
        libs = [_file("external/{}/lib/net8.0/{}.dll".format(name.lower(), name))],
        resource_assemblies = [],
        native = [],
    )

def _hash_path_test_impl(ctx):
    env = unittest.begin(ctx)

    package = _runtime_info(
        "Some.Package",
        "1.0.0-RC1",
        nuget_info = struct(sha512 = "sha512-abc", nupkg = _file("external/some.package/some.package.nupkg"), portable_assets = None),
    )
    deps_json = generate_depsjson(
        None,
        target_framework = "net8.0",
        is_self_contained = False,
        target_assembly_runtime_info = _runtime_info("App", "1.0.0"),
        transitive_runtime_deps = [package],
    )
    library = deps_json["libraries"]["Some.Package/1.0.0-RC1"]

    # NuGet lays packages out, and names their hash files, all in lower case.
    asserts.equals(env, "some.package/1.0.0-rc1", library["path"])
    asserts.equals(env, "some.package.1.0.0-rc1.nupkg.sha512", library["hashPath"])
    asserts.equals(
        env,
        {"Some.Package.dll": {"assemblyVersion": "1.0.0.0"}},
        deps_json["targets"][".NETCoreApp,Version=v8.0.0"]["Some.Package/1.0.0-RC1"]["runtime"],
    )

    return unittest.end(env)

_hash_path_test = unittest.make(_hash_path_test_impl)

def _fake_actions(written):
    return struct(
        declare_file = lambda path: _file("bazel-out/bin/pkg/" + path),
        write = lambda output, content, is_executable: written.append(content),
        run = lambda **kwargs: None,
    )

def _batch_copy_script_test_impl(ctx):
    env = unittest.begin(ctx)

    written = []
    copy_content_to_dir(
        "lib",
        _fake_actions(written),
        True,
        [struct(src = _file("pkg/100%/a b.txt"), dest = "50%/a b.txt")],
        "lib/net8.0",
    )

    asserts.equals(env, 1, len(written))
    asserts.equals(
        env,
        [
            "@echo off",
            "if not exist \"bazel-out\\bin\\pkg\\lib\\net8.0\\50%%\" @mkdir \"bazel-out\\bin\\pkg\\lib\\net8.0\\50%%\" >NUL || exit /b 1",
            "@copy /Y \"pkg\\100%%\\a b.txt\" \"bazel-out\\bin\\pkg\\lib\\net8.0\\50%%\\a b.txt\" >NUL || exit /b 1",
        ],
        written[0].split("\r\n"),
    )

    return unittest.end(env)

_batch_copy_script_test = unittest.make(_batch_copy_script_test_impl)

def common_unit_test_suite(name):
    unittest.suite(
        name,
        _hash_path_test,
        _batch_copy_script_test,
    )
