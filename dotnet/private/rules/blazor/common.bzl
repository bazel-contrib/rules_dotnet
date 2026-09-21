"""Shared pieces of the two ways a Blazor WebAssembly application is assembled.

A publish trims and ships no symbols; a development run does the opposite.
Everything else - which assemblies the browser loads, which of the runtime
pack's files are runtime rather than debugging aids, where the boot
configuration goes - is the same, and lives here.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:providers.bzl",
    "BlazorWasmSiteInfo",
    "DotnetAssemblyRuntimeInfo",
    "DotnetRuntimePackInfo",
    "StaticWebAssetsInfo",
)
load(
    "//dotnet/private/rules/common:static_web_assets.bzl",
    "STATIC_WEB_ASSETS_ATTRS",
    "endpoints_manifest_from_directory",
)
load("//dotnet/private/sdk:packs.bzl", "wasm_pack_tfms")
load("//dotnet/private/transitions:wasm_pack_transition.bzl", "wasm_pack_transition")

# The runtime pack ships debugging and typing aids beside the files a browser
# actually loads. Only these are served.
_PUBLISHED_NATIVE = [
    "dotnet.js",
    "dotnet.native.js",
    "dotnet.native.wasm",
    "dotnet.runtime.js",
]

_BOOT_HOST = "dotnet.js"

def _is_published_native(basename):
    return basename in _PUBLISHED_NATIVE or (
        basename.startswith("icudt") and basename.endswith(".dat")
    )

def _managed_assemblies(runtime_info, pack):
    """Every assembly the browser loads, keyed by file name.

    The runtime pack carries a whole framework; the application and its
    dependencies override any of it they replace, which is what a `deps.json`
    would resolve at run time on any other platform.

    Args:
      runtime_info: The application's `DotnetAssemblyRuntimeInfo`.
      pack: The WebAssembly `DotnetRuntimePackInfo`.

    Returns:
      A dict of file name to `File`.
    """
    assemblies = {}

    for info in pack.assembly_runtime_infos:
        for lib in info.libs:
            assemblies[lib.basename] = lib

        # The Mono pack keeps `System.Private.CoreLib.dll` among its native
        # files, but it is managed like any other.
        for native in info.native:
            if native.basename.endswith(".dll"):
                assemblies[native.basename] = native

    for dep in runtime_info.deps.to_list():
        for lib in dep.libs:
            assemblies[lib.basename] = lib

    for lib in runtime_info.libs:
        assemblies[lib.basename] = lib

    return assemblies

def _runtime_files(pack, tfm):
    """Separates the runtime pack's served files from its boot host.

    Args:
      pack: The WebAssembly `DotnetRuntimePackInfo`.
      tfm: The target framework, for diagnostics.

    Returns:
      A struct of `served` and `boot_host`.
    """
    served = []
    boot_host = None
    for info in pack.assembly_runtime_infos:
        for file in info.native:
            if not _is_published_native(file.basename):
                continue

            if file.basename == _BOOT_HOST:
                boot_host = file
            else:
                served.append(file)

    if not boot_host:
        fail("the WebAssembly runtime pack for %s carries no %s" % (tfm, _BOOT_HOST))

    return struct(served = served, boot_host = boot_host)

def only(files, basename, what, under = None):
    """The one file with this name, or a failure naming what wanted it.

    Args:
      files: The files to look in.
      basename: The file name to find.
      what: What is looking, for the failure message.
      under: Path fragments to restrict the search to, any one of which the
        file's path has to contain.

    Returns:
      The matching `File`.
    """
    for file in files:
        if file.basename != basename:
            continue

        if under == None or [True for fragment in under if fragment in file.path]:
            return file

    fail("the packs carry no %s%s, which %s needs" % (
        basename,
        " under %s" % " or ".join(under) if under else "",
        what,
    ))

def _tool_file(files, basename, tfm):
    # A pack ships the same tool for several frameworks, so take the one built
    # for the framework being published; older packs spell that `tools/net`.
    return only(files, basename, "a %s application" % tfm, ["/tools/%s/" % tfm, "/tools/net/"])

def _application_assets(binary):
    """The application's own servable files, with the route each takes.

    Args:
      binary: The application target.

    Returns:
      A struct of `routes` (source/route structs) and `files`.
    """
    if StaticWebAssetsInfo not in binary:
        return struct(routes = [], files = [])

    assets = binary[StaticWebAssetsInfo].assets.to_list()
    return struct(
        routes = [
            struct(source = asset.file.path, route = asset.serving_path)
            for asset in assets
        ],
        files = [asset.file for asset in assets],
    )

def _application_symbols(runtime_info):
    """The symbols of the application's own assemblies.

    A NuGet package hardly ever ships symbols, so this naturally yields
    first-party code only.

    Args:
      runtime_info: The application's `DotnetAssemblyRuntimeInfo`.

    Returns:
      A list of `File`.
    """
    symbols = list(runtime_info.pdbs)
    for dep in runtime_info.deps.to_list():
        symbols.extend(dep.pdbs)

    return symbols

def _assemble_action(ctx, binary, tfm, output, trimmed = None, trim_mode = "full", debug = False):
    """Assembles the directory a Blazor WebAssembly application boots from.

    Args:
      ctx: The rule context.
      binary: The application target.
      tfm: The target framework.
      output: The declared directory to assemble into.
      trimmed: Scratch directory for the trimmer, or None not to trim.
      trim_mode: How much the trimmer removes, when trimming.
      debug: Whether to ship symbols and say that debugging is available.
    """
    runtime_info = binary[DotnetAssemblyRuntimeInfo]
    pack = ctx.attr._wasm_pack[0][DotnetRuntimePackInfo]

    assemblies = _managed_assemblies(runtime_info, pack)
    runtime = _runtime_files(pack, tfm)

    starter = only(ctx.files._internal_assets, "blazor.webassembly.js", "a %s application" % tfm)
    webcil = _tool_file(ctx.files._wasm_sdk, "Microsoft.NET.WebAssembly.Webcil.dll", tfm)
    tasks = _tool_file(ctx.files._wasm_sdk, "Microsoft.NET.Sdk.WebAssembly.Pack.Tasks.dll", tfm)
    assets = _application_assets(binary)

    illink = _tool_file(ctx.files._illink, "illink.dll", tfm) if trimmed else None
    illink_tasks = _tool_file(ctx.files._illink, "ILLink.Tasks.dll", tfm) if trimmed else None
    symbols = _application_symbols(runtime_info) if debug else []

    # Beside the directory it describes, so that the two rules that assemble an
    # application do not collide on a package-relative path.
    request = ctx.actions.declare_file("blazor_wasm_request.json", sibling = output)
    ctx.actions.write(
        output = request,
        content = json.encode(struct(
            debug = debug,
            symbols = [symbol.path for symbol in symbols],
            illink = illink.path if illink else "",
            illinkTasks = illink_tasks.path if illink_tasks else "",
            trimmedDirectory = trimmed.path if trimmed else "",
            trimMode = trim_mode,
            webcilConverter = webcil.path,
            tasksAssembly = tasks.path,
            appAssembly = runtime_info.libs[0].path,
            assemblies = [lib.path for lib in assemblies.values()],
            outputDirectory = output.path,
            targetFrameworkVersion = "v" + tfm[len("net"):],
            applicationEnvironment = ctx.attr.application_environment,
            invariantGlobalization = ctx.attr.invariant_globalization,
            native = [file.path for file in runtime.served],
            starter = starter.path,
            dotnetJs = runtime.boot_host.path,
            assets = assets.routes,
        )),
    )

    args = ctx.actions.args()
    args.add(request)

    transitive = [
        depset(assemblies.values()),
        ctx.attr._wasm_sdk.files,
    ]
    if trimmed:
        transitive.append(ctx.attr._illink.files)

    ctx.actions.run(
        mnemonic = "BlazorWasmAssemble",
        progress_message = ("Trimming and assembling %{label}" if trimmed else "Assembling %{label}"),
        executable = ctx.attr._blazor_wasm_tool.files_to_run,
        arguments = [args],
        inputs = depset(
            direct = runtime.served + [runtime.boot_host, starter, request] + assets.files + symbols,
            transitive = transitive,
        ),
        outputs = [output] + ([trimmed] if trimmed else []),
    )

# Both rules take these; the shared doc is also what `publish_binary` shows for
# the same two settings.
APPLICATION_ENVIRONMENT_DOC = "The environment name the application starts in."

INVARIANT_GLOBALIZATION_DOC = """Drop the globalization data.

