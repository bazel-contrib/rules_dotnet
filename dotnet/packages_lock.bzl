"""The `packages_lock` module extension.

Point it at a [NuGet `packages.lock.json`](https://learn.microsoft.com/nuget/consume-packages/package-references-in-project-files#locking-dependencies)
file to make its packages available to Bazel:

```starlark
packages_lock = use_extension("@rules_dotnet//dotnet:packages_lock.bzl", "packages_lock")
packages_lock.parse(lock = "//:packages.lock.json")
use_repo(packages_lock, "nuget.net10.0")
```

Each target framework becomes its own repository, so a package in the `net10.0`
framework is addressed as `@nuget.net10.0//<package>`.
"""

load("//dotnet/private/packages_lock:extension.bzl", _packages_lock = "packages_lock")

packages_lock = _packages_lock
