"The SDK packs that ship a native tool"

load("//dotnet/private:common.bzl", "copy_files_to_dir")
load("//dotnet/private:providers.bzl", "DotnetToolPackInfo")

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
