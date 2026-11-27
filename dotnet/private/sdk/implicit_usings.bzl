"""The `Using` items the .NET SDK's props declare, which make up `ImplicitUsings`.

The namespaces and the conditions they come with are read out of the SDK when
its repository is fetched, rather than kept here, as they change from one SDK
to the next: SDK 11 added `System.Net.Http.Json` for `net11.0` and later, for
one. All rules_dotnet keeps is which props files a project imports, and in what
order, since an SDK's `Using Remove` only removes what came before it.

The `Using` items in a target, as Razor's, are left out: they are added as the
build runs, not when the project is evaluated, and only for features rules_dotnet
does not have.
"""

load("//dotnet/private:xml.bzl", "xml")
load("//dotnet/private/sdk:packs.bzl", "BLAZORWASM_SDK", "DEFAULT_SDK", "RAZOR_SDK", "WEB_SDK")

_CSHARP_PROPS = "Microsoft.NET.Sdk/targets/Microsoft.NET.Sdk.CSharp.props"
_WEB_PROPS = "Microsoft.NET.Sdk.Web/Targets/Sdk.Server.props"
_BLAZORWASM_PROPS = "Microsoft.NET.Sdk.BlazorWebAssembly/Sdk/Sdk.props"
_WINFORMS_PROPS = "Microsoft.NET.Sdk.WindowsDesktop/targets/Microsoft.NET.Sdk.WindowsDesktop.WindowsForms.props"
_WPF_PROPS = "Microsoft.NET.Sdk.WindowsDesktop/targets/Microsoft.NET.Sdk.WindowsDesktop.WPF.props"

# Every project imports the C# props first, then its SDK's, then the Windows
# desktop props, whose items are conditioned on `UseWPF` and `UseWindowsForms`.
_DESKTOP_PROPS = [_WINFORMS_PROPS, _WPF_PROPS]

SDK_IMPLICIT_USINGS_PROPS = {
    BLAZORWASM_SDK: [_CSHARP_PROPS, _BLAZORWASM_PROPS] + _DESKTOP_PROPS,
    DEFAULT_SDK: [_CSHARP_PROPS] + _DESKTOP_PROPS,
    RAZOR_SDK: [_CSHARP_PROPS] + _DESKTOP_PROPS,
    WEB_SDK: [_CSHARP_PROPS, _WEB_PROPS] + _DESKTOP_PROPS,
}

# The file that every project imports. An SDK without it has no implicit usings
# rules_dotnet knows how to read.
SDK_IMPLICIT_USINGS_BASE_PROPS = _CSHARP_PROPS

_ALL_PROPS = [_CSHARP_PROPS, _WEB_PROPS, _BLAZORWASM_PROPS] + _DESKTOP_PROPS

# The attributes of a `Using` item that rules_dotnet understands. `Alias` and
# `Static` change the directive written, so an SDK item with them is reported
# rather than written as a plain `global using`.
_KNOWN_USING_ATTRS = ["Include", "Remove", "Condition"]

def extract_using_items(content):
    """The evaluation-time `Using` items of a props file.

    Args:
        content: The props file's contents.

    Returns:
        A dict with `items`, each `{"op", "namespace", "conditions"}`, and
        `unsupported`, a message for an item rules_dotnet cannot represent, or
        "".
    """
    items = []
    unsupported = []

    # Walk the whole document so that an item somewhere rules_dotnet does not
    # look, such as under a `Choose`, is reported instead of missed.
    root = xml.parse(content)
    stack = [(root, [])] if root else []
    for _ in range(len(content)):
        if not stack:
            break
        (node, ancestors) = stack.pop()
        name = xml.local_name(node)
        if name == "Target":
            continue

        if name == "Using":
            if [xml.local_name(a) for a in ancestors] != ["Project", "ItemGroup"]:
                unsupported.append("a Using item under {}".format("/".join([xml.local_name(a) for a in ancestors])))
                continue

            extra = sorted([a for a in node["attrs"].keys() if a not in _KNOWN_USING_ATTRS])
            include = xml.attr(node, "Include")
            remove = xml.attr(node, "Remove")
            if extra or (include == "") == (remove == ""):
                unsupported.append("<Using {}>".format(" ".join(["{}=\"{}\"".format(k, v) for (k, v) in sorted(node["attrs"].items())])))
                continue

            conditions = [c for c in [xml.attr(ancestors[-1], "Condition"), xml.attr(node, "Condition")] if c]
            for namespace in (include or remove).split(";"):
                namespace = namespace.strip()
                if namespace:
                    items.append({
                        "conditions": conditions,
                        "namespace": namespace,
                        "op": "include" if include else "remove",
                    })
            continue

        for child in reversed(node["children"]):
            stack.append((child, ancestors + [node]))

    return {"items": items, "unsupported": "; ".join(unsupported)}

def read_sdk_implicit_usings(repository_ctx, sdks_dir):
    """Reads the `Using` items out of an extracted SDK's props files.

    Args:
        repository_ctx: The repository context of the SDK repository.
        sdks_dir: The SDK's `Sdks` directory, relative to the repository.

    Returns:
        A JSON string mapping each props file found, relative to `Sdks`, to
        its items, for `dotnet_toolchain`'s `implicit_usings`.
    """
    props = {}
    for path in _ALL_PROPS:
        file = repository_ctx.path("{}/{}".format(sdks_dir, path))
        if file.exists:
            props[path] = extract_using_items(repository_ctx.read(file))
    return json.encode(props)
