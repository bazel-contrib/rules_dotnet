"""Compiles each assembly to ReadyToRun in the target that defines it.

A ReadyToRun publish puts the framework and project SDK of its binary in the
configuration, and every target below the binary compiles its own assemblies
against that runtime pack and its own dependencies. A netstandard2.0 library
in a net10.0 publish is compiled against net10.0, once for every publish of
that framework that ships it.

The assemblies are not compiled again there: each target depends on itself
outside the publish, through an edge that resets the settings, and reuses
that build.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:common.bzl", "FRAMEWORK_COMPATIBILITY", "get_highest_compatible_runtime_identifier")
load("//dotnet/private:providers.bzl", "DotnetReadyToRunInfo", "DotnetRuntimePackInfo", "DotnetToolPackInfo")
load("//dotnet/private/sdk:packs.bzl", "RUNTIME_PACK_LOOKUP_TABLE")
load(
    "//dotnet/private/transitions:common.bzl",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "NO_READY_TO_RUN",
    "READY_TO_RUN_FRAMEWORK",
    "READY_TO_RUN_PROJECT_SDK",
)

DotnetReadyToRunToolsInfo = provider(
    doc = "What the targets below a ReadyToRun publish compile their images with.",
    fields = {
        "crossgen2": "DotnetToolPackInfo: crossgen2, for the execution platform.",
        "framework": "struct: The framework, as `ready_to_run_framework` returns it.",
    },
)

def native_target(runtime_identifier):
    """Splits a runtime identifier into --targetos/--targetarch.

    Both crossgen2 and ilc take the target this way, which is what lets either
    of them cross-compile.

    Args:
        runtime_identifier: The runtime identifier to compile for.

    Returns:
        The (os, arch) pair.
    """
    parts = runtime_identifier.split("-")

    if len(parts) < 2 or parts[0] not in ("linux", "osx", "win"):
        fail("Cannot compile native code for {}".format(runtime_identifier))

    return ("windows" if parts[0] == "win" else parts[0], parts[-1])

def ready_to_run_framework(runtime_pack_info):
    """The framework a ReadyToRun image resolves against: a runtime pack.

    Args:
        runtime_pack_info: The DotnetRuntimePackInfo of the runtime pack.

    Returns:
        A struct of `runtime_identifier`, `libs`, the assemblies in the order
        crossgen2 takes them, `files`, the same as a depset, and `key`, which
        tells frameworks apart without comparing their assemblies.
    """
    packs = runtime_pack_info.assembly_runtime_infos
    libs = [lib for pack in packs for lib in pack.libs]

    return struct(
        runtime_identifier = runtime_pack_info.runtime_identifier,
        libs = libs,
        files = depset(libs),
        key = " ".join([runtime_pack_info.runtime_identifier] + ["{}/{}".format(pack.name, pack.version) for pack in packs]),
    )

def _mapped_path(file):
    """The path of `file` as `--experimental_output_paths=strip` passes it to an action."""
    if file.is_source:
        return file.path

    (output_dir, _configuration, rest) = file.path.split("/", 2)

    return "{}/cfg/{}".format(output_dir, rest)

def ready_to_run_references(libs, deps):
    """What an assembly is compiled against besides the framework.

    The assemblies of its target and of everything that target depends on, so
    that changing the application recompiles none of its dependencies. crossgen2
    leaves methods needing any other reference to the JIT.

    Sorted by the path path mapping passes, so that neither the order of the
    dependency graph nor the configurations of the references change the
    command line.

    Args:
        libs: The target's own assemblies.
        deps: The depset of the DotnetAssemblyRuntimeInfo it depends on.

    Returns:
        A struct of `files`, a tuple, and the same as a depset in `depset`.
    """
    by_path = {file.path: file for file in libs}

    for dep in deps.to_list():
        for file in dep.libs:
            by_path[file.path] = file

    files = tuple(sorted(by_path.values(), key = _mapped_path))

    return struct(files = files, depset = depset(files))

def crossgen2_args(actions, framework, references):
    """The arguments every crossgen2 invocation starts with.

    The framework comes first, so that it takes precedence over a package
    shipping an assembly of the same name.

    The references alone run past any OS command line limit, so they always go
    into a parameter file. Each action builds its own rather than sharing one
    written ahead of time, because Bazel rewrites the paths inside a parameter
    file it writes for a path-mapped action and cannot rewrite those in a file
    that already exists.

    Args:
        actions: The `ctx.actions` to create the arguments with.
        framework: The framework, from `ready_to_run_framework`.
        references: The Files to resolve against besides the framework.

    Returns:
        The Args, which the caller adds the output and the inputs to.
    """
    (target_os, target_arch) = native_target(framework.runtime_identifier)

    args = actions.args()
    args.add("--targetos:" + target_os)
    args.add("--targetarch:" + target_arch)
    args.add("-O")
    args.add_all(framework.libs, format_each = "-r:%s")
    args.add_all(references, format_each = "-r:%s")
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    return args

def compile_ready_to_run(actions, crossgen2, framework, references, assembly, image):
    """Compiles one assembly to a ReadyToRun image.

    Args:
        actions: The `ctx.actions` to declare the action with.
        crossgen2: The DotnetToolPackInfo of crossgen2.
        framework: The framework, from `ready_to_run_framework`.
        references: What else the assembly resolves against, from
            `ready_to_run_references`.
        assembly: The File to compile.
        image: The File to write the image to.
    """
    args = crossgen2_args(actions, framework, references.files)
    args.add(image, format = "--out:%s")
    args.add(assembly)

    actions.run(
        executable = crossgen2.tool,
        arguments = [args],
        inputs = depset([assembly], transitive = [references.depset, framework.files, crossgen2.files]),
        outputs = [image],
        mnemonic = "Crossgen2",
        progress_message = "Compiling %{output} to ReadyToRun",
        execution_requirements = {"supports-path-mapping": "1"},
    )

def ready_to_run_images(ctx, runtime_info, deps):
    """The ReadyToRun images of a target and of everything it depends on.

    Args:
        ctx: The rule context, of a rule with `READY_TO_RUN_ATTRS`.
        runtime_info: The DotnetAssemblyRuntimeInfo of the target.
        deps: The targets it depends on, whose images it passes on.

    Returns:
        A list of the DotnetReadyToRunInfo, empty unless a publish asked for images.
    """
    tools = ctx.attr._ready_to_run_tools

    if DotnetReadyToRunToolsInfo not in tools:
        return []

    tools = tools[DotnetReadyToRunToolsInfo]
    images = []

    if runtime_info.libs:
        references = ready_to_run_references(runtime_info.libs, runtime_info.deps)

        for assembly in runtime_info.libs:
            image = ctx.actions.declare_file("{}/r2r/{}".format(ctx.label.name, assembly.basename))
            compile_ready_to_run(ctx.actions, tools.crossgen2, tools.framework, references, assembly, image)
            images.append(struct(
                assembly = assembly,
                image = image,
                framework = tools.framework.key,
                references = references.files,
            ))

    return [DotnetReadyToRunInfo(
        images = depset(images, transitive = [dep[DotnetReadyToRunInfo].images for dep in deps if DotnetReadyToRunInfo in dep]),
    )]

READY_TO_RUN_ATTRS = {
    "_ready_to_run_tools": attr.label(
        doc = """What the target compiles its ReadyToRun images with.

