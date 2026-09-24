"""Publishes NuGet packages with `dotnet nuget push`."""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(
    "//dotnet/private:common.bzl",
    "get_toolchain",
    "targets_windows",
    "to_rlocation_path",
)
load("//dotnet/private:providers.bzl", "NuGetPackInfo")

def _nuget_push_impl(ctx):
    toolchain = get_toolchain(ctx)
    is_windows = targets_windows(ctx)

    packages = []
    staged = []
    for target in ctx.attr.packages:
        if NuGetPackInfo in target:
            info = target[NuGetPackInfo]
            packages.append(info.nupkg)
            staged.append(info.nupkg)

            # Beside its package, where `dotnet nuget push` finds and pushes it too.
            if info.snupkg:
                staged.append(info.snupkg)
        else:
            files = target.files.to_list()
            found = [file for file in files if file.extension == "nupkg"]
            if not found:
                fail("{}: {} has no .nupkg to push".format(ctx.label, target.label))
            packages += found
            staged += files

    push_args = []
    if ctx.attr.skip_duplicate:
        push_args.append("--skip-duplicate")
    if ctx.attr.no_symbols:
        push_args.append("--no-symbols")
    if ctx.attr.symbol_source:
        push_args += ["--symbol-source", ctx.attr.symbol_source]
    if ctx.attr.timeout > 0:
        push_args += ["--timeout", str(ctx.attr.timeout)]

    package_paths = [to_rlocation_path(ctx, package) for package in packages]
    config_path = to_rlocation_path(ctx, ctx.file.nuget_config) if ctx.file.nuget_config else ""

    if is_windows:
        substitutions = {
            "TEMPLATED_packages": " ".join(["\"{}\"".format(path) for path in package_paths]),
            "TEMPLATED_source": ctx.attr.source,
            "TEMPLATED_push_args": " ".join(["\"{}\"".format(arg) for arg in push_args]),
            "TEMPLATED_config_file": config_path,
        }
    else:
        substitutions = {
            "TEMPLATED_packages": shell.array_literal(package_paths),
            "TEMPLATED_source": shell.quote(ctx.attr.source),
            "TEMPLATED_push_args": shell.array_literal(push_args),
            "TEMPLATED_config_file": shell.quote(config_path),
        }
    substitutions["TEMPLATED_dotnet"] = to_rlocation_path(ctx, toolchain.runtime.files_to_run.executable)

    launcher = ctx.actions.declare_file("{}.{}".format(ctx.label.name, "bat" if is_windows else "sh"))
    ctx.actions.expand_template(
        template = ctx.file._launcher_bat if is_windows else ctx.file._launcher_sh,
        output = launcher,
        substitutions = substitutions,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = staged + ([ctx.file.nuget_config] if ctx.file.nuget_config else []),
        transitive_files = depset(transitive = [
            toolchain.runtime.files,
            # `dotnet nuget` is an SDK command, and the SDK sits in the runtime
            # filegroup's runfiles rather than its files.
            toolchain.runtime[DefaultInfo].default_runfiles.files,
        ]),
    ).merge(ctx.attr._bash_runfiles[DefaultInfo].default_runfiles)

    return [DefaultInfo(executable = launcher, runfiles = runfiles)]

nuget_push = rule(
    _nuget_push_impl,
    doc = """Publishes packages to a NuGet feed when run.

    bazel run //:push
    bazel run //:push -- --api-key <key>
    bazel run //:push -- --source ./local-feed

Runs `dotnet nuget push` from the toolchain's SDK once per package, with a
`.snupkg` built beside a package pushed along with it. Arguments after `--`
go to `dotnet nuget push`; an explicit `--source` or `--api-key` there wins
over the target's `source` and over the `NUGET_API_KEY` environment variable,
which stands in for `--api-key` when set (`NUGET_SYMBOL_API_KEY` likewise for
`--symbol-api-key`). Failing both, credentials come from the user's
`NuGet.Config` as they would for any `dotnet nuget push`. Set
`RULES_DOTNET_NUGET_PUSH_DRY_RUN=1` to print the commands instead of running
them.
""",
    attrs = {
        "packages": attr.label_list(
            doc = "The `nuget_pack` targets, or `.nupkg` files, to push.",
            mandatory = True,
            allow_empty = False,
            allow_files = [".nupkg", ".snupkg"],
        ),
        "source": attr.string(
            doc = """The feed to push to: a URL such as `https://api.nuget.org/v3/index.json`,
            a folder, or the name of a source in `NuGet.Config`. Unset, the feed has to be
            given with `--source` when the target is run.""",
        ),
        "symbol_source": attr.string(
            doc = "A separate feed for the symbol packages. Unset, they go to `source`.",
        ),
        "skip_duplicate": attr.bool(
            doc = "Whether a version the feed already has is a warning rather than an error.",
            default = True,
        ),
        "no_symbols": attr.bool(
            doc = "Whether to leave the symbol packages out.",
            default = False,
        ),
        "timeout": attr.int(
            doc = "Seconds to wait for a push, or 0 for `dotnet nuget push`'s default.",
            default = 0,
        ),
        "nuget_config": attr.label(
            doc = "A `NuGet.Config` to use in place of the user's, for a hermetic push.",
            allow_single_file = True,
        ),
        "_launcher_sh": attr.label(
            default = "//dotnet/private:nuget_push.sh.tpl",
            allow_single_file = True,
        ),
        "_launcher_bat": attr.label(
            default = "//dotnet/private:nuget_push.bat.tpl",
            allow_single_file = True,
        ),
        "_bash_runfiles": attr.label(default = "@rules_shell//shell/runfiles"),
        "_windows_constraint": attr.label(default = "@platforms//os:windows"),
    },
    executable = True,
    toolchains = ["//dotnet:toolchain_type"],
)
