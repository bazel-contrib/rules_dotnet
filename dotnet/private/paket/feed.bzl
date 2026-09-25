"""Resolves NuGet package hashes from the feeds a lock file points at.

Paket does not record package hashes, so there is nothing in `paket.lock` to
pin a download against. NuGet V3 feeds publish the hash of every package as
part of their registration metadata, so the extension looks it up once and
hands it back to Bazel as a fact, which keeps it in `MODULE.bazel.lock` for
every later build to reuse and for reviewers to see.

Feeds that do not serve registration metadata simply yield no hash. The
packages are still pinned to an exact version by the lock file; they are just
not verified against a recorded digest.

A package without a hash is remembered too, as an empty hash, so that later
evaluations do not ask again. Only an answer from the feed is remembered.
Bazel does not say why a download failed, so a failed request can be an outage
as well as a missing package, and it is asked again next time.
"""

load(
    "@bazel_tools//tools/build_defs/repo:utils.bzl",
    "read_netrc",
    "read_user_netrc",
    "use_netrc",
)

# Bump when the shape of a fact changes so that stale entries are ignored
# rather than misread.
_FACT_VERSION = "v1"

# Registration resources in order of preference. Only the SemVer 2.0.0
# flavours list packages whose versions carry build metadata or dotted
# pre-release identifiers, which rules out the older resources for some feeds.
# The algorithms Bazel can verify a download against. NuGet publishes the hash
# in standard base 64, which is the encoding subresource integrity wants, so
# the algorithm name is all that has to be translated. nuget.org has always
# used SHA512, but the algorithm is up to the feed.
_HASH_ALGORITHMS = {
    "SHA256": "sha256",
    "SHA384": "sha384",
    "SHA512": "sha512",
}

_REGISTRATION_RESOURCES = [
    "RegistrationsBaseUrl/3.6.0",
    "RegistrationsBaseUrl/Versioned",
    "RegistrationsBaseUrl/3.4.0",
    "RegistrationsBaseUrl/3.0.0-rc",
    "RegistrationsBaseUrl/3.0.0-beta",
    "RegistrationsBaseUrl",
]

def _package_key(id, version):
    return "{}/{}".format(id.lower(), version.lower())

def integrity_fact_key(id, version):
    """Returns the key a package's hash is remembered under.

    A package version is downloaded once and shared by every dependency group
    that resolves it, so the feed it came from is not part of its identity.

    Args:
      id: The package id.
      version: The normalized package version.

    Returns:
      The fact key.
    """
    return "sha512/{}:{}".format(_FACT_VERSION, _package_key(id, version))

def read_netrc_entries(module_ctx, netrc):
    """Reads a netrc file once, for repeated `auth_for` calls.

    Args:
      module_ctx: The module extension context.
      netrc: A label pointing at a netrc file, or None to use the user's.

    Returns:
      The parsed netrc entries.
    """
    return read_netrc(module_ctx, netrc) if netrc else read_user_netrc(module_ctx)

def _auth(netrc_entries, urls):
    return use_netrc(netrc_entries, urls, {
        "type": "basic",
        "login": "<login>",
        "password": "<password>",
    })

def _read_json(module_ctx, path, url):
    content = module_ctx.read(path)
    if not content.startswith("{"):
        fail("{} did not return JSON. Check the feed, or set verify_integrity = False on paket.parse.".format(url))

    return json.decode(content)

def _download_all(module_ctx, requests, auth, directory):
    """Downloads `requests` concurrently and returns the parsed JSON bodies.

    Args:
      module_ctx: The module extension context.
      requests: A list of (key, url) pairs.
      auth: The auth dict to use.
      directory: Where to stage the downloaded files.

    Returns:
      A dict of key to parsed JSON. A request that failed is omitted; one the
      feed answers with something other than JSON fails the build.
    """
    pending = []

    for (index, (key, url)) in enumerate(requests):
        path = "{}/{}.json".format(directory, index)
        pending.append((key, path, url, module_ctx.download(
            url = url,
            output = path,
            allow_fail = True,
            block = False,
            auth = auth,
        )))

    results = {}
    for (key, path, url, token) in pending:
        # Bazel reports a 404 and an outage the same way, as `success = False`.
        if token.wait().success:
            results[key] = _read_json(module_ctx, path, url)

    return results

def _service_index(module_ctx, source, auth, indexes, required):
    """Returns a V3 feed's resources by type, or {} for a feed without them.

    Args:
      module_ctx: The module extension context.
      source: The feed to query.
      auth: The auth dict to use.
      indexes: A cache of source URL to resources, which this call adds to.
      required: Whether an unreachable feed should fail the build, rather than
        return None.
    """
    if source in indexes:
        return indexes[source]

    if not source.endswith("index.json"):
        # A V2 feed. Its metadata is OData rather than JSON.
        indexes[source] = {}
        return {}

    if not module_ctx.download(
        url = source,
        output = "service_index.json",
        allow_fail = True,
        auth = auth,
    ).success:
        if not required:
            # Not cached: a later caller that requires the feed must not take
            # the outage for a feed that offers nothing.
            return None

        fail(
            "Could not read the service index of {} to verify package hashes.".format(source) +
            " Check the feed and its credentials, or set verify_integrity = False on paket.parse.",
        )

    resources = {}
    for resource in _read_json(module_ctx, "service_index.json", source).get("resources", []):
        resources.setdefault(resource.get("@type", ""), resource.get("@id", ""))

    indexes[source] = resources

    return resources

def _base_url(resources, types):
    for name in types:
        base = resources.get(name)
        if base:
            return base if base.endswith("/") else base + "/"

    return ""

