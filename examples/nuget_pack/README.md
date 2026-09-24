# Example.Greeter

Greets people. Built and packed with [rules_dotnet](https://github.com/bazel-contrib/rules_dotnet).

```csharp
Console.WriteLine(Example.Greeter.Greet("Ada", "Grace"));
```

This directory also holds a source generator packed as an analyzer package, a
Razor class library packed with the files it serves, a package built once per
runtime identifier, and two versionings of one library - a release candidate
through `version` and a stamped nightly through `version_file`. It shows how a
package is built and published:

```sh
bazel build //nuget_pack/...                              # the .nupkg files
bazel run //nuget_pack:push -- --source ./local-feed      # into a folder
NUGET_API_KEY=... bazel run //nuget_pack:push             # to nuget.org
dotnet tool install --add-source ./local-feed --tool-path ./tools Example.Greet && ./tools/greet
```

A package version that comes out of a stamp needs a workspace status command:

```sh
bazel build --workspace_status_command=nuget_pack/version.sh //nuget_pack:formatting_nightly
```
