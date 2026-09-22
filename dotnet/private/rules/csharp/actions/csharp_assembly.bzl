"""
Actions for compiling targets with C#.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:common.bzl",
    "add_resource_args",
    "collect_compile_info",
    "copy_files_to_dir",
    "format_ref_arg",
    "framework_preprocessor_symbols",
    "generate_warning_args",
    "get_framework_version_info",
    "use_highentropyva",
)
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
    "StaticWebAssetsInfo",
)
load("//dotnet/private/icu:settings.bzl", "globalization_env", "icu_wrapper_arguments")
load(
    "//dotnet/private/rules/csharp/actions:razor.bzl",
    "partition_srcs",
    "razor_compile_inputs",
)
load("//dotnet/private/rules/csharp/actions:scoped_css.bzl", "scoped_css_action")
load("//dotnet/private/sdk:packs.bzl", "uses_razor")

def _write_internals_visible_to_csharp(actions, label_name, dll_name, others):
    """Write a .cs file containing InternalsVisibleTo attributes.

    Letting Bazel see which assemblies we are going to have InternalsVisibleTo
    allows for more robust caching of compiles.

    Args:
      actions: An actions module, usually from ctx.actions.
      label_name: The label name.
      dll_name: The assembly name.
      others: The names of other assemblies.

    Returns:
      A File object for a generated .cs file
    """

    if len(others) == 0:
        return None

    attrs = actions.args()
    attrs.set_param_file_format(format = "multiline")

    attrs.add_all(
        others,
        format_each = "[assembly: System.Runtime.CompilerServices.InternalsVisibleTo(\"%s\")]",
    )

    output = actions.declare_file("%s/%s/internalsvisibleto.cs" % (label_name, dll_name))

    actions.write(output, attrs)

    return output

def _collect_analyzer_dependencies(deps):
    """Collect the runtime libraries of this analyzer. These will be passed to the compiler.

    Args:
        deps: The list of dependencies of the analyzer.

    Returns:
        The list of analyzer dependencies.
    """

    dlls = []
    for dep in deps:
        runtime_info = dep[DotnetAssemblyRuntimeInfo]

        # FIXME: Should this respect `not strict_deps`?
        dlls.extend(runtime_info.libs)
    return dlls

# buildifier: disable=unnamed-macro
def AssemblyAction(
        actions,
        compiler_wrapper,
        compiler_worker,
        label,
        additionalfiles,
        debug,
        embed_sources,
        defines,
        deps,
        exports,
        targeting_pack,
        internals_visible_to,
        keyfile,
        langversion,
        resources,
        srcs,
        data,
        appsetting_files,
        compile_data,
        out,
        target,
        target_name,
        target_framework,
        toolchain,
        strict_deps,
        generate_documentation_file,
        include_host_model_dll,
        include_msbuild_dlls,
        treat_warnings_as_errors,
        warnings_as_errors,
        warnings_not_as_errors,
        warning_level,
        nowarn,
        project_sdk,
        root_namespace,
        scoped_css_tool,
        allow_unsafe_blocks,
        nullable,
        run_analyzers,
        is_analyzer,
        is_language_specific_analyzer,
        analyzer_configs,
        compiler_options,
        interceptors_namespaces,
        is_windows):
    """Creates an action that runs the CSharp compiler with the specified inputs.

    This macro aims to match the [C# compiler](https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-options/listed-alphabetically), with the inputs mapping to compiler options.

    Args:
        actions: Bazel module providing functions to create actions.
        compiler_wrapper: The wrapper script that invokes the C# compiler.
        compiler_worker: The persistent worker to compile with, or None to fall back to the wrapper script.
        label: The label of the target. This is used to determine the relative path of embedded resources.
        additionalfiles: Names additional files that don't directly affect code generation but may be used by analyzers for producing errors or warnings.
        debug: Emits debugging information.
        embed_sources: Embeds the sources in the PDB.
        defines: The list of conditional compilation symbols.
        deps: The list of other libraries to be linked in to the assembly.
        exports: List of exported targets.
        targeting_pack: The targeting pack being used.
        internals_visible_to: An optional list of assemblies that can see this assemblies internal symbols.
        keyfile: Specifies a strong name key file of the assembly.
        langversion: Specify language version: Default, ISO-1, ISO-2, 3, 4, 5, 6, 7, 7.1, 7.2, 7.3, or Latest
        resources: The list of resouces to be embedded in the assembly.
        srcs: The source files that are processed to create the assembly.
        data: List of files that are a direct runtime dependency
        appsetting_files: List of appsettings files to include in the output.
        compile_data: List of files that are a direct compile time dependency
        target_name: A unique name for this target.
        out: Specifies the output file name.
        target: Specifies the format of the output file by using one of four options.
        target_framework: The target framework moniker for the assembly.
        toolchain: The toolchain that supply the C# compiler.
        strict_deps: Whether or not to use strict dependencies.
        generate_documentation_file: Whether or not to output XML docs for the compiled dll.
        include_host_model_dll: Whether or not to include he Microsoft.NET.HostModel dll. ONLY USED FOR COMPILING THE APPHOST SHIMMER.
        include_msbuild_dlls: Whether or not to include the MSBuild interfaces. ONLY USED FOR COMPILING TOOLS THAT RUN AN SDK BUILD TASK.
        treat_warnings_as_errors: Whether or not to treat warnings as errors.
        warnings_as_errors: List of warnings to treat as errors.
        warnings_not_as_errors: List of warnings to not treat errors.
        warning_level: The warning level to use.
        nowarn: List of warnings to suppress.
        project_sdk: The project sdk being targeted
        root_namespace: The root namespace Razor derives component namespaces from.
        scoped_css_tool: The tool that rewrites `.razor.css`.
        allow_unsafe_blocks: Compiles the target with /unsafe
        nullable: Enable nullable context, or nullable warnings.
        run_analyzers: Enable analyzers.
        is_analyzer: Whether or not the target is an analyzer.
        is_language_specific_analyzer: Whether or not the target is a language specific analyzer.
        analyzer_configs: List of analyzer configuration files.
        compiler_options: Additional options to pass to the compiler.
        interceptors_namespaces: Namespaces that are allowed to contain interceptors.
        is_windows: Whether or not the target is running on Windows.
    Returns:
        The compile and runtime providers, and the static web assets the compile
        generated.
    """

    assembly_name = target_name if out == "" else out
    subsystem_version = get_framework_version_info(target_framework)
    compile_deps = list(deps)
    if include_host_model_dll:
        compile_deps.append(toolchain.host_model)
    if include_msbuild_dlls:
        compile_deps.extend(toolchain.msbuild_dlls)

    (
        irefs,
        prefs,
        analyzers,
        analyzers_csharp,
        analyzers_fsharp,
        analyzers_vb,
        transitive_compile_data,
        framework_files,
        exports_files,
    ) = collect_compile_info(
        assembly_name,
        compile_deps,
        targeting_pack,
        exports,
        strict_deps,
    )

    if (is_analyzer or is_language_specific_analyzer) and target_framework != "netstandard2.0":
        fail("Analyzers must have `target_frameworks = [\"netstandard2.0\"]`.")

    # TODO: Ensure that all the analyzer DLLs also target netstandard2.0.
    analyzer_dlls = _collect_analyzer_dependencies(deps) if (is_analyzer or is_language_specific_analyzer) else []

    defines = framework_preprocessor_symbols(target_framework) + defines

    out_dir = target_name + "/" + target_framework
    out_ext = "dll"

    # `.razor` and `.cshtml` are inputs to a source generator, not to the
    # compiler, so they travel as additional files rather than sources.
    partitioned = partition_srcs(srcs, label)
    srcs = partitioned.compile
    is_application = target != "library"

    scoped_css = None
    generated_web_assets = []
    if partitioned.scoped_css:
        if not partitioned.razor:
            fail(
                "%s has scoped CSS but no Razor sources: %s.\n" % (
                    label,
                    ", ".join([src.short_path for src in partitioned.scoped_css]),
                ) +
                "A `<component>.razor.css` only applies to the `<component>.razor` beside it.",
            )

        # An application's bundle imports its libraries' bundles, so it has to
        # know where each of those is served from.
        dep_assets = depset(transitive = [
            dep[StaticWebAssetsInfo].assets
            for dep in deps
            if StaticWebAssetsInfo in dep
        ]) if is_application else depset()
        project_bundles = [
            asset.serving_path
            for asset in dep_assets.to_list()
            if asset.scoped_css_bundle
        ]

        scoped_css = scoped_css_action(
            actions,
            label = label,
            out_dir = out_dir,
            assembly_name = assembly_name,
            is_application = is_application,
            scoped_css_srcs = partitioned.scoped_css,
            project_bundles = sorted(project_bundles),
            tool = scoped_css_tool,
            toolchain = toolchain,
        )
        generated_web_assets.append(struct(
            file = scoped_css.bundle,
            subpath = scoped_css.bundle.basename,
            scoped_css_bundle = True,
        ))

    razor = None
    if partitioned.razor:
        if not uses_razor(project_sdk):
            fail(
                "%s has Razor sources but `project_sdk = %r`.\n" % (label, project_sdk) +
                "Set `project_sdk` to \"razor\" for a Razor class library, or \"web\" for an " +
                "ASP.NET Core application. Razor sources: %s" % (
                    ", ".join([src.short_path for src in partitioned.razor]),
                ),
            )
        razor = razor_compile_inputs(
            actions,
            label = label,
            out_dir = out_dir,
            root_namespace = root_namespace or target_name,
            target_framework = target_framework,
            razor_srcs = partitioned.razor,
            toolchain = toolchain,
            extra_configs = [scoped_css.scope_config] if scoped_css else [],
        )
        srcs = srcs + razor.srcs

        # csc counts only the files it is handed as sources, so a target whose
        # code is entirely Razor looks empty to it and warns that it has no
        # source files. The sources exist; they reach csc through the generator.
        if not srcs:
            nowarn = nowarn + ["CS2008"]

    out_dll = actions.declare_file("%s/%s.%s" % (out_dir, assembly_name, out_ext))
    out_iref = None
    out_ref = actions.declare_file("%s/ref/%s.%s" % (out_dir, assembly_name, out_ext))
    out_pdb = actions.declare_file("%s/%s.pdb" % (out_dir, assembly_name))
    out_xml = actions.declare_file("%s/%s.xml" % (out_dir, assembly_name)) if generate_documentation_file else None

    # Appsettings
    out_appsettings = copy_files_to_dir(target_name, actions, is_windows, appsetting_files, out_dir)

    if len(internals_visible_to) == 0 or is_analyzer:
        _compile(
            actions,
            compiler_wrapper,
            compiler_worker,
            label,
            additionalfiles,
            analyzers,
            analyzers_csharp,
            analyzer_configs,
            debug,
            embed_sources,
            defines,
            keyfile,
            langversion,
            irefs,
            framework_files,
            resources,
            srcs,
            depset(compile_data, transitive = [transitive_compile_data]),
            subsystem_version,
            target,
            target_name,
            target_framework,
            toolchain,
            treat_warnings_as_errors,
            warnings_as_errors,
            warnings_not_as_errors,
            warning_level,
            nowarn,
            allow_unsafe_blocks,
            nullable,
            run_analyzers,
            compiler_options,
            interceptors_namespaces,
            razor,
            out_dll = out_dll,
            out_ref = out_ref,
            out_pdb = out_pdb,
            out_xml = out_xml,
        )
    else:
        # If the user is using internals_visible_to generate an additional
        # reference-only DLL that contains the internals. We want the
        # InternalsVisibleTo in the main DLL too to be less suprising to users.
        out_iref = actions.declare_file("%s/iref/%s.%s" % (out_dir, assembly_name, out_ext))

        internals_visible_to_cs = _write_internals_visible_to_csharp(
            actions,
            label_name = target_name,
            dll_name = assembly_name,
            others = internals_visible_to,
        )

        _compile(
            actions,
            compiler_wrapper,
            compiler_worker,
            label,
            additionalfiles,
            analyzers,
            analyzers_csharp,
            analyzer_configs,
            debug,
            embed_sources,
            defines,
            keyfile,
            langversion,
            irefs,
            framework_files,
            resources,
            srcs + [internals_visible_to_cs],
            depset(compile_data, transitive = [transitive_compile_data]),
            subsystem_version,
            target,
            target_name,
            target_framework,
            toolchain,
            treat_warnings_as_errors,
            warnings_as_errors,
            warnings_not_as_errors,
            warning_level,
            nowarn,
            allow_unsafe_blocks,
            nullable,
            run_analyzers,
            compiler_options,
            interceptors_namespaces,
            razor,
            out_ref = out_iref,
            out_dll = out_dll,
            out_pdb = out_pdb,
            out_xml = out_xml,
        )

        # Generate a ref-only DLL without internals
        _compile(
            actions,
            compiler_wrapper,
            compiler_worker,
            label,
            additionalfiles,
            analyzers,
            analyzers_csharp,
            analyzer_configs,
            debug,
            embed_sources,
            defines,
            keyfile,
            langversion,
            irefs,
            framework_files,
            resources,
            srcs,
            depset(compile_data, transitive = [transitive_compile_data]),
            subsystem_version,
            target,
            target_name,
            target_framework,
            toolchain,
            treat_warnings_as_errors,
            warnings_as_errors,
            warnings_not_as_errors,
            warning_level,
            nowarn,
            allow_unsafe_blocks,
            nullable,
            run_analyzers,
            compiler_options,
            interceptors_namespaces,
            razor,
            out_dll = None,
            out_ref = out_ref,
            out_pdb = None,
            out_xml = None,
        )

    return (DotnetAssemblyCompileInfo(
        name = assembly_name,
        version = "1.0.0",  #TODO: Maybe make this configurable?
        project_sdk = project_sdk,
        refs = [out_ref] if not is_analyzer else [],
        irefs = [out_iref] if out_iref else [out_ref],
        analyzers = [] if (not is_analyzer) or is_language_specific_analyzer else ([out_dll] + analyzer_dlls),
        analyzers_csharp = ([out_dll] + analyzer_dlls) if is_language_specific_analyzer else [],
        analyzers_fsharp = [],
        analyzers_vb = [],
        internals_visible_to = internals_visible_to or [],
        compile_data = compile_data,
        exports = exports_files,
        transitive_refs = prefs if not (is_analyzer or is_language_specific_analyzer) else depset(),
        transitive_analyzers = analyzers,
        transitive_analyzers_csharp = analyzers_csharp,
        transitive_analyzers_fsharp = analyzers_fsharp,
        transitive_analyzers_vb = analyzers_vb,
        transitive_compile_data = transitive_compile_data,
    ), DotnetAssemblyRuntimeInfo(
        name = assembly_name,
        version = "1.0.0",  #TODO: Maybe make this configurable?
        libs = [out_dll] if not (is_analyzer or is_language_specific_analyzer) else [],
        resource_assemblies = [],
        pdbs = [out_pdb] if out_pdb else [],
        xml_docs = [out_xml] if out_xml else [],
        data = data,
        appsetting_files = depset(out_appsettings),
        native = [],
        # `compile_deps` rather than `deps`: an assembly pulled in from the
        # toolchain has to be resolvable at run time too, which is what puts it
        # in deps.json.
        deps = depset(
            [dep[DotnetAssemblyRuntimeInfo] for dep in compile_deps],
            transitive = [dep[DotnetAssemblyRuntimeInfo].deps for dep in deps],
        ) if not (is_analyzer or is_language_specific_analyzer) else depset(),
        nuget_info = None,
        direct_deps_depsjson_fragment = {dep[DotnetAssemblyRuntimeInfo].name: dep[DotnetAssemblyRuntimeInfo].version for dep in deps},
    ), generated_web_assets)

def _compile(
        actions,
        compiler_wrapper,
        compiler_worker,
        label,
        additionalfiles,
        analyzer_assemblies,
        analyzer_assemblies_csharp,
        analyzer_configs,
        debug,
        embed_sources,
        defines,
        keyfile,
        langversion,
        refs,
        framework_files,
        resources,
        srcs,
        compile_data,
        subsystem_version,
        target,
        target_name,
        target_framework,
        toolchain,
        treat_warnings_as_errors,
        warnings_as_errors,
        warnings_not_as_errors,
        warning_level,
        nowarn,
        allow_unsafe_blocks,
        nullable,
        run_analyzers,
        compiler_options,
        interceptors_namespaces,
        razor,
        out_dll = None,
        out_ref = None,
        out_pdb = None,
        out_xml = None):
    # Our goal is to match msbuild as much as reasonable
    # https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-options/listed-alphabetically
    args = actions.args()
    if (allow_unsafe_blocks):
        args.add("/unsafe+")
    else:
        args.add("/unsafe-")
    args.add("/checked-")
    args.add("/nostdlib+")  # mscorlib will get added due to our transitive deps
    args.add("/utf8output")
    args.add("/deterministic+")
    args.add("/filealign:512")

    args.add("/nologo")

    if use_highentropyva(target_framework):
        args.add("/highentropyva+")
    else:
        args.add("/highentropyva-")

    if (nullable == "enable"):
        args.add("/nullable:enable")
    elif (nullable == "warnings"):
        args.add("/nullable:warnings")
    elif (nullable == "annotations"):
        args.add("/nullable:annotations")
    else:
        args.add("/nullable:disable")

    if subsystem_version != None:
        args.add("/subsystemversion:" + subsystem_version)

    generate_warning_args(
        args,
        treat_warnings_as_errors,
        warnings_as_errors,
        warnings_not_as_errors,
        warning_level,
        nowarn,
    )

    args.add("/target:" + target)
    args.add("/langversion:" + langversion)

    if debug:
        args.add("/debug+")
        args.add("/optimize-")
        args.add("/define:TRACE")
        args.add("/define:DEBUG")
    else:
        args.add("/debug-")
        args.add("/optimize+")
        args.add("/define:TRACE")
        args.add("/define:RELEASE")

    args.add("/debug:portable")

    # A PDB records execroot-relative document paths, which resolve to nothing
    # once the build is over. `/embed` puts the sources in the symbols instead.
    # See docs/README.md#embedded-sources.
    if embed_sources:
        args.add("/embed")

    # outputs
    if out_dll != None:
        args.add(out_dll, format = "/out:%s")
        args.add(out_ref, format = "/refout:%s")
        args.add(out_pdb, format = "/pdb:%s")
        outputs = [out_dll, out_ref, out_pdb]
    else:
        args.add("/refonly")
        args.add(out_ref, format = "/out:%s")
        outputs = [out_ref]

    if out_xml != None:
        args.add(out_xml, format = "/doc:%s")
        outputs.append(out_xml)

    # A `/refonly` pass does not record every reference the real compilation
    # uses, so only the latter can say which ones went unused. The worker writes
    # the list next to the assembly it just read, which is this path.
    unused_inputs = None
    if compiler_worker and compiler_worker.prune_unused_references and out_dll != None:
        unused_inputs = actions.declare_file(out_dll.basename + ".unused_inputs", sibling = out_dll)
        outputs.append(unused_inputs)

    # assembly references
    # csc resolves a duplicate assembly identity by order, so refs must come
    # before the framework files.
    format_ref_arg(args, depset(transitive = [refs, framework_files]))

    # A source generator rather than an analyzer, so it runs even when analyzers
    # are switched off: without it every component would be undefined rather
    # than merely undiagnosed.
    if razor:
        args.add_all(razor.analyzers, format_each = "/analyzer:%s")
        args.add_all(razor.additionalfiles, format_each = "/additionalfile:%s")
        args.add_all(razor.configs, format_each = "/analyzerconfig:%s")

    # analyzers
    if run_analyzers:
        args.add_all(analyzer_assemblies, format_each = "/analyzer:%s")
        args.add_all(analyzer_assemblies_csharp, format_each = "/analyzer:%s")
        args.add_all(additionalfiles, format_each = "/additionalfile:%s")
        args.add_all(analyzer_configs, format_each = "/analyzerconfig:%s")

    # .cs files
    args.add_all(srcs)

    # resources
    add_resource_args(args, resources, label, out_dll.basename if out_dll != None else None, "csharp")

    # defines
    args.add_all(defines, format_each = "/d:%s")

    # keyfile
    if keyfile != None:
        args.add(keyfile, format = "/keyfile:%s")

    # Additional compiler flags
    for option in compiler_options:
        args.add(option)

    # Namespaces that are allowed to contain interceptors
    if interceptors_namespaces:
        args.add("/features:InterceptorsNamespaces=" + ";".join(interceptors_namespaces))

    # A compile carrying the targeting pack's references is far past any OS
    # command line limit, so the arguments always go into a response file.
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    direct_inputs = srcs + resources + additionalfiles + analyzer_configs
    direct_inputs += [keyfile] if keyfile else []
    if razor:
        direct_inputs += razor.analyzers + razor.additionalfiles + razor.configs

    icu_arguments, icu_tools = [], []
    if compiler_worker:
        # A `FilesToRunProvider` rather than a `File`, so that the worker's own
        # runfiles reach the action without being listed as tools.
        executable = compiler_worker.executable
        extra_tools = []
        execution_requirements = {
            "requires-worker-protocol": "json",
            "supports-path-mapping": "1",
            "supports-workers": "1",
        }
    else:
        executable = compiler_wrapper
        extra_tools = [compiler_wrapper]
        execution_requirements = {"supports-path-mapping": "1"}

        icu_arguments, icu_tools = icu_wrapper_arguments(actions, toolchain)

    # Both the worker and the wrapper script take the dotnet host and csc.dll
    # first, then the csc arguments:
    # https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-options/
    actions.run(
        mnemonic = "CSharpCompile",
        progress_message = "Compiling " + target_name + (" (internals ref-only dll)" if out_dll == None else ""),
        inputs = depset(
            direct = direct_inputs,
            transitive = [framework_files, refs, analyzer_assemblies, analyzer_assemblies_csharp, compile_data],
        ),
        tools = depset(
            direct = extra_tools + [
                toolchain.compiler_host.files_to_run.executable,
                toolchain.csharp_compiler.files_to_run.executable,
            ],
            transitive = icu_tools + [
                toolchain.compiler_host.default_runfiles.files,
                toolchain.csharp_compiler.default_runfiles.files,
            ],
        ),
        outputs = outputs,
        executable = executable,
        arguments = icu_arguments + [
            toolchain.compiler_host.files_to_run.executable.path,
            toolchain.csharp_compiler.files_to_run.executable.path,
        ] + (["--prune_unused_inputs"] if unused_inputs else []) + [args],
        unused_inputs_list = unused_inputs,
        env = dicts.add(
            {"DOTNET_CLI_HOME": toolchain.compiler_host.files_to_run.executable.dirname},
            globalization_env(toolchain),
        ),
        execution_requirements = execution_requirements,
    )
