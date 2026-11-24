"""Razor support for the C# compile action.

Razor is a source generator: `csc` gets the SDK's generator assemblies as
analyzers, the `.razor`/`.cshtml` files as additional files, and two analyzer
configs. Roslyn forces the split:

  * a global config with the `build_property.*` settings. Global configs only
    take absolute section names, which are unknown at analysis time.
  * an `.editorconfig` with the per-file `build_metadata.*` settings. It only
    applies to files below its own directory, so the sources are staged there,
    which also stands in for the `.csproj` directory: a file's `TargetPath`
    (from which Razor derives its namespace and `@page` route) is its path
    relative to the package.
"""

load("@bazel_lib//lib:base64.bzl", "base64")
load("//dotnet/private:common.bzl", "is_core_framework", "tfm_version")

# `File.extension` reports these without the leading dot.
_RAZOR_EXTENSIONS = ["razor", "cshtml"]

# A `<component>.razor.css` styles the component beside it, so it is compiled
# rather than served.
_SCOPED_CSS_SUFFIX = ".razor.css"

# Razor sources are staged here, below the target's output directory. The
# `TargetPath` config sits above it and the `CssScope` config inside it, because
# Roslyn rejects two analyzer configs in one directory (CS8700).
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

# Characters a section name has to backslash-escape to match literally: the glob
# syntax, plus `#` and `;`, which Roslyn's section-header parser only accepts
# escaped. An unparsed header leaves its properties to the previous section.
_SECTION_NAME_SPECIAL_CHARACTERS = ["\\", "*", "?", "[", "]", "{", "}", "#", ";"]

def partition_srcs(srcs, label):
    """Splits `srcs` by what the compile action does with each file.

    Args:
      srcs: The target's `srcs`.
      label: The label of the target compiling them, for error messages.

    Returns:
      A struct of the `compile` sources `csc` is handed, the `razor` sources the
      generator reads, the `scoped_css` stylesheets and the `xaml` WPF compiles.
    """
    compile_srcs = []
    razor_srcs = []
    scoped_css_srcs = []
    xaml_srcs = []
    stray_css = []
    for src in srcs:
        if src.extension in _RAZOR_EXTENSIONS:
            razor_srcs.append(src)
        elif src.extension == "xaml":
            xaml_srcs.append(src)
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
        xaml = xaml_srcs,
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
    """Turns a target name, which may hold `-` and the like, into a C# namespace.

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

def escape_section_name(path):
    """Escapes a path for use as an editorconfig section name.

    Args:
      path: The path the section matches.

    Returns:
      The escaped path.
    """
    for character in _SECTION_NAME_SPECIAL_CHARACTERS:
        path = path.replace(character, "\\" + character)
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

    staged = []
    sections = []
    for src in razor_srcs:
        relative_path = target_path(src.short_path, label)

        # Symlinked rather than copied: staging costs nothing.
        staged_file = actions.declare_file("%s/%s/%s" % (out_dir, RAZOR_STAGING_DIR, relative_path))
        actions.symlink(output = staged_file, target_file = src)
        staged.append(staged_file)

        # The leading slash anchors the glob to this config's own directory;
        # without it `[Widget.razor]` would also match `sub/Widget.razor`. The
        # generator always base64-decodes `TargetPath`.
        sections.append("[/{}/{}]".format(RAZOR_STAGING_DIR, escape_section_name(relative_path)))
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
    if any([src.extension == "cshtml" for src in razor_srcs]):
        assembly_info = actions.declare_file("%s/RazorAssemblyInfo.cs" % out_dir)
        actions.write(assembly_info, _APPLICATION_PART_FACTORY_SRC)
        extra_srcs.append(assembly_info)

    return struct(
        analyzers = generator_files,
        additionalfiles = staged,
        configs = [metadata_config, property_config] + extra_configs,
        srcs = extra_srcs,
    )
