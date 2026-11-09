"The SDK packs that ship a native tool"

load("//dotnet/private:common.bzl", "copy_files_to_dir")
load("//dotnet/private:providers.bzl", "DotnetToolPackInfo")
load("//dotnet/private/sdk:packs.bzl", "NEWEST_BAND")

def tool_pack_rule(tool_name):
    """Returns a rule that extracts one native tool from its nuget package.

    Args:
      tool_name: The tool's basename, without the Windows `.exe` suffix.

    Returns:
      A rule producing `DotnetToolPackInfo`.
    """
    basenames = [tool_name, tool_name + ".exe"]

    def _impl(ctx):
        is_windows = ctx.target_platform_has_constraint(
            ctx.attr._windows_constraint[platform_common.ConstraintValueInfo],
        )

        # The tool loads its JIT libraries from its own directory, so the whole
        # tools directory moves together.
        files = copy_files_to_dir(
            ctx.label.name,
            ctx.actions,
            is_windows,
            [f for f in ctx.attr.pack_files.files.to_list() if "/tools/" in f.path],
            ctx.label.name,
            executables = basenames,
        )
        tools = [f for f in files if f.basename in basenames]

        if not tools:
            fail("{} executable not found in its pack".format(tool_name))

        return [DotnetToolPackInfo(tool = tools[0], files = depset(files))]

    return rule(
        _impl,
        doc = "The .Net SDK pack that ships `{}`".format(tool_name),
        attrs = {
            "pack_files": attr.label(
                doc = "Every file in the {} nuget package".format(tool_name),
            ),
            "_windows_constraint": attr.label(default = "@platforms//os:windows"),
        },
    )

_HOST_TOOL_BAND = "//dotnet/private/sdk:host_tool_band"

def _host_tool_band_impl(settings, attr):
    bands = attr.bands

    return {_HOST_TOOL_BAND: bands.get(settings["//dotnet:target_framework"]) or bands[NEWEST_BAND]}

# A label setting rather than a select, as for the other packs, so that an
# unconfigured query sees only the setting's default and fetches no tool pack.
_host_tool_band = transition(
    implementation = _host_tool_band_impl,
    inputs = ["//dotnet:target_framework"],
    outputs = [_HOST_TOOL_BAND],
)

def _host_tool_pack_impl(ctx):
    return [ctx.attr._pack[DotnetToolPackInfo]]

host_tool_pack = rule(
    _host_tool_pack_impl,
    doc = """A native tool for the machine the build runs on, from the band of the target framework.

The band's `host` alias is picked in the target configuration, and past the
exec transition selects the pack for the execution platform.""",
    attrs = {
        "bands": attr.string_dict(
            doc = "The `host` alias of each band, by target framework, and the newest band's under `NEWEST_BAND`.",
            mandatory = True,
        ),
        "_pack": attr.label(
            default = Label(_HOST_TOOL_BAND),
            cfg = "exec",
            providers = [DotnetToolPackInfo],
        ),
    },
    cfg = _host_tool_band,
    # Picks the execution platform the way the rules running the tool do, so
    # that the pack is the one for the machine their actions run on.
    toolchains = ["//dotnet:toolchain_type"],
    provides = [DotnetToolPackInfo],
)
