"Utility function for collecting compilation information from contexts"

load("//dotnet/private:providers.bzl", "NuGetInfo", "DotnetCompileInfo", "DotnetCompileDepVariantInfo", "DotnetAssemblyCompileInfo")


def gather_compile_info(ctx):
    """Collects compilation information from a context

    Args:
        ctx: Bazel build ctx.
    Returns:
        A collection of the source-files, dependencies and transitive dependencies
    """
    direct_deps = []
    transitive_deps = []

    for dep in ctx.attr.deps:
        if DotnetCompileInfo in dep:
            variant = DotnetCompileDepVariantInfo(
                label = dep.label,
                dotnet_compile_info = dep[DotnetCompileInfo],
                dotnet_assembly_compile_info = None,
            )

            direct_deps.append(variant)
            transitive_deps.append(depset(dep[DotnetCompileInfo].deps, transitive = [ dep[DotnetCompileInfo].transitive_deps ]))

        if NuGetInfo in dep and DotnetAssemblyCompileInfo in dep:
            variant = DotnetCompileDepVariantInfo(
                label = dep.label,
                dotnet_compile_info = None,
                dotnet_assembly_compile_info = dep[DotnetAssemblyCompileInfo],
            )

            direct_deps.append(variant)

    return DotnetCompileInfo(
        label = ctx.label,
        srcs = ctx.files.srcs,
        deps = direct_deps,
        transitive_deps = depset([], transitive = transitive_deps),
    )
