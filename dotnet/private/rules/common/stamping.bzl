"""Generate SDK assembly attributes and optional build-status overrides."""

load("@bazel_lib//lib:stamping.bzl", "maybe_stamp")

def generate_stamp_assembly_info(ctx, assembly_name, target_framework, stamp, language):
    """Generate the assembly attribute source for a configured target.

    Args:
        ctx: Rule context.
        assembly_name: Output assembly name.
        target_framework: Target framework moniker.
        stamp: Optional build-status inputs.
        language: Source language, csharp or fsharp.

    Returns:
        The generated source file, or None when generation is disabled.
    """
    if stamp == None and not ctx.attr.generate_assembly_info and not ctx.attr.assembly_metadata:
        return None

    extension = "cs" if language == "csharp" else "fs"
    output = ctx.actions.declare_file("%s/%s/%s.stamp_assembly_info.%s" % (
        ctx.attr.name,
        target_framework,
        assembly_name,
        extension,
    ))

    args = ctx.actions.args()
    args.add("--language", language)
    args.add("--out", output)
    if ctx.attr.generate_assembly_info:
        args.add("--assembly-name", assembly_name)
        args.add("--target-framework", target_framework)
        args.add("--configuration", "Debug" if ctx.var["COMPILATION_MODE"] in ["dbg", "fastbuild"] else "Release")
    for key, value in sorted(ctx.attr.assembly_metadata.items()):
        args.add("--metadata", key + "=" + value)
    status_files = [] if stamp == None else [stamp.stable_status_file, stamp.volatile_status_file]
    args.add_all(status_files)

    stamp2info = ctx.attr._stamp2info[DefaultInfo].files_to_run
    ctx.actions.run(
        mnemonic = "DotnetStampAssemblyInfo",
        progress_message = "Generating AssemblyInfo for " + ctx.attr.name,
        inputs = status_files,
        tools = [stamp2info],
        outputs = [output],
        executable = stamp2info,
        arguments = [args],
    )

    return output

def maybe_stamp_srcs(ctx, srcs, assembly_name, target_framework, language):
    """Include generated assembly attributes in language-appropriate source order.

    Args:
        ctx: Rule context.
        srcs: Existing source files.
        assembly_name: Output assembly name.
        target_framework: Target framework moniker.
        language: Source language, csharp or fsharp.

    Returns:
        Sources including assembly attributes when supported and enabled.
    """
    if not hasattr(ctx.attr, "_stamp2info"):
        return srcs

    stamp_assembly_info = generate_stamp_assembly_info(
        ctx,
        assembly_name,
        target_framework,
        maybe_stamp(ctx),
        language,
    )

    if stamp_assembly_info == None:
        return srcs

    return [stamp_assembly_info] + srcs if language == "fsharp" else srcs + [stamp_assembly_info]
