"""Unit tests of the names resources are embedded under.

MSBuild names an `EmbeddedResource` `<assembly name>.<path relative to the
project, with / as .>`, and a file outside the project by its file name only.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private:common.bzl", "add_resource_args", "embedded_resource_name")

def _file(short_path):
    return struct(basename = short_path.split("/")[-1], short_path = short_path)

def _root_package_test_impl(ctx):
    env = unittest.begin(ctx)

    # In the root package the whole path is relative to the package.
    asserts.equals(env, "app.resource.txt", embedded_resource_name(_file("resource.txt"), Label("//:app"), "app.exe"))
    asserts.equals(env, "Lib.sub.dir.resource.txt", embedded_resource_name(_file("sub/dir/resource.txt"), Label("//:lib"), "Lib.dll"))
    return unittest.end(env)

_root_package_test = unittest.make(_root_package_test_impl)

def _package_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, "app.a.b.txt", embedded_resource_name(_file("pkg/a/b.txt"), Label("//pkg:app"), "app.exe"))

    # Outside the target's package the name falls back to the basename.
    asserts.equals(env, "app.b.txt", embedded_resource_name(_file("other/b.txt"), Label("//pkg:app"), "app.exe"))
    asserts.equals(env, "Lib.x.txt", embedded_resource_name(_file("a/x.txt"), Label("//a/b:lib"), "Lib.dll"), "a parent package")
    asserts.equals(env, "Lib.x.txt", embedded_resource_name(_file("a/bc/x.txt"), Label("//a/b:lib"), "Lib.dll"), "a package whose name starts with the target's")
    asserts.equals(env, "Lib.x.txt", embedded_resource_name(_file("../other_repo/a/b/x.txt"), Label("//a/b:lib"), "Lib.dll"), "another repository")

    # Without an assembly there is nothing to name the resource after.
    asserts.equals(env, None, embedded_resource_name(_file("pkg/b.txt"), Label("//pkg:app"), None))
    return unittest.end(env)

_package_test = unittest.make(_package_test_impl)

def _external_repository_test_impl(ctx):
    env = unittest.begin(ctx)

    # A target in another repository names its files relative to its own package there.
    # (A struct, as a label of a repository that does not exist cannot be made.)
    asserts.equals(env, "Lib.n.x.txt", embedded_resource_name(_file("../repo/a/b/n/x.txt"), struct(repo_name = "repo", package = "a/b"), "Lib.dll"))
    asserts.equals(env, "Lib.n.x.txt", embedded_resource_name(_file("../repo/n/x.txt"), struct(repo_name = "repo", package = ""), "Lib.dll"))
    return unittest.end(env)

_external_repository_test = unittest.make(_external_repository_test_impl)

def _resource_formats(short_paths, out_dll = "Lib.dll", language = "csharp"):
    """The `format` of each argument `add_resource_args` adds."""
    added = []
    fake_args = struct(add = lambda value, format: added.append(format))
    add_resource_args(fake_args, [_file(path) for path in short_paths], Label("//a/b:lib"), out_dll, language)
    return added

def _resource_args_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, ["/resource:\"%s\",\"Lib.n.x.txt\""], _resource_formats(["a/b/n/x.txt"]))
    asserts.equals(env, ["--resource:%s,Lib.n.x.txt"], _resource_formats(["a/b/n/x.txt"], language = "fsharp"), "F# names are not quoted")
    asserts.equals(env, ["/resource:\"%s\",\"Lib.100%%.txt\""], _resource_formats(["a/b/100%.txt"]), "`%` is escaped in the format")
    asserts.equals(env, ["/resource:\"%s\""], _resource_formats(["a/b/n/x.txt"], out_dll = None), "no assembly, no name")
    return unittest.end(env)

_resource_args_test = unittest.make(_resource_args_test_impl)

def resource_name_test_suite(name):
    unittest.suite(
        name,
        _root_package_test,
        _package_test,
        _external_repository_test,
        _resource_args_test,
    )
