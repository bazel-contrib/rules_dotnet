"The SDK packs that ship a native tool"

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//dotnet/private:common.bzl", "copy_files_to_dir")
load("//dotnet/private:providers.bzl", "DotnetToolPackInfo")
load("//dotnet/private/sdk:packs.bzl", "NEWEST_BAND")

def tool_pack_rule(tool_name):
    """Returns a rule that extracts one native tool from its nuget package.

    Args:
      tool_name: The tool's basename, without the Windows `.exe` suffix.

    Returns:
      A rule producing `DotnetToolPackInfo`, and the `ToolchainInfo` that
      carries it as `pack`.
    """
    basenames = [tool_name, tool_name + ".exe"]

    def _impl(ctx):
        # A toolchain is configured for the target, while the tool runs on the
        # execution platform its runtime identifier names.
        is_windows = ctx.attr.rid.startswith("win-")
        tfm = ctx.attr._target_framework[BuildSettingInfo].value or NEWEST_BAND
        out_dir = "{}/{}".format(tfm, ctx.label.name)

        # The tool loads its JIT libraries from its own directory, so the whole
        # tools directory moves together.
        files = copy_files_to_dir(
            out_dir,
            ctx.actions,
            is_windows,
            [f for f in ctx.attr.pack_files.files.to_list() if "/tools/" in f.path],
            out_dir,
            executables = basenames,
        )
        tools = [f for f in files if f.basename in basenames]

        if not tools:
            fail("{} executable not found in its pack".format(tool_name))

        pack = DotnetToolPackInfo(tool = tools[0], files = depset(files))

        return [pack, platform_common.ToolchainInfo(pack = pack)]

    return rule(
        _impl,
        doc = "The .Net SDK pack that ships `{}`".format(tool_name),
        attrs = {
            "pack_files": attr.label(
                doc = "Every file in the {} nuget package".format(tool_name),
            ),
            "rid": attr.string(
                doc = "The runtime identifier of the machine the tool runs on.",
                mandatory = True,
            ),
            "_target_framework": attr.label(
                default = Label("//dotnet:target_framework"),
                providers = [BuildSettingInfo],
            ),
        },
    )
