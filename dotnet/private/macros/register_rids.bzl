"Register RID flags and set up the compatibility chains"

load("@bazel_skylib//rules:common_settings.bzl", "bool_setting", "string_flag")
load("//dotnet/private:common.bzl", "DEFAULT_RID")
load("//dotnet/private:portable_rids.bzl", "PORTABLE_RUNTIME_GRAPH")
load("//dotnet/private/sdk:rids.bzl", "RUNTIME_GRAPH")

# buildifier: disable=unnamed-macro
def register_rids():
    "Register RID flags and the config settings that resolve RID bound assets"
    string_flag(
        name = "rid",
        values = RUNTIME_GRAPH.keys(),
        build_setting_default = DEFAULT_RID,
        scope = "target",
        visibility = ["//visibility:public"],
    )

    default_compatible_rids = PORTABLE_RUNTIME_GRAPH[DEFAULT_RID] + [DEFAULT_RID]

    for rid in PORTABLE_RUNTIME_GRAPH.keys():
        # As with the framework settings, the defaults spell out `DEFAULT_RID`
        # so that an untouched configuration matches a `rid_*` condition.
        bool_setting(
            name = "rid_compatible_%s" % rid,
            build_setting_default = rid in default_compatible_rids,
            scope = "target",
            visibility = ["//visibility:public"],
        )

        flags = {":rid_compatible_%s" % f: repr(True) for f in PORTABLE_RUNTIME_GRAPH[rid] + [rid]}

        native.config_setting(
            name = "rid_%s" % rid,
            flag_values = flags,
            visibility = ["//visibility:public"],
        )
