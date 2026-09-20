"""Razor support for the C# compile action.

The Razor SDK runs no compiler of its own. It feeds `csc` through three ordinary
flags:

    /analyzer:        the generator assemblies, from the SDK
    /additionalfile:  the .razor and .cshtml files
    /analyzerconfig:  the settings the generator reads

The settings are split across two config files because Roslyn forces it:

  * a *global* config (`is_global = true`) carrying the `build_property.*`
    settings. Global configs may only have absolute section names, which Bazel
    cannot know at analysis time, so this one has no sections at all.

  * a plain `.editorconfig` carrying the per-file `build_metadata.*` settings.
    Its sections are globs relative to the config's own directory, and Roslyn
    applies it only to files *underneath* that directory, which is why the Razor
    sources are staged next to it.

That staging directory is what makes `TargetPath` well defined: it is the Bazel
equivalent of the directory a `.csproj` sits in, and `TargetPath` is a file's
path within it. The generator derives a component's namespace and its `@page`
route from that path, so it has to be package-relative rather than dependent on
where the execroot happens to be.
"""

load("@bazel_lib//lib:base64.bzl", "base64")
load("//dotnet/private:common.bzl", "is_core_framework", "tfm_version")

# `File.extension` reports these without the leading dot.
_RAZOR_EXTENSIONS = ["razor", "cshtml"]

# A `<component>.razor.css` styles the component beside it, so it is compiled
# rather than served.
_SCOPED_CSS_SUFFIX = ".razor.css"

# Razor sources are staged here, below the target's output directory. Roslyn
# applies a plain .editorconfig only to files underneath it, so this is also
# what decides where the configs can live: the `TargetPath` one sits above this
# directory and the `CssScope` one inside it, because Roslyn rejects two
# analyzer configs in the same directory (CS8700).
RAZOR_STAGING_DIR = "_razor"

# MSBuild attaches this to any assembly carrying compiled .cshtml so that MVC
# discovers the generated views at runtime. See
# Microsoft.NET.Sdk.Razor.MvcApplicationPartsDiscovery.targets.
_APPLICATION_PART_FACTORY_SRC = """\
[assembly: Microsoft.AspNetCore.Mvc.ApplicationParts.ProvideApplicationPartFactoryAttribute(
    "Microsoft.AspNetCore.Mvc.ApplicationParts.ConsolidatedAssemblyApplicationPartFactory, Microsoft.AspNetCore.Mvc.Razor")]
"""

_NAMESPACE_CHARACTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_."

