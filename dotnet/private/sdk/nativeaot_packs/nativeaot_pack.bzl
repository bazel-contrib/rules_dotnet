".Net NativeAOT runtime pack"

load("//dotnet/private:providers.bzl", "DotnetNativeAotPackInfo")

# What the native link consumes, under both Unix and MSVC naming.
_LINK_EXTENSIONS = ["a", "o", "lib", "obj"]

def _nativeaot_pack_impl(ctx):
    libs = []
    link_inputs = {}
    pack_files = ctx.attr.pack_files.files.to_list() if ctx.attr.pack_files else []

    # Every assembly is a reference, wherever it sits: `lib/` holds the framework
    # proper and `native/` holds both the static libraries and the private
    # framework assemblies that only exist for AOT.
    for file in pack_files:
        if file.extension == "dll":
            if "/lib/" in file.path or "/native/" in file.path:
                libs.append(file)
        elif "/native/" in file.path and file.extension in _LINK_EXTENSIONS:
            link_inputs[file.basename] = file

    return [DotnetNativeAotPackInfo(libs = libs, link_inputs = link_inputs)]

nativeaot_pack = rule(
    _nativeaot_pack_impl,
    doc = ".Net NativeAOT runtime pack",
    attrs = {
        "pack_files": attr.label(
            doc = "Every file in the NativeAOT runtime pack nuget package",
        ),
    },
)
