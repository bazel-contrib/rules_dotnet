"""The target frameworks rules_dotnet knows about.

The framework lists mirror the Supported*TargetFramework item groups in the
SDK's Microsoft.NET.SupportedTargetFrameworks.props, which is what its
GenerateNETCompatibleDefineConstants target consumes. A framework absent from
these lists never gets an *_OR_GREATER symbol.

.NET ships a major release a year, each one a framework like the last, so the
.NET frameworks are declared ahead of their release rather than as they ship.
An SDK for a new release then works the day it ships, without a release of
rules_dotnet: what can actually be built for is up to the SDK registered, whose
packs reach no further than its own release. See `pack_bands.bzl`.

Everything else here is derived from the lists, as are the pack bands in
`pack_bands.bzl`.
"""

# The newest .NET release declared ahead of time, due in November 2035.
# Moving it on is all the releases after it need.
_NEWEST_DECLARED_MAJOR = 20

SDK_NETSTANDARD_FRAMEWORKS = [
    "netstandard1.0",
    "netstandard1.1",
    "netstandard1.2",
    "netstandard1.3",
    "netstandard1.4",
    "netstandard1.5",
    "netstandard1.6",
    "netstandard2.0",
    "netstandard2.1",
]

SDK_NETFRAMEWORK_FRAMEWORKS = [
    "net20",
    "net30",
    "net35",
    "net40",
    "net45",
    "net451",
    "net452",
    "net46",
    "net461",
    "net462",
    "net47",
    "net471",
    "net472",
    "net48",
    "net481",
]

SDK_NETCOREAPP_FRAMEWORKS = [
    "netcoreapp1.0",
    "netcoreapp1.1",
    "netcoreapp2.0",
    "netcoreapp2.1",
    "netcoreapp2.2",
    "netcoreapp3.0",
    "netcoreapp3.1",
] + ["net{}.0".format(major) for major in range(5, _NEWEST_DECLARED_MAJOR + 1)]

# What a configuration that no transition has touched is in, and so what a
# target builds for at most unless something asks for less. The newest declared
# framework, so that nothing but the SDK limits what a target can build for.
DEFAULT_TARGET_FRAMEWORK = SDK_NETCOREAPP_FRAMEWORKS[-1]

def _dotted_version(tfm, prefix):
    return [int(part) for part in tfm[len(prefix):].split(".")]

def _netcoreapp_lang_version(tfm):
    version = _dotted_version(tfm, "netcoreapp" if tfm.startswith("netcoreapp") else "net")

    # .NET 5 has C# 9, and every release since has brought the next one.
    if version >= [5]:
        return "{}.0".format(version[0] + 4)

    return "8.0" if version >= [3] else "7.3"

# The C# language version the SDK defaults to for each framework, before it is
# capped at the newest one the compiler knows. Newer language features depend
# on runtime support that older targets lack, which is why the cap exists.
#
# Mirrors `_MaxSupportedLangVersion` in Roslyn's Microsoft.CSharp.Core.targets.
SDK_LANG_VERSIONS = (
    {
        tfm: "8.0" if _dotted_version(tfm, "netstandard") >= [2, 1] else "7.3"
        for tfm in SDK_NETSTANDARD_FRAMEWORKS
    } |
    {tfm: "7.3" for tfm in SDK_NETFRAMEWORK_FRAMEWORKS} |
    {tfm: _netcoreapp_lang_version(tfm) for tfm in SDK_NETCOREAPP_FRAMEWORKS}
)

# Monikers rules_dotnet accepts that the SDK's lists omit, by the framework
# each comes just before. They can be depended on, but get no `*_OR_GREATER`
# symbol, matching the SDK.
_LEGACY_BEFORE = {
    "net20": "net11",
    "net45": "net403",
    "netstandard1.0": "netstandard",
}

# Where .NET Framework and .NET Core gain access to a .NET Standard version.
# These are the only edges between families, and fixed history rather than
# anything a new release changes.
_NETSTANDARD_BRIDGES = {
    "net45": "netstandard1.1",
    "net451": "netstandard1.2",
    "net46": "netstandard1.3",
    "net461": "netstandard2.0",
    "netcoreapp1.0": "netstandard1.6",
    "netcoreapp2.0": "netstandard2.0",
    "netcoreapp3.0": "netstandard2.1",
}

def _compatibility(families):
    """Maps each framework to the frameworks it can directly compile against.

    Within a family that is the previous release; the only other edges are the
    netstandard bridges.
    """
    compatibility = {}

    for family in families:
        previous = []
        for tfm in family:
            for framework in ([_LEGACY_BEFORE[tfm]] if tfm in _LEGACY_BEFORE else []) + [tfm]:
                bridge = [_NETSTANDARD_BRIDGES[framework]] if framework in _NETSTANDARD_BRIDGES else []
                compatibility[framework] = previous + bridge
                previous = [framework]

    return compatibility

# Each framework mapped to the frameworks it can directly compile against.
# The relationship is transitive. Order matters: netstandard first, and
# within a family oldest to newest.
FRAMEWORK_COMPATIBILITY = _compatibility([
    SDK_NETSTANDARD_FRAMEWORKS,
    SDK_NETFRAMEWORK_FRAMEWORKS,
    SDK_NETCOREAPP_FRAMEWORKS,
])
