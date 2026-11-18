"Content files test suite."

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load(
    "//dotnet:defs.bzl",
    "csharp_binary",
    "csharp_test",
    "dotnet_content_files",
    "fsharp_binary",
    "fsharp_test",
    "publish_binary",
)
load("//dotnet/private/tests:utils.bzl", "get_target_rid", "get_target_tfm")

_CONTENT_FILES = [
    "content/settings.json",
    "content/nested/data.txt",
]

def _csharp_binary(name):
    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        content_files = _CONTENT_FILES,
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _content_files_test_impl,
        target = name + "_target_under_test",
    )

def _csharp_test(name):
    csharp_test(
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        content_files = _CONTENT_FILES,
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _content_files_test_impl,
        target = name + "_target_under_test",
    )

def _fsharp_binary(name):
    fsharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.fs"],
        content_files = _CONTENT_FILES,
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _content_files_test_impl,
        target = name + "_target_under_test",
    )

def _fsharp_test(name):
    fsharp_test(
        name = name + "_target_under_test",
        srcs = ["Main.fs"],
        content_files = _CONTENT_FILES,
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _content_files_test_impl,
        target = name + "_target_under_test",
    )

def _csharp_publish(name):
    csharp_binary(
        name = name + "_binary",
        srcs = ["Main.cs"],
        content_files = _CONTENT_FILES,
        target_frameworks = ["net6.0"],
    )

    publish_binary(
        name = name + "_target_under_test",
        binary = name + "_binary",
        roll_forward_behavior = "Major",
        self_contained = False,
        target_framework = "net6.0",
    )

    analysis_test(
        name = name,
        impl = _publish_test_impl,
        target = name + "_target_under_test",
    )

def _fsharp_publish(name):
    fsharp_binary(
        name = name + "_binary",
        srcs = ["Main.fs"],
        content_files = _CONTENT_FILES,
        target_frameworks = ["net6.0"],
    )

    publish_binary(
        name = name + "_target_under_test",
        binary = name + "_binary",
        roll_forward_behavior = "Major",
        self_contained = False,
        target_framework = "net6.0",
    )

    analysis_test(
        name = name,
        impl = _publish_test_impl,
        target = name + "_target_under_test",
    )

def _content_files_rule_csharp(name):
    dotnet_content_files(
        name = name + "_content",
        srcs = _CONTENT_FILES,
        strip_prefix = "content",
        prefix = "config",
    )

    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        content_files = [name + "_content"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _content_files_rule_test_impl,
        target = name + "_target_under_test",
    )

def _content_files_rule_fsharp(name):
    dotnet_content_files(
        name = name + "_content",
        srcs = _CONTENT_FILES,
        strip_prefix = "content",
        prefix = "config",
    )

    fsharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.fs"],
        content_files = [name + "_content"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _content_files_rule_test_impl,
        target = name + "_target_under_test",
    )

def _cross_package(name):
    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        content_files = ["//dotnet/private/tests/content_files/otherpkg:assets/ext.json"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _cross_package_test_impl,
        target = name + "_target_under_test",
    )

def _content_files_test_impl(env, target):
    tfm = get_target_tfm(target)
    prefix = "{}/{}/{}".format(target.label.package, target.label.name, tfm)

    env.expect.that_target(target).default_outputs().contains(
        "{}/content/settings.json".format(prefix),
    )
    env.expect.that_target(target).default_outputs().contains(
        "{}/content/nested/data.txt".format(prefix),
    )

def _publish_test_impl(env, target):
    rid = get_target_rid(target)
    prefix = "{}/{}/publish/{}".format(target.label.package, target.label.name, rid)

    env.expect.that_target(target).default_outputs().contains(
        "{}/content/settings.json".format(prefix),
    )
    env.expect.that_target(target).default_outputs().contains(
        "{}/content/nested/data.txt".format(prefix),
    )

def _cross_package_test_impl(env, target):
    tfm = get_target_tfm(target)
    prefix = "{}/{}/{}".format(target.label.package, target.label.name, tfm)

    # Anchored to the consuming binary's package, so the subpackage's path is preserved.
    env.expect.that_target(target).default_outputs().contains(
        "{}/otherpkg/assets/ext.json".format(prefix),
    )

def _content_files_rule_test_impl(env, target):
    tfm = get_target_tfm(target)
    prefix = "{}/{}/{}".format(target.label.package, target.label.name, tfm)

    env.expect.that_target(target).default_outputs().contains(
        "{}/config/settings.json".format(prefix),
    )
    env.expect.that_target(target).default_outputs().contains(
        "{}/config/nested/data.txt".format(prefix),
    )

def content_files_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _csharp_binary,
            _csharp_test,
            _fsharp_binary,
            _fsharp_test,
            _csharp_publish,
            _fsharp_publish,
            _cross_package,
            _content_files_rule_csharp,
            _content_files_rule_fsharp,
        ],
    )
