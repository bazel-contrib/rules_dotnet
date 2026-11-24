"""Copies a publish's files into place, one script per action."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("//dotnet/private:common.bzl", "get_toolchain")

# How many sources one `cp` takes, to stay clear of the execve argument limit.
_COPY_BATCH = 128

def _batch_path(path):
    """`path` as it has to appear between double quotes in a batch file."""

    # cmd.exe expands `%` even inside quotes.
    return path.replace("/", "\\").replace("%", "%%")

def _render_batch(by_directory, renamed, trees):
    # A batch file carries on past a failed command, which would leave a
    # declared directory silently incomplete, hence `|| exit /b 1`. `copy`
    # concatenates several sources, so each file takes its own line.
    lines = ["@echo off"]

    for (directory, sources) in by_directory.items():
        lines.append("if not exist \"{dir}\" mkdir \"{dir}\" || exit /b 1".format(dir = _batch_path(directory)))
        for src in sources:
            lines.append("copy /Y \"{}\" \"{}\" >NUL || exit /b 1".format(_batch_path(src.path), _batch_path(directory)))

    for (src, dst) in renamed:
        lines.append("copy /Y \"{}\" \"{}\" >NUL || exit /b 1".format(_batch_path(src.path), _batch_path(dst)))

    for (src, dst) in trees:
        lines.append("if not exist \"{dir}\" mkdir \"{dir}\" || exit /b 1".format(dir = _batch_path(dst)))
        lines.append("for %%F in (\"{}\\*\") do copy /Y \"%%F\" \"{}\" >NUL || exit /b 1".format(_batch_path(src.path), _batch_path(dst)))

    return lines

def _render_shell(by_directory, renamed, trees):
    lines = ["#! /usr/bin/env bash", "set -eou pipefail"]

    for (directory, sources) in by_directory.items():
        lines.append("mkdir -p {}".format(shell.quote(directory)))
        for start in range(0, len(sources), _COPY_BATCH):
            lines.append("cp -f {} {}".format(
                " ".join([shell.quote(src.path) for src in sources[start:start + _COPY_BATCH]]),
                shell.quote(directory),
            ))

    for (src, dst) in renamed:
        lines.append("cp -f {} {}".format(shell.quote(src.path), shell.quote(dst)))

    for (src, dst) in trees:
        lines.append("mkdir -p {}".format(shell.quote(dst)))
        lines.append("cp -Rf {}/. {}".format(shell.quote(src.path), shell.quote(dst)))

    return lines

def render_copy_script(copies, is_windows, directories = []):
    """The lines of a script that copies every source to its destination.

    A self-contained publish copies hundreds of files, so each directory is
    created once and, on Unix, the files that keep their name are copied in
    batches rather than one process per file. A directory source is copied as
    its contents.

    Args:
        copies: The (source File, destination path) pairs, one per destination.
        is_windows: Whether to write a batch file rather than a shell script.
        directories: Directories to create even when no file lands in them.

    Returns:
        A list of script lines.
    """
    by_directory = {directory: [] for directory in directories}
    renamed = []
    trees = []

    for (src, dst) in copies:
        if src.is_directory:
            trees.append((src, dst))
            continue

        directory = paths.dirname(dst)
        by_directory.setdefault(directory, [])

        if src.basename == paths.basename(dst):
            by_directory[directory].append(src)
        else:
            renamed.append((src, dst))

    return _render_batch(by_directory, renamed, trees) if is_windows else _render_shell(by_directory, renamed, trees)

def declare_like(ctx, source, path, sibling = None):
    """Declares where `source` is copied to: a directory for a tree artifact, else a file."""
    if source.is_directory:
        return ctx.actions.declare_directory(path, sibling = sibling)
    return ctx.actions.declare_file(path, sibling = sibling)

def run_copy_script(ctx, copies, suffix, mnemonic, progress_message, directory = None):
    """Runs one action that copies every (source, destination) pair.

    Args:
        ctx: The rule context.
        copies: The (source, destination) pairs. A destination is a File, or a
            path inside `directory` when one is given.
        suffix: Tells this script apart from the target's other copy scripts.
        mnemonic: The action's mnemonic.
        progress_message: The action's progress message.
        directory: The directory to copy into, which is then the only output.

    Returns:
        The action's outputs.
    """

    # The script runs where the build runs, which is not the publish's target
    # platform when cross-compiling; the toolchain is resolved for the former.
    is_windows = get_toolchain(ctx).dotnetinfo.os == "windows"

    if directory:
        # Created even when nothing lands in it: a remote worker does not
        # create a declared directory.
        outputs = [directory]
        directories = [directory.path]
        pairs = [(src, "{}/{}".format(directory.path, dst)) for (src, dst) in copies]
    else:
        outputs = [dst for (_, dst) in copies]
        directories = []
        pairs = [(src, dst.path) for (src, dst) in copies]

    script = ctx.actions.declare_file("{}.{}.{}".format(ctx.label.name, suffix, "bat" if is_windows else "sh"))

    ctx.actions.write(
        output = script,
        content = ("\r\n" if is_windows else "\n").join(render_copy_script(pairs, is_windows, directories)),
        is_executable = True,
    )
    ctx.actions.run(
        executable = script,
        inputs = depset([src for (src, _) in copies]),
        outputs = outputs,
        tools = [script],
        mnemonic = mnemonic,
        progress_message = progress_message,
    )

    return outputs
