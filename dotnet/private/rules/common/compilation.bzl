"""Compiles each assembly once, whatever runtime identifier or ReadyToRun framework reaches it.

A managed compile reads neither, but both are in the configuration, so a target
reached by publishes for several runtime identifiers, or by a ReadyToRun publish
and a test, would compile once in each. Such a target takes its compilation from
itself in the configuration it compiles in instead: the host's runtime
identifier and no ReadyToRun framework, which is where an ordinary build of it
compiles too. Its own configuration then only decides what it ships.

Unless what it compiles differs: a target that selects its sources on the
runtime identifier, or depends on one that does, compiles in its own
configuration as before. Both copies say what they compile from, and the
compilation is reused only when they agree.

An attribute default can neither name the target it belongs to nor be a select,
so the macros declaring the targets set `compilation` with `compilation_of`.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
    "StaticWebAssetsInfo",
)
load(
    "//dotnet/private/rules/common:static_web_assets.bzl",
    "collect_static_web_assets",
)
load(
    "//dotnet/private/rules/ready_to_run:ready_to_run.bzl",
    "compile_ready_to_run_images",
    "get_ready_to_run_tools",
)
load(
    "//dotnet/private/transitions:common.bzl",
    "NO_READY_TO_RUN",
    "platform_to_rid",
    "rid_compatability_transition_outputs",
)

# The runtime identifier an ordinary build resolves to, and so the one every
# target compiles with.
HOST_RID = platform_to_rid()

_COMPILE_CONFIGURATION = dicts.add(
    {"//dotnet:rid": HOST_RID},
    rid_compatability_transition_outputs(HOST_RID),
    NO_READY_TO_RUN,
)

def _compile_configuration_impl(_settings, _attr):
    return _COMPILE_CONFIGURATION

_compile_configuration = transition(
    implementation = _compile_configuration_impl,
    inputs = [],
    outputs = _COMPILE_CONFIGURATION.keys(),
)

COMPILATION_ATTRS = {
    "compilation": attr.label(
        doc = """This target in the configuration it compiles in, when that is another one.

