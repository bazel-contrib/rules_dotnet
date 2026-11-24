"""Runs the C# or F# compiler, in its persistent worker or through the wrapper script."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private/icu:settings.bzl", "globalization_env", "icu_wrapper_arguments")

def run_compiler(
        actions,
        *,
        mnemonic,
        progress_message,
        toolchain,
        compiler,
        compiler_wrapper,
        compiler_worker,
        args,
        inputs,
        outputs):
    """Runs `compiler` with `args`, in the persistent worker when there is one.

    Args:
        actions: The rule's `ctx.actions`.
        mnemonic: The action's mnemonic.
        progress_message: The action's progress message.
        toolchain: The resolved .NET toolchain.
        compiler: The toolchain's compiler target, such as `toolchain.csharp_compiler`.
        compiler_wrapper: The script that runs the compiler when there is no worker.
        compiler_worker: The worker's `FilesToRunProvider`, or None.
        args: The compiler's arguments, which always go into a response file.
        inputs: A depset of the files the compiler reads.
        outputs: The files the compiler writes.
    """

    # A compile carrying the targeting pack's references is far past any OS
    # command line limit.
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    if compiler_worker:
        # A `FilesToRunProvider` rather than a `File`, so that the worker's own
        # runfiles reach the action without being listed as tools.
        executable = compiler_worker
        wrapper_arguments, wrapper_tools, icu_tools = [], [], []
        execution_requirements = {
            "requires-worker-protocol": "json",
            "supports-path-mapping": "1",
            "supports-workers": "1",
        }
    else:
        executable = compiler_wrapper
        wrapper_arguments, icu_tools = icu_wrapper_arguments(actions, toolchain)
        wrapper_tools = [compiler_wrapper]
        execution_requirements = {"supports-path-mapping": "1"}

    host = toolchain.compiler_host.files_to_run.executable
    compiler_dll = compiler.files_to_run.executable

    # Both the worker and the wrapper script take the dotnet host and the
    # compiler first, then the compiler's arguments.
    actions.run(
        mnemonic = mnemonic,
        progress_message = progress_message,
        inputs = inputs,
        tools = depset(
            direct = wrapper_tools + [host, compiler_dll],
            transitive = icu_tools + [
                toolchain.compiler_host.default_runfiles.files,
                compiler.default_runfiles.files,
            ],
        ),
        outputs = outputs,
        executable = executable,
        arguments = wrapper_arguments + [host.path, compiler_dll.path, args],
        env = dicts.add({"DOTNET_CLI_HOME": host.dirname}, globalization_env(toolchain)),
        execution_requirements = execution_requirements,
    )
