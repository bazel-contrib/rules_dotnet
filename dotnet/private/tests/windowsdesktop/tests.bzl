"Tests for Windows Forms, WPF and Windows GUI executables."

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//dotnet:defs.bzl", "csharp_binary", "csharp_library", "csharp_nunit_test", "fsharp_binary", "publish_binary")
load("//dotnet/private:common.bzl", "runtime_frameworks")
load("//dotnet/private/rules/csharp/actions:xaml.bzl", "package_path", "xaml_plan")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

_WINDOWS_ONLY = ["@platforms//os:windows"]

def _files(argv, prefix, basename):
    """The arguments that start with `prefix` and name a file called `basename`."""
    return [
        arg
        for arg in argv
        if arg.startswith(prefix) and (arg.rstrip("\"").endswith("/" + basename) or arg.rstrip("\"").endswith("\\" + basename))
    ]

def _compile_inputs_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = [action for action in analysistest.target_actions(env) if action.mnemonic == "CSharpCompile"]
    asserts.true(env, len(actions) > 0, "the target compiles C#")

    for action in actions:
        for basename in ctx.attr.references:
            asserts.equals(env, 1, len(_files(action.argv, "-r:", basename)), "references {} once".format(basename))
        for basename in ctx.attr.no_references:
            asserts.equals(env, [], _files(action.argv, "-r:", basename), "does not reference {}".format(basename))
        for (basename, package) in ctx.attr.reference_from.items():
            for arg in _files(action.argv, "-r:", basename):
                asserts.true(env, package in arg.lower(), "takes {} from {}: {}".format(basename, package, arg))
        for basename in ctx.attr.analyzers:
            asserts.equals(env, 1, len(_files(action.argv, "/analyzer:", basename)), "runs {}".format(basename))
        for basename in ctx.attr.no_analyzers:
            asserts.equals(env, [], _files(action.argv, "/analyzer:", basename), "does not run {}".format(basename))

    return analysistest.end(env)

# What a compilation references and which analyzers it runs, by file name.
_compile_inputs_test = analysistest.make(
    _compile_inputs_test_impl,
    attrs = {
        "references": attr.string_list(),
        "no_references": attr.string_list(),
        "reference_from": attr.string_dict(doc = "The package a reference has to come from, by file name."),
        "analyzers": attr.string_list(),
        "no_analyzers": attr.string_list(),
    },
)

def _failure_test_impl(ctx):
    env = analysistest.begin(ctx)

    for fragment in ctx.attr.expected_message_fragments:
        asserts.expect_failure(env, fragment)

    return analysistest.end(env)

_failure_test = analysistest.make(
    _failure_test_impl,
    expect_failure = True,
    attrs = {
        "expected_message_fragments": attr.string_list(mandatory = True),
    },
)

def _unit_test_impl(ctx):
    env = unittest.begin(ctx)

    # The path relative to the package, also in another repository, and the
    # file name outside the package.
    def file(short_path, path = None):
        if path == None:
            path = "external/" + short_path[len("../"):] if short_path.startswith("../") else short_path
        return struct(short_path = short_path, path = path, basename = short_path.split("/")[-1])

    def generated(short_path):
        return file(short_path, "bazel-out/k8-fastbuild/bin/" + short_path)

    # Labels in this repository and in another.
    here = struct(repo_name = "", package = "app", workspace_root = "")
    there = struct(repo_name = "other", package = "app", workspace_root = "external/other")
    asserts.equals(env, "App.xaml", package_path(file("app/App.xaml"), here))
    asserts.equals(env, "Views/Main.xaml", package_path(file("app/Views/Main.xaml"), here))
    asserts.equals(env, "App.xaml", package_path(file("../other/app/App.xaml"), there))
    asserts.equals(env, "Shared.xaml", package_path(file("lib/Themes/Shared.xaml"), here))
    asserts.equals(env, "Shared.xaml", package_path(file("../other/lib/Shared.xaml"), there))

    # App.xaml at the package root is the application definition, in any repository.
    plan = xaml_plan(there, [file("../other/app/App.xaml"), file("../other/app/Page.xaml")], {"Microsoft.WindowsDesktop.App": ["WPF"]}, True)
    asserts.equals(env, "../other/app/App.xaml", plan.application.short_path)
    asserts.equals(env, ["../other/app/Page.xaml"], [page.short_path for page in plan.pages])
    outside = xaml_plan(here, [file("lib/App.xaml")], {"Microsoft.WindowsDesktop.App": None}, True)
    asserts.equals(env, None, outside.application, "only the package's own App.xaml")

    # A generated file does not collide with a source file of the same name
    # below the package root.
    distinct = xaml_plan(here, [file("app/Themes/Theme.xaml"), generated("app/Themes/Theme.xaml")], {"Microsoft.WindowsDesktop.App": None}, True)
    asserts.equals(env, 2, len(distinct.pages))

    # NuGet compares framework reference names case-insensitively.
    asserts.equals(
        env,
        ["Microsoft.AspNetCore.App", "Microsoft.WindowsDesktop.App"],
        runtime_frameworks(
            struct(framework_references = []),
            [struct(framework_references = ["microsoft.aspnetcore.APP"]), struct(framework_references = ["Microsoft.WindowsDesktop.App.wpf"])],
        ),
    )

    return unittest.end(env)

