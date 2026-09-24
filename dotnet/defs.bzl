"""Public API surface is re-exported here.

Users should not load files under "/dotnet"
"""

load(
    "//dotnet/private/rules/blazor:app.bzl",
    _blazor_wasm_app = "blazor_wasm_app",
)
load(
    "//dotnet/private/rules/blazor:devserver.bzl",
    _blazor_devserver = "blazor_devserver",
)
load(
    "//dotnet/private/rules/common:embed_sources.bzl",
    _embed_sources_or_flag = "embed_sources_or_flag",
)
load(
    "//dotnet/private/rules/csharp:binary.bzl",
    _csharp_binary = "csharp_binary",
)
load(
    "//dotnet/private/rules/csharp:library.bzl",
    _csharp_library = "csharp_library",
)
load(
    "//dotnet/private/rules/csharp:nunit_test.bzl",
    _csharp_nunit_test = "csharp_nunit_test",
)
load(
    "//dotnet/private/rules/csharp:test.bzl",
    _csharp_test = "csharp_test",
)
load(
    "//dotnet/private/rules/fsharp:binary.bzl",
    _fsharp_binary = "fsharp_binary",
)
load(
    "//dotnet/private/rules/fsharp:library.bzl",
    _fsharp_library = "fsharp_library",
)
load(
    "//dotnet/private/rules/fsharp:nunit_test.bzl",
    _fsharp_nunit_test = "fsharp_nunit_test",
)
load(
    "//dotnet/private/rules/fsharp:test.bzl",
    _fsharp_test = "fsharp_test",
)
load(
    "//dotnet/private/rules/nuget:dotnet_tool.bzl",
    _dotnet_tool = "dotnet_tool",
)
load(
    "//dotnet/private/rules/nuget:imports.bzl",
    _import_dll = "import_dll",
    _import_library = "import_library",
)
load(
    "//dotnet/private/rules/nuget:nuget_archive.bzl",
    _nuget_archive = "nuget_archive",
)
load(
    "//dotnet/private/rules/nuget:nuget_repo.bzl",
    _nuget_repo = "nuget_repo",
)
load(
    "//dotnet/private/rules/nuget_pack:nuget_pack.bzl",
    _nuget_pack = "nuget_pack",
)
load(
    "//dotnet/private/rules/nuget_pack:nuget_push.bzl",
    _nuget_push = "nuget_push",
)
load(
    "//dotnet/private/rules/publish_binary:publish_binary.bzl",
    _publish_binary = "publish_binary",
)
load(
    "//dotnet/private/sdk:packs.bzl",
    _BLAZORWASM_SDK = "BLAZORWASM_SDK",
)

def _binary(name, rule, kwargs):
    """Builds with `rule`, or wraps it when the target is a browser application.

    Args:
      name: The target name.
      rule: The language's binary rule.
      kwargs: The arguments the user passed, less `name`.
    """
    kwargs["embed_sources"] = _embed_sources_or_flag(kwargs.pop("embed_sources", None))

    if kwargs.get("project_sdk", None) == _BLAZORWASM_SDK:
        _blazor_wasm_app(name, rule, kwargs)
    else:
        rule(name = name, **kwargs)

def csharp_binary(name, **kwargs):
    """Builds a C# binary.

    `project_sdk = "blazorwasm"` builds an application that is served to a
    browser rather than executed, so it is built by a rule of its own.
    Dispatching here keeps one public name.

    Args:
      name: The target name.
      **kwargs: Passed to the underlying rule.
    """
    _binary(name, _csharp_binary, kwargs)

def fsharp_binary(name, **kwargs):
    """Builds an F# binary.

    See `csharp_binary` for what `project_sdk = "blazorwasm"` changes.

    Args:
      name: The target name.
      **kwargs: Passed to the underlying rule.
    """
    _binary(name, _fsharp_binary, kwargs)

# The remaining wrappers exist only so that an unset `embed_sources` can default
# to `//dotnet/settings:embed_all_sources`, which a rule attribute cannot do
# because the default would have to be a `select`.
def csharp_library(name, **kwargs):
    """Builds a C# library.

    Args:
      name: The target name.
      **kwargs: Passed to the underlying rule.
    """
    _csharp_library(name = name, embed_sources = _embed_sources_or_flag(kwargs.pop("embed_sources", None)), **kwargs)

def csharp_test(name, **kwargs):
    """Builds a C# test.

    Args:
      name: The target name.
      **kwargs: Passed to the underlying rule.
    """
    _csharp_test(name = name, embed_sources = _embed_sources_or_flag(kwargs.pop("embed_sources", None)), **kwargs)

def fsharp_library(name, **kwargs):
    """Builds an F# library.

    Args:
      name: The target name.
      **kwargs: Passed to the underlying rule.
    """
    _fsharp_library(name = name, embed_sources = _embed_sources_or_flag(kwargs.pop("embed_sources", None)), **kwargs)

def fsharp_test(name, **kwargs):
    """Builds an F# test.

    Args:
      name: The target name.
      **kwargs: Passed to the underlying rule.
    """
    _fsharp_test(name = name, embed_sources = _embed_sources_or_flag(kwargs.pop("embed_sources", None)), **kwargs)

csharp_nunit_test = _csharp_nunit_test
fsharp_nunit_test = _fsharp_nunit_test
publish_binary = _publish_binary
blazor_devserver = _blazor_devserver
import_library = _import_library
import_dll = _import_dll
nuget_repo = _nuget_repo
nuget_archive = _nuget_archive
dotnet_tool = _dotnet_tool
nuget_pack = _nuget_pack
nuget_push = _nuget_push
