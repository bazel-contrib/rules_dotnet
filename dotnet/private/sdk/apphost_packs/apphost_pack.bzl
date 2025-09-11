".Net Runtime Pack"

load("//dotnet:providers.bzl", "DotnetApphostPackInfo", "DotnetAssemblyRuntimeInfo")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _apphost_pack_impl(ctx):
    # This is a workaround because label settings require a default target
    # so we create a default target with `pack` set as None.
    if ctx.label.name == "empty_pack":
        apphost_file = None
    else:
        apphost_file = None
        for f in ctx.attr.pack[0][DotnetAssemblyRuntimeInfo].native:
            if f.basename == "apphost" or f.basename == "apphost.exe":
                apphost_file = f

        if apphost_file == None:
            fail("Apphost file not found in apphost pack")

    return [DotnetApphostPackInfo(
        apphost = apphost_file,
    )]

apphost_pack = rule(
    _apphost_pack_impl,
    doc = """.Net apphost Pack""",
    attrs = {
        "pack": attr.label(
            cfg = tfm_transition,
            doc = "The App Host nuget package target",
        ),
        "target_framework": attr.string(
            doc = "The target framework of the apphost pack",
        ),
        "runtime_identifier": attr.string(
            doc = "The apphost identifier of the apphost pack",
        ),
    },
)
