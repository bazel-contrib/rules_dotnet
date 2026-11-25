"""Compiles WPF XAML with the SDK's PresentationBuildTasks, as Microsoft.WinFX.targets does.

1. MarkupCompilePass1 generates the code behind each XAML file, and BAML for
   those that name no type of the assembly being built.
2. The sources and that code are compiled into a temporary assembly, which
   MarkupCompilePass2 compiles the remaining XAML against. Whether it is needed
   is only known after pass1, so it is always compiled.
3. ResourcesGenerator embeds the BAML and WPF resources in
   `<assembly name>.g.resources`.

The tasks run in the package's directory, as MSBuild runs them in the
project's: they write a XAML file's output under its path below that
directory, or under its file name alone if it is outside it, as a generated
file is. Its BAML is still embedded under its `package_path`, the URI WPF
loads it by.
"""

load("//dotnet/private:common.bzl", "UNREFERENCEABLE_ASSEMBLIES")
load("//dotnet/private/sdk:packs.bzl", "WINDOWSDESKTOP_FRAMEWORK")

# The application definition a C# project picks up implicitly.
_APPLICATION_DEFINITION = "App.xaml"

_TASKS_ASSEMBLY = "PresentationBuildTasks.dll"

# What Microsoft.WinFX.targets passes as `OutputType`.
_OUTPUT_TYPES = {
    "exe": "Exe",
    "library": "Library",
    "winexe": "WinExe",
}

def _build_tasks(toolchain, label):
    """PresentationBuildTasks, and the assemblies it loads from the SDK."""
    files = toolchain.wpf_build_tasks.files if getattr(toolchain, "wpf_build_tasks", None) else depset()
    tasks = None
    dependencies = []
    for file in files.to_list():
        if file.basename == _TASKS_ASSEMBLY:
            tasks = file
        else:
            dependencies.append(file)

    if tasks == None:
        fail(
            "the resolved .NET toolchain provides no %s, so %s cannot compile XAML.\n" % (_TASKS_ASSEMBLY, label) +
            "The SDK is expected to carry it under Sdks/Microsoft.NET.Sdk.WindowsDesktop/tools.",
        )

    return struct(tasks = tasks, dependencies = dependencies, files = files)

def _uses_wpf(frameworks):
    """Whether Microsoft.WindowsDesktop.App is referenced whole or with the WPF profile."""
    if WINDOWSDESKTOP_FRAMEWORK not in frameworks:
        return False

    profiles = frameworks[WINDOWSDESKTOP_FRAMEWORK]
    return profiles == None or "WPF" in profiles

def check_wpf(label, frameworks, target_framework_is_core, what, target_framework_is_netfx = False):
    """Fails unless a target that compiles WPF XAML or resources references WPF.

    Args:
      label: The label of the target.
      frameworks: Its shared frameworks, as `resolve_framework_references` returns them.
      target_framework_is_core: Whether it is built for .NET Core or .NET.
      what: What it has, for the message.
      target_framework_is_netfx: Whether it is built for .NET Framework 3.5+, which includes WPF.
    """
    if target_framework_is_netfx:
        return

    if not target_framework_is_core:
        fail("%s: %s are only compiled for .NET Core 3.0 and later or .NET Framework 3.5 and later." % (label, what))

    if not _uses_wpf(frameworks):
        fail(
            "%s has %s but does not reference WPF: add \"Microsoft.WindowsDesktop.App.WPF\" " % (label, what) +
            "or \"Microsoft.WindowsDesktop.App\" to its `framework_references`.",
        )

