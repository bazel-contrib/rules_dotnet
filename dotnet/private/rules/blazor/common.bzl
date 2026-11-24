"""Shared pieces of the two ways a Blazor WebAssembly application is assembled.

A publish trims and ships no symbols; a development run does the opposite.
Everything else - which assemblies the browser loads, which of the runtime
pack's files are runtime rather than debugging aids, where the boot
configuration goes - is the same, and lives here.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:common.bzl", "get_toolchain")
load("//dotnet/private:nuget_version.bzl", "nuget_version")
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

# What the page loads, and what starts the runtime.
_STARTER = "_framework/blazor.webassembly.js"

def _is_published_native(basename):
    return basename in _PUBLISHED_NATIVE or (
        basename.startswith("icudt") and basename.endswith(".dat")
    )

def _managed_assemblies(runtime_info, pack):
    """Every assembly the browser loads, keyed by file name.

    As in MSBuild's conflict resolution, a dependency replaces a runtime pack
    assembly only when it is newer, and the newest such dependency wins: the
    framework's own assemblies may fail to load an older copy. A dependency
    without a version never counts as newer.

    Args:
      runtime_info: The application's `DotnetAssemblyRuntimeInfo`.
      pack: The WebAssembly `DotnetRuntimePackInfo`.

    Returns:
      A dict of file name to `File`.
    """
    assemblies = {}

    # The version of whatever holds each of the pack's assemblies: the pack, or
    # the dependency that beat it.
    versions = {}

    for info in pack.assembly_runtime_infos:
        # The Mono pack keeps `System.Private.CoreLib.dll` among its native
        # files, but it is managed like any other.
        for lib in info.libs + [file for file in info.native if file.basename.endswith(".dll")]:
            assemblies[lib.basename] = lib
            versions[lib.basename] = info.version

    for dep in runtime_info.deps.to_list():
        for lib in dep.libs:
            if lib.basename in versions:
                if not nuget_version.is_newer(dep.version, versions[lib.basename]):
                    continue
                versions[lib.basename] = dep.version

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

        if under == None or any([fragment in file.path for fragment in under]):
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

def _application_assets(ctx, binary, tfm):
    """The application's and its dependencies' static web assets, plus the starter script.

    From .NET 11 the `Microsoft.AspNetCore.Components.WebAssembly` package
    serves the starter script as an ordinary asset; before that it comes from
    the internal assets pack.

    Args:
      ctx: The rule context.
      binary: The application target.
      tfm: The target framework, for diagnostics.

    Returns:
      A struct of `routes` (source/route structs) and `files`.
    """
    assets = binary[StaticWebAssetsInfo].assets.to_list() if StaticWebAssetsInfo in binary else []
    routes = {asset.serving_path: asset.file for asset in assets}

    if _STARTER not in routes:
        starter = [file for file in ctx.files._internal_assets if file.basename == "blazor.webassembly.js"]
        if not starter:
            fail(
                "%s serves no %s, which starts a %s application.\n" % (binary.label, _STARTER, tfm) +
                "From .NET 11 it comes from the application's Microsoft.AspNetCore.Components.WebAssembly package, " +
                "which the application has to depend on.",
            )

        routes[_STARTER] = starter[0]

    return struct(
        routes = [
            struct(source = file.path, route = route)
            for (route, file) in routes.items()
        ],
        files = routes.values(),
    )

def _application_symbols(runtime_info, assemblies):
    """The symbols of the application and of the dependencies whose assemblies are shipped.

    A dependency that lost to the runtime pack's copy keeps its symbols out,
    since they would match nothing the site serves.

    Args:
      runtime_info: The application's `DotnetAssemblyRuntimeInfo`.
      assemblies: What `_managed_assemblies` chose, by file name.

    Returns:
      A list of `File`.
    """
    symbols = list(runtime_info.pdbs)
    for dep in runtime_info.deps.to_list():
        for pdb in dep.pdbs:
            shipped = assemblies.get(pdb.basename.removesuffix(".pdb") + ".dll")
            if shipped and shipped in dep.libs:
                symbols.append(pdb)

    return symbols

def _assemble_action(ctx, binary, tfm, output, trimmed = None, trim_mode = "partial", debug = False):
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

    webcil = _tool_file(ctx.files._wasm_sdk, "Microsoft.NET.WebAssembly.Webcil.dll", tfm)
    tasks = _tool_file(ctx.files._wasm_sdk, "Microsoft.NET.Sdk.WebAssembly.Pack.Tasks.dll", tfm)
    assets = _application_assets(ctx, binary, tfm)

    illink = _tool_file(ctx.files._illink, "illink.dll", tfm) if trimmed else None
    illink_tasks = _tool_file(ctx.files._illink, "ILLink.Tasks.dll", tfm) if trimmed else None

    # The registered SDK moves `illink` to its own version, so it runs on that
    # SDK's runtime, as under MSBuild, rather than on the one this tool runs on.
    illink_host = get_toolchain(ctx).compiler_host if trimmed else None

    symbols = _application_symbols(runtime_info, assemblies) if debug else []

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
            illinkHost = illink_host.files_to_run.executable.path if illink_host else "",
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
            dotnetJs = runtime.boot_host.path,
            assets = assets.routes,
        )),
    )

    args = ctx.actions.args()
    args.add(request)

    transitive = [
        depset(assemblies.values()),
        ctx.attr._wasm_sdk[0].files,
    ]
    if trimmed:
        transitive.append(ctx.attr._illink.files)
        transitive.append(depset(
            [illink_host.files_to_run.executable],
            transitive = [illink_host.default_runfiles.files],
        ))

    ctx.actions.run(
        mnemonic = "BlazorWasmAssemble",
        progress_message = ("Trimming and assembling %{label}" if trimmed else "Assembling %{label}"),
        executable = ctx.attr._blazor_wasm_tool.files_to_run,
        arguments = [args],
        inputs = depset(
            direct = runtime.served + [runtime.boot_host, request] + assets.files + symbols,
            transitive = transitive,
        ),
        outputs = [output] + ([trimmed] if trimmed else []),
    )

# Shared with `publish_binary`, which offers the same settings for `wasm = True`.
APPLICATION_ENVIRONMENT_DOC = """The hosting environment a Blazor WebAssembly application starts in, as
`IWebAssemblyHostEnvironment.Environment` reports it.