Culture-sensitive behaviour then falls back to the invariant culture, which
saves the ICU payload at the cost of correct formatting and comparison."""

TRIM_MODE_DOC = """How much of the application the trimmer removes.

`full` is what `dotnet publish` uses and what a production application wants.
`copyused` keeps every member of every assembly that is used at all, which is
worth trying if a trimmed application misbehaves."""

TRIM_MODES = ["full", "partial", "copyused", "copy"]

def assemble_site(ctx, tfm, verb, trimmed = None, trim_mode = "full", debug = False, compress = True):
    """Assembles an application and describes the directory it is served from.

    Args:
      ctx: The rule context, carrying `ASSEMBLE_ATTRS` and a `binary`.
      tfm: The target framework.
      verb: What the rule is doing, for the failure message.
      trimmed: Scratch directory for the trimmer, or None not to trim.
      trim_mode: How much the trimmer removes, when trimming.
      debug: Whether to ship symbols and say that debugging is available.
      compress: Whether to write the compressed variants of every asset.

    Returns:
      A struct of the wrapped `binary` and the `site` it produced.
    """
    if tfm not in wasm_pack_tfms():
        fail(
            "%s cannot %s for %r.\n" % (ctx.label, verb, tfm) +
            "Blazor WebAssembly needs a framework whose whole toolchain ships as packages, " +
            "which is %s." % ", ".join(sorted(wasm_pack_tfms())),
        )

    binary = ctx.attr.binary[0]
    out_dir = ctx.label.name

    assembled = ctx.actions.declare_directory("{}/assembled".format(out_dir))
    _assemble_action(
        ctx,
        binary = binary,
        tfm = tfm,
        output = assembled,
        trimmed = trimmed,
        trim_mode = trim_mode,
        debug = debug,
    )

    runtime_info = binary[DotnetAssemblyRuntimeInfo]

    # The server and a deployed site both read the endpoint manifest rather than
    # the directory, so both go through the same pipeline.
    served = endpoints_manifest_from_directory(
        ctx.actions,
        ctx.label,
        out_dir,
        runtime_info.name,
        assembled,
        ctx.attr._static_web_assets_tool,
        compress = compress,
    )

    return struct(
        binary = binary,
        site = BlazorWasmSiteInfo(
            wwwroot = served.wwwroot,
            manifest = served.manifest,
            assembly = runtime_info.libs[0],
        ),
    )

# What `assemble_site` reads off the rule. Both the publish and the development
# run carry these; only a publish adds `_illink`.
ASSEMBLE_ATTRS = dicts.add(STATIC_WEB_ASSETS_ATTRS, {
    "application_environment": attr.string(
        doc = APPLICATION_ENVIRONMENT_DOC,
        default = "Production",
    ),
    "invariant_globalization": attr.bool(
        doc = INVARIANT_GLOBALIZATION_DOC,
        default = False,
    ),
    "_wasm_pack": attr.label(
        default = "//dotnet/private:wasm_pack",
        cfg = wasm_pack_transition,
    ),
    "_wasm_sdk": attr.label(
        default = "//dotnet/private:wasm_sdk",
        allow_files = True,
        cfg = "exec",
    ),
    "_internal_assets": attr.label(
        default = "//dotnet/private:internal_assets",
        allow_files = True,
        cfg = "exec",
    ),
    "_blazor_wasm_tool": attr.label(
        default = "//dotnet/private/tools/blazor_wasm",
        executable = True,
        cfg = "exec",
    ),
})
