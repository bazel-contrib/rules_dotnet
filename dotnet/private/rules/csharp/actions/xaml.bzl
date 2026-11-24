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
    if not target_framework_is_core:
        fail("%s: XAML is only compiled for .NET Core 3.0 and later." % label)

    if not uses_wpf(frameworks):
        fail(
            "%s has XAML sources but does not reference WPF: add \"Microsoft.WindowsDesktop.App.WPF\" " % label +
            "or \"Microsoft.WindowsDesktop.App\" to its `framework_references`. XAML sources: %s" % (
                ", ".join([src.short_path for src in xaml_srcs]),
            ),
        )

    application = None
    pages = []
    for src in xaml_srcs:
        if src.basename == _APPLICATION_DEFINITION and src.short_path == "{}/{}".format(label.package, _APPLICATION_DEFINITION).lstrip("/"):
            application = src
        else:
            pages.append(src)

    return struct(application = application, pages = pages)

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
    args.add_all(plan.pages, before_each = "--page")
    if plan.application:
        args.add("--application", plan.application)
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

    Args:
      actions: The rule's `ctx.actions`.
      label: The label of the target.
      plan: From `xaml_plan`.
      pass1: What `xaml_pass1` returned.
      temporary_assembly: The sources and pass1's code compiled together.
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
      compilation takes as sources, and the `resources` file it embeds.
    """
    tasks = _build_tasks(toolchain, label)
    output = actions.declare_directory("{}/xaml/obj".format(out_dir))
    resources = actions.declare_file("{}/xaml/{}.g.resources".format(out_dir, assembly_name))

    args = _common_args(actions, label, tasks, assembly_name, root_namespace, target, depset([temporary_assembly], transitive = [references]))
    args.add("--pass1-dir", pass1.path)
    args.add("--output-dir", output.path)
    args.add("--resources-file", resources.path)
    args.add_all(wpf_resources, before_each = "--resource")

    actions.run(
        mnemonic = "XamlCompilePass2",
        progress_message = "Compiling XAML that names local types for %{label}",
        executable = tool.files_to_run,
        arguments = ["pass2", args],
        # Pass2 compiles the XAML that pass1 left for it from source.
        inputs = depset(
            direct = [pass1, temporary_assembly] + plan.pages + ([plan.application] if plan.application else []) + wpf_resources,
            transitive = [references, toolchain.wpf_build_tasks.files],
        ),
        outputs = [output, resources],
    )

    return struct(code = output, resources = resources)

def generated_code(file):
    """`map_each` for a XAML output directory: only the code the compiler takes."""
    return file.path if file.path.endswith(".g.cs") else None
