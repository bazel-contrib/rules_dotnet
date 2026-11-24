"""WPF XAML: pages and an application definition compiled into the assembly.

`//dotnet/private/tools/xaml` runs the SDK's own PresentationBuildTasks the way
Microsoft.WinFX.targets does:

1. MarkupCompilePass1 generates the code behind every XAML file, and compiles
   to BAML every one that names no type of the assembly being built.
2. If any does, the sources are compiled into a temporary assembly together
   with that code, as GenerateTemporaryTargetAssembly does, and
   MarkupCompilePass2 compiles the rest against it.
3. ResourcesGenerator embeds every BAML file and WPF resource in
   `<assembly name>.g.resources`.

The compilation then takes the generated code as sources and embeds the
resources. Whether a project needs the temporary assembly only shows once pass1
has run, so it is always compiled.
"""

load("//dotnet/private/sdk:packs.bzl", "WINDOWSDESKTOP_FRAMEWORK")

# What MSBuild calls the application definition a C# project picks up by
# itself: the `App.xaml` at the root of the project.
_APPLICATION_DEFINITION = "App.xaml"

_TASKS_ASSEMBLY = "PresentationBuildTasks.dll"

# What Microsoft.WinFX.targets passes as `OutputType`.
_OUTPUT_TYPES = {
    "exe": "Exe",
    "library": "Library",
    "winexe": "WinExe",
}

def _build_tasks(toolchain, label):
    tasks = None
    dependencies = []
    for file in toolchain.wpf_build_tasks.files.to_list() if getattr(toolchain, "wpf_build_tasks", None) else []:
        if file.basename == _TASKS_ASSEMBLY:
            tasks = file
        else:
            # What the tasks load from the SDK rather than from beside them.
            dependencies.append(file)

    if tasks == None:
        fail(
            "the resolved .NET toolchain provides no %s, so %s cannot compile XAML.\n" % (_TASKS_ASSEMBLY, label) +
            "The SDK is expected to carry it under Sdks/Microsoft.NET.Sdk.WindowsDesktop/tools.",
        )

    return struct(tasks = tasks, dependencies = dependencies)

def uses_wpf(frameworks):
    """Whether a target references WPF, which XAML compiles against.

    Args:
      frameworks: The shared frameworks, as `resolve_framework_references` returns them.

    Returns:
      True if Microsoft.WindowsDesktop.App is referenced whole or with the WPF profile.
    """
    if WINDOWSDESKTOP_FRAMEWORK not in frameworks:
        return False

    profiles = frameworks[WINDOWSDESKTOP_FRAMEWORK]
    return profiles == None or "WPF" in profiles

def check_wpf(label, frameworks, target_framework_is_core, what):
    """Fails unless a target that compiles WPF XAML or resources references WPF.

    Args:
      label: The label of the target.
      frameworks: Its shared frameworks.
      target_framework_is_core: Whether it is built for .NET Core or .NET.
      what: What it has, for the message.
    """
    if not target_framework_is_core:
        fail("%s: %s are only compiled for .NET Core 3.0 and later." % (label, what))

    if not uses_wpf(frameworks):
        fail(
            "%s has %s but does not reference WPF: add \"Microsoft.WindowsDesktop.App.WPF\" " % (label, what) +
            "or \"Microsoft.WindowsDesktop.App\" to its `framework_references`.",
        )

def package_path(file, label):
    """A file's path relative to the target's package: MSBuild's path relative to the project.

    It names the file's BAML or resource, and the URI WPF loads it by. A file
    generated into the package is named as its source would be. One from
    outside the package is named by its file name, as MSBuild names a file
    from outside the project.

    Args:
      file: A XAML source or WPF resource.
      label: The label of the target.

    Returns:
      The path, with forward slashes.
    """

    return _path_in_package(file, label) or file.basename

def _path_in_package(file, label):
    """A file's path relative to the target's package, or None if it is outside it."""

    # A file reaches `short_path` as `<package>/<rel>`, or as
    # `../<repo>/<package>/<rel>` when it comes from another repository.
    prefix = "../%s/" % label.repo_name if label.repo_name else ""
    if label.package:
        prefix += label.package + "/"

    path = file.short_path[len(prefix):]
    if not file.short_path.startswith(prefix) or path.startswith("../"):
        return None

    return path

def xaml_plan(label, xaml_srcs, frameworks, target_framework_is_core):
    """Splits XAML sources into the application definition and the pages.

    Args:
      label: The label of the target.
      xaml_srcs: The `.xaml` files among its `srcs`.
      frameworks: Its shared frameworks.
      target_framework_is_core: Whether it is built for .NET Core or .NET.

    Returns:
      A struct of the `application` definition, or None, and the `pages`.
    """
    check_wpf(label, frameworks, target_framework_is_core, "XAML sources")

    application = None
    pages = []
    for src in xaml_srcs:
        if _path_in_package(src, label) == _APPLICATION_DEFINITION:
            application = src
        else:
            pages.append(src)

    return struct(application = application, pages = pages)

def _named(files, label):
    """Each file with the name it takes in the assembly, as the tool reads them."""
    return ["{}|{}".format(file.path, package_path(file, label)) for file in files]

