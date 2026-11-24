"""The `paket` module extension.

Point it at a [Paket](https://fsprojects.github.io/Paket/) lock file to make
its NuGet packages available to Bazel:

```starlark
paket = use_extension("@rules_dotnet//dotnet:paket.bzl", "paket")
paket.parse(
    dependencies = "//:paket.dependencies",
    lock = "//:paket.lock",
)
use_repo(paket, "paket.main")
```

Each dependency group becomes its own repository, so a package in the `Main`
group is `@paket.main//fsharp.core` and one in a `Build` group is
`@paket.build//fake.core`. A dotnet tool package's commands can be run as
`@paket.<group>//<package>/tools:<command>`. Run `bazel mod tidy` to keep the
`use_repo` call in step with the groups in the lock file.
"""

load("//dotnet/private/paket:extension.bzl", _paket = "paket")

paket = _paket
