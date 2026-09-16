"""Rule for compiling Blazor libraries."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//dotnet/private:common.bzl",
    "collect_transitive_runfiles",
    "get_targeting_pack",
    "get_toolchain",
    "is_debug",
)
load(
    "//dotnet/private:providers.bzl",
    "BlazorComponentInfo",
    "BlazorLibraryInfo",
    "DotnetAssemblyRuntimeInfo",
)
load("//dotnet/private/rules/common:attrs.bzl", "COMMON_ATTRS", "LIBRARY_COMMON_ATTRS")
load("//dotnet/private/rules/common:stamping.bzl", "maybe_stamp_srcs")
load("//dotnet/private/rules/csharp/actions:csharp_assembly.bzl", "AssemblyAction")
load("//dotnet/private/transitions:default_transition.bzl", "default_transition")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")
load("//proto/private:providers.bzl", "CsharpProtoSourceInfo")

_EXEC_ROOT_TOKEN = "__RULES_DOTNET_EXEC_ROOT__"

def _is_razor_source(file):
    return file.extension == "razor"

def _is_csharp_source(file):
    return file.extension == "cs"

def _is_scoped_css(file):
    return file.basename.endswith(".razor.css")

def _logical_path(ctx, file):
    package_prefix = ctx.label.package + "/" if ctx.label.package else ""
    if file.short_path.startswith(package_prefix):
        return file.short_path[len(package_prefix):]
    package_marker = "/" + package_prefix
    if package_marker in file.short_path:
        return file.short_path.split(package_marker, 1)[1]
    return file.basename

def _join_path(left, right):
    if not left:
        return right.strip("/")
    if not right:
        return left.strip("/")
    return left.strip("/") + "/" + right.strip("/")

def _partition_srcs(srcs):
    csharp_srcs = []
    razor_srcs = []
    for src in srcs:
        if _is_csharp_source(src):
            csharp_srcs.append(src)
        elif _is_razor_source(src):
            razor_srcs.append(src)
        else:
            fail("blazor_library srcs only supports .cs and .razor files: {}".format(src.path))
    return csharp_srcs, razor_srcs

def _partition_assets(assets):
    static_assets = []
    scoped_css = []
    for asset in assets:
        if _is_scoped_css(asset):
            scoped_css.append(asset)
        else:
            static_assets.append(asset)
    return static_assets, scoped_css

def _target_path(ctx, component, file):
    return _join_path(component.effective_root, _logical_path(ctx, file))

def _asset_relative_path(ctx, file):
    logical_path = _logical_path(ctx, file)
    if logical_path.startswith("wwwroot/"):
        return logical_path[len("wwwroot/"):]
    return logical_path

def _scoped_css_component_target_path(ctx, component, file):
    target_path = _target_path(ctx, component, file)
    if target_path.endswith(".css"):
        return target_path[:-4]
    return target_path

def _scoped_css_output(ctx, tfm, component, asset):
    logical_path = _scoped_css_component_target_path(ctx, component, asset)
    if logical_path.endswith(".razor"):
        logical_path = logical_path + ".rz.scp.css"
    else:
        logical_path = logical_path + ".razor.rz.scp.css"
    return ctx.actions.declare_file("%s/%s/scopedcss/%s" % (ctx.attr.name, tfm, logical_path))

def _razor_source_generator_files(toolchain):
    if not hasattr(toolchain, "aspnetcore_razor_toolset") or toolchain.aspnetcore_razor_toolset == None:
        fail("The selected .NET toolchain does not provide ASP.NET Core Razor source generators.")

    files = []
    for file in toolchain.aspnetcore_razor_toolset[DotnetAssemblyRuntimeInfo].libs:
        if "/source-generators/" in file.path and file.basename.endswith(".dll"):
            files.append(file)

    if len(files) == 0:
        fail("The selected .NET toolchain did not expose any Razor source generator DLLs.")

    return files

def _preprocess_blazor(ctx, tfm, assembly_name, component, razor_srcs, import_srcs, import_target_paths, static_assets, scoped_css):
    analyzer_config = ctx.actions.declare_file("%s/%s/%s.razor.editorconfig" % (ctx.attr.name, tfm, assembly_name))
    scoped_css_outputs = [_scoped_css_output(ctx, tfm, component, asset) for asset in scoped_css]
    scoped_css_bundle = ctx.actions.declare_file("%s/%s/scopedcss/bundle/%s.styles.css" % (ctx.attr.name, tfm, assembly_name))
    project_scoped_css_bundle = ctx.actions.declare_file("%s/%s/scopedcss/projectbundle/%s.bundle.scp.css" % (ctx.attr.name, tfm, assembly_name))

    args = ctx.actions.args()
    args.add("preprocess")
    args.add("--assembly-name", assembly_name)
    args.add("--root-namespace", component.effective_namespace)
    args.add("--target-framework", tfm)
    if ctx.attr.razor_langversion:
        args.add("--razor-lang-version", ctx.attr.razor_langversion)
    args.add("--project-dir", component.effective_root)
    args.add("--path-prefix", _EXEC_ROOT_TOKEN)
    args.add("--analyzer-config", analyzer_config)
    args.add("--scoped-css-bundle", scoped_css_bundle)
    args.add("--project-scoped-css-bundle", project_scoped_css_bundle)

    for i, import_src in enumerate(import_srcs):
        args.add("--razor-file", import_src.path + "|" + import_target_paths[i])
    for razor_src in razor_srcs:
        args.add("--razor-file", razor_src.path + "|" + _target_path(ctx, component, razor_src))

    args.add_all(static_assets, before_each = "--asset")
    args.add_all(scoped_css, before_each = "--scoped-css")
    args.add_all(scoped_css_outputs, before_each = "--scoped-css-output")
    args.add_all([_target_path(ctx, component, scoped_css_file) for scoped_css_file in scoped_css], before_each = "--scoped-css-target-path")

    outputs = [analyzer_config, scoped_css_bundle, project_scoped_css_bundle] + scoped_css_outputs

    ctx.actions.run(
        mnemonic = "BlazorPreprocess",
        progress_message = "Preprocessing Blazor assets for " + ctx.attr.name,
        inputs = depset(razor_srcs + import_srcs + static_assets + scoped_css),
        outputs = outputs,
        executable = ctx.attr._blazor_helper[DefaultInfo].files_to_run,
        arguments = [args],
    )

    return struct(
        analyzer_config = analyzer_config,
        scoped_css_outputs = scoped_css_outputs,
        scoped_css_bundle = scoped_css_bundle,
        project_scoped_css_bundle = project_scoped_css_bundle,
    )

def _compile_action(ctx, tfm):
    toolchain = get_toolchain(ctx)
    component = ctx.attr.component[BlazorComponentInfo]
    assembly_name = ctx.attr.out or ctx.attr.name
    csharp_srcs, razor_srcs = _partition_srcs(ctx.files.srcs)
    static_assets, scoped_css = _partition_assets(ctx.files.assets)
    srcs = maybe_stamp_srcs(ctx, csharp_srcs + component.global_using_files, assembly_name, tfm, "csharp")
    import_srcs = component.import_files
    preprocess = _preprocess_blazor(ctx, tfm, assembly_name, component, razor_srcs, import_srcs, component.import_target_paths, static_assets, scoped_css)
    generated_source_dirs = []
    for generated_src in ctx.attr.generated_srcs:
        generated_source_dirs.extend(generated_src[CsharpProtoSourceInfo].generated_source_dirs)

    compilation = dict(
        compiler_wrapper = ctx.executable._compiler_wrapper_bat if ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]) else ctx.executable._compiler_wrapper_sh,
        compiler_worker = None,
        label = ctx.label,
        additionalfiles = razor_srcs + import_srcs + ctx.files.additionalfiles,
        debug = is_debug(ctx),
        defines = ctx.attr.defines,
        deps = ctx.attr.deps,
        exports = ctx.attr.exports,
        targeting_pack = get_targeting_pack(ctx),
        internals_visible_to = ctx.attr.internals_visible_to,
        keyfile = ctx.file.keyfile,
        langversion = ctx.attr.langversion if ctx.attr.langversion != "" else toolchain.dotnetinfo.csharp_default_version,
        resources = ctx.files.resources,
        srcs = srcs,
        data = ctx.files.data,
        appsetting_files = [],
        compile_data = ctx.files.compile_data,
        out = ctx.attr.out,
        target = "library",
        target_name = ctx.attr.name,
        target_framework = tfm,
        toolchain = toolchain,
        strict_deps = toolchain.strict_deps[BuildSettingInfo].value,
        generate_documentation_file = ctx.attr.generate_documentation_file,
        include_host_model_dll = False,
        treat_warnings_as_errors = ctx.attr.treat_warnings_as_errors,
        warnings_as_errors = ctx.attr.warnings_as_errors,
        warnings_not_as_errors = ctx.attr.warnings_not_as_errors,
        warning_level = ctx.attr.warning_level,
        nowarn = ctx.attr.nowarn,
        project_sdk = ctx.attr.project_sdk,
        allow_unsafe_blocks = ctx.attr.allow_unsafe_blocks,
        nullable = ctx.attr.nullable,
        run_analyzers = ctx.attr.run_analyzers,
        is_analyzer = False,
        is_language_specific_analyzer = False,
        analyzer_configs = ctx.files.analyzer_configs,
        analyzer_config_template = preprocess.analyzer_config,
        compiler_options = ctx.attr.compiler_options,
        interceptors_namespaces = [],
        is_windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]),
        extra_analyzers_csharp = _razor_source_generator_files(toolchain),
        generated_source_dirs = generated_source_dirs,
        additionalfiles_path_prefix = _EXEC_ROOT_TOKEN + "/",
    )

    compile_provider, runtime_provider = AssemblyAction(ctx.actions, **compilation)
    return compile_provider, runtime_provider, preprocess, static_assets, compilation

def _blazor_library_impl(ctx):
    tfm = ctx.attr._target_framework[BuildSettingInfo].value
    compile_provider, runtime_provider, preprocess, static_assets, compilation = _compile_action(ctx, tfm)

    transitive_assets = []
    transitive_scoped_css = []
    transitive_static_web_assets = []
    for dep in ctx.attr.deps:
        if BlazorLibraryInfo in dep:
            transitive_assets.append(dep[BlazorLibraryInfo].transitive_assets)
            transitive_scoped_css.append(dep[BlazorLibraryInfo].transitive_scoped_css)
            transitive_static_web_assets.extend(dep[BlazorLibraryInfo].transitive_static_web_assets)

    direct_scoped_css = preprocess.scoped_css_outputs + [preprocess.scoped_css_bundle, preprocess.project_scoped_css_bundle]
    static_web_assets = [
        struct(
            file = asset,
            relative_path = _asset_relative_path(ctx, asset),
            source_name = runtime_provider.name,
        )
        for asset in static_assets
    ]
    if len(preprocess.scoped_css_outputs) > 0:
        static_web_assets.append(struct(
            file = preprocess.scoped_css_bundle,
            relative_path = preprocess.scoped_css_bundle.basename,
            source_name = runtime_provider.name,
        ))
    blazor_info = BlazorLibraryInfo(
        assembly_compile_info = compile_provider,
        assembly_runtime_info = runtime_provider,
        compilation = compilation,
        assets = static_assets,
        scoped_css = direct_scoped_css,
        transitive_assets = depset(direct = static_assets, transitive = transitive_assets),
        transitive_scoped_css = depset(direct = direct_scoped_css, transitive = transitive_scoped_css),
        static_web_assets = static_web_assets,
        transitive_static_web_assets = static_web_assets + transitive_static_web_assets,
    )

    runfiles = collect_transitive_runfiles(ctx, runtime_provider, ctx.attr.deps).merge(ctx.runfiles(files = static_assets + direct_scoped_css))

    return [
        compile_provider,
        runtime_provider,
        blazor_info,
        DefaultInfo(
            files = depset(runtime_provider.libs + runtime_provider.xml_docs + static_assets + direct_scoped_css),
            default_runfiles = runfiles,
        ),
    ]

BLAZOR_LIBRARY_ATTRS = dicts.add(
    COMMON_ATTRS,
    LIBRARY_COMMON_ATTRS,
    {
        "srcs": attr.label_list(
            doc = "C# and Razor source files for this Blazor library.",
            allow_files = [".cs", ".razor"],
            cfg = default_transition,
        ),
        "assets": attr.label_list(
            doc = "Static web assets for this Blazor library. Files ending in .razor.css are processed as scoped CSS.",
            allow_files = True,
            cfg = default_transition,
        ),
        "component": attr.label(
            doc = "Controlling Blazor component context for this library.",
            mandatory = True,
            providers = [BlazorComponentInfo],
        ),
        "generated_srcs": attr.label_list(
            doc = "Targets providing generated C# source trees to compile into this assembly.",
            providers = [CsharpProtoSourceInfo],
            cfg = tfm_transition,
        ),
        "additionalfiles": attr.label_list(
            doc = "Extra files to pass to analyzers.",
            allow_files = True,
            cfg = default_transition,
        ),
        "analyzer_configs": attr.label_list(
            doc = "Additional analyzer configuration files.",
            allow_files = True,
            allow_empty = True,
            cfg = default_transition,
        ),
        "allow_unsafe_blocks": attr.bool(
            doc = "Allow compiling unsafe code.",
            default = False,
        ),
        "nullable": attr.string(
            doc = "Enable nullable context, or nullable warnings.",
            default = "disable",
            values = ["disable", "enable", "warnings", "annotations"],
        ),
        "run_analyzers": attr.bool(
            doc = "Controls whether analyzers run at build time.",
            default = True,
        ),
        "nowarn": attr.string_list(
            doc = "List of warnings that should be ignored.",
            default = ["CS1701", "CS1702"],
        ),
        "razor_langversion": attr.string(
            doc = "Razor language version. Defaults to the target framework version.",
        ),
        "project_sdk": attr.string(
            doc = "The project SDK that is being targeted.",
            default = "default",
            values = ["default", "web"],
        ),
        "_blazor_helper": attr.label(
            default = "//tools/blazor",
            executable = True,
            cfg = "exec",
        ),
    },
)

blazor_library = rule(
    _blazor_library_impl,
    doc = "Compile a Blazor library and expose its Blazor assets.",
    attrs = BLAZOR_LIBRARY_ATTRS,
    executable = False,
    toolchains = ["//dotnet:toolchain_type"],
    cfg = tfm_transition,
)
