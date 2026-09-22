"""The ICU sources, under a build file of our own.

The `icu` module's own build files serve its data tooling: they build static
libraries and leave out whatever that tooling does not need. The .NET runtime
instead loads `libicuuc`, `libicui18n` and `libicudata` as shared libraries, so
this repository symlinks the module's `common` and `i18n` sources and builds
each directory as one library for `//dotnet/private/icu` to link.
"""

# The major version of the `icu` module in MODULE.bazel, which names the
# libraries, the data file and the symbol the data is linked in as.
ICU_MAJOR_VERSION = "78"

_BUILD_HEADER = '''"""The ICU sources of the `icu` module, built as the two libraries the runtime loads."""

load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])
'''

_LIBRARY = '''
cc_library(
    name = "{name}",
    srcs = [
{sources}
    ],
    hdrs = [
{headers}
    ],
    copts = ["-std=c++17"],
    includes = ["{directory}"],
    local_defines = ["{define}"],
    target_compatible_with = ["@platforms//os:linux"],
    deps = [
{deps}
    ],
)
'''

def _list(items):
    return "\n".join(['        "{}",'.format(item) for item in items])

def _link(rctx, directory, into, suffix):
    """Symlinks the files of a directory with a suffix into the repository.

    File by file rather than the directory as a whole: the directory carries
    the module's own `BUILD.bazel`, which would make it a package of its own
    and put its files out of this build file's reach.

    Args:
        rctx: The repository context.
        directory: The path of the module's directory.
        into: The directory of this repository to link into.
        suffix: The suffix of the files to link.

    Returns:
        The linked files, as labels of this repository, sorted.
    """

    files = []
    for file in directory.readdir():
        if file.basename.endswith(suffix):
            link = "{}/{}".format(into, file.basename)
            rctx.symlink(file, link)
            files.append(link)
    return sorted(files)

def _library(rctx, name, define, deps):
    """Links one of the module's source directories in and describes it as a library."""
    source = rctx.path(Label("@icu//icu4c/source/{}:BUILD.bazel".format(name))).dirname

    # Every header goes in `hdrs`, private ones included, since `i18n` includes
    # `common`'s private headers as ICU's own build does.
    headers = _link(rctx, source, name, ".h") + _link(rctx, source.get_child("unicode"), name + "/unicode", ".h")
    return _LIBRARY.format(
        name = name,
        directory = name,
        sources = _list(_link(rctx, source, name, ".cpp")),
        headers = _list(headers),
        define = define,
        deps = _list(deps),
    )

def _icu_sources_impl(rctx):
    build = _BUILD_HEADER

    # The module patches `putil.cpp` to include the runfiles library, which it
    # then only uses under a define this build does not set.
    build += _library(rctx, "common", "U_COMMON_IMPLEMENTATION", ["@rules_cc//cc/runfiles"])
    build += _library(rctx, "i18n", "U_I18N_IMPLEMENTATION", [":common"])

    rctx.file("BUILD.bazel", build)

icu_sources = repository_rule(
    implementation = _icu_sources_impl,
    doc = "The `common` and `i18n` sources of the `icu` module, under a build file that builds each as one library.",
)
