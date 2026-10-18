"""The pinned hub: reads the lock file, validates freshness, generates the hub.

The hub never resolves; it serves exactly what the lock file pins. Freshness
is the Starlark-computed input hash the extension passes in: the extension
re-evaluates whenever the tag changes, so a changed hash lands here as a
changed attribute, which refetches the hub and trips the comparison.
"""

load(
    "//dotnet/private/nuget_resolve:input_hash.bzl",
    "classify_input_hash",
)
load("//dotnet/private/nuget_resolve:lock.bzl", "parse_lock")
load(
    "//dotnet/private/rules/nuget:nuget_repo.bzl",
    "nuget_archive_name",
    "write_hub_files",
)

def _spoke_archive(id, version):
    archive = "@{}//".format(nuget_archive_name(id, version))
    return struct(archive = archive, package_info = archive + ":package_info.bzl")

def _repin_command(resolve_name, framework):
    return "REPIN=1 bazel run @{}.{}//:pin".format(resolve_name, framework)

def _pinned_hub_impl(ctx):
    path = str(ctx.attr.lock_file)
    lock = parse_lock(ctx.read(ctx.attr.lock_file), path)
    repin = _repin_command(ctx.attr.resolve_name, ctx.attr.framework)

    status = classify_input_hash(lock.input_hash, ctx.attr.input_hash)
    if status == "legacy":
        # buildifier: disable=print
        print("Warning: {} was written with a superseded input hash algorithm. Regenerate it with `{}`.".format(path, repin))
    elif status == "mismatch":
        message = "{} is out of date: its inputs no longer match the resolve tag in MODULE.bazel. Regenerate it with `{}`.".format(path, repin)
        if ctx.os.environ.get("REPIN") != None:
            # A repin is in flight: the pin target must build while the lock
            # file is stale.
            # buildifier: disable=print
            print("Warning: " + message)
        elif ctx.attr.fail_if_repin_required:
            fail(message)
        else:
            # buildifier: disable=print
            print("Warning: " + message)

    group = lock.frameworks.get(ctx.attr.framework)
    if group == None:
        fail("{} has no framework '{}'. It has: {}. Regenerate it with `{}`.".format(
            path,
            ctx.attr.framework,
            ", ".join(lock.frameworks.keys()),
            repin,
        ))

    packages = [
        {"id": package.id, "sha512": package.sha512, "version": package.version}
        for package in group
    ]
    write_hub_files(
        ctx,
        packages,
        _spoke_archive,
        extra_root_build = "\nalias(name = \"pin\", actual = \"@unpinned_{}//:pin\")\n".format(ctx.attr.resolve_name),
    )

pinned_hub = repository_rule(
    _pinned_hub_impl,
    doc = "Generates the hub for one framework of a pinned resolve tag.",
    attrs = {
        "lock_file": attr.label(
            doc = "The checked-in nuget_resolve.json.",
            mandatory = True,
        ),
        "input_hash": attr.string(
            doc = "The Starlark-computed hash of the resolve inputs.",
            mandatory = True,
        ),
        "fail_if_repin_required": attr.bool(
            doc = "Fail the fetch when the lock file's input hash no longer matches; otherwise warn and build on.",
            default = True,
        ),
        "framework": attr.string(
            doc = "The target framework this hub serves.",
            mandatory = True,
        ),
        "resolve_name": attr.string(
            doc = "The `name` of the resolve tag, used for the `:pin` alias and repin instructions.",
            mandatory = True,
        ),
    },
    environ = ["REPIN"],
)
