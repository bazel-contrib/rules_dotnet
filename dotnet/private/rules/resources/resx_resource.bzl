"""Rule for generating .NET .resources files from .resx files."""

def _replace_extension(path, extension):
    dot = path.rfind(".")
    if dot == -1:
        return path + extension

    return path[:dot] + extension

def _default_output_path(ctx, src):
    package = ctx.label.package
    if package == "":
        relative_path = src.short_path
    elif src.short_path.startswith(package + "/"):
        relative_path = src.short_path[len(package) + 1:]
    else:
        relative_path = src.basename

    return _replace_extension(relative_path, ".resources")

def _resx_resource_impl(ctx):
    src = ctx.file.src
    if not src.basename.endswith(".resx"):
        fail("resx_resource src must be a .resx file")

    output_path = ctx.attr.out or _default_output_path(ctx, src)
    if not output_path.endswith(".resources"):
        fail("resx_resource out must end with .resources")

    output = ctx.actions.declare_file(output_path)
    args = ctx.actions.args()
    args.add("--src", src.path)
    args.add("--out", output.path)
    args.add("--resource")

    ctx.actions.run(
        inputs = [src],
        outputs = [output],
        executable = ctx.attr._resx2source[DefaultInfo].files_to_run,
        arguments = [args],
        mnemonic = "ResxResource",
        progress_message = "Generating .NET resource %s" % output.short_path,
    )

    return [DefaultInfo(files = depset([output]))]

def _resx_source_impl(ctx):
    src = ctx.file.src
    if not src.basename.endswith(".resx"):
        fail("resx_source src must be a .resx file")

    class_name = ctx.attr.class_name or _replace_extension(src.basename, "")
    output_path = ctx.attr.out or _replace_extension(_default_output_path(ctx, src), ".Designer.cs")
    if not output_path.endswith(".cs"):
        fail("resx_source out must end with .cs")

    output = ctx.actions.declare_file(output_path)
    args = ctx.actions.args()
    args.add("--src", src.path)
    args.add("--out", output.path)
    args.add("--namespace", ctx.attr.namespace)
    args.add("--class", class_name)
    args.add("--accessibility", ctx.attr.accessibility)
    if ctx.attr.constants:
        args.add("--constants")

    ctx.actions.run(
        inputs = [src],
        outputs = [output],
        executable = ctx.attr._resx2source[DefaultInfo].files_to_run,
        arguments = [args],
        mnemonic = "ResxSource",
        progress_message = "Generating .NET resource source %s" % output.short_path,
    )

    return [DefaultInfo(files = depset([output]))]

resx_resource = rule(
    implementation = _resx_resource_impl,
    doc = "Generates a .resources file from a .resx file.",
    attrs = {
        "src": attr.label(
            doc = "The .resx file to convert.",
            allow_single_file = [".resx"],
            mandatory = True,
        ),
        "out": attr.string(
            doc = "The generated .resources path. Defaults to the source path with a .resources extension.",
        ),
        "_resx2source": attr.label(
            default = "//tools/resx2source",
            executable = True,
            cfg = "exec",
        ),
    },
)

resx_source = rule(
    implementation = _resx_source_impl,
    doc = "Generates a strongly typed C# resource source file from a .resx file.",
    attrs = {
        "src": attr.label(
            doc = "The .resx file to convert.",
            allow_single_file = [".resx"],
            mandatory = True,
        ),
        "namespace": attr.string(
            doc = "Namespace for the generated resource class.",
            mandatory = True,
        ),
        "class_name": attr.string(
            doc = "Name of the generated resource class. Defaults to the .resx basename.",
        ),
        "accessibility": attr.string(
            doc = "Accessibility for the generated resource class and members.",
            default = "internal",
            values = ["internal", "public"],
        ),
        "constants": attr.bool(
            doc = "Generate const string resource keys instead of resource value properties.",
            default = False,
        ),
        "out": attr.string(
            doc = "The generated C# source path. Defaults to the source path with .Designer.cs extension.",
        ),
        "_resx2source": attr.label(
            default = "//tools/resx2source",
            executable = True,
            cfg = "exec",
        ),
    },
)
