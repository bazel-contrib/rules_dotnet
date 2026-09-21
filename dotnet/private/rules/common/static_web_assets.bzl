"""Static web assets: the files a web target serves.

An asset is a file plus the path it is served from, and propagation across
dependency edges is a transitive depset. Two of MSBuild's conventions are
reproduced rather than invented:

  * files live under a `wwwroot` directory, and are served at their path
    relative to it. This is MSBuild's default content root.
  * a library's assets are served under `_content/<assembly name>`, so two
    libraries shipping `site.css` do not collide. An application's assets sit at
    the root.

Assets are always materialized into a `wwwroot` tree rather than recorded in a
manifest that points at their original locations, because only that layout works
under remote execution and `bazel run`. It is also the layout `dotnet publish`
produces, which is why no `{Assembly}.staticwebassets.runtime.json` is written:
a published application does not carry one either.
"""

load("//dotnet/private:providers.bzl", "StaticWebAssetsInfo")

# Every rule that describes a served tree needs the tool that does it.
STATIC_WEB_ASSETS_ATTRS = {
    "_static_web_assets_tool": attr.label(
        doc = "Fingerprints and compresses the served tree and writes the endpoint manifest.",
        default = "//dotnet/private/tools/static_web_assets",
        cfg = "exec",
    ),
}

WEB_ROOT = "wwwroot"

# Extensions worth compressing, from
# Microsoft.NET.Sdk.StaticWebAssets.Compression.targets and trimmed to what a
# web application actually ships. Anything unlisted is left alone, which covers
# the formats that are already compressed.
_COMPRESSIBLE = [
    "css",
    "dat",
    "dll",
    "html",
    "htm",
    "js",
    "json",
    "map",
    "md",
    "mjs",
    "pdb",
    "svg",
    "txt",
    "wasm",
    "webmanifest",
    "xml",
]

# The base path MSBuild gives a Razor class library's assets.
_LIBRARY_BASE_PATH = "_content"

# Where a NuGet package puts the files it serves. See the
# `build/Microsoft.AspNetCore.StaticWebAssets.props` such a package ships.
PACKAGE_CONTENT_ROOT = "staticwebassets"

def _serving_subpath(file, label, content_root):
    """The path a file is served from, relative to its content root.

    Args:
      file: The asset.
      label: The label of the target contributing it, for error messages.
      content_root: The directory the asset's serving path is relative to.

    Returns:
      The path relative to `content_root`.
    """
    path = file.short_path

    marker = "/" + content_root + "/"
    index = path.rfind(marker)
    if index >= 0:
        return path[index + len(marker):]

    if path.startswith(content_root + "/"):
        return path[len(content_root) + 1:]

    fail(
        "the static web asset %s of %s is not under a %r directory.\n" % (
            file.short_path,
            label,
            content_root,
        ) +
        "A web asset is served at its path relative to %r, which is the content root " % content_root +
        "MSBuild uses, so there is nowhere to serve this file from. Move it under %r." % content_root,
    )

def base_path(assembly_name, is_application):
    """Where a target's own assets are served from.

    Args:
      assembly_name: The target's assembly name.
      is_application: Whether the target is an application.

    Returns:
      The base path, without a trailing slash.
    """
    return "" if is_application else "{}/{}".format(_LIBRARY_BASE_PATH, assembly_name)

def collect_static_web_assets(
        label,
        assembly_name,
        files,
        deps,
        is_application,
        generated = [],
        content_root = WEB_ROOT):
    """Builds the `StaticWebAssetsInfo` for a target.

    Args:
      label: The label of the target.
      assembly_name: The target's assembly name, which names its base path.
      files: The target's own static web assets, living under a `wwwroot`.
      deps: The target's dependencies.
      is_application: Whether the target serves at the root rather than under
        `_content/<assembly name>`.
      generated: Assets the build produced rather than the user declaring, as
        structs of a `file` and the `subpath` it is served at below the base
        path. The scoped CSS bundle arrives this way: it has no `wwwroot` to be
        relative to.
      content_root: The directory `files` are served relative to. A NuGet
        package puts them under `staticwebassets` rather than `wwwroot`.

    Returns:
      A `StaticWebAssetsInfo`.
    """
    prefix = base_path(assembly_name, is_application)

    def serving_path(subpath):
        return "{}/{}".format(prefix, subpath) if prefix else subpath

    own = [
        struct(
            file = asset.file,
            serving_path = serving_path(asset.subpath),
            scoped_css_bundle = asset.scoped_css_bundle,
        )
        for asset in generated
    ]
    for file in files:
        own.append(struct(
            file = file,
            serving_path = serving_path(_serving_subpath(file, label, content_root)),
            scoped_css_bundle = False,
        ))

    return StaticWebAssetsInfo(
        assets = depset(
            direct = own,
            transitive = [
                dep[StaticWebAssetsInfo].assets
                for dep in deps
                if StaticWebAssetsInfo in dep
            ],
        ),
    )

