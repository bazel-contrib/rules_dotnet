"""Lays a binary out as a tool package's `tools/<tfm>/any` folder."""

load("//dotnet/private:providers.bzl", "DotnetBinaryInfo")

_SETTINGS = """<?xml version="1.0" encoding="utf-8"?>
<DotNetCliTool Version="1">
  <Commands>
    <Command Name="{name}" EntryPoint="{entrypoint}" Runner="dotnet" />
  </Commands>
</DotNetCliTool>
"""

def _staged_tool_impl(ctx):
    binary = ctx.attr.binary[DotnetBinaryInfo]
    files = []
    for file in [binary.dll, binary.runtimeconfig_json]:
        staged = ctx.actions.declare_file("{}/{}".format(ctx.label.name, file.basename))
        ctx.actions.symlink(output = staged, target_file = file)
        files.append(staged)

    settings = ctx.actions.declare_file("{}/DotnetToolSettings.xml".format(ctx.label.name))
    ctx.actions.write(settings, _SETTINGS.format(name = ctx.label.name, entrypoint = binary.dll.basename))

    return [DefaultInfo(files = depset(files + [settings]))]

staged_tool = rule(
    implementation = _staged_tool_impl,
    doc = "The assembly, runtimeconfig.json and DotnetToolSettings.xml of a framework-dependent tool, side by side.",
    attrs = {
        "binary": attr.label(providers = [DotnetBinaryInfo]),
    },
)