_unit_test = unittest.make(_unit_test_impl)

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def windowsdesktop_tests():
    # Both WPF and Windows Forms.
    csharp_binary(
        name = "app",
        srcs = ["app/Program.cs"],
        framework_references = ["Microsoft.WindowsDesktop.App"],
        target_frameworks = ["net10.0-windows"],
        winexe = True,
    )

    action_args_test(
        name = "app_compile_args_test",
        target_under_test = ":app",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [
            "/target:winexe",
            "/d:NET10_0",
            "/d:WINDOWS",
            "/d:WINDOWS7_0",
            "/d:WINDOWS7_0_OR_GREATER",
        ],
        expected_nonexistent_partial_args = ["/target:exe"],
    )

    _compile_inputs_test(
        name = "app_compile_inputs_test",
        target_under_test = ":app",
        references = [
            "PresentationCore.dll",
            "System.Windows.Forms.dll",
            # Only part of the whole framework, not of either profile.
            "WindowsFormsIntegration.dll",
            # Both shared frameworks ship these; Windows Forms' is newer.
            "System.Drawing.dll",
            "Microsoft.VisualBasic.dll",
        ],
        reference_from = {
            "System.Drawing.dll": "windowsdesktop.app.ref",
            "Microsoft.VisualBasic.dll": "windowsdesktop.app.ref",
        },
        analyzers = ["System.Windows.Forms.Analyzers.CSharp.dll"],
    )

    # WPF only.
    csharp_library(
        name = "wpf",
        srcs = ["wpf/Wpf.cs"],
        framework_references = ["Microsoft.WindowsDesktop.App.WPF"],
        target_frameworks = ["net10.0-windows"],
    )

    _compile_inputs_test(
        name = "wpf_compile_inputs_test",
        target_under_test = ":wpf",
        references = ["PresentationCore.dll", "WindowsBase.dll", "System.Xaml.dll"],
        # Microsoft.NETCore.App ships a facade of it too; WPF's is newer.
        reference_from = {"WindowsBase.dll": "windowsdesktop.app.ref"},
        no_references = ["System.Windows.Forms.dll", "WindowsFormsIntegration.dll"],
        no_analyzers = [
            "System.Windows.Forms.Analyzers.dll",
            "System.Windows.Forms.Analyzers.CSharp.dll",
        ],
    )

    # Windows Forms only.
    csharp_library(
        name = "winforms",
        srcs = ["winforms/WinForms.cs"],
        framework_references = ["Microsoft.WindowsDesktop.App.WindowsForms"],
        target_frameworks = ["net10.0-windows"],
    )

    _compile_inputs_test(
        name = "winforms_compile_inputs_test",
        target_under_test = ":winforms",
        # Without WPF, `WindowsBase.dll` is Microsoft.NETCore.App's facade.
        references = ["System.Windows.Forms.dll", "WindowsBase.dll"],
        reference_from = {"WindowsBase.dll": "netcore.app.ref"},
        no_references = ["PresentationCore.dll", "System.Xaml.dll", "WindowsFormsIntegration.dll"],
        analyzers = ["System.Windows.Forms.Analyzers.CSharp.dll"],
    )

    # An app that references no shared framework itself, but depends on a
    # library that references WPF.
    csharp_binary(
        name = "uses_wpf",
        srcs = ["uses_wpf/Program.cs"],
        target_frameworks = ["net10.0-windows"],
        deps = [":wpf"],
    )

    # WPF is ignored on .NET Standard, so a plain app can use that build of a
    # WPF library.
    csharp_library(
        name = "multi",
        srcs = ["multi/Multi.cs"],
        framework_references = ["Microsoft.WindowsDesktop.App.WPF"],
        target_frameworks = [
            "netstandard2.0",
            "net10.0-windows",
        ],
    )

    csharp_binary(
        name = "uses_multi",
        srcs = ["multi/Program.cs"],
        target_frameworks = ["net10.0"],
        deps = [":multi"],
    )

    native.filegroup(
        name = "uses_multi_runtimeconfig",
        srcs = [":uses_multi"],
        output_group = "runtimeconfig_json",
    )

    native.filegroup(
        name = "uses_wpf_runtimeconfig",
        srcs = [":uses_wpf"],
        output_group = "runtimeconfig_json",
    )

    # A Windows GUI executable that uses neither, and its console sibling.
    csharp_binary(
        name = "gui",
        srcs = ["gui/Program.cs"],
        target_frameworks = ["net10.0"],
        winexe = True,
    )

    csharp_binary(
        name = "console",
        srcs = ["gui/Program.cs"],
        target_frameworks = ["net10.0"],
    )

    fsharp_binary(
        name = "fsharp_gui",
        srcs = ["gui/Program.fs"],
        target_frameworks = ["net10.0"],
        winexe = True,
    )

    action_args_test(
        name = "fsharp_gui_compile_args_test",
        target_under_test = ":fsharp_gui",
        action_mnemonic = "FSharpCompile",
        expected_partial_args = ["--target:winexe"],
        expected_nonexistent_partial_args = ["--target:exe"],
    )

    publish_binary(
        name = "app_publish",
        binary = ":app",
        runtime_identifier = "win-x64",
        target_framework = "net10.0-windows",
    )

    publish_binary(
        name = "app_self_contained",
        binary = ":app",
        runtime_identifier = "win-x64",
        self_contained = True,
        target_framework = "net10.0-windows",
    )

    publish_binary(
        name = "app_single_file",
        binary = ":app",
        runtime_identifier = "win-x64",
        self_contained = True,
        single_file = True,
        target_framework = "net10.0-windows",
    )

    publish_binary(
        name = "console_publish",
        binary = ":console",
        runtime_identifier = "win-x64",
        target_framework = "net10.0",
    )

    csharp_nunit_test(
        name = "publish_test",
        srcs = ["PublishTests.cs"],
        # Has no effect on a test, but is still accepted.
        winexe = True,
        data = [
            ":app_publish",
            ":app_self_contained",
            ":app_single_file",
            ":console_publish",
            ":uses_multi_runtimeconfig",
            ":uses_wpf_runtimeconfig",
        ],
        target_frameworks = ["net10.0"],
        deps = ["//tools/runfiles"],
    )

    # Windows only: runs Windows Forms and WPF.
    csharp_nunit_test(
        name = "run_test",
        srcs = ["RunTests.cs"],
        framework_references = ["Microsoft.WindowsDesktop.App"],
        target_compatible_with = _WINDOWS_ONLY,
        target_frameworks = ["net10.0-windows"],
    )

    # A NativeAOT executable gets the Windows GUI subsystem from the linker.
    # It is only linked for Windows on Windows.
    publish_binary(
        name = "gui_native_aot",
        binary = ":gui",
        native_aot = True,
        self_contained = True,
        tags = ["manual"],
        target_compatible_with = _WINDOWS_ONLY,
        target_framework = "net10.0",
    )

    action_args_test(
        name = "gui_native_aot_link_args_test",
        target_under_test = ":gui_native_aot",
        action_mnemonic = "IlcLink",
        expected_partial_args = ["/SUBSYSTEM:WINDOWS"],
        expected_nonexistent_partial_args = ["/SUBSYSTEM:CONSOLE"],
        target_compatible_with = _WINDOWS_ONLY,
    )

    # What the SDK refuses.
    csharp_library(
        name = "wpf_without_windows_framework",
        srcs = ["wpf/Wpf.cs"],
        framework_references = ["Microsoft.WindowsDesktop.App.WPF"],
        tags = ["manual"],
        target_frameworks = ["net10.0"],
    )

    _failure_test(
        name = "wpf_without_windows_framework_test",
        target_under_test = ":wpf_without_windows_framework",
        expected_message_fragments = ["use net10.0-windows rather than net10.0", "NETSDK1136"],
    )

    csharp_library(
        name = "xaml_on_netstandard",
        srcs = ["wpf/Wpf.cs"],
        tags = ["manual"],
        target_frameworks = ["netstandard2.0"],
        wpf_resources = ["wpf/Wpf.cs"],
    )

    _failure_test(
        name = "xaml_on_netstandard_test",
        target_under_test = ":xaml_on_netstandard",
        expected_message_fragments = ["only compiled for .NET Core 3.0 and later or .NET Framework 3.5 and later"],
    )

    csharp_library(
        name = "xaml_on_net20",
        srcs = ["wpf/Wpf.cs"],
        tags = ["manual"],
        target_frameworks = ["net20"],
        wpf_resources = ["wpf/Wpf.cs"],
    )

    _failure_test(
        name = "xaml_on_net20_test",
        target_under_test = ":xaml_on_net20",
        expected_message_fragments = ["only compiled for .NET Core 3.0 and later or .NET Framework 3.5 and later"],
    )

    publish_binary(
        name = "app_native_aot",
        binary = ":app",
        native_aot = True,
        runtime_identifier = "win-x64",
        self_contained = True,
        tags = ["manual"],
        target_framework = "net10.0-windows",
    )

    _failure_test(
        name = "app_native_aot_test",
        target_under_test = ":app_native_aot",
        expected_message_fragments = ["native_aot cannot publish", "do not support trimming"],
    )

    publish_binary(
        name = "app_for_linux",
        binary = ":app",
        runtime_identifier = "linux-x64",
        tags = ["manual"],
        target_framework = "net10.0-windows",
    )

    _failure_test(
        name = "app_for_linux_test",
        target_under_test = ":app_for_linux",
        expected_message_fragments = ["only exists on Windows", "runtime_identifier"],
    )

    # Strict, whatever the flag says: otherwise the publish takes the frameworks
    # of the binary's dependencies too.
    publish_binary(
        name = "uses_wpf_self_contained",
        binary = ":uses_wpf",
        runtime_identifier = "win-x64",
        self_contained = True,
        strict_framework_references = True,
        tags = ["manual"],
        target_framework = "net10.0-windows",
    )

    _failure_test(
        name = "uses_wpf_self_contained_test",
        target_under_test = ":uses_wpf_self_contained",
        expected_message_fragments = ["Microsoft.WindowsDesktop.App", "framework_references"],
    )

    # ReadyToRun compiles every assembly against the binary's runtime pack too.
    publish_binary(
        name = "uses_wpf_ready_to_run",
        binary = ":uses_wpf",
        ready_to_run = True,
        runtime_identifier = "win-x64",
        strict_framework_references = True,
        tags = ["manual"],
        target_framework = "net10.0-windows",
    )

    _failure_test(
        name = "uses_wpf_ready_to_run_test",
        target_under_test = ":uses_wpf_ready_to_run",
        expected_message_fragments = ["a ReadyToRun publish", "Microsoft.WindowsDesktop.App", "framework_references"],
    )

    # Generated XAML files are compiled by file name, so two with the same name collide.
    for theme in ["Light", "Dark"]:
        native.genrule(
            name = "colliding_{}_theme".format(theme.lower()),
            outs = ["colliding/{}/Theme.xaml".format(theme)],
            cmd = "echo '<ResourceDictionary xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" />' > $@",
            tags = ["manual"],
        )

    csharp_library(
        name = "colliding_xaml",
        srcs = [
            ":colliding_dark_theme",
            ":colliding_light_theme",
        ],
        framework_references = ["Microsoft.WindowsDesktop.App.WPF"],
        tags = ["manual"],
        target_frameworks = ["net10.0-windows"],
    )

    _failure_test(
        name = "colliding_xaml_test",
        target_under_test = ":colliding_xaml",
        expected_message_fragments = ["would both compile to theme.baml", "rename one of them"],
    )

    # WPF resources are embedded by their path in the package, which WPF
    # compares case-insensitively.
    for (case, name) in [("upper", "Icon.txt"), ("lower", "icon.txt")]:
        native.genrule(
            name = "colliding_{}_resource".format(case),
            outs = ["colliding_resources/" + name],
            cmd = "echo > $@",
            tags = ["manual"],
        )

    csharp_library(
        name = "colliding_wpf_resources",
        srcs = ["wpf/Wpf.cs"],
        framework_references = ["Microsoft.WindowsDesktop.App.WPF"],
        tags = ["manual"],
        target_frameworks = ["net10.0-windows"],
        wpf_resources = [
            ":colliding_lower_resource",
            ":colliding_upper_resource",
        ],
    )

    _failure_test(
        name = "colliding_wpf_resources_test",
        target_under_test = ":colliding_wpf_resources",
        expected_message_fragments = ["would both be embedded as colliding_resources/icon.txt", "rename one of them"],
    )

    _unit_test(name = "windowsdesktop_unit_test")
