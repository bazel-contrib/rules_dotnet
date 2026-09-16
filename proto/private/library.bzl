"Rule for compiling C# proto libraries."

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@com_google_protobuf//bazel/common:proto_common.bzl", "proto_common")
load("@com_google_protobuf//bazel/common:proto_info.bzl", "ProtoInfo")
load(
    "//dotnet/private:common.bzl",
    "collect_transitive_runfiles",
    "get_targeting_pack",
    "get_toolchain",
    "is_debug",
)
load("//dotnet/private/rules/common:attrs.bzl", "CSHARP_LIBRARY_COMMON_ATTRS")
load("//dotnet/private/rules/common:stamping.bzl", "maybe_stamp_srcs")
load(
    "//dotnet/private/rules/csharp:global_usings.bzl",
    "collect_global_usings",
    "generate_global_usings_source",
)
load("//dotnet/private/rules/csharp/actions:csharp_assembly.bzl", "AssemblyAction")
load("//dotnet/private/transitions:default_transition.bzl", "default_transition")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")
load("//proto/private:providers.bzl", "CsharpProtoCompilerInfo", "CsharpProtoSourceInfo")

def _without(attrs, names):
    return {name: value for (name, value) in attrs.items() if name not in names}

def _safe_path_fragment(value):
    return value.replace("@", "_").replace("/", "_").replace(":", "_").replace(".", "_").replace("-", "_")

def _generated_proto_source_dirs(ctx, tfm):
    generated_source_dirs = []
    for proto_compiler in ctx.attr.proto_compilers:
        compiler = proto_compiler[CsharpProtoCompilerInfo]
        for proto in ctx.attr.protos:
            proto_info = proto[ProtoInfo]
            if not proto_common.experimental_should_generate_code(proto_info, compiler.proto_lang_toolchain_info, "csharp_proto_library", proto.label):
                continue

            output_dir = ctx.actions.declare_directory("%s/%s/proto/%s/%s" % (
                ctx.attr.name,
                tfm,
                _safe_path_fragment(str(proto_compiler.label)),
                _safe_path_fragment(str(proto.label)),
            ))
            proto_common.compile(
                actions = ctx.actions,
                proto_info = proto_info,
                proto_lang_toolchain_info = compiler.proto_lang_toolchain_info,
                generated_files = [output_dir],
                plugin_output = output_dir.path,
                experimental_output_files = "legacy",
            )
            generated_source_dirs.append(output_dir)
    return generated_source_dirs

def _compile_action(ctx, tfm, generated_source_dirs):
    toolchain = get_toolchain(ctx)
    assembly_name = ctx.attr.out or ctx.attr.name
    global_usings = collect_global_usings(ctx.attr.global_usings, ctx.attr.implicit_usings, [])
    global_using_srcs = generate_global_usings_source(
        ctx.actions,
        "%s/%s/%s.GlobalUsings.g.cs" % (ctx.attr.name, tfm, assembly_name),
        global_usings,
    )
    srcs = maybe_stamp_srcs(ctx, ctx.files.embed_srcs + global_using_srcs, assembly_name, tfm, "csharp")

    return AssemblyAction(
        ctx.actions,
        ctx.executable._compiler_wrapper_bat if ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]) else ctx.executable._compiler_wrapper_sh,
        compiler_worker = None,
        label = ctx.label,
        additionalfiles = ctx.files.additionalfiles,
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
        is_analyzer = ctx.attr.is_analyzer,
        is_language_specific_analyzer = ctx.attr.is_language_specific_analyzer,
        analyzer_configs = ctx.files.analyzer_configs,
        compiler_options = ctx.attr.compiler_options,
        interceptors_namespaces = ctx.attr.interceptors_namespaces,
        is_windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]),
        generated_source_dirs = generated_source_dirs,
    )

def _library_impl(ctx):
    tfm = ctx.attr._target_framework[BuildSettingInfo].value
    generated_source_dirs = _generated_proto_source_dirs(ctx, tfm)
    compile_provider, runtime_provider = _compile_action(ctx, tfm, generated_source_dirs)
    return [
        compile_provider,
        runtime_provider,
        CsharpProtoSourceInfo(generated_source_dirs = generated_source_dirs),
        DefaultInfo(
            files = depset(runtime_provider.libs + runtime_provider.xml_docs),
            default_runfiles = collect_transitive_runfiles(ctx, runtime_provider, ctx.attr.deps),
        ),
    ]

csharp_proto_library = rule(
    _library_impl,
    doc = "Generate C# sources from proto_library targets and compile them into a DLL",
    attrs = dicts.add(
        _without(CSHARP_LIBRARY_COMMON_ATTRS, ["srcs"]),
        {
            "embed_srcs": attr.label_list(
                doc = "Optional C# source files compiled together with generated proto sources.",
                allow_files = [".cs"],
                cfg = default_transition,
            ),
            "protos": attr.label_list(
                doc = "proto_library targets to generate C# sources from.",
                providers = [ProtoInfo],
                mandatory = True,
                allow_empty = False,
                cfg = default_transition,
            ),
            "proto_compilers": attr.label_list(
                doc = "C# proto compiler targets used to generate source files.",
                providers = [CsharpProtoCompilerInfo],
                default = ["//proto:csharp_proto"],
            ),
        },
    ),
    executable = False,
    toolchains = ["//dotnet:toolchain_type"],
    cfg = tfm_transition,
)
