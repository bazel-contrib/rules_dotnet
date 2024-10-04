"""
Actions for compiling targets with C#.
"""

load(
    "//dotnet/private:common.bzl",
    "collect_compile_info",
    "copy_files_to_dir",
    "format_ref_arg",
    "framework_preprocessor_symbols",
    "generate_warning_args",
    "get_framework_version_info",
    "is_core_framework",
    "is_greater_or_equal_framework",
    "is_standard_framework",
    "use_highentropyva",
)
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
)

def _format_targetprofile(tfm):
    if is_standard_framework(tfm):
        return "--targetprofile:netstandard"

    if is_core_framework(tfm):
        return "--targetprofile:netcore"

    return "--targetprofile:mscorlib"

def _write_internals_visible_to_fsharp(actions, label_name, dll_name, others):
    """Write a .fs file containing InternalsVisibleTo attributes.

    Letting Bazel see which assemblies we are going to have InternalsVisibleTo
    allows for more robust caching of compiles.

    Args:
      actions: An actions module, usually from ctx.actions.
      label_name: The label name
      dll_name: The assembly name.
      others: The names of other assemblies.

    Returns:
      A File object for a generated .fs file
    """

    if len(others) == 0:
        return None

    content = """
module AssemblyInfo

"""
    for other in others:
        content += """
[<assembly: System.Runtime.CompilerServices.InternalsVisibleTo(\"%s\")>]
do()

""" % other

    output = actions.declare_file("%s/%s/internalsvisibleto.fs" % (label_name, dll_name))
    actions.write(output, content)

    return output

# Reference assembly support did not come to F# until .Net 7.0
# This check should be removed once the .Net 6.0 LTS release is no longer supported
def _should_output_ref_assembly(toolchain):
    return is_greater_or_equal_framework(toolchain.dotnetinfo.runtime_tfm, "net7.0")

