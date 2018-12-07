load(
    "@io_bazel_rules_dotnet//dotnet/private:providers.bzl",
    "DotnetLibrary",
    "DotnetResource",
)
load(
    "@io_bazel_rules_dotnet//dotnet/private:common.bzl",
    "paths",
)

DotnetContext = provider()

def _declare_file(dotnet, path = None, ext = None):
    result = path if path else dotnet._ctx.label.name
    if ext:
        result += ext
    return dotnet.actions.declare_file(result)

def _new_library(dotnet, name = None, deps = None, transitive = None, result = None, pdb = None, runfiles = None, **kwargs):
    return DotnetLibrary(
        name = dotnet.label.name if not name else name,
        label = dotnet.label,
        deps = deps,
        transitive = transitive,
        result = result,
        pdb = pdb,
        runfiles = runfiles,
        **kwargs
    )

def _new_resource(dotnet, name, result, identifier = None, **kwargs):
    return DotnetResource(
        name = name,
        label = dotnet.label,
        result = result,
        identifier = result.basename if not identifier else identifier,
        **kwargs
    )

def dotnet_context(ctx, attr = None):
    if not attr:
        attr = ctx.attr

    context_data = attr._dotnet_context_data
    toolchain = ctx.toolchains[context_data._toolchain_type]

    ext = ""
    if toolchain.default_dotnetos == "windows":
        ext = ".exe"

    # Handle empty toolchain for .NET on linux and osx
    if toolchain.get_dotnet_runner == None:
        runner = None
        mcs = None
        stdlib = None
        resgen = None
        tlbimp = None
    else:
        runner = toolchain.get_dotnet_runner(context_data, ext)
        mcs = toolchain.get_dotnet_mcs(context_data)
        stdlib = toolchain.get_dotnet_stdlib(context_data)
        resgen = toolchain.get_dotnet_resgen(context_data)
        tlbimp = toolchain.get_dotnet_tlbimp(context_data)

    return DotnetContext(
        # Fields
        label = ctx.label,
        toolchain = toolchain,
        actions = ctx.actions,
        assembly = toolchain.actions.assembly,
        resx = toolchain.actions.resx,
        com_ref = toolchain.actions.com_ref,
        stdlib_byname = toolchain.actions.stdlib_byname,
        exe_extension = ext,
        runner = runner,
        mcs = mcs,
        stdlib = stdlib,
        resgen = resgen,
        tlbimp = tlbimp,
        declare_file = _declare_file,
        new_library = _new_library,
        new_resource = _new_resource,
        workspace_name = ctx.workspace_name,
        libVersion = context_data._libVersion,
        lib = context_data._lib,
        shared = context_data._shared,
        debug = ctx.var["COMPILATION_MODE"] == "dbg",
        _ctx = ctx,
    )

def _dotnet_context_data(ctx):
    return struct(
        _mcs_bin = ctx.attr._mcs_bin,
        _mono_bin = ctx.attr._mono_bin,
        _lib = ctx.attr._lib,
        _tools = ctx.attr._tools,
        _shared = ctx.attr._shared,
        _host = ctx.attr._host,
        _libVersion = ctx.attr._libVersion,
        _toolchain_type = ctx.attr._toolchain_type,
    )

dotnet_context_data = rule(
    _dotnet_context_data,
    attrs = {
        "_mcs_bin": attr.label(
            allow_files = True,
            default = "@dotnet_sdk//:mcs_bin",
        ),
        "_mono_bin": attr.label(
            allow_files = True,
            default = "@dotnet_sdk//:mono_bin",
        ),
        "_lib": attr.label(
            allow_files = True,
            default = "@dotnet_sdk//:lib",
        ),
        "_tools": attr.label(
            allow_files = True,
            default = "@net_sdk//:lib",
        ),
        "_shared": attr.label(
            allow_files = True,
            default = "@dotnet_sdk//:lib",
        ),
        "_host": attr.label(
            allow_files = True,
            default = "@dotnet_sdk//:lib",
        ),
        "_libVersion": attr.string(
            default = "4.5",
        ),
        "_toolchain_type": attr.string(
            default = "@io_bazel_rules_dotnet//dotnet:toolchain",
        ),
    },
)

core_context_data = rule(
    _dotnet_context_data,
    attrs = {
        "_mcs_bin": attr.label(
            allow_files = True,
            default = "@core_sdk//:mcs_bin",
        ),
        "_mono_bin": attr.label(
            allow_files = True,
            default = "@core_sdk//:mono_bin",
        ),
        "_lib": attr.label(
            allow_files = True,
            default = "@core_sdk//:lib",
        ),
        "_tools": attr.label(
            allow_files = True,
            default = "@net_sdk//:lib",
        ),
        "_shared": attr.label(
            allow_files = True,
            default = "@core_sdk//:shared",
        ),
        "_host": attr.label(
            allow_files = True,
            default = "@core_sdk//:host",
        ),
        "_libVersion": attr.string(
            default = "",
        ),
        "_toolchain_type": attr.string(
            default = "@io_bazel_rules_dotnet//dotnet:toolchain_core",
        ),
    },
)

net_context_data = rule(
    _dotnet_context_data,
    attrs = {
        "_mcs_bin": attr.label(
            allow_files = True,
            default = "@net_sdk//:mcs_bin",
        ),
        "_mono_bin": attr.label(
            allow_files = True,
            default = "@net_sdk//:mono_bin",
        ),
        "_lib": attr.label(
            allow_files = True,
            default = "@net_sdk//:lib",
        ),
        "_tools": attr.label(
            allow_files = True,
            default = "@net_sdk//:tools",
        ),
        "_shared": attr.label(
            allow_files = True,
            default = "@net_sdk//:lib",
        ),
        "_host": attr.label(
            allow_files = True,
            default = "@net_sdk//:mcs_bin",
        ),
        "_libVersion": attr.string(
            default = "",
        ),
        "_toolchain_type": attr.string(
            default = "@io_bazel_rules_dotnet//dotnet:toolchain_net",
        ),
    },
)
