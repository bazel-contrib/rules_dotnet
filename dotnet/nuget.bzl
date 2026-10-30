"""The `nuget` module extension.

Resolves NuGet packages transitively — the same graph resolution as
`dotnet restore` — and optionally pins the result in a checked-in
`nuget_resolve.json`:

```starlark
nuget = use_extension("@rules_dotnet//dotnet:nuget.bzl", "nuget")
nuget.resolve(
    name = "nuget",
    packages = {
        "Newtonsoft.Json": "13.0.3",
        "Serilog": "4.0.0",
    },
    frameworks = ["net8.0", "net10.0"],
    lock_file = "//:nuget_resolve.json",
)
use_repo(nuget, "nuget.net8.0", "nuget.net10.0")
```

Each target framework becomes its own repository, so a package in the
`net10.0` framework is addressed as `@nuget.net10.0//<package-id-lowercase>`.

Without `lock_file` every fetch resolves fresh. Create or refresh the lock
file with `REPIN=1 bazel run @nuget.net10.0//:pin` and check it in.
"""

load("//dotnet/private/nuget_resolve:extension.bzl", _nuget = "nuget")

nuget = _nuget
