"""Rule for declaring Blazor component contexts."""

load("//dotnet/private:providers.bzl", "BlazorComponentInfo")
load(
    "//dotnet/private/rules/csharp:global_usings.bzl",
    "collect_global_usings",
    "generate_global_usings_source",
)
load("//dotnet/private/transitions:default_transition.bzl", "default_transition")

def _join_path(left, right):
    if not left:
        return right.strip("/")
    if not right:
        return left.strip("/")
    return left.strip("/") + "/" + right.strip("/")

def _namespace_segment_from_path(path):
    parts = []
    for part in path.replace("-", "_").split("/"):
        if part:
            parts.append(part)
    return ".".join(parts)

def _component_impl(ctx):
    parent = ctx.attr.parent[BlazorComponentInfo] if ctx.attr.parent else None

    if parent == None and not ctx.attr.namespace:
        fail("Root blazor_component targets must set namespace.")

    parent_root = parent.effective_root if parent else ""
    parent_namespace = parent.effective_namespace if parent else ""
    path_segment = ctx.attr.path.strip("/")
    effective_root = _join_path(parent_root, path_segment)

    if parent == None:
        effective_namespace = ctx.attr.namespace
    else:
        namespace_segment = ctx.attr.namespace or _namespace_segment_from_path(path_segment)
        effective_namespace = parent_namespace + ("." + namespace_segment if namespace_segment else "")

    import_files = list(parent.import_files) if parent else []
    import_target_paths = list(parent.import_target_paths) if parent else []
    for import_file in ctx.files.imports:
        import_files.append(import_file)
        import_target_paths.append(_join_path(effective_root, import_file.basename))

    global_usings = collect_global_usings(
        ctx.attr.global_usings,
        ctx.attr.implicit_usings,
        parent.global_usings if parent else [],
    )
    global_using_files = generate_global_usings_source(
        ctx.actions,
        ctx.label.name + ".GlobalUsings.g.cs",
        global_usings,
    )

    return [BlazorComponentInfo(
        effective_root = effective_root,
        effective_namespace = effective_namespace,
        import_files = import_files,
        import_target_paths = import_target_paths,
        global_usings = global_usings,
        global_using_files = global_using_files,
    )]

blazor_component = rule(
    _component_impl,
    doc = "Declare a Blazor virtual component context.",
    attrs = {
        "parent": attr.label(
            doc = "Parent Blazor component context.",
            providers = [BlazorComponentInfo],
        ),
        "path": attr.string(
            doc = "Virtual path segment appended to the parent component context.",
        ),
        "namespace": attr.string(
            doc = "Root namespace, or namespace segment overriding the path-derived child segment.",
        ),
        "imports": attr.label_list(
            doc = "Global Razor imports contributed at this component context.",
            allow_files = [".razor"],
            cfg = default_transition,
        ),
        "implicit_usings": attr.bool(
            doc = "Generate the standard Microsoft.NET.Sdk implicit C# global usings for this component context.",
            default = False,
        ),
        "global_usings": attr.string_list(
            doc = "C# global usings contributed at this component context. Entries may include 'static ' or aliases.",
        ),
    },
)
