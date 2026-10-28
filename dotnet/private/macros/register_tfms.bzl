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

        # when activating a certain target framework there should be a transation
        # that enables pricesly all compatible framework versions. This allows us to
        # create config_settings for each tfm that a nuget package provides Where the
        # best match is correctly picked because it has the largest set of compatible frameworks.

        # e.g. a setting with {"net6.0": "True", "net5.0": "True", ...} takes precedence over {"net5.0": "True", ...}
        tfm_flags = {":framework_compatible_%s" % f: repr(True) for f in sets.to_list(TRANSITIVE_FRAMEWORK_COMPATIBILITY[framework])}

        native.config_setting(
            name = "tfm_%s" % framework,
            flag_values = tfm_flags,
            visibility = ["//visibility:public"],
        )
