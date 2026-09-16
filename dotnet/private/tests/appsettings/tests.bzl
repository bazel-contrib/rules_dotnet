"Appsettings test suite."

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load(
    "//dotnet:defs.bzl",
    "csharp_binary",
    "fsharp_binary",
    "publish_binary",
)
load("//dotnet/private/tests:utils.bzl", "get_target_rid", "get_target_tfm")

def _csharp_binary(name):
    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        appsetting_files = [
            "appsettings.json",
            "appsettings.Development.json",
        ],
        target_frameworks = ["net8.0"],
    )

    analysis_test(
        name = name,
        impl = _binary_test_impl,
        target = name + "_target_under_test",
    )

def _csharp_publish(name):
    csharp_binary(
        name = name + "_binary",
        srcs = ["Main.cs"],
        appsetting_files = [
            "appsettings.json",
            "appsettings.Development.json",
        ],
        target_frameworks = ["net8.0"],
    )

    publish_binary(
        name = name + "_target_under_test",
        binary = name + "_binary",
        roll_forward_behavior = "Major",
        self_contained = False,
        target_framework = "net8.0",
    )

    analysis_test(
        name = name,
        impl = _publish_test_impl,
        target = name + "_target_under_test",
    )

def _csharp_publish_self_contained(name):
    csharp_binary(
        name = name + "_binary",
        srcs = ["Main.cs"],
        appsetting_files = [
            "appsettings.json",
            "appsettings.Development.json",
        ],
        target_frameworks = ["net8.0"],
    )

    publish_binary(
        name = name + "_target_under_test",
        binary = name + "_binary",
        roll_forward_behavior = "Major",
        self_contained = True,
        target_framework = "net8.0",
    )

    analysis_test(
        name = name,
        impl = _publish_test_impl,
        target = name + "_target_under_test",
    )

def _fsharp_binary(name):
    fsharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.fs"],
        appsetting_files = [
            "appsettings.json",
            "appsettings.Development.json",
        ],
        target_frameworks = ["net8.0"],
    )

    analysis_test(
        name = name,
        impl = _binary_test_impl,
        target = name + "_target_under_test",
    )

def _fsharp_publish(name):
    fsharp_binary(
        name = name + "_binary",
        srcs = ["Main.fs"],
        appsetting_files = [
            "appsettings.json",
            "appsettings.Development.json",
        ],
        target_frameworks = ["net8.0"],
    )

    publish_binary(
        name = name + "_target_under_test",
        binary = name + "_binary",
        roll_forward_behavior = "Major",
        self_contained = False,
        target_framework = "net8.0",
    )

    analysis_test(
        name = name,
        impl = _publish_test_impl,
        target = name + "_target_under_test",
    )

def _fsharp_publish_self_contained(name):
    fsharp_binary(
        name = name + "_binary",
        srcs = ["Main.fs"],
        appsetting_files = [
            "appsettings.json",
            "appsettings.Development.json",
        ],
        target_frameworks = ["net8.0"],
    )

    publish_binary(
        name = name + "_target_under_test",
        binary = name + "_binary",
        roll_forward_behavior = "Major",
        self_contained = True,
        target_framework = "net8.0",
    )

    analysis_test(
        name = name,
        impl = _publish_test_impl,
        target = name + "_target_under_test",
    )

def _binary_test_impl(env, target):
    tfm = get_target_tfm(target)
    env.expect.that_target(target).default_outputs().contains(
        "{}/{}/{}/appsettings.json".format(target.label.package, target.label.name, tfm),
    )

    env.expect.that_target(target).default_outputs().contains(
        "{}/{}/{}/appsettings.Development.json".format(target.label.package, target.label.name, tfm),
    )

def _publish_test_impl(env, target):
    rid = get_target_rid(target)
    env.expect.that_target(target).default_outputs().contains(
        "{}/{}/publish/{}/appsettings.json".format(target.label.package, target.label.name, rid),
    )

    env.expect.that_target(target).default_outputs().contains(
        "{}/{}/publish/{}/appsettings.Development.json".format(target.label.package, target.label.name, rid),
    )

def appsettings_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _csharp_binary,
            _csharp_publish,
            _csharp_publish_self_contained,
            _fsharp_binary,
            _fsharp_publish,
            _fsharp_publish_self_contained,
        ],
    )