def materialize_static_web_assets(actions, label, out_dir, assets_info):
    """Lays the transitive assets out as a servable `wwwroot` tree.

    Args:
      actions: The rule's `ctx.actions`.
      label: The label of the target, for error messages.
      out_dir: The target's output directory prefix.
      assets_info: The `StaticWebAssetsInfo` to lay out.

    Returns:
      A list of structs of the `file` in the tree and the `route` it is served
      at.
    """
    outputs = []
    by_serving_path = {}

    for asset in assets_info.assets.to_list():
        previous = by_serving_path.get(asset.serving_path)
        if previous:
            # Same file reached through two dependency paths is not a conflict.
            if previous == asset.file:
                continue

            fail(
                "%s serves two different files at %r:\n" % (label, asset.serving_path) +
                "  %s\n  %s\n" % (previous.short_path, asset.file.short_path) +
                "Static web assets of different libraries are kept apart by their assembly " +
                "names, so this is two assets of one library, or two libraries with the same " +
                "assembly name.",
            )
        by_serving_path[asset.serving_path] = asset.file

        output = actions.declare_file("{}/{}/{}".format(out_dir, WEB_ROOT, asset.serving_path))
        actions.symlink(output = output, target_file = asset.file)
        outputs.append(struct(file = output, route = asset.serving_path))

    return outputs

def _is_compressible(route):
    parts = route.rsplit(".", 1)
    return len(parts) == 2 and parts[1].lower() in _COMPRESSIBLE

def _manifest(actions, out_dir, assembly_name):
    return actions.declare_file("{}/{}.staticwebassets.endpoints.json".format(
        out_dir,
        assembly_name,
    ))

def _describe_action(actions, label, out_dir, tool, request_fields, inputs, outputs):
    """Runs the tool that compresses the served files and describes them."""
    request = actions.declare_file("{}/static_web_assets_request.json".format(out_dir))
    actions.write(output = request, content = json.encode(struct(**request_fields)))

    args = actions.args()
    args.add(request)

    actions.run(
        mnemonic = "StaticWebAssetsManifest",
        progress_message = "Describing static web assets for " + label.name,
        executable = tool.files_to_run,
        arguments = [args],
        inputs = inputs + [request],
        outputs = outputs,
    )

def endpoints_manifest_action(actions, label, out_dir, assembly_name, assets, tool):
    """Fingerprints and compresses the served tree, and describes it.

    Args:
      actions: The rule's `ctx.actions`.
      label: The label of the target, for the progress message.
      out_dir: The target's output directory prefix.
      assembly_name: The target's assembly name, which names the manifest.
      assets: The materialized assets, as structs of a `file` and its `route`.
      tool: The `static_web_assets` tool.

    Returns:
      A struct of the `manifest` and the `compressed` variants, each a struct of
      a `file` and the `route` it is served at.
    """
    manifest = _manifest(actions, out_dir, assembly_name)

    outputs = [manifest]
    variants = []
    requests = []
    for asset in assets:
        compressed = []
        if _is_compressible(asset.route):
            for suffix in ["gz", "br"]:
                route = "{}.{}".format(asset.route, suffix)
                output = actions.declare_file("{}/{}/{}".format(out_dir, WEB_ROOT, route))
                outputs.append(output)
                variants.append(struct(file = output, route = route))
                compressed.append(output.path)

        requests.append(struct(
            route = asset.route,
            file = asset.file.path,
            gzip = compressed[0] if compressed else None,
            brotli = compressed[1] if compressed else None,
        ))

    _describe_action(
        actions,
        label,
        out_dir,
        tool,
        {"manifest": manifest.path, "assets": requests},
        [asset.file for asset in assets],
        outputs,
    )

    return struct(manifest = manifest, compressed = variants)

def endpoints_manifest_from_directory(actions, label, out_dir, assembly_name, directory, tool, compress = True):
    """Serves a whole directory, copying it into a `wwwroot` and describing it.

    The files are not known at analysis time, so the tool walks the tree and
    decides for itself what to compress. A Blazor WebAssembly publish arrives
    this way, because trimming decides which assemblies it ships.

    Args:
      actions: The rule's `ctx.actions`.
      label: The label of the target, for the progress message.
      out_dir: The target's output directory prefix.
      assembly_name: The target's assembly name, which names the manifest.
      directory: The directory to serve, as a `File`.
      tool: The `static_web_assets` tool.
      compress: Whether to write the compressed variants. A development run
        serves from the same machine that built it, so it pays for none.

    Returns:
      A struct of the served `wwwroot` directory and the endpoint `manifest`.
    """
    wwwroot = actions.declare_directory("{}/{}".format(out_dir, WEB_ROOT))
    manifest = _manifest(actions, out_dir, assembly_name)

    _describe_action(
        actions,
        label,
        out_dir,
        tool,
        {
            "manifest": manifest.path,
            "inputDirectory": directory.path,
            "outputDirectory": wwwroot.path,
            "compressibleExtensions": _COMPRESSIBLE if compress else [],
        },
        [directory],
        [wwwroot, manifest],
    )

    return struct(wwwroot = wwwroot, manifest = manifest)