# buildifier: disable=unnamed-macro
def AssemblyAction(
        actions,
        compiler_wrapper,
        debug,
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
        treat_warnings_as_errors,
        warnings_as_errors,
        warnings_not_as_errors,
        warning_level,
        nowarn,
        project_sdk,
        compiler_options,
        is_windows):
    """Creates an action that runs the F# compiler with the specified inputs.

    This macro aims to match the [F# compiler](https://docs.microsoft.com/en-us/dotnet/fsharp/language-reference/compiler-options), with the inputs mapping to compiler options.

    Args:
        actions: Bazel module providing functions to create actions.
        compiler_wrapper: The wrapper script that invokes the F# compiler.
        debug: Emits debugging information.
        defines: The list of conditional compilation symbols.
        deps: The list of other libraries to be linked in to the assembly.
        exports: List of exported targets.
        targeting_pack: The targeting pack being used.
        internals_visible_to: An optional list of assemblies that can see this assemblies internal symbols.
        keyfile: Specifies a strong name key file of the assembly.
        langversion: Specify language version: Default, ISO-1, ISO-2, 3, 4, 5, 6, 7, 7.1, 7.2, 7.3, or Latest
        resources: The list of resouces to be embedded in the assembly.
        srcs: The list of source (.cs) files that are processed to create the assembly.
        data: List of files that are a direct runtime dependency
        appsetting_files: List of appsettings files to include in the output.
        compile_data: List of files that are a direct compile time dependency
        target_name: A unique name for this target.
        out: Specifies the output file name.
        target: Specifies the format of the output file by using one of four options.
        target_framework: The target framework moniker for the assembly.
        toolchain: The toolchain that supply the F# compiler.
        strict_deps: Whether or not to use strict dependencies.
        generate_documentation_file: Whether or not to output XML docs for the compiled dll.
        treat_warnings_as_errors: Whether or not to treat warnings as errors.
        warnings_as_errors: List of warnings to treat as errors.
        warnings_not_as_errors: List of warnings to not treat errors.
        warning_level: The warning level to use.
        nowarn: List of warnings to suppress.
        project_sdk: The project SDK being targeted
        compiler_options: Additional compiler options to pass to the compiler.
        is_windows: Whether or not the target is running on Windows.

    Returns:
        The compiled fsharp artifacts.
    """

    assembly_name = target_name if out == "" else out
    (subsystem_version, _default_lang_version) = get_framework_version_info(target_framework)
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
        deps,
        targeting_pack,
        exports,
        strict_deps,
    )
    defines = framework_preprocessor_symbols(target_framework) + defines

    out_dir = target_name + "/" + target_framework
    out_ext = "dll"
    out_dll = actions.declare_file("%s/%s.%s" % (out_dir, assembly_name, out_ext))
    out_iref = None
    out_ref = actions.declare_file("%s/ref/%s.%s" % (out_dir, assembly_name, out_ext)) if _should_output_ref_assembly(toolchain) else None
    out_pdb = actions.declare_file("%s/%s.pdb" % (out_dir, assembly_name))
    out_xml = actions.declare_file("%s/%s.xml" % (out_dir, assembly_name)) if generate_documentation_file else None

    out_appsettings = copy_files_to_dir(target_name, actions, is_windows, appsetting_files, out_dir)

    if len(internals_visible_to) == 0:
        _compile(
            actions,
            compiler_wrapper,
            debug,
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
            compiler_options,
            out_dll = out_dll,
            out_ref = out_ref,
            out_pdb = out_pdb,
            out_xml = out_xml,
        )
    else:
        # If the user is using internals_visible_to generate an additional
        # reference-only DLL that contains the internals. We want the
        # InternalsVisibleTo in the main DLL too to be less suprising to users.
        out_iref = actions.declare_file("%s/iref/%s.%s" % (out_dir, assembly_name, out_ext)) if _should_output_ref_assembly(toolchain) else None

        internals_visible_to_fs = _write_internals_visible_to_fsharp(
            actions,
            label_name = target_name,
            dll_name = assembly_name,
            others = internals_visible_to,
        )
        _compile(
            actions,
            compiler_wrapper,
            debug,
            defines,
            keyfile,
            langversion,
            irefs,
            framework_files,
            resources,
            srcs + [internals_visible_to_fs],
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
            compiler_options,
            out_ref = out_iref,
            out_dll = out_dll,
            out_pdb = out_pdb,
            out_xml = out_xml,
        )

        if out_iref != None:
            # Generate a ref-only DLL without internals
            _compile(
                actions,
                compiler_wrapper,
                debug,
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
                compiler_options,
                out_dll = None,
                out_ref = out_ref,
                out_pdb = None,
                out_xml = None,
            )

    return (DotnetAssemblyCompileInfo(
        name = assembly_name,
        version = "1.0.0",  #TODO: Maybe make this configurable?
        project_sdk = project_sdk,
        refs = [out_dll],
        irefs = [out_iref] if out_iref else [out_ref] if out_ref else [out_dll],
        analyzers = [],
        analyzers_csharp = [],
        analyzers_fsharp = [],
        analyzers_vb = [],
        internals_visible_to = internals_visible_to or [],
        compile_data = compile_data,
        exports = exports_files,
        transitive_refs = prefs,
        transitive_analyzers = analyzers,
        transitive_analyzers_csharp = analyzers_csharp,
        transitive_analyzers_fsharp = analyzers_fsharp,
        transitive_analyzers_vb = analyzers_vb,
        transitive_compile_data = transitive_compile_data,
    ), DotnetAssemblyRuntimeInfo(
        name = assembly_name,
        version = "1.0.0",  #TODO: Maybe make this configurable?
        libs = [out_dll],
        pdbs = [out_pdb] if out_pdb else [],
        xml_docs = [out_xml] if out_xml else [],
        data = data,
        appsetting_files = depset(out_appsettings),
        native = [],
        deps = depset([dep[DotnetAssemblyRuntimeInfo] for dep in deps], transitive = [dep[DotnetAssemblyRuntimeInfo].deps for dep in deps]),
        nuget_info = None,
        direct_deps_depsjson_fragment = {dep[DotnetAssemblyRuntimeInfo].name: dep[DotnetAssemblyRuntimeInfo].version for dep in deps},
    ))

