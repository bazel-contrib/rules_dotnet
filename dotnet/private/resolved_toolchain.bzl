"""This module implements an alias rule to the resolved toolchain.
"""

DOC = """\
Exposes a concrete toolchain which is the result of Bazel resolving the
toolchain for the execution or target platform.
Workaround for https://github.com/bazel-contrib/bazel/issues/14009
"""

# Forward all the providers
def _resolved_toolchain_impl(ctx):
    toolchain_info = ctx.toolchains["//dotnet:toolchain_type"]
    return [
        toolchain_info,
        toolchain_info.default,
        toolchain_info.dotnetinfo,
        toolchain_info.template_variables,
    ]

# Copied from java_toolchain_alias
# https://cs.opensource.google/bazel/bazel/+/master:tools/jdk/java_toolchain_alias.bzl
resolved_toolchain = rule(
    implementation = _resolved_toolchain_impl,
    toolchains = ["//dotnet:toolchain_type"],
    incompatible_use_toolchain_transition = True,
    doc = DOC,
)
