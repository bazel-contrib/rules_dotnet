"""The `dotnet_content_files` rule, and resolving the `content_files` attribute to destination paths."""

load("@bazel_skylib//lib:paths.bzl", "paths")
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
        # Normalized, as Bazel's output paths are: `config/./x` is `config/x`.
        dest = paths.normalize(_remap(package_relative_path(f, ctx.label), strip_prefix, prefix))
        if dest in seen:
            fail("dotnet_content_files %s: sources %s and %s both map to destination %r; adjust `srcs`, `strip_prefix`, or `prefix` to disambiguate." % (ctx.label, seen[dest], f.short_path, dest))
        seen[dest] = f.short_path
        mappings.append(struct(src = f, dest = dest))

    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        DotnetContentFilesInfo(mappings = mappings),
    ]

dotnet_content_files = rule(
    implementation = _dotnet_content_files_impl,
    doc = """Groups data files and controls where they are copied next to a consuming assembly.

Reference the target from the `content_files` attribute of a `csharp_library`, `csharp_binary`,
`csharp_test`, `fsharp_library`, `fsharp_binary`, or `fsharp_test`. Each file's destination,
relative to the assembly's directory (`AppContext.BaseDirectory` at run time), is its path
relative to this target's package with `strip_prefix` removed and `prefix` prepended. A file
outside this package's directory starts from its file name.

Like the `Link` metadata of an MSBuild
[`Content`](https://learn.microsoft.com/en-us/visualstudio/msbuild/common-msbuild-project-items#content)
item copied to the output directory, this can flatten a directory, relocate files or re-root a
tree, which plain `content_files` cannot.

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
            doc = "The data files to copy.",
            allow_files = True,
            allow_empty = True,
        ),
        "strip_prefix": attr.string(
            doc = "A leading directory, relative to this target's package, to remove from each " +
                  "file's path. Files outside it keep their whole path.",
            default = "",
        ),
        "prefix": attr.string(
            doc = "A directory, relative to the assembly's directory, to place every file under. " +
                  "Must not contain `..`.",
            default = "",
        ),
    },
)

def resolve_content_file_mappings(content_targets, label):
    """Resolves the targets of a `content_files` attribute into destination paths.

    A `dotnet_content_files` target gives its own; any other file keeps its
    path relative to the consuming target's package. Two different files may
    not share a destination.

    Args:
        content_targets: The list of `Target`s from the `content_files` attribute.
        label: The label of the consuming target.

    Returns:
        A list of `struct(src = File, dest = string)` mappings, one per destination.
    """
    sources = {}
    mappings = []
    for t in content_targets:
        if DotnetContentFilesInfo in t:
            target_mappings = t[DotnetContentFilesInfo].mappings
        else:
            target_mappings = [struct(src = f, dest = package_relative_path(f, label)) for f in t[DefaultInfo].files.to_list()]

        for mapping in target_mappings:
            previous = sources.get(mapping.dest)
            if previous == None:
                sources[mapping.dest] = mapping.src
                mappings.append(mapping)
            elif previous != mapping.src:
                fail(("%s: `content_files` would stage both %s and %s at %r. Give one of them " +
                      "another destination, for example with `dotnet_content_files`.") % (
                    label,
                    previous.short_path,
                    mapping.src.short_path,
                    mapping.dest,
                ))
    return mappings