# `base64.encode` maps each character to a single byte, which matches UTF-8 only
# for ASCII. Above 127 it would quietly emit Latin-1 and disagree with the
# UTF-8 bytes MSBuild encodes, so those paths are rejected instead.
_ASCII_PRINTABLE = (
    " !\"#$%&'()*+,-./0123456789:;<=>?@" +
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`" +
    "abcdefghijklmnopqrstuvwxyz{|}~"
)

# editorconfig treats these as glob syntax, so a literal one in a file name has
# to be escaped or the section would match the wrong files, or nothing at all.
_GLOB_METACHARACTERS = ["\\", "*", "?", "[", "]", "{", "}"]

def partition_srcs(srcs, label):
    """Splits `srcs` by what the compile action does with each file.

    Args:
      srcs: The target's `srcs`.
      label: The label of the target compiling them, for error messages.

    Returns:
      A struct of the `compile` sources `csc` is handed, the `razor` sources the
      generator reads, and the `scoped_css` stylesheets.
    """
    compile_srcs = []
    razor_srcs = []
    scoped_css_srcs = []
    stray_css = []
    for src in srcs:
        if src.extension in _RAZOR_EXTENSIONS:
            razor_srcs.append(src)
        elif src.basename.endswith(_SCOPED_CSS_SUFFIX):
            scoped_css_srcs.append(src)
        elif src.extension == "css":
            stray_css.append(src)
        else:
            compile_srcs.append(src)

    if stray_css:
        fail(
            "%s has stylesheets in `srcs` that are not scoped CSS: %s.\n" % (
                label,
                ", ".join([src.short_path for src in stray_css]),
            ) +
            "Only `<component>%s` belongs in `srcs`, because it is compiled into the " % _SCOPED_CSS_SUFFIX +
            "component it is named after. Anything else belongs in `static_web_assets`.",
        )

    return struct(
        compile = compile_srcs,
        razor = razor_srcs,
        scoped_css = scoped_css_srcs,
    )

def target_path(short_path, label):
    """The path of a Razor file relative to the package that declares the target.

    This is the Bazel stand-in for a file's path relative to its `.csproj`, and
    the generator turns it into the component's namespace suffix and route.

    Args:
      short_path: The `short_path` of the Razor source.
      label: The label of the target compiling it.

    Returns:
      The package-relative path, using forward slashes.
    """

    # A file reaches `short_path` as `<package>/<rel>`, or as
    # `../<repo>/<package>/<rel>` when it comes from another repository.
    prefix = "../%s/" % label.repo_name if label.repo_name else ""
    if label.package:
        prefix += label.package + "/"

    path = short_path[len(prefix):]
    if not short_path.startswith(prefix) or path.startswith("../"):
        fail(
            "the Razor source %s is outside the package of %s.\n" % (short_path, label) +
            "Razor derives a component's namespace and route from its path relative to the " +
            "package that compiles it, so the file has to live in that package or below it. " +
            "Move the file, or compile it with a target in its own package and depend on that.",
        )

    for character in path.elems():
        if character not in _ASCII_PRINTABLE:
            fail(
                "the Razor source %s in %s has a non-ASCII character (%r) in its path.\n" % (
                    short_path,
                    label,
                    character,
                ) +
                "Razor identifies a component by that path, encoded as UTF-8 bytes, and these " +
                "rules can only encode ASCII. Rename the file to use ASCII characters only.",
            )

    return path

def _sanitize_namespace(value):
    """Turns a target name into something usable as a C# namespace.

    Bazel target names routinely contain characters a namespace cannot, and
    MSBuild sanitizes `RootNamespace` the same way.

    Args:
      value: The namespace to sanitize.

    Returns:
      A valid C# namespace.
    """
    sanitized = "".join([
        character if character in _NAMESPACE_CHARACTERS else "_"
        for character in value.elems()
    ])

    if sanitized and sanitized[0] in "0123456789":
        return "_" + sanitized

    return sanitized

def _escape_section_name(path):
    for metacharacter in _GLOB_METACHARACTERS:
        path = path.replace(metacharacter, "\\" + metacharacter)
    return path

# Razor's versioning has tracked .NET's since net5.0, so
# Sdk.Razor.CurrentVersion.targets only restates the target framework's version.
# Deriving it means a new .NET release needs no change here.
_MINIMUM_RAZOR_FRAMEWORK = [5, 0]

def razor_lang_version(target_framework):
    """The `RazorLangVersion` a target framework implies.

    Args:
      target_framework: The target framework moniker being compiled.

    Returns:
      The Razor language version, e.g. `10.0`.
    """
    version = tfm_version(target_framework) if is_core_framework(target_framework) else []

    if version < _MINIMUM_RAZOR_FRAMEWORK:
        fail(
            "Razor sources are not supported for target framework %r.\n" % target_framework +
            "The Razor source generator needs net5.0 or later.",
        )

    return "{}.{}".format(version[0], version[1])

def razor_compile_inputs(
        actions,
        label,
        out_dir,
        root_namespace,
        target_framework,
        razor_srcs,
        toolchain,
        extra_configs = []):
    """Stages Razor sources and writes the configs the generator reads.

    Args:
      actions: The rule's `ctx.actions`.
      label: The label of the target being compiled.
      out_dir: The target's output directory prefix.
      root_namespace: The assembly's root namespace.
      target_framework: The target framework moniker being compiled.
      razor_srcs: The `.razor` and `.cshtml` sources.
      toolchain: The resolved .NET toolchain.
      extra_configs: Further analyzer configs the generator has to read, such as
        the one carrying the scoped CSS identifiers.

    Returns:
      A struct with the `analyzers`, `additionalfiles` and `configs` to pass to
      `csc`, plus any `srcs` that have to be compiled alongside the originals.
    """
    generators = toolchain.razor_source_generators
    generator_files = generators.files.to_list() if generators else []
    if not generator_files:
        fail(
            "%s has Razor sources, but the resolved .NET toolchain provides no Razor source " % label +
            "generators. The SDK is expected to carry them under " +
            "Sdks/Microsoft.NET.Sdk.Razor/source-generators.",
        )

    # Roslyn applies a plain .editorconfig only to files under its own
    # directory, so the sources are staged beside it. Symlinks keep this free:
    # nothing is copied, and the action still depends on the real file.
    staged = []
    sections = []
    seen = {}
    has_cshtml = False
    for src in razor_srcs:
        relative_path = target_path(src.short_path, label)
        if relative_path in seen:
            fail(
                "two Razor sources in %s both map to %r: %s and %s.\n" % (
                    label,
                    relative_path,
                    seen[relative_path],
                    src.short_path,
                ) +
                "Razor names a component after this path, so it has to be unique.",
            )
        seen[relative_path] = src.short_path
        has_cshtml = has_cshtml or src.extension == "cshtml"

        staged_file = actions.declare_file("%s/%s/%s" % (out_dir, RAZOR_STAGING_DIR, relative_path))
        actions.symlink(output = staged_file, target_file = src)
        staged.append(staged_file)

        # The leading slash anchors the glob to this config's own directory,
        # which is the one above the staging directory. Without it,
        # `[Widget.razor]` would also match `sub/Widget.razor`.
        sections.append("[/{}/{}]".format(
            RAZOR_STAGING_DIR,
            _escape_section_name(relative_path),
        ))

        # The generator decodes this with Convert.FromBase64String
        # unconditionally, so it is never written unencoded.
        sections.append("build_metadata.AdditionalFiles.TargetPath = " + base64.encode(relative_path))
        sections.append("")

    metadata_config = actions.declare_file("%s/razor.editorconfig" % out_dir)
    actions.write(metadata_config, "\n".join(sections))

    property_config = actions.declare_file("%s/razor.globalconfig" % out_dir)
    actions.write(property_config, "\n".join([
        "is_global = true",
        "build_property.RootNamespace = " + _sanitize_namespace(root_namespace),
        "build_property.RazorLangVersion = " + razor_lang_version(target_framework),
        "",
    ]))

    extra_srcs = []
    if has_cshtml:
        assembly_info = actions.declare_file("%s/RazorAssemblyInfo.cs" % out_dir)
        actions.write(assembly_info, _APPLICATION_PART_FACTORY_SRC)
        extra_srcs.append(assembly_info)

    return struct(
        analyzers = generator_files,
        additionalfiles = staged,
        configs = [metadata_config, property_config] + extra_configs,
        srcs = extra_srcs,
    )
