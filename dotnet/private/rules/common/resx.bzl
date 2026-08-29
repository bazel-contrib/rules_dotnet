"""The `resx_resource` rule.

Compiles `.resx` files into binary `.resources` blobs so that `csharp_library`,
`csharp_binary`, `fsharp_library`, `fsharp_binary` and the test rules can embed them and
support .NET localization.

A `resx_resource` target accepts a mix of neutral (culture-invariant) `.resx` files and
per-culture variants (e.g. `Strings.resx` and `Strings.fr.resx`). Neutral files are
compiled and exposed for embedding in the consuming assembly; culture files are compiled
and exposed so the consuming rule can emit satellite assemblies. The rule itself only runs
the `resourcegen` tool and is language and target-framework agnostic.
"""

load("//dotnet/private:providers.bzl", "DotnetResxInfo")

_LOWER = "abcdefghijklmnopqrstuvwxyz"
_ALPHA = _LOWER + "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

def _all_in(s, charset):
    for c in s.elems():
        if c not in charset:
            return False
    return True

def _is_culture_token(token):
    # Detects whether a `.resx` sub-extension is a culture tag: `<lang>` or
    # `<lang>-<script/region>` where lang is 2-3 lowercase letters and the optional suffix
    # is 2-4 letters (e.g. fr, af, zh-Hans, pt-BR). The narrow shape avoids treating a
    # neutral file with a dotted name (e.g. `My.Config.resx`) as culture-specific.
    if not token:
        return False
    segments = token.split("-")
    lang = segments[0]
    if len(lang) < 2 or len(lang) > 3 or not _all_in(lang, _LOWER):
        return False
    if len(segments) == 1:
        return True
    if len(segments) != 2:
        return False
    suffix = segments[1]
    return len(suffix) >= 2 and len(suffix) <= 4 and _all_in(suffix, _ALPHA)

def _culture_of(filename):
    # `Strings.fr.resx` -> `fr`; `Strings.resx` or `My.Config.resx` -> None.
    parts = filename.split(".")
    if len(parts) >= 3 and _is_culture_token(parts[-2]):
        return parts[-2]
    return None

def _package_relative(ctx, file):
    prefix = ctx.label.package + "/"
    short = file.short_path
    if short.startswith(prefix):
        return short[len(prefix):]
    return file.basename

def _neutral_base(rel):
    # `Resources/Strings.fr.resx` -> `Resources/Strings` (strip culture and extension).
    # `Resources/Strings.resx`    -> `Resources/Strings`.
    head = rel[:-len(".resx")]
    parts = head.rsplit("/", 1)
    filename = parts[-1]
    segments = filename.split(".")
    if len(segments) >= 2 and _is_culture_token(segments[-1]):
        filename = ".".join(segments[:-1])
    if len(parts) == 2:
        return "%s/%s" % (parts[0], filename)
    return filename

def _validate_logical_names(ctx, rels):
    seen = {}
    for rel, logical in ctx.attr.logical_names.items():
        if rel not in rels:
            fail("logical_names key '%s' is not one of the resx srcs of %s" % (rel, ctx.label))
        if _culture_of(rel.rsplit("/", 1)[-1]) != None:
            fail("logical_names key '%s' must be a neutral .resx (no culture sub-extension); " % rel +
                 "culture variants inherit the neutral logical name automatically")
        if logical.endswith(".resources"):
            fail("logical_names value '%s' must not end with '.resources'" % logical)
        if logical in seen:
            fail("logical_names value '%s' is used by both '%s' and '%s'" % (logical, seen[logical], rel))
        seen[logical] = rel

def _compile_resx(ctx, src, out):
    ctx.actions.run(
        executable = ctx.executable._resourcegen,
        arguments = ["compile", src.path, out.path],
        inputs = [src],
        outputs = [out],
        mnemonic = "ResxCompile",
        progress_message = "Compiling resx %s" % src.short_path,
        toolchain = None,
    )

def _resx_resource_impl(ctx):
    rels = [_package_relative(ctx, src) for src in ctx.files.srcs]
    _validate_logical_names(ctx, rels)

    neutral = []
    culture = []
    for src in ctx.files.srcs:
        rel = _package_relative(ctx, src)
        base_name = _neutral_base(rel)
        culture_token = _culture_of(src.basename)
        logical_name = ctx.attr.logical_names.get("%s.resx" % base_name)

        if culture_token == None:
            out = ctx.actions.declare_file("%s/%s.resources" % (ctx.label.name, base_name))
            _compile_resx(ctx, src, out)
            neutral.append(struct(
                file = out,
                base_name = base_name,
                logical_name = logical_name,
            ))
        else:
            out = ctx.actions.declare_file(
                "%s/_culture/%s/%s.resources" % (ctx.label.name, culture_token, base_name),
            )
            _compile_resx(ctx, src, out)
            culture.append(struct(
                file = out,
                culture = culture_token,
                base_name = base_name,
                logical_name = logical_name,
            ))

    all_files = [n.file for n in neutral] + [c.file for c in culture]
    return [
        DefaultInfo(files = depset(all_files)),
        DotnetResxInfo(neutral = neutral, culture = culture),
    ]

resx_resource = rule(
    implementation = _resx_resource_impl,
    doc = """Compiles `.resx` files into `.resources` blobs for embedding and localization.

Pass the resulting target to the `resx` attribute of a `csharp_library`, `csharp_binary`,
`fsharp_library`, `fsharp_binary` or a test rule. Neutral `.resx` files are compiled and
embedded in the assembly; per-culture files (e.g. `Strings.fr.resx`) are compiled into
satellite assemblies (`<assembly>.resources.dll`) that the .NET runtime resolves via
`System.Resources.ResourceManager`.

Example:

```starlark
resx_resource(
    name = "strings",
    srcs = glob(["**/*.resx"]),
)

csharp_library(
    name = "lib",
    srcs = glob(["**/*.cs"]),
    out = "MyAssembly",
    resx = [":strings"],
    target_frameworks = ["net8.0"],
)
```
""",
    attrs = {
        "srcs": attr.label_list(
            doc = "The `.resx` files to compile. May include neutral files and per-culture " +
                  "variants such as `Strings.fr.resx`.",
            allow_files = [".resx"],
            mandatory = True,
            allow_empty = False,
        ),
        "logical_names": attr.string_dict(
            doc = "Map of package-relative neutral `.resx` path to an explicit manifest base " +
                  "name (without the `.resources` suffix). Overrides the default name (derived " +
                  "from the assembly name and file path) when a resource needs to be addressable " +
                  "by a specific manifest name. Culture variants inherit their neutral " +
                  "counterpart's logical name automatically.",
        ),
        "_resourcegen": attr.label(
            default = Label("//dotnet/private/tools/resourcegen:resourcegen"),
            executable = True,
            cfg = "exec",
        ),
    },
)
