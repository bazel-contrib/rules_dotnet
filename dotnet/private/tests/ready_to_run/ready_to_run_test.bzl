"""Tests for what a ReadyToRun image is compiled against."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//dotnet/private/rules/ready_to_run:ready_to_run.bzl", "ready_to_run_references")

def _stripped_references(app_configuration, lib_configuration):
    """The references of an application and a library it depends on, built in two configurations.

    Returned as `--experimental_output_paths=strip` passes them to crossgen2.
    """
    app = struct(path = "bazel-out/{}/bin/app/app.dll".format(app_configuration), is_source = False)
    lib = struct(path = "bazel-out/{}/bin/lib/lib.dll".format(lib_configuration), is_source = False)
    package = struct(path = "external/package/lib/package.dll", is_source = True)

    references = ready_to_run_references([app], depset([struct(libs = (lib,)), struct(libs = (package,))]))

    return [
        file.path.replace(app_configuration, "cfg").replace(lib_configuration, "cfg")
        for file in references.files
    ]

def _order_independent_of_configurations_test_impl(ctx):
    """The same image in two configurations has one command line under path mapping.

    Otherwise it is compiled once per configuration, which happens when the
    configurations of its references sort the other way round.
    """
    env = unittest.begin(ctx)

    expected = [
        "bazel-out/cfg/bin/app/app.dll",
        "bazel-out/cfg/bin/lib/lib.dll",
        "external/package/lib/package.dll",
    ]
    asserts.equals(env, expected, _stripped_references("k8-fastbuild-ST-aaaaaaaaaaaa", "k8-fastbuild-ST-ffffffffffff"))
    asserts.equals(env, expected, _stripped_references("k8-fastbuild-ST-ffffffffffff", "k8-fastbuild-ST-aaaaaaaaaaaa"))

    return unittest.end(env)

order_independent_of_configurations_test = unittest.make(_order_independent_of_configurations_test_impl)

def ready_to_run_test_suite(name):
    unittest.suite(
        name,
        order_independent_of_configurations_test,
    )
