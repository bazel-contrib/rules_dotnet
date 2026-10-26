"""Compiles each assembly to ReadyToRun once, in the target that defines it.

A publish used to compile every assembly it shipped, so a library or package
shared by many applications was compiled once per application. Instead, a
publish that compiles image by image puts the framework it runs on in the
configuration, and every target below it compiles its own assemblies against
that framework and its own dependencies. The action is then the same for every
publish of that framework that ships the assembly.

The framework is the one the published binary runs on rather than the one an
assembly was built for: a netstandard2.0 library in a net10.0 publish is
compiled against net10.0. The binary sets it from its own framework and
project SDK, so that the images are compiled against the runtime pack the
publish ships.

The settings are scoped to the target configuration, so the tools a publish
runs are configured once, not once per framework.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:common.bzl", "FRAMEWORK_COMPATIBILITY", "get_highest_compatible_runtime_identifier")
load("//dotnet/private:providers.bzl", "DotnetRuntimePackInfo", "DotnetToolPackInfo")
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

def ready_to_run_references(libs, deps):
    """What an assembly is compiled against besides the framework.

    The assemblies of the target defining it and of everything that target
    depends on, and nothing that depends on it, so that changing the
    application recompiles none of its dependencies and changing a library of
    ours leaves the packages alone. A reference its metadata does not declare
    is left unresolved, and crossgen2 leaves the methods that need it to the
    JIT.

    Sorted, so that the order of the dependency graph cannot change a command
    line.

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

    files = tuple([by_path[path] for path in sorted(by_path)])

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

def compile_ready_to_run_images(actions, tools, label, libs, deps):
    """Compiles a target's own assemblies to ReadyToRun, when a publish asked for them.

    Args:
        actions: The `ctx.actions` to declare the actions with.
        tools: What to compile with, from `get_ready_to_run_tools`, or None
            when no publish asked.
        label: The label of the target, whose package the images go in.
        libs: The target's own assemblies.
        deps: The depset of the DotnetAssemblyRuntimeInfo the target depends on.

    Returns:
        A list with a struct per assembly, carrying the `assembly` compiled, its
        `image`, the `framework` key it was compiled against, and the tuple of
        `references` it was compiled against besides that.
    """
    if tools == None or not libs:
        return []

    references = ready_to_run_references(libs, deps)
    images = []

    for assembly in libs:
        image = actions.declare_file("{}/r2r/{}".format(label.name, assembly.basename))
        compile_ready_to_run(actions, tools.crossgen2, tools.framework, references, assembly, image)
        images.append(struct(
            assembly = assembly,
            image = image,
            framework = tools.framework.key,
            references = references.files,
        ))

    return images

def get_ready_to_run_tools(ctx):
    """The tools to compile the target's ReadyToRun images with.

    Args:
        ctx: The rule context, of a rule with `READY_TO_RUN_ATTRS`.

    Returns:
        The DotnetReadyToRunToolsInfo, or None when no publish asked for images.
    """
    tools = ctx.attr._ready_to_run_tools[0]

    return tools[DotnetReadyToRunToolsInfo] if DotnetReadyToRunToolsInfo in tools else None

_PINNED = ["//dotnet:target_framework"] + ["//dotnet:framework_compatible_%s" % framework for framework in FRAMEWORK_COMPATIBILITY.keys()]

def _pin_framework_impl(settings, _attr):
    framework = settings[READY_TO_RUN_FRAMEWORK]

    # Unchanged, which keeps the configuration the target is in.
    if not framework:
        return {key: settings[key] for key in _PINNED}

    return dicts.add(
        {"//dotnet:target_framework": framework},
        FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[framework],
    )

# Moves the tools onto the publish's framework, whatever the target's, so that
# the targets below one publish share them.
_pin_framework = transition(
    implementation = _pin_framework_impl,
    inputs = [READY_TO_RUN_FRAMEWORK] + _PINNED,
    outputs = _PINNED,
)

READY_TO_RUN_ATTRS = {
    "_ready_to_run_tools": attr.label(
        doc = """What the target compiles its ReadyToRun images with.

Resolves to nothing unless a publish of the target asked for images, so that
no other build analyses the packs.""",
        default = Label("//dotnet/private/rules/ready_to_run:tools"),
        cfg = _pin_framework,
    ),
}

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

The target framework is the publish's, pinned by `READY_TO_RUN_ATTRS`, and the
project SDK the published binary's.""",
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
)
