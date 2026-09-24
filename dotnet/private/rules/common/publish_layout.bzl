"""The file layout of a framework-dependent or self-contained publish.

Shared by `publish_binary`, which copies the layout into a directory, and
`nuget_pack`, which puts the same tree under `tools/<tfm>/any/` in a tool
package.
"""

load("//dotnet/private:common.bzl", "runtime_target_path")

def publish_layout(runtime_identifier, binary_info, assembly_files, runtime_pack_files, is_self_contained):
    """Every published file paired with the path it takes inside the publish directory.

    The directory is flat apart from resource assemblies, the servable `wwwroot`
    tree and, unless the publish is self-contained, native libraries.

    Args:
      runtime_identifier: The RID the binary is published for.
      binary_info: The `DotnetBinaryInfo` of the binary.
      assembly_files: The struct `collect_assembly_files` returns.
      runtime_pack_files: The runtime pack's files, as structs of `libs`, `native`
        and `data`; empty unless the publish is self-contained.
      is_self_contained: Whether the runtime is published alongside the binary.

    Returns:
      A list of `(path, File)` pairs, the path relative to the publish directory.
    """
    layout = [(binary_info.dll.basename, binary_info.dll)]

    for file in assembly_files.libs + assembly_files.appsetting_files:
        layout.append((file.basename, file))

    # Resource assemblies go in a folder named after their locale, so that a
    # German one lands at `de/MyAssembly.resources.dll`.
    for file in assembly_files.resource_assemblies:
        layout.append(("{}/{}".format(file.dirname.split("/")[-1], file.basename), file))

    for file in assembly_files.native:
        if is_self_contained:
            # A self-contained publish carries native libraries next to the main DLL.
            layout.append((file.basename, file))
        else:
            # Everything else goes under runtimes/{rid}/native/. A native
            # library from a NuGet package carries its RID in its path; one we
            # built ourselves does not, but is by definition built for our RID.
            # Files inside a NuGet package are modelled as source files, which
            # is what tells the two apart.
            rid = file.dirname.split("/")[-2] if file.is_source else runtime_identifier
            layout.append(("runtimes/{}/native/{}".format(rid, file.basename), file))

    # A self-contained publish carries the runtime pack at the root of the
    # publish folder.
    for pack in runtime_pack_files:
        for file in pack.libs + pack.native + pack.data:
            layout.append((file.basename, file))

    # The servable tree, and the manifest describing it, keep the shape the
    # binary already gave them: `wwwroot/...` with the endpoint manifest beside
    # the assembly, which is what a published ASP.NET Core application expects.
    for entry in binary_info.static_web_files:
        layout.append((entry.publish_path, entry.file))

    return layout

def reject_conflicting_paths(layout, label, what = "published"):
    """Fails when two files the build produces would take the same path.

    Only files the build produces, because only their name can be changed. A
    file out of a NuGet package keeps the behaviour of the compile actions: a
    duplicate assembly identity is resolved by order rather than rejected.

    Args:
      layout: A list of `(path, File)` pairs.
      label: The label of the target being laid out, for the message.
      what: The verb for the message: the files are both "published" or "packed".
    """
    built = {}

    for (path, file) in layout:
        if file.is_source:
            continue

        previous = built.setdefault(path, file)

        if previous.path != file.path:
            fail(("{}: {} and {} are both {} as \"{}\".\n\n" +
                  "Only one file can take a path, so only one of them can be there. " +
                  "Set `out` on one of them to give its assembly a different " +
                  "file name.").format(label, previous.owner, file.owner, what, path))

def collect_assembly_files(assembly_info, transitive_runtime_deps, deps_json_struct):
    """The files a publish copies, gathered from the target and its deps.

    Args:
      assembly_info: The `DotnetAssemblyRuntimeInfo` of the binary.
      transitive_runtime_deps: The `DotnetAssemblyRuntimeInfo`s of its transitive dependencies.
      deps_json_struct: The generated `deps.json`, which says which of a
        dependency's files the runtime will load.

    Returns:
      A struct of `libs`, `resource_assemblies`, `native`, `data` and
      `appsetting_files` lists.
    """
    libs = list(assembly_info.libs)
    resource_assemblies = list(assembly_info.resource_assemblies)
    native_files = list(assembly_info.native)
    data = list(assembly_info.data)
    targets = deps_json_struct["targets"].values()[0]

    for dep in transitive_runtime_deps:
        # A file missing from the deps.json is not published: the runtime pack
        # may be providing it instead of the dependency.
        target = targets.get("{}/{}".format(dep.name, dep.version))

        if target:
            dep_native = target.get("native", {})
            runtime_targets = target.get("runtimeTargets", {})
            runtime = target.get("runtime", {})

            # `native` is keyed by basename, `runtimeTargets` by the path the
            # asset takes inside the publish.
            for file in dep.native:
                if file.basename in dep_native or runtime_targets.get(runtime_target_path(file), {}).get("assetType") == "native":
                    native_files.append(file)

            for file in dep.libs:
                if file.basename in runtime:
                    libs.append(file)

        data += dep.data
        resource_assemblies += dep.resource_assemblies

    return struct(
        libs = libs,
        resource_assemblies = resource_assemblies,
        native = native_files,
        data = data,
        appsetting_files = assembly_info.appsetting_files.to_list(),
    )
