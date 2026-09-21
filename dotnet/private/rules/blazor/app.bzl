"""Giving a Blazor WebAssembly binary something to run.

A Bazel rule cannot change its own executable after the fact - MSBuild does it
by overriding `RunCommand` - so the binary is built under a private name and
wrapped by a target that carries the public one.
"""

load(":blazor_wasm_binary.bzl", "blazor_wasm_binary")

# The suffix the wrapped binary is built under. It is an implementation detail:
# everything the binary provides is forwarded by the wrapper, so nothing needs
# to name it.
_BINARY_SUFFIX = ".app"

def blazor_wasm_app(name, binary_rule, kwargs):
    """Declares a Blazor WebAssembly binary and the server that runs it.

    Args:
      name: The public target name.
      binary_rule: The language's binary rule.
      kwargs: The arguments the user passed, less `name`.
    """
    target_frameworks = kwargs.get("target_frameworks", [])
    if len(target_frameworks) != 1:
        fail(
            "%s targets %s.\n" % (name, target_frameworks or "no framework") +
            "A Blazor WebAssembly application is built for exactly one framework, " +
            "because the browser only ever loads one.",
        )

    # Taken before the binary is declared: these belong to the wrapper, and the
    # binary rule has no such attributes.
    wrapper_kwargs = {
        attribute: kwargs.pop(attribute)
        for attribute in ["application_environment", "invariant_globalization"]
        if attribute in kwargs
    }

    binary_rule(
        name = name + _BINARY_SUFFIX,
        # The assembly is named for the public target, not the private one it
        # is built under. Its name reaches the browser - it is what the boot
        # configuration starts - so the suffix must not show up there.
        out = kwargs.pop("out", None) or name,
        # Built as a dependency of the wrapper; a wildcard should not pick it
        # up in its own right.
        tags = kwargs.pop("tags", []) + ["manual"],
        **kwargs
    )

    blazor_wasm_binary(
        name = name,
        binary = ":" + name + _BINARY_SUFFIX,
        target_framework = target_frameworks[0],
        visibility = kwargs.get("visibility", None),
        **wrapper_kwargs
    )
