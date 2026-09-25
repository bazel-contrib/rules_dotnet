"""Tests for looking up package hashes on a feed."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//dotnet/private/paket:feed.bzl",
    "integrity_fact_key",
    "package_versions",
    "resolve_integrity_cached",
)

def _fake_module_ctx(responses, facts = {}):
    """A module_ctx whose downloads answer from `responses`, a dict of URL to JSON.

    A URL that is not in `responses` fails, as both a 404 and an outage do.
    """
    files = {}
    requested = []

    def download(url, output, allow_fail = False, block = True, **_kwargs):
        requested.append(url)
        if url in responses:
            files[output] = json.encode(responses[url])
        elif not allow_fail:
            fail("unexpected download of " + url)

        result = struct(success = url in responses)
        return result if block else struct(wait = lambda: result)

    return struct(
        download = download,
        facts = facts,
        read = lambda path: files[path],
        requested = requested,
    )

def _source(host):
    return "https://{}/v3/index.json".format(host)

def _service_index(host, registration = True):
    resources = [{"@type": "PackageBaseAddress/3.0.0", "@id": "https://{}/flat/".format(host)}]
    if registration:
        resources.append({"@type": "RegistrationsBaseUrl/3.6.0", "@id": "https://{}/registration/".format(host)})

    return {_source(host): {"resources": resources}}

def _leaf(host, id, version):
    return "https://{}/registration/{}/{}.json".format(host, id.lower(), version)

def _catalog(host, id, version):
    return "https://{}/catalog/{}.{}.json".format(host, id.lower(), version)

def _versions(host, id):
    return "https://{}/flat/{}/index.json".format(host, id.lower())

def _hashed(host, id, version):
    return {
        _leaf(host, id, version): {"catalogEntry": _catalog(host, id, version)},
        _catalog(host, id, version): {"packageHash": "abc", "packageHashAlgorithm": "SHA512"},
    }

def _package(id, version):
    return struct(id = id, version = version)

def _answers_test_impl(ctx):
    env = unittest.begin(ctx)

    feed = "feed.test"
    module_ctx = _fake_module_ctx(_service_index(feed) | _hashed(feed, "Hashed", "1.0.0") | {
        _leaf(feed, "Unhashed", "1.0.0"): {"catalogEntry": _catalog(feed, "Unhashed", "1.0.0")},
        _catalog(feed, "Unhashed", "1.0.0"): {},
        _leaf(feed, "Inlined", "1.0.0"): {"catalogEntry": {"version": "1.0.0"}},
        _versions(feed, "Missing"): {"versions": ["1.0.0"]},
        _versions(feed, "Served"): {"versions": ["1.0.0"]},
        _leaf(feed, "CatalogDown", "1.0.0"): {"catalogEntry": _catalog(feed, "CatalogDown", "1.0.0")},
    })

    resolved = {}
    resolve_integrity_cached(
        module_ctx,
        [_source(feed)],
        [
            _package("Hashed", "1.0.0"),
            _package("Unhashed", "1.0.0"),
            _package("Inlined", "1.0.0"),
            _package("Missing", "2.0.0"),
            _package("Served", "1.0.0"),
            _package("Unlisted", "1.0.0"),
            _package("CatalogDown", "1.0.0"),
        ],
        {},
        resolved,
        {},
    )

    # Served, Unlisted and CatalogDown each had a request fail, which may be an
    # outage, so they are asked again next time.
    asserts.equals(
        env,
        {
            integrity_fact_key("Hashed", "1.0.0"): "sha512-abc",
            integrity_fact_key("Unhashed", "1.0.0"): "",
            integrity_fact_key("Inlined", "1.0.0"): "",
            integrity_fact_key("Missing", "2.0.0"): "",
        },
        resolved,
    )

    return unittest.end(env)

_answers_test = unittest.make(_answers_test_impl)

def _remembered_test_impl(ctx):
    env = unittest.begin(ctx)

    facts = {
        integrity_fact_key("Hashed", "1.0.0"): "sha512-abc",
        integrity_fact_key("Missing", "2.0.0"): "",
    }
    module_ctx = _fake_module_ctx({}, facts = facts)

    resolved = {}
    resolve_integrity_cached(
        module_ctx,
        [_source("feed.test")],
        [_package("Hashed", "1.0.0"), _package("Missing", "2.0.0")],
        {},
        resolved,
        {},
    )

    asserts.equals(env, facts, resolved)
    asserts.equals(env, [], module_ctx.requested, "a remembered empty hash is not asked for again")

    return unittest.end(env)

_remembered_test = unittest.make(_remembered_test_impl)

def _feeds_test_impl(ctx):
    env = unittest.begin(ctx)

    first = "first.test"
    second = "second.test"
    module_ctx = _fake_module_ctx(
        _service_index(first, registration = False) | _service_index(second) | _hashed(second, "Hashed", "1.0.0") | {
            _versions(second, "Missing"): {"versions": ["1.0.0"]},
        },
    )

    resolved = {}
    resolve_integrity_cached(
        module_ctx,
        [_source(first), _source(second)],
        [_package("Hashed", "1.0.0"), _package("Missing", "2.0.0"), _package("Unlisted", "1.0.0")],
        {},
        resolved,
        {},
    )

    asserts.equals(
        env,
        {
            integrity_fact_key("Hashed", "1.0.0"): "sha512-abc",
            integrity_fact_key("Missing", "2.0.0"): "",
        },
        resolved,
        "only a package that every feed answered for gets an empty hash",
    )

    v2 = _fake_module_ctx({})
    resolved = {}
    resolve_integrity_cached(v2, ["https://v2.test/api/v2"], [_package("Hashed", "1.0.0")], {}, resolved, {})

    asserts.equals(env, {integrity_fact_key("Hashed", "1.0.0"): ""}, resolved, "a V2 feed has no hashes")
    asserts.equals(env, [], v2.requested)

    return unittest.end(env)

_feeds_test = unittest.make(_feeds_test_impl)

def _package_versions_test_impl(ctx):
    env = unittest.begin(ctx)

    feed = "feed.test"
    module_ctx = _fake_module_ctx(_service_index(feed) | {_versions(feed, "Listed"): {"versions": ["1.0.0"]}})

    asserts.equals(env, ["1.0.0"], package_versions(module_ctx, _source(feed), "Listed", {}, {}))
    asserts.equals(env, None, package_versions(module_ctx, _source(feed), "Unlisted", {}, {}))

    indexes = {}
    asserts.equals(env, None, package_versions(_fake_module_ctx({}), _source(feed), "Listed", {}, indexes))
    asserts.equals(env, {}, indexes, "an unreachable feed is not cached as one without resources")

    return unittest.end(env)

_package_versions_test = unittest.make(_package_versions_test_impl)

def feed_test_suite(name):
    unittest.suite(
        name,
        _answers_test,
        _feeds_test,
        _package_versions_test,
        _remembered_test,
    )
