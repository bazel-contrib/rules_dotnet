"Register TFM flags and set up the compatibility chains"

load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//rules:common_settings.bzl", "bool_setting", "string_flag")
load(
    "//dotnet/private:common.bzl",
    "DEFAULT_TFM",
    "FRAMEWORK_COMPATIBILITY",
    "TRANSITIVE_FRAMEWORK_COMPATIBILITY",
)

# buildifier: disable=unnamed-macro
def register_tfms():
    "Register TFM flags and set up the compatibility chains"
    string_flag(
        name = "target_framework",
        values = FRAMEWORK_COMPATIBILITY.keys(),
        build_setting_default = DEFAULT_TFM,
        scope = "target",
        visibility = ["//visibility:public"],
    )

    for framework in FRAMEWORK_COMPATIBILITY.keys():
        # The defaults spell out `DEFAULT_TFM`, the framework
        # `target_framework` itself defaults to, so that a configuration no
        # transition has touched still matches a `tfm_*` condition. Anything
        # reaching a NuGet filegroup outside the .NET rules resolves there.
        bool_setting(
            name = "framework_compatible_%s" % framework,
            build_setting_default = sets.contains(TRANSITIVE_FRAMEWORK_COMPATIBILITY[DEFAULT_TFM], framework),
            scope = "target",
            visibility = ["//visibility:public"],
        )

        # A framework's condition requires every framework it is compatible
        # with, so that of two matching conditions where one's set contains the
        # other's, `select` picks the closer: {net6.0, net5.0, ...} takes
        # precedence over {net5.0, ...}. Sets that are not nested, such as
        # netcoreapp2.2's and netstandard2.1's for netcoreapp3.0, or
        # net9.0's and net8.0-windows's for net9.0-windows, make a flat
        # `select` ambiguous: `_tfm_alias` in nuget_archive.bzl selects within
        # one framework family at a time and resolves `-windows` frameworks
        # itself.
        tfm_flags = {":framework_compatible_%s" % f: repr(True) for f in sets.to_list(TRANSITIVE_FRAMEWORK_COMPATIBILITY[framework])}

        native.config_setting(
            name = "tfm_%s" % framework,
            flag_values = tfm_flags,
            visibility = ["//visibility:public"],
        )
