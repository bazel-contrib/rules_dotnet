"""Unit tests of the names resources are embedded under."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private:common.bzl", "embedded_resource_name")

def _file(short_path, owner):
    return struct(
        basename = short_path.split("/")[-1],
        short_path = short_path,
        owner = Label(owner),
    )

def _root_package_test_impl(ctx):
    env = unittest.begin(ctx)

    # A target in the root package used to lose the first character of the path.
    asserts.equals(
        env,
        "app.resource.txt",
        embedded_resource_name(_file("resource.txt", "//:resource.txt"), Label("//:app"), "app.exe"),
    )
    asserts.equals(
        env,
        "Lib.sub.dir.resource.txt",
        embedded_resource_name(_file("sub/dir/resource.txt", "//:sub/dir/resource.txt"), Label("//:lib"), "Lib.dll"),
    )
    return unittest.end(env)

_root_package_test = unittest.make(_root_package_test_impl)

def _package_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(
        env,
        "app.a.b.txt",
        embedded_resource_name(_file("pkg/a/b.txt", "//pkg:a/b.txt"), Label("//pkg:app"), "app.exe"),
    )

    # Outside the target's package the name falls back to the basename.
    asserts.equals(
        env,
        "app.b.txt",
        embedded_resource_name(_file("other/b.txt", "//other:b.txt"), Label("//pkg:app"), "app.exe"),
    )

    # Without an assembly there is nothing to name the resource after.
    asserts.equals(env, None, embedded_resource_name(_file("pkg/b.txt", "//pkg:b.txt"), Label("//pkg:app"), None))
    return unittest.end(env)

_package_test = unittest.make(_package_test_impl)

def resource_name_test_suite(name):
    unittest.suite(
        name,
        _root_package_test,
        _package_test,
    )