def _package_hash(catalog_entry, url):
    """Returns a catalog entry's hash as subresource integrity, or None."""
    hash = catalog_entry.get("packageHash")
    algorithm = catalog_entry.get("packageHashAlgorithm")

    # Both are required by the spec, but a feed that omits them is just a feed
    # that publishes no hash.
    if not hash or not algorithm:
        return None

    prefix = _HASH_ALGORITHMS.get(algorithm.upper())
    if prefix == None:
        fail(
            "{} hashes packages with {}, which Bazel cannot verify.".format(url, algorithm) +
            " Set verify_integrity = False on paket.parse.",
        )

    return "{}-{}".format(prefix, hash)

def _served_versions(module_ctx, resources, ids, netrc_entries):
    """Returns the versions a feed serves of each package, by lower case id.

    An id is left out if its version list did not download.
    """
    base = _base_url(resources, ["PackageBaseAddress/3.0.0"])
    if not base:
        return {}

    lists = _download_all(
        module_ctx,
        [(id, "{}{}/index.json".format(base, id)) for id in {id.lower(): None for id in ids}],
        _auth(netrc_entries, [base]),
        "versions",
    )

    return {id: index.get("versions", []) for (id, index) in lists.items()}

def resolve_integrity(module_ctx, source, packages, netrc_entries, indexes):
    """Looks up the subresource integrity of each package on a feed.

    Args:
      module_ctx: The module extension context.
      source: The feed to query.
      packages: Structs with `id` and `version` fields.
      netrc_entries: Parsed netrc entries, from `read_netrc_entries`.
      indexes: A cache of service index lookups, which this call adds to.

    Returns:
      A dict of "<lower id>/<lower version>" to an integrity string. The
      string is empty where the feed's answer shows it has no hash for the
      package. A package the feed gave no answer for is left out.
    """
    if not packages:
        return {}

    resources = _service_index(module_ctx, source, _auth(netrc_entries, [source]), indexes, required = True)
    base = _base_url(resources, _REGISTRATION_RESOURCES)
    if not base:
        return {_package_key(package.id, package.version): "" for package in packages}

    auth = _auth(netrc_entries, [base])

    leaves = _download_all(
        module_ctx,
        [
            (
                _package_key(package.id, package.version),
                "{}{}/{}.json".format(base, package.id.lower(), package.version.lower()),
            )
            for package in packages
        ],
        auth,
        "registration",
    )

    # The hash lives on the catalog entry, which a registration leaf links to.
    # Feeds that inline the entry instead do not carry a hash in it.
    integrity = {}
    catalog_requests = []
    for (key, leaf) in leaves.items():
        entry = leaf.get("catalogEntry")
        if type(entry) == "string" and entry:
            catalog_requests.append((key, entry))
        else:
            integrity[key] = ""

    for (key, entry) in _download_all(module_ctx, catalog_requests, auth, "catalog").items():
        integrity[key] = _package_hash(entry, source) or ""

    # A leaf that did not download is a version the feed does not have, or a
    # failed request. The feed's version list tells the two apart.
    unlisted = [package for package in packages if _package_key(package.id, package.version) not in leaves]
    served = _served_versions(module_ctx, resources, [package.id for package in unlisted], netrc_entries)
    for package in unlisted:
        versions = served.get(package.id.lower())
        if versions != None and package.version.lower() not in versions:
            integrity[_package_key(package.id, package.version)] = ""

    return integrity

def package_versions(module_ctx, source, id, netrc_entries, indexes):
    """Returns the versions of a package a feed publishes.

    Args:
      module_ctx: The module extension context.
      source: The feed to query. Must be a V3 service index.
      id: The package id.
      netrc_entries: Parsed netrc entries, from `read_netrc_entries`.
      indexes: A cache of service index lookups, which this call adds to.

    Returns:
      A list of versions, or None if the feed could not be asked.
    """
    resources = _service_index(module_ctx, source, _auth(netrc_entries, [source]), indexes, required = False)
    if resources == None:
        return None

    return _served_versions(module_ctx, resources, [id], netrc_entries).get(id.lower())

def resolve_integrity_cached(module_ctx, sources, packages, netrc_entries, resolved, indexes):
    """Fills `resolved` with each package's integrity, keyed for `facts`.

    A hash remembered by an earlier evaluation, or already resolved in this
    one, is reused. Feeds are tried in order, which is the order the package
    itself is downloaded in. A package gets an empty hash only when every feed
    answered that it has none.

    Args:
      module_ctx: The module extension context.
      sources: The feeds to try.
      packages: Structs with `id` and `version` fields.
      netrc_entries: Parsed netrc entries, from `read_netrc_entries`.
      resolved: Integrity by fact key, which this call adds to.
      indexes: A cache of service index lookups, which this call adds to.
    """
    remembered = getattr(module_ctx, "facts", {})
    pending = {}

    for package in packages:
        key = integrity_fact_key(package.id, package.version)
        if key in resolved:
            continue

        if key in remembered:
            resolved[key] = remembered[key]
        else:
            pending[_package_key(package.id, package.version)] = package

    unanswered = {}
    for source in sources:
        if not pending:
            break

        answers = resolve_integrity(module_ctx, source, pending.values(), netrc_entries, indexes)
        for key in pending.keys():
            if key not in answers:
                unanswered[key] = True
            elif answers[key]:
                package = pending.pop(key)
                resolved[integrity_fact_key(package.id, package.version)] = answers[key]

    for (key, package) in pending.items():
        if key not in unanswered:
            resolved[integrity_fact_key(package.id, package.version)] = ""
