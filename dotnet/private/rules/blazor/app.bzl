"""Giving a Blazor WebAssembly binary something to run.

A rule cannot change its own executable after the fact (MSBuild overrides
`RunCommand`), so the binary is built under a private name and wrapped by a
target that carries the public one.
"""

load(":blazor_wasm_binary.bzl", "blazor_wasm_binary")

# Everything the binary provides is forwarded by the wrapper, so nothing needs
# to name the binary itself.
_BINARY_SUFFIX = ".app"

# Attributes the wrapper takes rather than the binary.
_WRAPPER_ATTRS = ["application_environment", "invariant_globalization"]

# Attributes that have to agree across the wrapper's edge to the binary, or
# Bazel rejects the dependency.
_SHARED_ATTRS = ["testonly", "compatible_with", "restricted_to", "target_compatible_with"]

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

    wrapper_kwargs = {
        attribute: kwargs.pop(attribute)
        for attribute in _WRAPPER_ATTRS
        if attribute in kwargs
    }
    wrapper_kwargs.update({
        attribute: kwargs[attribute]
        for attribute in _SHARED_ATTRS
        if attribute in kwargs
    })

    tags = kwargs.pop("tags", [])

    binary_rule(
        name = name + _BINARY_SUFFIX,
        # Defaulted from the public name rather than the private one, as MSBuild
        # defaults both from the project name. The browser loads `out`.
        out = kwargs.pop("out", None) or name,
        root_namespace = kwargs.pop("root_namespace", None) or name.replace(" ", "_"),
        # Only built as the wrapper's dependency, never by a wildcard.
        tags = tags + ["manual"],
        **kwargs
    )

    blazor_wasm_binary(
        name = name,
        binary = ":" + name + _BINARY_SUFFIX,
        tags = tags,
        target_framework = target_frameworks[0],
        visibility = kwargs.get("visibility", None),
        **wrapper_kwargs
    )
