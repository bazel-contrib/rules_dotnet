"""Compiles each assembly to ReadyToRun once, in the package that owns it.

A publish used to compile every assembly it shipped, so a library or package
shared by many applications was compiled once per application. The aspects
here compile an assembly where it is defined instead, against its own
dependencies and the publish's framework, which makes the action the same for
every publish that ships it.

The framework is the publish's rather than the one the assembly was built for,
because that is what it runs on: a netstandard2.0 library in a net10.0 publish
is compiled against net10.0. An aspect cannot be handed that framework, and the
parameters it can be handed cannot pick a dependency, so there is one aspect per
framework, which only propagates for a ReadyToRun publish of that framework.

Whether the framework includes ASP.NET Core depends on the application, which
nothing below it knows, so each assembly is compiled for both project SDKs. A
publish only builds the images it ships.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:common.bzl", "FRAMEWORK_COMPATIBILITY")
load("//dotnet/private:providers.bzl", "DotnetAssemblyRuntimeInfo", "DotnetRuntimePackInfo", "DotnetToolPackInfo")
load("//dotnet/private/sdk:packs.bzl", "DEFAULT_SDK", "PROJECT_SDKS", "WEB_SDK", "crossgen2_pack_rids", "runtime_pack_tfms")
load("//dotnet/private/sdk/runtime_packs:runtime_pack_transition.bzl", "runtime_pack_transition")
load("//dotnet/private/transitions:common.bzl", "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS")

DotnetReadyToRunInfo = provider(
    doc = "The ReadyToRun images of an assembly and of everything it depends on.",
    fields = {
        "images": """depset[struct]: One per assembly and framework, each carrying

  * `assembly`: the File that was compiled.
  * `image`: its ReadyToRun image.
  * `framework`: the `key` of the framework it was compiled against.
  * `references`: the tuple of Files it was compiled against besides that.""",
    },
)

DotnetReadyToRunToolsInfo = provider(
    doc = "What a ReadyToRun image is compiled with, for one framework.",
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

def ready_to_run_references(runtime_info):
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
        runtime_info: The DotnetAssemblyRuntimeInfo of the target.

    Returns:
        A struct of `files`, a tuple, and the same as a depset in `depset`.
    """
    by_path = {file.path: file for file in runtime_info.libs}

    for dep in runtime_info.deps.to_list():
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

def _ready_to_run_tools_impl(ctx):
    return [DotnetReadyToRunToolsInfo(
        crossgen2 = ctx.attr._crossgen2_pack[DotnetToolPackInfo],
        framework = ready_to_run_framework(ctx.attr._runtime_pack[0][DotnetRuntimePackInfo]),
    )]

ready_to_run_tools = rule(
    _ready_to_run_tools_impl,
    doc = """What the ReadyToRun aspects compile with for one project SDK.

The target framework comes from the configuration, which the aspects pin to the
publish's. crossgen2 is for the execution platform the dotnet toolchain picks,
as it is for the aspect that runs it.""",
    attrs = {
        "project_sdk": attr.string(
            doc = "The project SDK whose runtime pack the images resolve against.",
            mandatory = True,
            values = PROJECT_SDKS,
        ),
        "_runtime_pack": attr.label(
            default = Label("//dotnet/private/sdk/runtime_packs:runtime_pack"),
            cfg = runtime_pack_transition,
            providers = [DotnetRuntimePackInfo],
        ),
        "_crossgen2_pack": attr.label(
            cfg = "exec",
            default = Label("//dotnet/private:crossgen2_pack"),
            providers = [DotnetToolPackInfo],
        ),
    },
    toolchains = ["//dotnet:toolchain_type"],
    provides = [DotnetReadyToRunToolsInfo],
)

def _pin_framework(target_framework):
    """Configures the tools for the publish's framework, whatever the assembly's."""
    settings = dicts.add(
        {"//dotnet:target_framework": target_framework},
        FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[target_framework],
    )

    def _impl(_settings, _attr):
        return settings

    return transition(implementation = _impl, inputs = [], outputs = settings.keys())

_DEP_ATTRS = ["deps", "exports"]

_TOOLS = {
    DEFAULT_SDK: "_default_tools",
    WEB_SDK: "_web_tools",
}

