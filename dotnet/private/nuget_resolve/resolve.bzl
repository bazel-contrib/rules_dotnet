"""The unpinned resolve repository: runs the resolver tool and offers `:pin`.

Every `resolve` tag gets one of these, pinned or not: the pinned hubs only
read the checked-in lock file, so repinning always goes through this
repository, which resolves fresh.
"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc")

# A bash script after the rules_jvm_external pin.sh pattern: locate the
# generated lock file through the runfiles library and copy it into the
# workspace. {dest} is the workspace-relative destination, {message} the
# closing note.
_PIN_SH = """\
#!/usr/bin/env bash

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${{RUNFILES_DIR:-/dev/null}}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${{RUNFILES_MANIFEST_FILE:-/dev/null}}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  {{ echo>&2 "ERROR: cannot find $f"; exit 1; }}; f=; set -e
# --- end runfiles.bash initialization v3 ---

set -euo pipefail
if [[ -z "${{BUILD_WORKSPACE_DIRECTORY:-}}" ]]; then
  echo >&2 "ERROR: BUILD_WORKSPACE_DIRECTORY is not set; run this target with 'bazel run @<repo>//:pin'."
  exit 1
fi
resolved_file=$(rlocation "${{1#external\\/}}")
if [[ ! -e $resolved_file ]]; then
  # for --experimental_sibling_repository_layout
  resolved_file="${{1#..\\/}}"
fi
if [[ ! -e $resolved_file ]]; then (echo >&2 "Failed to locate the resolved lock file: $1" && exit 1) fi
dest="$BUILD_WORKSPACE_DIRECTORY/{dest}"

cp "$resolved_file" "$dest"
echo "{message}"
"""

_BUILD = """\
"GENERATED"

# The native sh_binary no longer exists in Bazel 9; rules_shell is a non-dev
# dependency of rules_dotnet, so the label resolves in every consumer.
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

package(default_visibility = ["//visibility:public"])

exports_files(["nuget_resolve.json"])

sh_binary(
    name = "pin",
    srcs = ["pin.sh"],
    args = ["$(rlocationpath :nuget_resolve.json)"],
    data = [
        ":nuget_resolve.json",
        "@bazel_tools//tools/bash/runfiles",
    ],
)
"""

def _is_windows(repository_ctx):
    return repository_ctx.os.name.lower().find("windows") != -1

def _netrc_path(ctx):
    """Resolves the netrc file to hand the resolver tool, or None.

    Returns the `netrc` attr's path when set. Otherwise falls back to the
    user's netrc ($HOME/.netrc) via `read_user_netrc`, the same fallback the
    downloads use; since the tool consumes a netrc path rather than parsed
    entries (and the sandboxed fetch redirects HOME, so a $HOME/.netrc probe
    from C# would miss the real file), the parsed entries are serialized to
    a `user.netrc` file in the repository. Returns None when no netrc exists.
    """
    if ctx.attr.netrc:
        return str(ctx.path(ctx.attr.netrc))
    netrc = read_user_netrc(ctx)
    if not netrc:
        return None
    lines = []
    for machine, entry in sorted(netrc.items()):
        lines.append("machine " + machine if machine else "default")
        for key in ("login", "password", "account"):
            if key in entry:
                lines.append("{} {}".format(key, entry[key]))
    ctx.file("user.netrc", "\n".join(lines) + "\n")
    return str(ctx.path("user.netrc"))

def _nuget_resolve_impl(ctx):
    spec = {
        "frameworks": ctx.attr.frameworks,
        "packages": ctx.attr.packages,
        "sources": ctx.attr.sources,
    }
    ctx.file("spec.json", json.encode_indent(spec, prefix = "", indent = "  "))

    dotnet = str(ctx.path(ctx.attr.dotnet))
    tool = str(ctx.path(ctx.attr.tool))
    home = str(ctx.path("home"))
    ctx.file("home/.keep", "")
    env = {
        "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
        "DOTNET_CLI_HOME": home,
        "DOTNET_NOLOGO": "1",
        "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1",
        "NUGET_PACKAGES": str(ctx.path("nuget_packages")),
        "NUGET_HTTP_CACHE_PATH": str(ctx.path("nuget_http_cache")),
        # Offline revocation checks: signed-package verification can hang on
        # online CRL fetches in restricted-network repos (matches tool.bzl).
        "NUGET_CERT_REVOCATION_MODE": "offline",
    }
    if _is_windows(ctx):
        env["USERPROFILE"] = home
    else:
        env["HOME"] = home

    args = [
        dotnet,
        "exec",
        tool,
        "--spec",
        "spec.json",
        "--input-hash",
        ctx.attr.input_hash,
        "--output",
        "nuget_resolve.json",
    ]
    netrc_path = _netrc_path(ctx)
    if netrc_path:
        args += ["--netrc", netrc_path]

    result = ctx.execute(args, environment = env, timeout = 1200)
    if result.return_code != 0:
        fail("NuGet resolution failed:\n" + result.stdout + result.stderr)

    if ctx.attr.lock_file:
        label = ctx.attr.lock_file
        dest = (label.package + "/" + label.name) if label.package else label.name
        message = "Updated {}.".format(dest)
    else:
        dest = "nuget_resolve.json"
        message = "Wrote {0}. Check it in and point the resolve tag at it with lock_file = \"//:{0}\".".format(dest)

    ctx.file("pin.sh", _PIN_SH.format(dest = dest, message = message), executable = True)
    ctx.file("BUILD.bazel", _BUILD)

nuget_resolve = repository_rule(
    _nuget_resolve_impl,
    doc = "Resolves the full transitive graph with the NuGet resolver tool and writes nuget_resolve.json.",
    attrs = {
        "packages": attr.string_dict(
            doc = "Package id to version range, in PackageReference syntax.",
            mandatory = True,
            allow_empty = False,
        ),
        "frameworks": attr.string_list(
            doc = "The target frameworks to resolve for.",
            mandatory = True,
            allow_empty = False,
        ),
        "sources": attr.string_list(
            doc = "The NuGet feeds, in lookup order.",
            mandatory = True,
            allow_empty = False,
        ),
        "input_hash": attr.string(
            doc = "The Starlark-computed hash of the resolve inputs, stamped into the lock file by the tool.",
            mandatory = True,
        ),
        "lock_file": attr.label(
            doc = "The checked-in lock file; determines where `:pin` writes.",
        ),
        "netrc": attr.label(
            doc = "A netrc file with the credentials for the feeds.",
        ),
        "dotnet": attr.label(
            doc = "The dotnet binary of the bootstrap SDK.",
            mandatory = True,
        ),
        "tool": attr.label(
            doc = "The published resolver dll, `@nuget_resolver_tool//:publish/NuGetResolver.dll`.",
            mandatory = True,
        ),
    },
)
