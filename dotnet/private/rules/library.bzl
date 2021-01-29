load("//dotnet/private:context.bzl", "dotnet_context")
load(
    "//dotnet/private:providers.bzl",
    "DotnetLibrary",
    "DotnetResourceList",
)
load("//dotnet/platform:list.bzl", "DOTNET_CORE_FRAMEWORKS", "DOTNET_NETSTANDARD")
load("//dotnet/private:rules/versions.bzl", "parse_version")

def _library_impl(ctx):
    """_library_impl emits actions for compiling dotnet executable assembly."""
    dotnet = dotnet_context(ctx)
    name = ctx.label.name

    # Handle case of empty toolchain on linux and darwin
    if dotnet.assembly == None:
        library = dotnet.new_library(dotnet = dotnet)
        return [library]

    library = dotnet.assembly(
        dotnet,
        name = name,
        srcs = ctx.attr.srcs,
        deps = ctx.attr.deps,
        resources = ctx.attr.resources,
        out = ctx.attr.out,
        defines = ctx.attr.defines,
        unsafe = ctx.attr.unsafe,
        data = ctx.attr.data,
        keyfile = ctx.attr.keyfile,
        executable = False,
        target_framework = ctx.attr.target_framework,
        nowarn = ctx.attr.nowarn,
        langversion = ctx.attr.langversion,
        version = (0, 0, 0, 0, "") if ctx.attr.version == "" else parse_version(ctx.attr.version),
    )

    runfiles = ctx.runfiles(files = [], transitive_files = library.runfiles)

    return [
        library,
        DefaultInfo(
            files = depset([library.result]),
            runfiles = ctx.runfiles(files = [], transitive_files = depset(transitive = [t.runfiles for t in library.transitive])),
        ),
    ]

core_library = rule(
    _library_impl,
    attrs = {
        "deps": attr.label_list(providers = [DotnetLibrary], doc = "The direct dependencies of this library. These may be dotnet_library rules or compatible rules with the [DotnetLibrary](api.md#dotnetlibrary) provider."),
        "version": attr.string(doc = "Version to be set for the assembly. The version is set by compiling in [AssemblyVersion](https://docs.microsoft.com/en-us/troubleshoot/visualstudio/general/assembly-version-assembly-file-version) attribute."),
        "resources": attr.label_list(providers = [DotnetResourceList], doc = "The list of resources to compile with. Usually provided via reference to [core_resx](api.md#core_resx) or the rules compatible with [DotnetResource](api.md#dotnetresource) provider."),
        "srcs": attr.label_list(allow_files = [".cs"], doc = "The list of .cs source files that are compiled to create the assembly."),
        "out": attr.string(doc = "An alternative name of the output file."),
        "defines": attr.string_list(doc = "The list of defines passed via /define compiler option."),
        "unsafe": attr.bool(default = False, doc = "If true passes /unsafe flag to the compiler."),
        "data": attr.label_list(allow_files = True, doc = "The list of additional files to include in the list of runfiles for the assembly."),
        "keyfile": attr.label(allow_files = True, doc = "The key to sign the assembly with."),
        "dotnet_context_data": attr.label(default = Label("@io_bazel_rules_dotnet//:core_context_data"), doc = "The reference to label created with [core_context_data rule](api.md#core_context_data). It points the SDK to be used for compiling given target."),
        "target_framework": attr.string(values = DOTNET_CORE_FRAMEWORKS.keys() + DOTNET_NETSTANDARD.keys() + [""], default = "", doc = "Target framework."),
        "nowarn": attr.string_list(doc = "The list of warnings to be ignored. The warnings are passed to -nowarn compiler opion."),
        "langversion": attr.string(default = "latest", doc = "Version of the language to use. See [this page](https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/configure-language-version)."),
    },
    toolchains = ["@io_bazel_rules_dotnet//dotnet:toolchain_type_core"],
    executable = False,
    doc = """This builds a dotnet assembly from a set of source files.

    Providers
    ^^^^^^^^^

    * [DotnetLibrary](api.md#dotnetlibrary)
    * [DotnetResource](api.md#dotnetresource)

    Example:
    ^^^^^^^^
    ```python
    [core_library(
        name = "{}_TransitiveClass-core.dll".format(framework),
        srcs = [
            "TransitiveClass.cs",
        ],
        dotnet_context_data = "@io_bazel_rules_dotnet//:core_context_data_{}".format(framework),
        visibility = ["//visibility:public"],
        deps = [
            "@io_bazel_rules_dotnet//dotnet/stdlib.core/{}:libraryset".format(framework),
        ],
    ) for framework in DOTNET_CORE_FRAMEWORKS]
    ```
    """,
)
