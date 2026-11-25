"Content files test suite."

load("@bazel_skylib//rules:write_file.bzl", "write_file")
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
        impl = _conflict_test_impl,
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

def _binary_overrides_library(name):
    # By default (matching MSBuild CopyConflictingTransitiveContent=false), a
    # consuming binary's own content file supersedes a dependency's at the same
    # destination path.
    dotnet_content_files(
        name = name + "_lib_content",
        srcs = ["conflict/settings.json"],
        prefix = "content",
        strip_prefix = "conflict",
    )
    csharp_library(
        name = name + "_lib",
        srcs = ["Main.cs"],
        out = name + "_lib_dll",
        content_files = [
            name + "_lib_content",
            "content/nested/data.txt",
        ],
        target_frameworks = ["net6.0"],
    )

    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        content_files = ["content/settings.json"],
        deps = [name + "_lib"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _content_files_test_impl,
        target = name + "_target_under_test",
    )

def _publish_overrides_library(name):
    dotnet_content_files(
        name = name + "_lib_content",
        srcs = ["conflict/settings.json"],
        prefix = "content",
        strip_prefix = "conflict",
    )
    csharp_library(
        name = name + "_lib",
        srcs = ["Main.cs"],
        out = name + "_lib_dll",
        content_files = [
            name + "_lib_content",
            "content/nested/data.txt",
        ],
        target_frameworks = ["net6.0"],
    )

    csharp_binary(
        name = name + "_binary",
        srcs = ["Main.cs"],
        content_files = ["content/settings.json"],
        deps = [name + "_lib"],
        target_frameworks = ["net6.0"],
    )

    publish_binary(
        name = name + "_target_under_test",
        binary = name + "_binary",
        runtime_identifier = "linux-x64",
        self_contained = False,
        target_framework = "net6.0",
    )

    analysis_test(
        name = name,
        impl = _publish_test_impl,
        target = name + "_target_under_test",
    )

