"""Applying the globalization settings to the .Net processes the rules start.

On Linux the runtime loads ICU from shared libraries, which the machine may not
have. `//dotnet/settings:invariant_globalization` makes the runtime do without
culture data; `//dotnet/settings:icu` names an ICU for the build to carry, such
as the one this package builds. Either setting has to reach the compilers and
the tools of a build as well as the binaries and tests it produces.
See docs/README.md#globalization-and-icu.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//dotnet/private:common.bzl", "to_rlocation_path")

# The runtime reads this to decide whether to load ICU at all. See
# https://learn.microsoft.com/dotnet/core/runtime-config/globalization#invariant-mode
INVARIANT_GLOBALIZATION_VARIABLE = "DOTNET_SYSTEM_GLOBALIZATION_INVARIANT"

# The version of ICU the runtime is to look for. It reads the first; the second
# is its name before .NET 10. See
# https://learn.microsoft.com/dotnet/core/extensions/globalization-icu#load-specific-icu-version-on-linux
ICU_VERSION_VARIABLES = ["DOTNET_ICU_VERSION_OVERRIDE", "CLR_ICU_VERSION_OVERRIDE"]

_ICUUC_PREFIX = "libicuuc.so."

def _icu_library(toolchain):
    """The `libicuuc.so.<version>` of the ICU the build carries, or None.

    The runtime looks that one up first, by the version in its name, and takes
    `libicui18n` and `libicudata` from beside it, so it stands for the set.
    """

    for file in icu_files(toolchain).to_list():
        if file.basename.startswith(_ICUUC_PREFIX):
            return file
    return None

def _icu_version(library):
    """The major version in the name of a `libicuuc.so.<version>`."""

    return library.basename[len(_ICUUC_PREFIX):].split(".")[0]

def icu_files(toolchain):
    """The shared libraries of the ICU `//dotnet/settings:icu` names.

    Args:
        toolchain: The resolved .Net toolchain, which carries the flag.

    Returns:
        A depset of files, empty when the runtime is to use the machine's own.
    """

    return toolchain.icu[DefaultInfo].files

def globalization_env(toolchain):
    """The environment that applies the globalization settings to a .Net process.

    An action runs with the environment the rules give it rather than the
    client's, so `--action_env` cannot carry these. Without the ICU version the
    runtime takes the highest it finds, which could be the machine's rather than
    the one the build carries.

    Args:
        toolchain: The resolved .Net toolchain, which carries the settings.

    Returns:
        A dict of environment variables, empty unless a setting applies.
    """

    env = {}
    if toolchain.invariant_globalization[BuildSettingInfo].value:
        env[INVARIANT_GLOBALIZATION_VARIABLE] = "1"

    library = _icu_library(toolchain)
    if library != None:
        for variable in ICU_VERSION_VARIABLES:
            env[variable] = _icu_version(library)

    return env

def icu_wrapper_arguments(actions, toolchain):
    """The leading arguments and tools that tell the compiler wrapper about the ICU.

    An `Args` rather than a plain string, so that path mapping rewrites the
    path along with the rest of the compile. See docs/README.md#path-mapping.

    Args:
        actions: The rule's `actions`.
        toolchain: The resolved .Net toolchain.

    Returns:
        An (arguments, tools) pair, both empty when the build carries no ICU.
    """

    library = _icu_library(toolchain)
    if library == None:
        return [], []

    arguments = actions.args()
    arguments.add(library, format = "--icu=%s")
    return [arguments], [icu_files(toolchain)]

def icu_launcher_environment(ctx, toolchain, is_windows):
    """The lines a launcher runs before the runtime, applying the globalization settings.

    A launcher starts the binaries and tests as well as the tools of a build.
    The invariant line only supplies a default, so a value already in the
    environment, such as one from `envs` or `--test_env`, wins. Only Linux loads
    ICU from shared libraries, so a batch file gets no ICU lines.

    Args:
        ctx: The rule context, for the runfiles path of the libraries.
        toolchain: The resolved .Net toolchain.
        is_windows: Whether the launcher is a batch file.

    Returns:
        The text to substitute for `TEMPLATED_environment`, empty unless a
        setting applies.
    """

    lines = []
    if toolchain.invariant_globalization[BuildSettingInfo].value:
        if is_windows:
            lines.append("if not defined {v} set {v}=1".format(v = INVARIANT_GLOBALIZATION_VARIABLE))
        else:
            lines.append('export {v}="${{{v}:-1}}"'.format(v = INVARIANT_GLOBALIZATION_VARIABLE))

    library = None if is_windows else _icu_library(toolchain)
    if library != None:
        lines.append('export LD_LIBRARY_PATH="$(dirname "$(rlocation {})")${{LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}}"'.format(
            to_rlocation_path(ctx, library),
        ))
        for variable in ICU_VERSION_VARIABLES:
            lines.append('export {}="{}"'.format(variable, _icu_version(library)))

    return "\n".join(lines)
