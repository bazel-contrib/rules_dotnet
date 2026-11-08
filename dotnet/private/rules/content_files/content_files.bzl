"""The `dotnet_content_files` rule and helpers for resolving `content_files` targets.

`dotnet_content_files` groups a set of data files and gives explicit control over where each
one is copied relative to a consuming binary/test's output directory. It mirrors MSBuild's
[`CopyToOutputDirectory`](https://learn.microsoft.com/en-us/visualstudio/msbuild/common-msbuild-project-items)
combined with [`Link`/`TargetPath`](https://learn.microsoft.com/en-us/visualstudio/msbuild/common-msbuild-project-items#content):
`strip_prefix` removes a leading directory from each file's package-relative path and `prefix`
prepends a destination directory, so you can flatten, relocate, or re-root arbitrary trees.

Pass the resulting target to the `content_files` attribute of a `csharp_binary`,
`csharp_test`, `fsharp_binary`, or `fsharp_test`.
"""

load("//dotnet/private:common.bzl", "package_relative_path")
load("//dotnet/private:providers.bzl", "DotnetContentFilesInfo")

def _remap(rel, strip_prefix, prefix):
    """Applies strip_prefix then prefix to a package-relative path."""
    if strip_prefix:
        normalized = strip_prefix + "/"
        if rel.startswith(normalized):
            rel = rel[len(normalized):]
        elif rel == strip_prefix:
            # strip_prefix names the file itself; nothing meaningful remains but its basename.
            rel = rel[rel.rfind("/") + 1:]
    if prefix:
        rel = prefix + "/" + rel
    return rel

def _dotnet_content_files_impl(ctx):
    strip_prefix = ctx.attr.strip_prefix.strip("/")
    prefix = ctx.attr.prefix.strip("/")

    if prefix and ".." in prefix.split("/"):
        fail("dotnet_content_files %s: `prefix` must not contain `..` segments (got %r)." % (ctx.label, ctx.attr.prefix))

    mappings = []
    seen = {}
    for f in ctx.files.srcs:
        dest = _remap(package_relative_path(f, ctx.label.package), strip_prefix, prefix)
        if dest in seen:
            fail("dotnet_content_files %s: sources %s and %s both map to destination %r; adjust `srcs`, `strip_prefix`, or `prefix` to disambiguate." % (ctx.label, seen[dest], f.short_path, dest))
        seen[dest] = f.short_path
        mappings.append(struct(src = f, dest = dest))

    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        DotnetContentFilesInfo(
            files = depset(ctx.files.srcs),
            mappings = mappings,
        ),
    ]

dotnet_content_files = rule(
    implementation = _dotnet_content_files_impl,
    doc = """Groups data files and controls where they are copied next to a consuming assembly.

Reference the target from the `content_files` attribute of a `csharp_binary`, `csharp_test`,
`fsharp_binary`, or `fsharp_test`. Each source file's destination (relative to the assembly
output directory, resolvable at runtime via `AppContext.BaseDirectory`) is computed from its
path relative to this target's Bazel package, after applying `strip_prefix` and `prefix`.

This mirrors an MSBuild
[`Content`](https://learn.microsoft.com/en-us/visualstudio/msbuild/common-msbuild-project-items#content)
or [`None`](https://learn.microsoft.com/en-us/visualstudio/msbuild/common-msbuild-project-items#none)
item marked
[`CopyToOutputDirectory`](https://learn.microsoft.com/en-us/visualstudio/msbuild/common-msbuild-project-items):
its `Link`/`TargetPath` metadata controls where each file lands, so you can flatten a directory,
relocate files, or re-root a whole tree — the cases plain `content_files` (which preserves the
package-relative structure verbatim) cannot express.

Example:

```starlark
load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary", "dotnet_content_files")

# Files live under `assets/` but should ship under `config/` next to the assembly.
dotnet_content_files(
    name = "config",
    srcs = glob(["assets/**"]),
    strip_prefix = "assets",
    prefix = "config",
)

csharp_binary(
    name = "app",
    srcs = ["Program.cs"],
    content_files = [":config"],
)
```
""",
    attrs = {
        "srcs": attr.label_list(
            doc = "The data files to stage. Directory structure is taken relative to this " +
                  "target's Bazel package before `strip_prefix`/`prefix` are applied. " +
                  "Typically populated with `glob`.",
            allow_files = True,
            allow_empty = True,
        ),
        "strip_prefix": attr.string(
            doc = "A leading directory (relative to this target's package) to remove from each " +
                  "source's path before computing its destination. Sources whose package-relative " +
                  "path does not start with this prefix are left unchanged. Defaults to stripping " +
                  "nothing, preserving the package-relative structure.",
            default = "",
        ),
        "prefix": attr.string(
            doc = "A destination directory to prepend to every file's path (after `strip_prefix`), " +
                  "relative to the consuming assembly's output directory. Defaults to no prefix.",
            default = "",
        ),
    },
)

def resolve_content_file_mappings(content_targets, package):
    """Resolves the `content_files` attribute targets into `(src, dest)` mappings.

    Targets providing `DotnetContentFilesInfo` (i.e. `dotnet_content_files`) contribute their
    explicit destination paths. Plain file targets fall back to their path relative to `package`
    (the consuming target's Bazel package) via `package_relative_path`, preserving the
    package-relative directory structure.

    Args:
        content_targets: The list of `Target`s from the `content_files` attribute.
        package: The Bazel package of the consuming target (`ctx.label.package`).

    Returns:
        A list of `struct(src = File, dest = string)` mappings.
    """
    mappings = []
    for t in content_targets:
        if DotnetContentFilesInfo in t:
            mappings.extend(t[DotnetContentFilesInfo].mappings)
        else:
            for f in t[DefaultInfo].files.to_list():
                mappings.append(struct(src = f, dest = package_relative_path(f, package)))
    return mappings