def _conflicting_with_binary_no_overwrite(name):
    # Setting `overwrite = False` restores a build failure when a binary's
    # content file shares its destination with an inherited dependency's.
    dotnet_content_files(
        name = name + "_lib_content",
        srcs = ["conflict/settings.json"],
        prefix = "content",
        strip_prefix = "conflict",
    )
    util.helper_target(
        csharp_library,
        name = name + "_lib",
        srcs = ["Main.cs"],
        out = name + "_lib_dll",
        content_files = [name + "_lib_content"],
        target_frameworks = ["net6.0"],
    )

    dotnet_content_files(
        name = name + "_app_content",
        srcs = ["content/settings.json"],
        overwrite = False,
    )
    util.helper_target(
        csharp_binary,
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        content_files = [name + "_app_content"],
        deps = [name + "_lib"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _conflict_test_impl,
        target = name + "_target_under_test",
        expect_failure = True,
    )

def _library_overrides_transitive_library(name):
    # An intermediate library's content file supersedes its own dependency's
    # content file at the same destination for downstream binaries.
    dotnet_content_files(
        name = name + "_base_content",
        srcs = ["conflict/settings.json"],
        prefix = "content",
        strip_prefix = "conflict",
    )
    csharp_library(
        name = name + "_base_lib",
        srcs = ["Main.cs"],
        out = name + "_base_lib_dll",
        content_files = [
            name + "_base_content",
            "content/nested/data.txt",
        ],
        target_frameworks = ["net6.0"],
    )

    csharp_library(
        name = name + "_mid_lib",
        srcs = ["Main.cs"],
        out = name + "_mid_lib_dll",
        content_files = ["content/settings.json"],
        deps = [name + "_base_lib"],
        target_frameworks = ["net6.0"],
    )

    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        deps = [name + "_mid_lib"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _library_overrides_transitive_library_test_impl,
        target = name + "_target_under_test",
    )

def _library_overrides_transitive_library_test_impl(env, target):
    _content_files_test_impl(env, target)
    tfm = get_target_tfm(target)
    expected_out = "{}/{}/{}/content/settings.json".format(target.label.package, target.label.name, tfm)
    stage_actions = [
        a
        for a in target.actions
        if any([o.short_path == expected_out for o in a.outputs.to_list()])
    ]
    env.expect.that_collection(stage_actions).has_size(1)
    input_paths = [i.short_path for i in stage_actions[0].inputs.to_list()]
    env.expect.that_collection([p for p in input_paths if "_mid_lib/" in p]).has_size(1)
    env.expect.that_collection([p for p in input_paths if "_base_lib/" in p]).has_size(0)

def _diamond_partial_override_conflicts(name):
    # In a diamond (E -> [mid, side] -> base) where `mid` overrides `base`'s
    # content file at `dest` but `side` does not, `base`'s content file still
    # reaches `E` through `side` and collides with `mid`'s override unless `E`
    # overrides `dest` itself.
    dotnet_content_files(
        name = name + "_base_content",
        srcs = ["conflict/settings.json"],
        prefix = "content",
        strip_prefix = "conflict",
    )
    csharp_library(
        name = name + "_base_lib",
        srcs = ["Main.cs"],
        out = name + "_base_lib_dll",
        content_files = [
            name + "_base_content",
            "content/nested/data.txt",
        ],
        target_frameworks = ["net6.0"],
    )

    csharp_library(
        name = name + "_mid_lib",
        srcs = ["Main.cs"],
        out = name + "_mid_lib_dll",
        content_files = ["content/settings.json"],
        deps = [name + "_base_lib"],
        target_frameworks = ["net6.0"],
    )

    csharp_library(
        name = name + "_side_lib",
        srcs = ["Main.cs"],
        out = name + "_side_lib_dll",
        deps = [name + "_base_lib"],
        target_frameworks = ["net6.0"],
    )

    util.helper_target(
        csharp_binary,
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        deps = [name + "_mid_lib", name + "_side_lib"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _conflict_test_impl,
        target = name + "_target_under_test",
        expect_failure = True,
    )

def _diamond_consumer_override_succeeds(name):
    # When the consumer `E` itself overrides `dest`, it supersedes both `mid`
    # and the un-overridden `side -> base` branch in a diamond.
    dotnet_content_files(
        name = name + "_base_content",
        srcs = ["conflict/settings.json"],
        prefix = "content",
        strip_prefix = "conflict",
    )
    csharp_library(
        name = name + "_base_lib",
        srcs = ["Main.cs"],
        out = name + "_base_lib_dll",
        content_files = [
            name + "_base_content",
            "content/nested/data.txt",
        ],
        target_frameworks = ["net6.0"],
    )

    write_file(
        name = name + "_mid_gen",
        out = name + "_mid/settings.json",
        content = ["mid"],
    )
    dotnet_content_files(
        name = name + "_mid_content",
        srcs = [name + "_mid/settings.json"],
        prefix = "content",
        strip_prefix = name + "_mid",
    )
    csharp_library(
        name = name + "_mid_lib",
        srcs = ["Main.cs"],
        out = name + "_mid_lib_dll",
        content_files = [name + "_mid_content"],
        deps = [name + "_base_lib"],
        target_frameworks = ["net6.0"],
    )

    csharp_library(
        name = name + "_side_lib",
        srcs = ["Main.cs"],
        out = name + "_side_lib_dll",
        deps = [name + "_base_lib"],
        target_frameworks = ["net6.0"],
    )

    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        content_files = ["content/settings.json"],
        deps = [name + "_mid_lib", name + "_side_lib"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _content_files_test_impl,
        target = name + "_target_under_test",
    )

def _non_transitive_library_content(name):
    # `transitive = False` stages the file for the declaring library itself,
    # without propagating it to dependents or colliding across peer libraries.
    for (suffix, directory) in [("_a", "content"), ("_b", "conflict")]:
        dotnet_content_files(
            name = name + suffix + "_private",
            srcs = [directory + "/settings.json"],
            prefix = "private",
            strip_prefix = directory,
            transitive = False,
        )
        csharp_library(
            name = name + suffix + "_lib",
            srcs = ["Main.cs"],
            out = name + suffix + "_lib_dll",
            content_files = [name + suffix + "_private"] + (_CONTENT_FILES if suffix == "_a" else []),
            target_frameworks = ["net6.0"],
        )

    csharp_binary(
        name = name + "_target_under_test",
        srcs = ["Main.cs"],
        deps = [name + "_a_lib", name + "_b_lib"],
        target_frameworks = ["net6.0"],
    )

    analysis_test(
        name = name,
        impl = _non_transitive_test_impl,
        target = name + "_target_under_test",
    )

def _non_transitive_test_impl(env, target):
    tfm = get_target_tfm(target)
    prefix = "{}/{}/{}".format(target.label.package, target.label.name, tfm)

    env.expect.that_target(target).default_outputs().contains(
        "{}/content/settings.json".format(prefix),
    )
    env.expect.that_target(target).default_outputs().not_contains(
        "{}/private/settings.json".format(prefix),
    )

def _conflict_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*would be staged at*already taken by*"),
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
            _publish_overrides_library,
            _conflicting_with_binary_no_overwrite,
            _library_overrides_transitive_library,
            _diamond_partial_override_conflicts,
            _diamond_consumer_override_succeeds,
            _non_transitive_library_content,
            _cross_package,
            _content_files_rule_csharp,
            _content_files_rule_fsharp,
        ],
    )
