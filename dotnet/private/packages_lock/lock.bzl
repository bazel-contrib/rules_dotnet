"""Parser for NuGet's `packages.lock.json` files."""

def parse_lock(content, path = "packages.lock.json"):
    """Parses the contents of a `packages.lock.json` file.

    Args:
      content: The file contents.
      path: The path to report in error messages.

    Returns:
      A list of structs, one per target framework, each with:
        name: The target framework.
        sources: An empty list; package sources are not recorded in this file.
        packages: A list of structs with `id` and resolved `version` fields.
    """
    lock = json.decode(content)
    groups = []

    for (framework, entries) in lock.get("dependencies", {}).items():
        packages = []
        for (id, entry) in entries.items():
            version = entry.get("resolved")
            if not version:
                fail(
                    "{}: package '{}' in framework '{}' has no resolved version".format(
                        path,
                        id,
                        framework,
                    ),
                )

            packages.append(struct(
                id = id,
                version = version,
            ))

        if packages:
            groups.append(struct(name = framework, packages = packages, sources = []))

    return groups
