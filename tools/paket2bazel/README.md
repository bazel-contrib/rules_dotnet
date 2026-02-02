# paket2bazel

`paket2bazel` is a tool for parsing [Paket](https://fsprojects.github.io/Paket/) dependencies files

Paket fits well with Bazel because it generates a `paket.lock` file that can be used
to deterministically generate Bazel targets for NuGet packages.

## Bazel MODULE

The first steps are creating a `paket.dependencies` file to then use `paket` to generate a `paket.lock` file. Both are required to generate a local Bazel extension for use in `MODULE.bazel`.

To generate the `paket.lock` file, these steps work on Linux systems:
- `curl -L https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh`
- `chmod +x dotnet-install.sh`
- `./dotnet-install.sh --version [#.#.###]`
- `export DOTNET_ROOT=$HOME/.dotnet`
- `export PATH=$PATH:$HOME/.dotnet`
- `dotnet new tool-manifest`
- `dotnet tool install paket`
- `dotnet paket install`

NOTE: This expects the `paket.dependencies` file to live in the root folder.

After generating the `paket.lock` file, you can then generate the required Bazel extension with:
```sh
bazel run @rules_dotnet//tools/paket2bazel -- --dependencies-file $(pwd)/paket.dependencies  --output-folder $(pwd)/deps
```

Add an empty `BUILD` file to `($pwd)` so that Bazel recognizes the folder as part of its domain.

Now there should be a `paket.bzl` and `paket.extensions.bzl` in the root folder. This may also appear as `paket.main.bzl` and `paket.main_extensions.bzl` where each group is labeled in the same pattern.

In your `MODULE.bazel` file, the following exposes the dependencies for consumption in BUILD files:
```starlark
main_extension = use_extension("//deps:paket.main_extension.bzl", "main_extension")
use_repo(main_extension, "paket.main")
```

## Bazel WORKSPACES (Legacy, Bazel <8.0.0)

First you need to set up your paket.dependencies and paket.lock file. See the [Paket docs](https://fsprojects.github.io/Paket/) on how to get started with Paket.

Next you will have to add the following to your `WORKSPACE` file:

```python
load("@rules_dotnet//dotnet:paket2bazel_dependencies.bzl", "paket2bazel_dependencies")

paket2bazel_dependencies()
```

Then you needs to run `paket2bazel` to generate the `paket.bzl` file which will be
loaded in your `WORKSPACE` file.

```sh
bazel run @rules_dotnet//tools/paket2bazel -- --dependencies-file $(pwd)/paket.dependencies  --output-folder $(pwd)/deps
```

Next you need to add the following to your `WORKSPACE` file

```python
load("//OUTPUT_FOLDER:paket.bzl", "paket")
paket()
```

Once you have this set up you can reference each package with the following format:

If you only have the main Paket group in `paket.dependencies` file:

```
@main.package.name//:lib
```

If you are using groups in your `paket.dependencies` file:

```
@groupname.package.name//:lib
```

Full examples can be seen in the `examples/paket` directory in this repository.
