"Content files test suite."

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "util")
load(
    "//dotnet:defs.bzl",
    "csharp_binary",
    "csharp_library",
    "csharp_test",
    "dotnet_content_files",
    "fsharp_binary",
    "fsharp_library",
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

def _csharp_library(name):
    csharp_library(
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

def _fsharp_library(name):
    fsharp_library(
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

def _csharp_library_transitive_binary(name):
    csharp_library(
        name = name + "_lib",
        srcs = ["Main.cs"],
        out = name + "_lib_dll",
        content_files = _CONTENT_FILES,
        target_frameworks = ["net6.0"],
    )

    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        deps = [name + "_lib"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _content_files_test_impl,
        target = name + "_target_under_test",
    )

def _csharp_library_transitive_publish(name):
    csharp_library(
        name = name + "_lib",
        srcs = ["Main.cs"],
        out = name + "_lib_dll",
        content_files = _CONTENT_FILES,
        target_frameworks = ["net6.0"],
    )

    csharp_binary(
        name = name + "_binary",
        srcs = ["Main.cs"],
        deps = [name + "_lib"],
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

def _fsharp_library_transitive_binary(name):
    fsharp_library(
        name = name + "_lib",
        srcs = ["Main.fs"],
        out = name + "_lib_dll",
        content_files = _CONTENT_FILES,
        target_frameworks = ["net6.0"],
    )

    fsharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.fs"],
        deps = [name + "_lib"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _content_files_test_impl,
        target = name + "_target_under_test",
    )

def _content_files_rule_library_transitive_binary(name):
    dotnet_content_files(
        name = name + "_content",
        srcs = _CONTENT_FILES,
        prefix = "config",
        strip_prefix = "content",
    )

    csharp_library(
        name = name + "_lib",
        srcs = ["Main.cs"],
        out = name + "_lib_dll",
        content_files = [name + "_content"],
        target_frameworks = ["net6.0"],
    )

    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        deps = [name + "_lib"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _content_files_rule_test_impl,
        target = name + "_target_under_test",
    )

def _shared_content_file(name):
    # Two libraries staging the same source file at the same path is not a clash.
    for lib in ["_lib_a", "_lib_b"]:
        csharp_library(
            name = name + lib,
            srcs = ["Main.cs"],
            out = name + lib + "_dll",
            content_files = _CONTENT_FILES,
            target_frameworks = ["net6.0"],
        )

    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        deps = [name + "_lib_a", name + "_lib_b"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _content_files_test_impl,
        target = name + "_target_under_test",
    )

def _conflicting_libraries(name):
    # Two libraries staging different files at the same path must fail rather
    # than silently drop one of them.
    for (lib, directory) in [("_lib_a", "content"), ("_lib_b", "conflict")]:
        dotnet_content_files(
            name = name + lib + "_content",
            srcs = [directory + "/settings.json"],
            strip_prefix = directory,
        )
        util.helper_target(
            csharp_library,
            name = name + lib,
            srcs = ["Main.cs"],
            out = name + lib + "_dll",
            content_files = [name + lib + "_content"],
            target_frameworks = ["net6.0"],
        )

    util.helper_target(
        csharp_binary,
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        deps = [name + "_lib_a", name + "_lib_b"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _dependency_conflict_test_impl,
        target = name + "_target_under_test",
        expect_failure = True,
    )

def _conflicting_own_content_files(name):
    # Two of a target's own content files staged at the same path must fail
    # rather than silently drop one of them.
    for (suffix, directory) in [("_a", "content"), ("_b", "conflict")]:
        dotnet_content_files(
            name = name + suffix + "_content",
            srcs = [directory + "/settings.json"],
            strip_prefix = directory,
        )

    util.helper_target(
        csharp_library,
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        content_files = [name + "_a_content", name + "_b_content"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _own_conflict_test_impl,
        target = name + "_target_under_test",
        expect_failure = True,
    )

def _own_conflict_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*would stage both*/content/settings.json*/conflict/settings.json*\"settings.json\"*"),
    )

def _conflicting_normalized_destinations(name):
    # `config/./settings.json` is `config/settings.json`, so two files staged
    # there must fail rather than overwrite one another.
    for (suffix, directory, prefix) in [("_a", "content", "config/."), ("_b", "conflict", "config")]:
        dotnet_content_files(
            name = name + suffix + "_content",
            srcs = [directory + "/settings.json"],
            prefix = prefix,
            strip_prefix = directory,
        )

    util.helper_target(
        csharp_library,
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        content_files = [name + "_a_content", name + "_b_content"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _normalized_conflict_test_impl,
        target = name + "_target_under_test",
        expect_failure = True,
    )

def _normalized_conflict_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*would stage both*/content/settings.json*/conflict/settings.json*\"config/settings.json\"*"),
    )

def _library_with_default_settings(name):
    """A library that ships `conflict/settings.json` at `content/settings.json`."""
    dotnet_content_files(
        name = name + "_content",
        srcs = ["conflict/settings.json"],
        prefix = "content",
        strip_prefix = "conflict",
    )
    util.helper_target(
        csharp_library,
        name = name,
        srcs = ["Main.cs"],
        out = name + "_dll",
        content_files = [name + "_content"],
        target_frameworks = ["net6.0"],
    )

def _binary_overrides_library(name):
    # A binary's own content file replaces a library's at the same path, as on
    # an MSBuild build (`CopyConflictingTransitiveContent=false`).
    _library_with_default_settings(name + "_lib")

    util.helper_target(
        csharp_binary,
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        content_files = ["content/settings.json"],
        deps = [name + "_lib"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _binary_override_test_impl,
        target = name + "_target_under_test",
    )

def _binary_override_test_impl(env, target):
    tfm = get_target_tfm(target)
    package = target.label.package
    staged = env.expect.that_target(target).action_generating(
        "{}/{}/{}/content/settings.json".format(package, target.label.name, tfm),
    )
    staged.inputs().contains("{}/content/settings.json".format(package))
    staged.inputs().not_contains("{}/conflict/settings.json".format(package))

def _test_overrides_library(name):
    # The common case: a test replaces the default settings a library ships.
    _library_with_default_settings(name + "_lib")

    util.helper_target(
        csharp_test,
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        content_files = ["content/settings.json"],
        deps = [name + "_lib"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _binary_override_test_impl,
        target = name + "_target_under_test",
    )

def _publish_overrides_library(name):
    # A publish ships the binary's own file, not the library's. MSBuild's
    # publish fails here (NETSDK1152) unless `ErrorOnDuplicatePublishOutputFiles`
    # is off; a publish shipping something else than the build is worse.
    _library_with_default_settings(name + "_lib")

    util.helper_target(
        csharp_binary,
        name = name + "_binary",
        srcs = ["Main.cs"],
        content_files = ["content/settings.json"],
        deps = [name + "_lib"],
        target_frameworks = ["net6.0"],
    )

    util.helper_target(
        publish_binary,
        name = name + "_target_under_test",
        binary = name + "_binary",
        roll_forward_behavior = "Major",
        self_contained = False,
        target_framework = "net6.0",
    )

    analysis_test(
        name = name,
        impl = _publish_override_test_impl,
        target = name + "_target_under_test",
    )

def _publish_override_test_impl(env, target):
    rid = get_target_rid(target)
    tfm = "net6.0"
    package = target.label.package
    binary = target.label.name.removesuffix("_target_under_test")
    staged = env.expect.that_target(target).action_generating(
        "{}/{}/publish/{}/content/settings.json".format(package, target.label.name, rid),
    )
    staged.inputs().contains("{}/{}_binary/{}/content/settings.json".format(package, binary, tfm))
    staged.inputs().not_contains("{}/{}_lib/{}/content/settings.json".format(package, binary, tfm))

def _library_does_not_hide_its_dependency(name):
    # A library's own content file does not hide its dependency's from the
    # binary: MSBuild still copies both there, through the transitive project
    # reference, and fails to publish. The binary has to choose.
    _library_with_default_settings(name + "_base")
    util.helper_target(
        csharp_library,
        name = name + "_lib",
        srcs = ["Main.cs"],
        out = name + "_lib_dll",
        content_files = ["content/settings.json"],
        deps = [name + "_base"],
        target_frameworks = ["net6.0"],
    )

    util.helper_target(
        csharp_binary,
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        deps = [name + "_lib"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _dependency_conflict_test_impl,
        target = name + "_target_under_test",
        expect_failure = True,
    )

def _dependency_conflict_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*would be staged at*already taken by*or list the file*own `content_files`*"),
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
            _csharp_library,
            _csharp_test,
            _fsharp_binary,
            _fsharp_library,
            _fsharp_test,
            _csharp_publish,
            _fsharp_publish,
            _csharp_library_transitive_binary,
            _csharp_library_transitive_publish,
            _fsharp_library_transitive_binary,
            _content_files_rule_library_transitive_binary,
            _shared_content_file,
            _conflicting_libraries,
            _conflicting_own_content_files,
            _conflicting_normalized_destinations,
            _binary_overrides_library,
            _test_overrides_library,
            _publish_overrides_library,
            _library_does_not_hide_its_dependency,
            _cross_package,
            _content_files_rule_csharp,
            _content_files_rule_fsharp,
        ],
    )
