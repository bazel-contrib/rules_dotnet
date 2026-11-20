"Test rule that uses ctx.actions.run"

def _run_rule_impl(ctx):
    output = ctx.actions.declare_file("{}_out".format(ctx.label.name))

    # A File rather than its path, so that path mapping rewrites it along with
    # the paths the tool and its runfiles are staged at.
    args = ctx.actions.args()
    args.add(output)

    ctx.actions.run(
        outputs = [output],
        arguments = [args],
        executable = ctx.executable.tool,
        execution_requirements = {"supports-path-mapping": "1"} if ctx.attr.supports_path_mapping else {},
    )

    return [DefaultInfo(files = depset([output]))]

run_rule = rule(
    implementation = _run_rule_impl,
    attrs = {
        "supports_path_mapping": attr.bool(
            doc = "Whether the action opts in to `--experimental_output_paths=strip`, as bazel_lib's `run_binary` does.",
            default = False,
        ),
        "tool": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
        ),
    },
)
