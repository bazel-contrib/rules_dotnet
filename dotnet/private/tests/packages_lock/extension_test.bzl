"""Tests for the packages_lock module extension."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private/packages_lock:extension.bzl", "packages_from_lock")

_LOCK = """\
{
  "version": 1,
  "dependencies": {
    "net10.0": {
      "Argu": {
        "type": "Direct",
        "requested": "[6.2.3, )",
        "resolved": "6.2.3"
      },
      "Newtonsoft.Json": {
        "type": "Transitive",
        "resolved": "13.0.3"
      }
    },
    "net9.0": {
      "LibGit2Sharp": {
        "type": "Direct",
        "requested": "[0.27.0-preview-0182, )",
        "resolved": "0.27.0-preview-0182"
      }
    }
  }
}
"""

_SOURCES = [
    "https://api.nuget.org/v3/index.json",
    "https://pkgs.example.com/v3/index.json",
]

def _packages_from_lock_test_impl(ctx):
    env = unittest.begin(ctx)

    groups = packages_from_lock(_LOCK, _SOURCES)

    asserts.equals(env, ["net10.0", "net9.0"], [group.name for group in groups])
    asserts.equals(
        env,
        [
            {
                "id": "Argu",
                "sources": _SOURCES,
                "version": "6.2.3",
            },
            {
                "id": "Newtonsoft.Json",
                "sources": _SOURCES,
                "version": "13.0.3",
            },
        ],
        groups[0].packages,
        "package ids and versions are read from the lock; integrity is resolved separately",
    )

    return unittest.end(env)

_packages_from_lock_test = unittest.make(_packages_from_lock_test_impl)

def extension_test_suite(name):
    unittest.suite(name, _packages_from_lock_test)