def _ready_to_run_aspect_impl(target, ctx):
    transitive = [
        dep[DotnetReadyToRunInfo].images
        for name in _DEP_ATTRS
        for dep in getattr(ctx.rule.attr, name, [])
        if DotnetReadyToRunInfo in dep
    ]

    if DotnetAssemblyRuntimeInfo not in target or not target[DotnetAssemblyRuntimeInfo].libs:
        return [DotnetReadyToRunInfo(images = depset(transitive = transitive))]

    runtime_info = target[DotnetAssemblyRuntimeInfo]
    references = ready_to_run_references(runtime_info)
    images = []

    for (project_sdk, attribute) in _TOOLS.items():
        tools = getattr(ctx.attr, attribute)[0][DotnetReadyToRunToolsInfo]
        framework = tools.framework

        for assembly in runtime_info.libs:
            image = ctx.actions.declare_file("{}/r2r/{}/{}/{}/{}".format(
                target.label.name,
                ctx.attr.target_framework,
                project_sdk,
                framework.runtime_identifier,
                assembly.basename,
            ))
            compile_ready_to_run(ctx.actions, tools.crossgen2, framework, references, assembly, image)
            images.append(struct(
                assembly = assembly,
                image = image,
                framework = framework.key,
                references = references.files,
            ))

    return [DotnetReadyToRunInfo(images = depset(images, transitive = transitive))]

def _ready_to_run_aspect(target_framework):
    def _propagates(ctx):
        return ctx.attr.ready_to_run and not ctx.attr.ready_to_run_composite and ctx.attr.target_framework == target_framework

    pin = _pin_framework(target_framework)

    return aspect(
        implementation = _ready_to_run_aspect_impl,
        doc = "Compiles each assembly a {} publish ships to ReadyToRun, in the package that owns it.".format(target_framework),
        attr_aspects = _DEP_ATTRS,
        # Any other publish leaves the aspect out entirely, along with the
        # packs it would fetch.
        propagation_predicate = _propagates,
        attrs = {
            # Read from the publish, which is why it cannot select on them.
            "ready_to_run": attr.bool(),
            "ready_to_run_composite": attr.bool(),
            "target_framework": attr.string(values = FRAMEWORK_COMPATIBILITY.keys()),
            "_default_tools": attr.label(
                default = Label(":ready_to_run_tools_default"),
                cfg = pin,
                providers = [DotnetReadyToRunToolsInfo],
            ),
            "_web_tools": attr.label(
                default = Label(":ready_to_run_tools_web"),
                cfg = pin,
                providers = [DotnetReadyToRunToolsInfo],
            ),
        },
        # Picks the execution platform the way `ready_to_run_tools` does, so
        # crossgen2 runs on the machine it was resolved for.
        toolchains = ["//dotnet:toolchain_type"],
        provides = [DotnetReadyToRunInfo],
    )

# The frameworks crossgen2 shipped for, in band order. A publish of any other
# compiles its images itself.
_FRAMEWORKS = [tfm for tfm in runtime_pack_tfms() if crossgen2_pack_rids(tfm)]

# Bazel only accepts an aspect bound to a top-level name of its own, so the
# aspects cannot be kept in a collection alone. Each name takes the next
# framework, which lets a new band through without a change here, and the
# names left over stay None.
_SLOTS = 12

def _ready_to_run_aspects():
    if len(_FRAMEWORKS) > _SLOTS:
        fail("ReadyToRun has {} frameworks to compile for, but only {} aspects: raise _SLOTS and bind as many names.".format(len(_FRAMEWORKS), _SLOTS))

    return [_ready_to_run_aspect(tfm) for tfm in _FRAMEWORKS] + [None] * (_SLOTS - len(_FRAMEWORKS))

_ASPECTS = _ready_to_run_aspects()

(
    ready_to_run_aspect_0,
    ready_to_run_aspect_1,
    ready_to_run_aspect_2,
    ready_to_run_aspect_3,
    ready_to_run_aspect_4,
    ready_to_run_aspect_5,
    ready_to_run_aspect_6,
    ready_to_run_aspect_7,
    ready_to_run_aspect_8,
    ready_to_run_aspect_9,
    ready_to_run_aspect_10,
    ready_to_run_aspect_11,
) = _ASPECTS

READY_TO_RUN_ASPECTS = dict(zip(_FRAMEWORKS, _ASPECTS))
