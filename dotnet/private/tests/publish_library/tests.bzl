"""Analysis tests for `publish_library`."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//dotnet:defs.bzl", "csharp_library", "publish_library")

LAYERS = ["third_party", "first_party", "app"]

def _actions(target, mnemonics):
    return [action for action in target[TestingAspectInfo].actions if action.mnemonic in mnemonics]

def _copied(target, action):
    script_prefix = "{}/{}.".format(target.label.package, target.label.name)
    return [file for file in action.inputs.to_list() if not file.short_path.startswith(script_prefix)]

def _layers(target):
    root = "{}/{}/layers/".format(target.label.package, target.label.name)
    return {
        output.short_path.removeprefix(root): _copied(target, action)
        for action in _actions(target, ["DotnetPublishLayer"])
        for output in action.outputs.to_list()
    }

def _publish_relative_paths(target, subdir):
    prefix = "{}/{}/publish/{}/".format(target.label.package, target.label.name, subdir)
    return [
        file.short_path.removeprefix(prefix)
        for file in target[DefaultInfo].files.to_list()
    ]

def _portable_library_test(name):
    publish_library(
        name = name + "_publish",
        library = ":portable_lib",
        tags = ["manual"],
        target_framework = "net9.0",
    )

    analysis_test(
        name = name,
        impl = _portable_library_test_impl,
        target = name + "_publish",
    )

def _portable_library_test_impl(env, target):
    paths = _publish_relative_paths(target, "net9.0")

    # Root assemblies, appsettings, and deps.json.
    env.expect.that_collection(paths).contains_at_least([
        "portable_lib.dll",
        "portable_lib.deps.json",
        "private_dep.dll",
        "FSharp.Core.dll",
        "RocksDbSharp.dll",
        "de/FSharp.Core.resources.dll",
        "fr/FSharp.Core.resources.dll",
        "runtimes/linux-arm64/native/librocksdb.so",
        "runtimes/linux-x64/native/librocksdb.so",
        "runtimes/osx-arm64/native/librocksdb.dylib",
        "runtimes/osx-x64/native/librocksdb.dylib",
        "runtimes/win-x64/native/rocksdb.dll",
    ])

    # Output groups: `publish_dir` and the three layer directories.
    env.expect.that_target(target).output_group("publish_dir").contains_exactly([
        "{}/{}/publish_dir/net9.0".format(target.label.package, target.label.name),
    ])

    layers = _layers(target)
    env.expect.that_collection(layers.keys()).contains_exactly(LAYERS)
    env.expect.that_collection([f.basename for f in layers["app"]]).contains_exactly([
        "portable_lib.dll",
        "portable_lib.deps.json",
    ])
    env.expect.that_collection([f.basename for f in layers["first_party"]]).contains_exactly([
        "private_dep.dll",
    ])
    env.expect.that_collection([f.basename for f in layers["third_party"]]).contains_at_least([
        "FSharp.Core.dll",
        "RocksDbSharp.dll",
        "rocksdb.dll",
    ])

    # Layer actions copy from the original sources, not from DotnetPublishCopy outputs.
    copy_outputs = {
        file.path: None
        for action in _actions(target, ["DotnetPublishCopy"])
        for file in action.outputs.to_list()
    }
    for (layer, files) in layers.items():
        for file in files:
            if file.path in copy_outputs:
                env.fail("The {} layer copies {} out of the publish directory".format(layer, file.short_path))

def _rid_specific_library_test(name):
    publish_library(
        name = name + "_publish",
        library = ":native_lib",
        runtime_identifier = "win-x64",
        tags = ["manual"],
        target_framework = "net9.0",
    )

    analysis_test(
        name = name,
        impl = _rid_specific_library_test_impl,
        target = name + "_publish",
    )

def _rid_specific_library_test_impl(env, target):
    paths = _publish_relative_paths(target, "win-x64")

    env.expect.that_collection(paths).contains_at_least([
        "native_lib.dll",
        "native_lib.deps.json",
        "native_stub.dll",
        "RocksDbSharp.dll",
        "runtimes/win-x64/native/rocksdb.dll",
    ])
    env.expect.that_collection(paths).contains_none_of([
        "runtimes/win-x64/native/native_stub.dll",
        "runtimes/linux-x64/native/librocksdb.so",
        "runtimes/osx-arm64/native/librocksdb.dylib",
    ])

def _portable_rejects_workspace_native_test(name):
    publish_library(
        name = name + "_publish",
        library = ":native_lib",
        tags = ["manual"],
        target_framework = "net9.0",
    )

    analysis_test(
        name = name,
        impl = _portable_rejects_workspace_native_test_impl,
        target = name + "_publish",
        expect_failure = True,
    )

def _portable_rejects_workspace_native_test_impl(env, target):
    failures = env.expect.that_target(target).failures()
    failures.contains_predicate(matching.contains("depends on workspace_native, whose native libraries"))
    failures.contains_predicate(matching.contains("Set `runtime_identifier`"))

def _exclude_deps_test(name):
    publish_library(
        name = name + "_publish",
        exclude_deps = [":plugin_contract"],
        library = ":sample_plugin",
        tags = ["manual"],
        target_framework = "net9.0",
    )

    analysis_test(
        name = name,
        impl = _exclude_deps_test_impl,
        target = name + "_publish",
    )

def _exclude_deps_test_impl(env, target):
    paths = _publish_relative_paths(target, "net9.0")

    # Keeps the plugin, its private dependency, and its deps.json, while
    # excluding plugin_contract and its transitive dependency contract_base.
    env.expect.that_collection(paths).contains_exactly([
        "sample_plugin.dll",
        "sample_plugin.deps.json",
        "private_dep.dll",
    ])

def _exclude_self_fails_test(name):
    publish_library(
        name = name + "_publish",
        exclude_deps = [":sample_plugin"],
        library = ":sample_plugin",
        tags = ["manual"],
        target_framework = "net9.0",
    )

    analysis_test(
        name = name,
        impl = _exclude_self_fails_test_impl,
        target = name + "_publish",
        expect_failure = True,
    )

def _exclude_self_fails_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("`exclude_deps` excludes"),
    )

def _imported_library_fails_test(name):
    publish_library(
        name = name + "_publish",
        library = "@paket.rules_dotnet_dev_nuget_packages//fsharp.core",
        tags = ["manual"],
        target_framework = "net9.0",
    )

    analysis_test(
        name = name,
        impl = _imported_library_fails_test_impl,
        target = name + "_publish",
        expect_failure = True,
    )

def _imported_library_fails_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("is an imported assembly. `publish_library` publishes a csharp_library or fsharp_library."),
    )

def _netframework_no_deps_json_test(name):
    publish_library(
        name = name + "_publish",
        library = ":netfx_lib",
        tags = ["manual"],
        target_framework = "net48",
    )

    analysis_test(
        name = name,
        impl = _netframework_no_deps_json_test_impl,
        target = name + "_publish",
    )

def _netframework_no_deps_json_test_impl(env, target):
    paths = _publish_relative_paths(target, "net48")

    # .NET Framework resolves a Windows RID even when `runtime_identifier` is
    # omitted, staging RID-specific managed libraries flat at the root without
    # emitting `runtimes/<rid>/` directories or a `.deps.json` file.
    env.expect.that_collection(paths).contains_at_least([
        "netfx_lib.dll",
        "WinHelper.dll",
        "RocksDbSharp.dll",
    ])
    env.expect.that_collection(paths).contains_none_of([
        "netfx_lib.deps.json",
    ])
    for path in paths:
        if path.startswith("runtimes/"):
            env.fail(".NET Framework publish placed {} under runtimes/, which AppDomain will not probe".format(path))

def _netframework_rid_flattens_natives_test(name):
    publish_library(
        name = name + "_publish",
        library = ":netfx_lib",
        runtime_identifier = "win-x64",
        tags = ["manual"],
        target_framework = "net48",
    )

    analysis_test(
        name = name,
        impl = _netframework_rid_flattens_natives_test_impl,
        target = name + "_publish",
    )

def _netframework_rid_flattens_natives_test_impl(env, target):
    paths = _publish_relative_paths(target, "win-x64")

    # Both managed and NuGet native dependencies are staged flat at the publish
    # root on .NET Framework.
    env.expect.that_collection(paths).contains_at_least([
        "netfx_lib.dll",
        "WinHelper.dll",
        "RocksDbSharp.dll",
        "rocksdb.dll",
    ])
    env.expect.that_collection(paths).contains_none_of([
        "netfx_lib.deps.json",
        "runtimes/win-x64/native/rocksdb.dll",
    ])

def _netframework_rejects_non_windows_rid_test(name):
    publish_library(
        name = name + "_publish",
        library = ":netfx_lib",
        runtime_identifier = "linux-x64",
        tags = ["manual"],
        target_framework = "net48",
    )

    analysis_test(
        name = name,
        impl = _netframework_rejects_non_windows_rid_test_impl,
        target = name + "_publish",
        expect_failure = True,
    )

def _netframework_rejects_non_windows_rid_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("targets .NET Framework, which only runs on Windows"),
    )

def _windows_desktop_rejects_non_windows_rid_test(name):
    csharp_library(
        name = name + "_lib",
        srcs = ["PrivateDep.cs"],
        framework_references = ["Microsoft.WindowsDesktop.App.WPF"],
        tags = ["manual"],
        target_frameworks = ["net10.0-windows"],
    )

    publish_library(
        name = name + "_publish",
        library = ":" + name + "_lib",
        runtime_identifier = "linux-x64",
        tags = ["manual"],
        target_framework = "net10.0-windows",
    )

    analysis_test(
        name = name,
        impl = _windows_desktop_rejects_non_windows_rid_test_impl,
        target = name + "_publish",
        expect_failure = True,
    )

def _windows_desktop_rejects_non_windows_rid_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("runs on Microsoft.WindowsDesktop.App, which only exists on Windows"),
    )

def _include_deps_json_false_test(name):
    publish_library(
        name = name + "_publish",
        include_deps_json = False,
        library = ":sample_plugin",
        tags = ["manual"],
        target_framework = "net9.0",
    )

    analysis_test(
        name = name,
        impl = _include_deps_json_false_test_impl,
        target = name + "_publish",
    )

def _include_deps_json_false_test_impl(env, target):
    paths = _publish_relative_paths(target, "net9.0")
    env.expect.that_collection(paths).contains_none_of(["sample_plugin.deps.json"])
    env.expect.that_collection(paths).contains_at_least([
        "sample_plugin.dll",
        "private_dep.dll",
        "plugin_contract.dll",
        "contract_base.dll",
    ])

def _wrong_target_framework_fails_test(name):
    csharp_library(
        name = name + "_netstandard_lib",
        srcs = ["PrivateDep.cs"],
        tags = ["manual"],
        target_frameworks = ["netstandard2.0"],
    )

    publish_library(
        name = name + "_publish",
        library = ":" + name + "_netstandard_lib",
        tags = ["manual"],
        target_framework = "net9.0",
    )

    analysis_test(
        name = name,
        impl = _wrong_target_framework_fails_test_impl,
        target = name + "_publish",
        expect_failure = True,
    )

def _wrong_target_framework_fails_test_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.contains("for net9.0, but that target builds netstandard2.0"),
    )

def publish_library_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _portable_library_test,
            _rid_specific_library_test,
            _portable_rejects_workspace_native_test,
            _exclude_deps_test,
            _exclude_self_fails_test,
            _imported_library_fails_test,
            _wrong_target_framework_fails_test,
            _netframework_no_deps_json_test,
            _netframework_rid_flattens_natives_test,
            _netframework_rejects_non_windows_rid_test,
            _windows_desktop_rejects_non_windows_rid_test,
            _include_deps_json_false_test,
        ],
    )