Resolves to nothing unless a publish of the target asked for images, so that
no other build analyses the packs.""",
        default = Label("//dotnet/private/rules/ready_to_run:tools"),
    ),
}

def _without_ready_to_run_impl(_settings, _attr):
    return NO_READY_TO_RUN

_without_ready_to_run = transition(
    implementation = _without_ready_to_run_impl,
    inputs = [],
    outputs = NO_READY_TO_RUN.keys(),
)

READY_TO_RUN_COMPILATION_ATTRS = {
    "compilation": attr.label(
        doc = """The target itself outside a ReadyToRun publish, whose build it reuses
inside one. Set by the rule; there is no need to set it.""",
        cfg = _without_ready_to_run,
    ),
}

def ready_to_run_initializer(name, **_kwargs):
    """Points `compilation` at the target itself, under a ReadyToRun publish.

    An attribute default can neither name its target nor be a select, so the
    rule's initializer sets it. Elsewhere the edge would lead back to the target
    itself.

    Args:
        name: The name of the target.
        **_kwargs: Its other attributes, which are left as they are.

    Returns:
        The value of `compilation`.
    """
    return {
        "compilation": select({
            Label("//dotnet/private/rules/ready_to_run:off"): None,
            # A relative label would resolve in this file's package.
            "//conditions:default": native.package_relative_label(name),
        }),
    }

def ready_to_run_compilation(ctx):
    """The target outside a ReadyToRun publish, when it is inside one.

    Args:
        ctx: The rule context, of a rule with `READY_TO_RUN_COMPILATION_ATTRS`.

    Returns:
        The Target whose build to reuse, or None where the target builds itself.
    """
    return ctx.attr.compilation[0] if ctx.attr.compilation else None

_PINNED = ["//dotnet:target_framework"] + ["//dotnet:framework_compatible_%s" % framework for framework in FRAMEWORK_COMPATIBILITY.keys()]

def _pin_framework_impl(settings, _attr):
    framework = settings[READY_TO_RUN_FRAMEWORK]

    # Only a target built directly has no framework.
    if not framework:
        return {key: settings[key] for key in _PINNED}

    return dicts.add(
        {"//dotnet:target_framework": framework},
        FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[framework],
    )

# Puts the tools on the published binary's framework, whatever the target's, so
# that the targets below one publish share them.
_pin_framework = transition(
    implementation = _pin_framework_impl,
    inputs = [READY_TO_RUN_FRAMEWORK] + _PINNED,
    outputs = _PINNED,
)

def _runtime_pack_impl(settings, _attr):
    project_sdk = settings[READY_TO_RUN_PROJECT_SDK]
    target_framework = settings["//dotnet:target_framework"]
    by_rid = RUNTIME_PACK_LOOKUP_TABLE.get(project_sdk, {}).get(target_framework, {})
    pack = by_rid.get(get_highest_compatible_runtime_identifier(settings["//dotnet:rid"], by_rid.keys()))

    if not pack:
        fail("No runtime pack to compile ReadyToRun images against for {}/{}/{}".format(
            project_sdk,
            target_framework,
            settings["//dotnet:rid"],
        ))

    return dicts.add({"//dotnet/private/sdk/runtime_packs:runtime_pack": pack}, NO_READY_TO_RUN)

_runtime_pack_transition = transition(
    implementation = _runtime_pack_impl,
    inputs = [READY_TO_RUN_PROJECT_SDK, "//dotnet:target_framework", "//dotnet:rid"],
    outputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack"] + NO_READY_TO_RUN.keys(),
)

def _ready_to_run_tools_impl(ctx):
    return [DotnetReadyToRunToolsInfo(
        crossgen2 = ctx.attr._crossgen2_pack[DotnetToolPackInfo],
        framework = ready_to_run_framework(ctx.attr._runtime_pack[0][DotnetRuntimePackInfo]),
    )]

ready_to_run_tools = rule(
    _ready_to_run_tools_impl,
    doc = """What the targets below a ReadyToRun publish compile their images with.

The target framework and project SDK are the published binary's.""",
    attrs = {
        "_runtime_pack": attr.label(
            default = Label("//dotnet/private/sdk/runtime_packs:runtime_pack"),
            cfg = _runtime_pack_transition,
            providers = [DotnetRuntimePackInfo],
        ),
        "_crossgen2_pack": attr.label(
            default = Label("//dotnet/private:crossgen2_pack"),
            providers = [DotnetToolPackInfo],
        ),
    },
    provides = [DotnetReadyToRunToolsInfo],
    cfg = _pin_framework,
)