def _compile(
        actions,
        compiler_wrapper,
        debug,
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
        compiler_options,
        out_dll = None,
        out_ref = None,
        out_pdb = None,
        out_xml = None):
    # Our goal is to match msbuild as much as reasonable
    # https://docs.microsoft.com/en-us/dotnet/fsharp/language-reference/compiler-options
    args = actions.args()
    args.add("--noframework")
    args.add("--utf8output")
    args.add("--deterministic+")
    args.add("--nowin32manifest")
    args.add("--nocopyfsharpcore")
    args.add("--simpleresolution")
    args.add(_format_targetprofile(target_framework))
    args.add("--nologo")

    if use_highentropyva(target_framework):
        args.add("--highentropyva+")
    else:
        args.add("--highentropyva-")

    if subsystem_version != None:
        args.add("--subsystemversion:" + subsystem_version)

    generate_warning_args(
        args,
        treat_warnings_as_errors,
        warnings_as_errors,
        warnings_not_as_errors,
        warning_level,
        nowarn,
    )

    args.add("--target:" + target)
    if langversion:
        args.add("--langversion:" + langversion)

    if debug:
        args.add("--debug+")
        args.add("--optimize-")
        args.add("--define:TRACE")
        args.add("--define:DEBUG")
        args.add("--tailcalls-")
    else:
        args.add("--debug-")
        args.add("--optimize+")
        args.add("--define:TRACE")
        args.add("--define:RELEASE")

    args.add("--debug:portable")

    # outputs
    if out_dll != None:
        args.add("--out:" + out_dll.path)
        args.add("--pdb:" + out_pdb.path)
        outputs = [out_dll, out_pdb]

        if out_ref != None:
            args.add("--refout:" + out_ref.path)
            outputs.append(out_ref)

    else:
        args.add("--refonly")
        args.add("--out:" + out_ref.path)
        outputs = [out_ref]

    if out_xml != None:
        args.add("--doc:" + out_xml.path)
        outputs.append(out_xml)

    # assembly references
    format_ref_arg(args, depset(framework_files, transitive = [refs]))

    # .fs files
    args.add_all(srcs)

    # resources
    args.add_all(resources, format_each = "--resource:%s")

    # defines
    args.add_all(defines, format_each = "-d:%s")

    # keyfile
    if keyfile != None:
        args.add("--keyfile:" + keyfile.path)

    # Additional compiler options
    for option in compiler_options:
        args.add(option)

    # spill to a "response file" when the argument list gets too big (Bazel
    # makes that call based on limitations of the OS).
    args.set_param_file_format("multiline")

    args.use_param_file("@%s", use_always = True)

    direct_inputs = srcs + resources + [toolchain.fsharp_compiler.files_to_run.executable]
    direct_inputs += [keyfile] if keyfile else []

    # dotnet.exe fsc.dll --noconfig <other fsc args>
    actions.run(
        mnemonic = "FSharpCompile",
        progress_message = "Compiling " + target_name + (" (internals ref-only dll)" if out_dll == None else ""),
        inputs = depset(
            direct = direct_inputs + framework_files + [compiler_wrapper, toolchain.runtime.files_to_run.executable],
            transitive = [refs, toolchain.runtime.default_runfiles.files, toolchain.fsharp_compiler.default_runfiles.files, compile_data],
        ),
        outputs = outputs,
        executable = compiler_wrapper,
        arguments = [
            toolchain.runtime.files_to_run.executable.path,
            toolchain.fsharp_compiler.files_to_run.executable.path,
            args,
        ],
        env = {
            "DOTNET_CLI_HOME": toolchain.runtime.files_to_run.executable.dirname,
        },
    )
