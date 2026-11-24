"""Forwards a file as built in two configurations, which share its `short_path`."""

def _other_compilation_mode_impl(settings, _attr):
    mode = settings["//command_line_option:compilation_mode"]
    return {"//command_line_option:compilation_mode": "opt" if mode == "dbg" else "dbg"}

_other_compilation_mode = transition(
    implementation = _other_compilation_mode_impl,
    inputs = ["//command_line_option:compilation_mode"],
    outputs = ["//command_line_option:compilation_mode"],
)

def _in_two_configurations_impl(ctx):
    return [DefaultInfo(files = depset(ctx.files.src + ctx.files.other))]

in_two_configurations = rule(
    implementation = _in_two_configurations_impl,
    doc = "The files of `src` in this configuration and in another compilation mode.",
    attrs = {
        "src": attr.label(allow_files = True, mandatory = True),
        "other": attr.label(allow_files = True, cfg = _other_compilation_mode),
    },
)
