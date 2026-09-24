"""Test rules that feed a tool package `nuget_pack` built back into `dotnet_tool`.

`dotnet_tool` runs a tool from the files of its package, so extracting the
package and handing the files over proves the package is one `dotnet tool`
would install.
"""

load("//dotnet/private:providers.bzl", "NuGetPackInfo")
load("//dotnet/private/rules/nuget:dotnet_tool.bzl", "DotnetToolInfo")

def _extract_nupkg_impl(ctx):
    nupkg = ctx.attr.nupkg[NuGetPackInfo].nupkg
    outputs = [ctx.actions.declare_file("{}/{}".format(ctx.label.name, entry)) for entry in ctx.attr.entries]

    # Every output sits under the same folder, which is where the tool extracts to.
    directory = outputs[0].path[:-len(ctx.attr.entries[0]) - 1]

    ctx.actions.run(
        executable = ctx.executable._unzip,
        arguments = [nupkg.path, directory] + ctx.attr.entries,
        inputs = [nupkg],
        outputs = outputs,
        mnemonic = "Unzip",
    )

    return [DefaultInfo(files = depset(outputs))]

extract_nupkg = rule(
    _extract_nupkg_impl,
    doc = "Extracts the named entries of a package built by `nuget_pack`.",
    attrs = {
        "nupkg": attr.label(providers = [NuGetPackInfo], mandatory = True),
        "entries": attr.string_list(mandatory = True, allow_empty = False),
        "_unzip": attr.label(
            default = "//dotnet/private/tests/nuget_pack/unzip",
            executable = True,
            cfg = "exec",
        ),
    },
)

def _tool_files_impl(ctx):
    return [DotnetToolInfo(files_by_tfm = {ctx.attr.tfm: ctx.attr.files})]

tool_files = rule(
    _tool_files_impl,
    doc = "Presents extracted package files to `dotnet_tool` as a tool's files for one framework.",
    attrs = {
        "tfm": attr.string(mandatory = True),
        "files": attr.label(mandatory = True),
    },
)
