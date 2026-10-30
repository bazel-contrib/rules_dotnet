"""Parser and validator for `nuget_resolve.json` lock files."""

_FORMAT_VERSION = 1

_REPIN_HINT = "Do not edit nuget_resolve.json by hand; regenerate it with `REPIN=1 bazel run @<name>.<tfm>//:pin`."

def _error(path, message):
    return "%s: %s %s" % (path, message, _REPIN_HINT)

def validate_lock(content, path = "nuget_resolve.json"):
    """Validates lock file contents without failing.

    Args:
      content: The file contents. Must be valid JSON — malformed JSON fails in
        json.decode before validation runs.
      path: The path reported in error messages.

    Returns:
      A list of problems; empty when the file is valid.
    """
    lock = json.decode(content)
    if type(lock) != "dict":
        return [_error(path, "expected a JSON object at the top level.")]

    errors = []

    version = lock.get("version")
    if version != _FORMAT_VERSION:
        errors.append(_error(path, "unsupported version %s; this rules_dotnet version reads version %d." % (
            json.encode(version),
            _FORMAT_VERSION,
        )))

    if type(lock.get("inputHash")) != "string":
        errors.append(_error(path, "missing or invalid \"inputHash\" (a decimal string)."))

    frameworks = lock.get("frameworks")
    if type(frameworks) != "dict" or len(frameworks) == 0:
        errors.append(_error(path, "missing or empty \"frameworks\" map."))
    else:
        for (tfm, group) in frameworks.items():
            packages = group.get("packages") if type(group) == "dict" else None
            if type(packages) != "list":
                errors.append(_error(path, "framework \"%s\" has no \"packages\" list." % tfm))
                continue
            for package in packages:
                if type(package) != "dict":
                    errors.append(_error(path, "framework \"%s\" has a non-object package entry." % tfm))
                    continue
                for field in ("id", "version", "sha512", "urls"):
                    if field not in package:
                        errors.append(_error(path, "package %s in framework \"%s\" has no \"%s\"." % (
                            package.get("id", "<unknown>"),
                            tfm,
                            field,
                        )))
                if "sha512" in package and not str(package["sha512"]).startswith("sha512-"):
                    errors.append(_error(path, "package %s in framework \"%s\" has a sha512 that is not an SRI string (\"sha512-<base64>\")." % (
                        package.get("id", "<unknown>"),
                        tfm,
                    )))
                if "urls" in package and (type(package["urls"]) != "list" or len(package["urls"]) == 0):
                    errors.append(_error(path, "package %s in framework \"%s\" has no download urls." % (
                        package.get("id", "<unknown>"),
                        tfm,
                    )))

    return errors

def parse_lock(content, path = "nuget_resolve.json"):
    """Parses and validates a `nuget_resolve.json` file.

    Args:
      content: The file contents.
      path: The path reported in error messages.

    Returns:
      A struct with `input_hash` (string) and `frameworks` (a dict of TFM to a
      list of structs with `id`, `version`, `sha512` and `urls` fields, in
      file order).
    """
    errors = validate_lock(content, path)
    if errors:
        fail("\n".join(errors))

    lock = json.decode(content)
    frameworks = {}
    for (tfm, group) in lock["frameworks"].items():
        frameworks[tfm] = [
            struct(
                id = package["id"],
                version = package["version"],
                sha512 = package["sha512"],
                urls = package["urls"],
            )
            for package in group["packages"]
        ]

    return struct(input_hash = lock["inputHash"], frameworks = frameworks)