def package_path(file, label):
    """A file's path relative to the package, or its file name if it is outside it.

    It names the file's BAML or resource, and the URI WPF loads it by.

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

def xaml_plan(label, xaml_srcs, frameworks, target_framework_is_core, target_framework_is_netfx = False):
    """Checks a target's XAML sources and splits them into the application definition and the pages.

    Args:
      label: The label of the target.
      xaml_srcs: The `.xaml` files among its `srcs`.
      frameworks: Its shared frameworks, as `resolve_framework_references` returns them.
      target_framework_is_core: Whether it is built for .NET Core or .NET.
      target_framework_is_netfx: Whether it is built for .NET Framework 3.5+, which includes WPF.

    Returns:
      A struct of the `application` definition, or None, and the `pages`.
    """
    check_wpf(label, frameworks, target_framework_is_core, "XAML sources", target_framework_is_netfx = target_framework_is_netfx)
    _check_unique_names(
        label,
        [(src, _compiled_path(src, label) + ".baml") for src in xaml_srcs],
        "compile to",
        "The markup compiler places a XAML file from outside the package's directory, such as a generated one, by its file name alone",
    )

    application = None
    pages = []
    for src in xaml_srcs:
        if _path_in_package(src, label) == _APPLICATION_DEFINITION:
            application = src
        else:
            pages.append(src)

    return struct(application = application, pages = pages)

def _xaml_files(plan):
    return plan.pages + ([plan.application] if plan.application else [])

def _compiled_path(file, label):
    """Where the markup compiler writes a XAML file's output, lowercased and without extension."""
    project_dir = _project_dir(label)
    prefix = "" if project_dir == "." else project_dir + "/"
    path = file.path[len(prefix):]
    if not file.path.startswith(prefix) or path.startswith("../"):
        path = file.basename

    return _without_extension(path).lower()

def _without_extension(path):
    return path.rpartition(".")[0] if "." in path.rpartition("/")[2] else path

def _check_unique_names(label, named_files, collision, why):
    """Fails if two files take the same name, which the build tasks compare case-insensitively.

    Args:
      label: The label of the target.
      named_files: A list of (file, name) tuples.
      collision: What sharing the name does to them, for the message.
      why: Why names can collide, for the message.
    """
    files = {}
    for (file, name) in named_files:
        key = name.lower()
        if key in files:
            fail("{}: {} and {} would both {} {}. {}; rename one of them.".format(
                label,
                files[key].short_path,
                file.short_path,
                collision,
                key,
                why,
            ))
        files[key] = file

def _named(files, label):
    """Each file with the name it takes in the assembly, as the tool reads them."""
    return ["{}|{}".format(file.path, package_path(file, label)) for file in files]

def _project_dir(label):
    """The directory the tasks run in, as MSBuild runs them in the project's."""
    return "/".join([part for part in [label.workspace_root, label.package] if part]) or "."

def _reference_path(assembly):
    return None if assembly.path.endswith(UNREFERENCEABLE_ASSEMBLIES) else assembly.path

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
    args.add_all(references, map_each = _reference_path, before_each = "--reference")

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
        inputs = depset(_xaml_files(plan) + srcs, transitive = [references, tasks.files]),
        outputs = [output],
    )

    return output

def xaml_pass2(actions, label, plan, pass1, temporary_assembly, wpf_resources, out_dir, assembly_name, root_namespace, target, references, tool, toolchain):
    """Runs MarkupCompilePass2 if pass1 needs it, then ResourcesGenerator.

    Without XAML, only ResourcesGenerator runs.

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
    xaml = _xaml_files(plan) if plan else []

    # ResourcesGenerator fails on a duplicate name without saying which files have it.
    _check_unique_names(
        label,
        [(src, _without_extension(package_path(src, label)) + ".baml") for src in xaml] +
        [(resource, package_path(resource, label)) for resource in wpf_resources],
        "be embedded as",
        "Names are compared case-insensitively, and a file from outside the package's directory is named by its file name alone",
    )

    tasks = _build_tasks(toolchain, label)
    output = actions.declare_directory("{}/xaml/obj".format(out_dir))
    resources = actions.declare_file("{}/xaml/{}.g.resources".format(out_dir, assembly_name))

    # Pass2 compiles the XAML that pass1 left for it from source, against the
    # temporary assembly and everything that references.
    references = depset([temporary_assembly], transitive = [references]) if xaml else depset()

    args = _common_args(actions, label, tasks, assembly_name, root_namespace, target, references)
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
        inputs = depset(
            ([pass1] if pass1 else []) + xaml + wpf_resources,
            transitive = [references, tasks.files],
        ),
        outputs = [output, resources],
    )

    return struct(code = output if xaml else None, resources = resources)

def generated_code(file):
    """`map_each` for a XAML output directory: only the code the compiler takes."""
    return file.path if file.path.endswith(".g.cs") else None
