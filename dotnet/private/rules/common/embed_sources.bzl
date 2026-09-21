"""The default a target's `embed_sources` takes when it does not set one.

It follows `//dotnet/settings:embed_all_sources`, which is a flag, so the
default has to be a `select`. A rule attribute default cannot be one, so the
macros in front of the rules supply it instead.
"""

# `Label` rather than a bare string: the macros are called from other
# workspaces, where a relative label would resolve against the caller.
_FLAG = select({
    Label("//dotnet/settings:embed_all_sources_enabled"): True,
    "//conditions:default": False,
})

def embed_sources_or_flag(embed_sources):
    """Resolves an unset `embed_sources` to the flag.

    Args:
      embed_sources: What the caller passed, or None if they passed nothing.

    Returns:
      The value to give the rule.
    """
    return _FLAG if embed_sources == None else embed_sources