def _project_dir(label):
    """The directory the tasks run in, as MSBuild runs them in the project's."""
    return "/".join([part for part in [label.workspace_root, label.package] if part]) or "."

def _common_args(actions, label, tasks, assembly_name, root_namespace, target, references):
    args = actions.args()
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    args.add("--tasks", tasks.tasks)
    args.add_all(tasks.dependencies, before_each = "--task-dependency")
    args.add("--project-dir", _project_dir(label))
    args.add("--assembly-name", assembly_name)
    args.add("--root-namespace", root_namespace)
    args.add("--output-type", _OUTPUT_TYPES[target])
    args.add_all(references, before_each = "--reference")

    return args

def xaml_pass1(actions, label, plan, srcs, out_dir, assembly_name, root_namespace, target, defines, references, tool, toolchain):
    """Runs MarkupCompilePass1.

    Args:
      actions: The rule's `ctx.actions`.
      label: The label of the target.
      plan: From `xaml_plan`.
      srcs: The C# sources.
      out_dir: The target's output directory prefix.
      assembly_name: The assembly name.
      root_namespace: MSBuild's `RootNamespace`.
      target: `library`, `exe` or `winexe`.
      defines: The preprocessor symbols.
      references: A depset of the assemblies the compilation references.
      tool: The `xaml` tool.
      toolchain: The resolved .NET toolchain.

    Returns:
      The directory of what pass1 generated.
    """
    tasks = _build_tasks(toolchain, label)
    output = actions.declare_directory("{}/xaml/pass1".format(out_dir))

    args = _common_args(actions, label, tasks, assembly_name, root_namespace, target, references)
    args.add("--output-dir", output.path)
    args.add_all(_named(plan.pages, label), before_each = "--page")
    if plan.application:
        args.add("--application", _named([plan.application], label)[0])
    args.add_all(srcs, before_each = "--source")
    args.add_all(defines, before_each = "--define")

    actions.run(
        mnemonic = "XamlCompilePass1",
        progress_message = "Compiling XAML for %{label}",
        executable = tool.files_to_run,
        arguments = ["pass1", args],
        inputs = depset(
            direct = plan.pages + ([plan.application] if plan.application else []) + srcs,
            transitive = [references, toolchain.wpf_build_tasks.files],
        ),
        outputs = [output],
    )

    return output

def xaml_pass2(actions, label, plan, pass1, temporary_assembly, wpf_resources, out_dir, assembly_name, root_namespace, target, references, tool, toolchain):
    """Runs MarkupCompilePass2 where pass1 asks for it, then ResourcesGenerator.

    Without XAML, only ResourcesGenerator runs, as MSBuild embeds `<Resource>`
    items whether or not there is any.

    Args:
      actions: The rule's `ctx.actions`.
      label: The label of the target.
      plan: From `xaml_plan`, or None without XAML.
      pass1: What `xaml_pass1` returned, or None without XAML.
      temporary_assembly: The sources and pass1's code compiled together, or None without XAML.
      wpf_resources: The `wpf_resources` to embed.
      out_dir: The target's output directory prefix.
      assembly_name: The assembly name.
      root_namespace: MSBuild's `RootNamespace`.
      target: `library`, `exe` or `winexe`.
      references: A depset of the assemblies the compilation references.
      tool: The `xaml` tool.
      toolchain: The resolved .NET toolchain.

    Returns:
      A struct of the generated `code` directory, whose `.g.cs` files the
      compilation takes as sources, or None without XAML, and the `resources`
      file it embeds.
    """
    tasks = _build_tasks(toolchain, label)
    output = actions.declare_directory("{}/xaml/obj".format(out_dir))
    resources = actions.declare_file("{}/xaml/{}.g.resources".format(out_dir, assembly_name))
    xaml = (plan.pages + ([plan.application] if plan.application else [])) if plan else []

    args = _common_args(
        actions,
        label,
        tasks,
        assembly_name,
        root_namespace,
        target,
        depset([temporary_assembly] if temporary_assembly else [], transitive = [references] if xaml else []),
    )
    if pass1:
        args.add("--pass1-dir", pass1.path)
    args.add("--output-dir", output.path)
    args.add("--resources-file", resources.path)

    # The XAML again, so that each BAML file is named as its source.
    args.add_all(_named(xaml, label), before_each = "--page")
    args.add_all(_named(wpf_resources, label), before_each = "--resource")

    actions.run(
        mnemonic = "XamlCompilePass2" if xaml else "WpfResources",
        progress_message = ("Compiling XAML that names local types for %{label}" if xaml else "Embedding WPF resources for %{label}"),
        executable = tool.files_to_run,
        arguments = ["pass2", args],
        # Pass2 compiles the XAML that pass1 left for it from source.
        inputs = depset(
            direct = ([pass1, temporary_assembly] if pass1 else []) + xaml + wpf_resources,
            transitive = ([references] if xaml else []) + [toolchain.wpf_build_tasks.files],
        ),
        outputs = [output, resources],
    )

    return struct(code = output if xaml else None, resources = resources)

def generated_code(file):
    """`map_each` for a XAML output directory: only the code the compiler takes."""
    return file.path if file.path.endswith(".g.cs") else None