Set by the macro declaring the target, with `compilation_of`.""",
        cfg = _compile_configuration,
        providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo],
    ),
}

def compilation_of(name):
    """What a target's `compilation` is: itself, unless it already compiles where it is.

    Args:
        name: The name of the target, in the package being loaded.

    Returns:
        A select for the `compilation` attribute.
    """
    return select({
        Label("//dotnet/private/rules/common:compiles_here"): None,
        "//conditions:default": ":" + name,
    })

_CompileInputsInfo = provider(
    doc = "What a target compiles from, as `_compile_inputs` gathers it.",
    fields = {"inputs": "list: The attributes and what each holds."},
)

# Attributes that differ between configurations without being compiled from.
_NOT_COMPILED_FROM = ["compilation", "_ready_to_run_tools", "_runtime_pack", "_apphost_pack"]

def _compiled_from(value):
    """What a compile reads of one attribute value.

    Of a dependency, what it gives a compile, which is where a dependency that
    compiled differently shows: its assemblies are other files.
    """
    if type(value) != "Target":
        return value

    if DotnetAssemblyCompileInfo in value:
        info = value[DotnetAssemblyCompileInfo]

        return (info.refs, info.irefs, info.analyzers, info.analyzers_csharp, info.analyzers_fsharp, info.analyzers_vb, info.compile_data, info.exports)

    return value[DefaultInfo].files.to_list()

def _compile_inputs(ctx):
    """What a target compiles from: each attribute, with selects resolved.

    Args:
        ctx: The rule context.

    Returns:
        A list that compares equal between two configurations of the target
        exactly when they compile the same.
    """
    inputs = []

    for name in dir(ctx.attr):
        value = getattr(ctx.attr, name)

        if name in _NOT_COMPILED_FROM or type(value) == "builtin_function_or_method":
            continue

        if type(value) == "list":
            value = [_compiled_from(item) for item in value]
        elif type(value) == "dict":
            value = [(_compiled_from(key), _compiled_from(item)) for (key, item) in value.items()]
        else:
            value = _compiled_from(value)

        inputs.append((name, value))

    return inputs

def _reuse(ctx, compilation, toolchain):
    """The providers of a target whose compilation happened in another configuration.

    The assembly and everything about compiling it come from there. What it
    depends on at run time, and so what it ships, comes from this one.
    """
    compiled = compilation[DotnetAssemblyRuntimeInfo]

    # As the compile actions collect them, assemblies taken from the toolchain
    # included.
    from_toolchain = (
        ([toolchain.host_model] if getattr(ctx.attr, "include_host_model_dll", False) else []) +
        (toolchain.msbuild_dlls if getattr(ctx.attr, "include_msbuild_dlls", False) else [])
    )
    deps = depset(
        [dep[DotnetAssemblyRuntimeInfo] for dep in ctx.attr.deps + from_toolchain],
        transitive = [dep[DotnetAssemblyRuntimeInfo].deps for dep in ctx.attr.deps],
    ) if compiled.libs else depset()

    runtime_info = DotnetAssemblyRuntimeInfo(
        name = compiled.name,
        version = compiled.version,
        libs = compiled.libs,
        pdbs = compiled.pdbs,
        xml_docs = compiled.xml_docs,
        native = compiled.native,
        data = compiled.data,
        resource_assemblies = compiled.resource_assemblies,
        appsetting_files = compiled.appsetting_files,
        nuget_info = compiled.nuget_info,
        deps = deps,
        direct_deps_depsjson_fragment = {dep[DotnetAssemblyRuntimeInfo].name: dep[DotnetAssemblyRuntimeInfo].version for dep in ctx.attr.deps},
        ready_to_run = compile_ready_to_run_images(ctx.actions, get_ready_to_run_tools(ctx), ctx.label, compiled.libs, deps),
    )

    return struct(
        compile_info = compilation[DotnetAssemblyCompileInfo],
        runtime_info = runtime_info,
        static_web_assets_info = compilation[StaticWebAssetsInfo],
        files = compilation[DefaultInfo].files.to_list(),
        inputs_info = compilation[_CompileInputsInfo],
    )

def compile_once(ctx, compile_action, tfm, toolchain, is_application):
    """Compiles the target, or reuses its compilation in the configuration it compiles in.

    Args:
        ctx: The rule context, of a rule with `COMPILATION_ATTRS`.
        compile_action: A function taking (ctx, tfm, toolchain) that compiles
            the srcs and returns a (DotnetAssemblyCompileInfo,
            DotnetAssemblyRuntimeInfo, generated static web assets) tuple.
        tfm: The target framework.
        toolchain: The .Net toolchain to compile with.
        is_application: Whether the target serves its static web assets at the
            root rather than under `_content/<assembly name>`.

    Returns:
        A struct of the `compile_info` and `runtime_info` providers, the
        `static_web_assets_info`, the `files` the compilation produced, and the
        `inputs_info` to return, which says what the target compiles from.
    """
    inputs = _compile_inputs(ctx)

    if ctx.attr.compilation:
        compilation = ctx.attr.compilation[0]

        if compilation[_CompileInputsInfo].inputs == inputs:
            return _reuse(ctx, compilation, toolchain)

    (compile_info, runtime_info, generated_assets) = compile_action(ctx, tfm, toolchain)

    return struct(
        inputs_info = _CompileInputsInfo(inputs = inputs),
        compile_info = compile_info,
        runtime_info = runtime_info,
        static_web_assets_info = collect_static_web_assets(
            label = ctx.label,
            assembly_name = runtime_info.name,
            files = ctx.files.static_web_assets,
            deps = ctx.attr.deps,
            is_application = is_application,
            generated = generated_assets,
        ),
        files = runtime_info.libs + runtime_info.xml_docs + [asset.file for asset in generated_assets],
    )