Defaults to `Development` for `bazel run` and to `Production` for a publish."""

INVARIANT_GLOBALIZATION_DOC = """Run a Blazor WebAssembly application without globalization data.

Culture-sensitive formatting, parsing and comparison then behave as in the
invariant culture. The site no longer downloads the ICU data, at the cost of
culture-correct behaviour."""

TRIM_MODE_DOC = """How much of a published Blazor WebAssembly application is trimmed away.

* `partial` (the default, as in `dotnet publish`): trims the framework and the
  assemblies that declare themselves trimmable, and keeps every other assembly
  whole.
* `full`: trims every assembly. Smaller, but it can remove code that is only
  reached through reflection, and no trim warnings are reported.
* `copyused`: keeps every member of every assembly that is used at all. Worth
  trying if a trimmed application misbehaves."""

TRIM_MODES = ["full", "partial", "copyused", "copy"]

def assemble_site(ctx, tfm, verb, trimmed = None, trim_mode = "partial", debug = False, compress = True):
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
            "which is %s or newer." % wasm_pack_tfms()[0],
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
    # Platform-independent files of the framework's band, which the browser
    # transition picks.
    "_wasm_sdk": attr.label(
        default = "//dotnet/private:wasm_sdk",
        allow_files = True,
        cfg = wasm_pack_transition,
    ),
    # Where the starter script comes from before .NET 11.
    "_internal_assets": attr.label(
        default = "//dotnet/private:internal_assets",
        allow_files = True,
        cfg = wasm_pack_transition,
    ),
    "_blazor_wasm_tool": attr.label(
        default = "//dotnet/private/tools/blazor_wasm",
        executable = True,
        cfg = "exec",
    ),
})
