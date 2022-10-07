#!/usr/bin/env bash

# shellcheck disable=SC1090
{
{{rlocation_function}}
}

set -o pipefail -o errexit -o nounset

{{envs}}

# ==============================================================================
# Prepare stdout capture, stderr capture && logging
# ==============================================================================

if [ "${DOTNET_BINARY__STDOUT_OUTPUT_FILE:-}" ] || [ "${DOTNET_BINARY__SILENT_ON_SUCCESS:-}" ]; then
    STDOUT_CAPTURE=$(mktemp)
fi

if [ "${DOTNET_BINARY__STDERR_OUTPUT_FILE:-}" ] || [ "${DOTNET_BINARY__SILENT_ON_SUCCESS:-}" ]; then
    STDERR_CAPTURE=$(mktemp)
fi

export DOTNET_BINARY__LOG_PREFIX="{{log_prefix_rule_set}}[{{log_prefix_rule}}]"

function logf_stderr {
    local format_string="$1\n"
    shift
    if [ "${STDERR_CAPTURE:-}" ]; then
        # shellcheck disable=SC2059
        printf "$format_string" "$@" >>"$STDERR_CAPTURE"
    else
        # shellcheck disable=SC2059
        printf "$format_string" "$@" >&2
    fi
}

function logf_fatal {
    if [ "${DOTNET_BINARY__LOG_FATAL:-}" ]; then
        if [ "${STDERR_CAPTURE:-}" ]; then
            printf "FATAL: %s: " "$DOTNET_BINARY__LOG_PREFIX" >>"$STDERR_CAPTURE"
        else
            printf "FATAL: %s: " "$DOTNET_BINARY__LOG_PREFIX" >&2
        fi
        logf_stderr "$@"
    fi
}

function logf_error {
    if [ "${DOTNET_BINARY__LOG_ERROR:-}" ]; then
        if [ "${STDERR_CAPTURE:-}" ]; then
            printf "ERROR: %s: " "$DOTNET_BINARY__LOG_PREFIX" >>"$STDERR_CAPTURE"
        else
            printf "ERROR: %s: " "$DOTNET_BINARY__LOG_PREFIX" >&2
        fi
        logf_stderr "$@"
    fi
}

function logf_warn {
    if [ "${DOTNET_BINARY__LOG_WARN:-}" ]; then
        if [ "${STDERR_CAPTURE:-}" ]; then
            printf "WARN: %s: " "$DOTNET_BINARY__LOG_PREFIX" >>"$STDERR_CAPTURE"
        else
            printf "WARN: %s: " "$DOTNET_BINARY__LOG_PREFIX" >&2
        fi
        logf_stderr "$@"
    fi
}

function logf_info {
    if [ "${DOTNET_BINARY__LOG_INFO:-}" ]; then
        if [ "${STDERR_CAPTURE:-}" ]; then
            printf "INFO: %s: " "$DOTNET_BINARY__LOG_PREFIX" >>"$STDERR_CAPTURE"
        else
            printf "INFO: %s: " "$DOTNET_BINARY__LOG_PREFIX" >&2
        fi
        logf_stderr "$@"
    fi
}

function logf_debug {
    if [ "${DOTNET_BINARY__LOG_DEBUG:-}" ]; then
        if [ "${STDERR_CAPTURE:-}" ]; then
            printf "DEBUG: %s: " "$DOTNET_BINARY__LOG_PREFIX" >>"$STDERR_CAPTURE"
        else
            printf "DEBUG: %s: " "$DOTNET_BINARY__LOG_PREFIX" >&2
        fi
        logf_stderr "$@"
    fi
}

_exit() {
    EXIT_CODE=$?

    if [ "${STDERR_CAPTURE:-}" ]; then
        if [ "${DOTNET_BINARY__STDERR_OUTPUT_FILE:-}" ]; then
            cp -f "$STDERR_CAPTURE" "$DOTNET_BINARY__STDERR_OUTPUT_FILE"
        fi
        if [ "$EXIT_CODE" != 0 ] || [ -z "${DOTNET_BINARY__SILENT_ON_SUCCESS:-}" ]; then
            cat "$STDERR_CAPTURE" >&2
        fi
        rm "$STDERR_CAPTURE"
    fi

    if [ "${STDOUT_CAPTURE:-}" ]; then
        if [ "${DOTNET_BINARY__STDOUT_OUTPUT_FILE:-}" ]; then
            cp -f "$STDOUT_CAPTURE" "$DOTNET_BINARY__STDOUT_OUTPUT_FILE"
        fi
        if [ "$EXIT_CODE" != 0 ] || [ -z "${DOTNET_BINARY__SILENT_ON_SUCCESS:-}" ]; then
            cat "$STDOUT_CAPTURE"
        fi
        rm "$STDOUT_CAPTURE"
    fi

    exit $EXIT_CODE
}

trap _exit EXIT

# ==============================================================================
# Initialize RUNFILES environment variable
# ==============================================================================

# It helps to determine if we are running on a Windows environment (excludes WSL as it acts like Unix)
function is_windows {
    case "$(uname -s)" in
        CYGWIN*)    local IS_WINDOWS=1 ;;
        MINGW*)     local IS_WINDOWS=1 ;;
        MSYS_NT*)   local IS_WINDOWS=1 ;;
        *)          local IS_WINDOWS=0 ;;
    esac

    echo $IS_WINDOWS
    return
}

# It helps to normalizes paths when running on Windows.
#
# Example:
# C:/Users/XUser/_bazel_XUser/7q7kkv32/execroot/A/b/C -> /c/Users/XUser/_bazel_XUser/7q7kkv32/execroot/A/b/C
function normalize_windows_path {
    # Apply the followings paths transformations to normalize paths on Windows
    # -process driver letter
    # -convert path separator
    sed -e 's#^\(.\):#/\L\1#' -e 's#\\#/#g' <<< "$1"
    return
}
# Find our runfiles as ${PWD}/${RUNFILES_DIR} is not always correct.
# We need this to launch dotnet with the correct entry point.
#
# Call this program X. X was generated by a genrule and may be invoked
# in many ways:
#   1a) directly by a user, with $0 in the output tree
#   1b) via 'bazel run' (similar to case 1a)
#   2) directly by a user, with $0 in X's runfiles
#   3) by another program Y which has a data dependency on X, with $0 in Y's
#      runfiles
#   4a) via 'bazel test'
#   4b) case 3 in the context of a test
#   5a) by a genrule cmd, with $0 in the output tree
#   6a) case 3 in the context of a genrule
#
# For case 1, $0 will be a regular file, and the runfiles will be
# at $0.runfiles.
# For case 2 or 3, $0 will be a symlink to the file seen in case 1.
# For case 4, $TEST_SRCDIR should already be set to the runfiles by
# blaze.
# Case 5a is handled like case 1.
# Case 6a is handled like case 3.
if [ "${TEST_SRCDIR:-}" ]; then
    # Case 4, bazel has identified runfiles for us.
    RUNFILES="$TEST_SRCDIR"
elif [ "${RUNFILES_MANIFEST_FILE:-}" ]; then
    if [ "$(is_windows)" -eq "1" ]; then
        # If Windows, normalize the path
        NORMALIZED_RUNFILES_MANIFEST_FILE=$(normalize_windows_path "$RUNFILES_MANIFEST_FILE")
    else
        NORMALIZED_RUNFILES_MANIFEST_FILE="$RUNFILES_MANIFEST_FILE"
    fi
    if [[ "${NORMALIZED_RUNFILES_MANIFEST_FILE}" == *.runfiles_manifest ]]; then
        # Newer versions of Bazel put the manifest besides the runfiles with the suffix .runfiles_manifest.
        # For example, the runfiles directory is named my_binary.runfiles then the manifest is beside the
        # runfiles directory and named my_binary.runfiles_manifest
        RUNFILES=${NORMALIZED_RUNFILES_MANIFEST_FILE%_manifest}
    elif [[ "${NORMALIZED_RUNFILES_MANIFEST_FILE}" == */MANIFEST ]]; then
        # Older versions of Bazel put the manifest file named MANIFEST in the runfiles directory
        RUNFILES=${NORMALIZED_RUNFILES_MANIFEST_FILE%/MANIFEST}
    else
        logf_fatal "Unexpected RUNFILES_MANIFEST_FILE value $RUNFILES_MANIFEST_FILE"
        exit 1
    fi
else
    case "$0" in
    /*) self="$0" ;;
    *) self="$PWD/$0" ;;
    esac
    while true; do
        if [ -e "$self.runfiles" ]; then
            RUNFILES="$self.runfiles"
            break
        fi

        if [[ "$self" == *.runfiles/* ]]; then
            RUNFILES="${self%%.runfiles/*}.runfiles"
            # don't break; this is a last resort for case 6b
        fi

        if [ ! -L "$self" ]; then
            break;
        fi

        readlink="$(readlink "$self")"
        if [[ "$readlink" == /* ]]; then
            self="$readlink"
        else
            # resolve relative symlink
            self="${self%%/*}/$readlink"
        fi
    done

    if [ -z "${RUNFILES:-}" ]; then
        logf_fatal "RUNFILES environment variable is not set"
        exit 1
    fi
fi
if [ "${RUNFILES:0:1}" != "/" ]; then
    # Ensure RUNFILES set above is an absolute path. It may be a path relative
    # to the PWD in case where RUNFILES_MANIFEST_FILE is used above.
    RUNFILES="$PWD/$RUNFILES"
fi
export RUNFILES

# ==============================================================================
# Prepare to run main program
# ==============================================================================

# Convert stdout, stderr and exit_code capture outputs paths to absolute paths
if [ "${DOTNET_BINARY__STDOUT_OUTPUT_FILE:-}" ]; then
    DOTNET_BINARY__STDOUT_OUTPUT_FILE="$PWD/$DOTNET_BINARY__STDOUT_OUTPUT_FILE"
fi
if [ "${DOTNET_BINARY__STDERR_OUTPUT_FILE:-}" ]; then
    DOTNET_BINARY__STDERR_OUTPUT_FILE="$PWD/$DOTNET_BINARY__STDERR_OUTPUT_FILE"
fi
if [ "${DOTNET_BINARY__EXIT_CODE_OUTPUT_FILE:-}" ]; then
    DOTNET_BINARY__EXIT_CODE_OUTPUT_FILE="$PWD/$DOTNET_BINARY__EXIT_CODE_OUTPUT_FILE"
fi

if [[ "$PWD" == *"/bazel-out/"* ]]; then
    # We in runfiles
    bazel_out="/bazel-out/"
    rest="${PWD#*"$bazel_out"}"
    index=$(( ${#PWD} - ${#rest} - ${#bazel_out} ))
    if [ ${index} -lt 0 ]; then
        printf "\nERROR: %s: No 'bazel-out' folder found in path '${PWD}'\n" "$DOTNET_BINARY__LOG_PREFIX" >&2
        exit 1
    fi
    execroot="${PWD:0:$index}"
else
    # We are in execroot or in some other context all together such as a manually run binary target.
    execroot="$PWD"
    if [ -z "${BAZEL_BINDIR:-}" ]; then
        logf_fatal "BAZEL_BINDIR must be set in environment to the makevar \$(BINDIR) in binary build actions (which \
run in the execroot) so that build actions can change directories to always run out of the root of the Bazel output \
tree. See https://docs.bazel.build/versions/main/be/make-variables.html#predefined_variables. The reason for this is that \
the deps.json file is generated in a way where every path is relative to the output tree."
        exit 1
    fi

    # Since the process was launched in the execroot, we automatically change directory into the root of the
    # output tree (which we expect to be set in BAZEL_BIN).
    logf_debug "changing directory to BAZEL_BINDIR (root of Bazel output tree) %s" "$BAZEL_BINDIR"
    cd "$BAZEL_BINDIR"
fi

entry_point="$RUNFILES/{{workspace_name}}/{{entry_point_path}}"
if [ ! -f "$entry_point" ]; then
    logf_fatal "the entry_point '%s' not found in runfiles" "$entry_point"
    exit 1
fi

export DOTNET_BINARY__DOTNET_EXECUTABLE="$RUNFILES/{{workspace_name}}/{{dotnet}}"
if [ ! -f "$DOTNET_BINARY__DOTNET_EXECUTABLE" ]; then
    logf_fatal "dotnet binary '%s' not found in runfiles" "$DOTNET_BINARY__DOTNET_EXECUTABLE"
    exit 1
fi
if [ ! -x "$DOTNET_BINARY__DOTNET_EXECUTABLE" ]; then
    logf_fatal "dotnet binary '%s' is not executable" "$DOTNET_BINARY__DOTNET_EXECUTABLE"
    exit 1
fi

export DOTNET_BINARY__DOTNET_WRAPPER="$RUNFILES/{{workspace_name}}/{{dotnet_wrapper}}"
if [ ! -f "$DOTNET_BINARY__DOTNET_WRAPPER" ]; then
    logf_fatal "dotnet wrapper '%s' not found in runfiles" "$DOTNET_BINARY__DOTNET_WRAPPER"
    exit 1
fi

ARGS=()
ALL_ARGS=("$@")
for ARG in ${ALL_ARGS[@]+"${ALL_ARGS[@]}"}; do
    case "$ARG" in
        # Remaining argv is collected to pass to the program
        *) ARGS+=( "$ARG" )
    esac
done

# Put the dotnet wrapper directory on the path so that child processes find it first
PATH="$(dirname "$DOTNET_BINARY__DOTNET_WRAPPER"):$PATH"
export PATH

# Debug logs
if [ "${DOTNET_BINARY__LOG_DEBUG:-}" ]; then
    if [ "${BAZEL_BINDIR:-}" ]; then
        logf_debug "BAZEL_BINDIR %s" "${BAZEL_BINDIR:-}"
    fi
    if [ "${BAZEL_TARGET_CPU:-}" ]; then
        logf_debug "BAZEL_TARGET_CPU %s" "${BAZEL_TARGET_CPU:-}"
    fi
    if [ "${BAZEL_COMPILATION_MODE:-}" ]; then
        logf_debug "BAZEL_COMPILATION_MODE %s" "${BAZEL_COMPILATION_MODE:-}"
    fi
    if [ "${BAZEL_WORKSPACE:-}" ]; then
        logf_debug "BAZEL_WORKSPACE %s" "${BAZEL_WORKSPACE:-}"
    fi
    if [ "${BAZEL_BUILD_FILE_PATH:-}" ]; then
        logf_debug "BAZEL_BUILD_FILE_PATH %s" "${BAZEL_BUILD_FILE_PATH:-}"
    fi
    if [ "${BAZEL_INFO_FILE:-}" ]; then
        logf_debug "BAZEL_INFO_FILE %s" "${BAZEL_INFO_FILE:-}"
    fi
    if [ "${BAZEL_VERSION_FILE:-}" ]; then
        logf_debug "BAZEL_VERSION_FILE %s" "${BAZEL_VERSION_FILE:-}"
    fi
    logf_debug "binary target BINDIR %s" "${DOTNET_BINARY__BINDIR:-}"
    logf_debug "binary target TARGET_CPU %s" "${DOTNET_BINARY__TARGET_CPU:-}"
    logf_debug "binary target COMPILATION_MODE %s" "${DOTNET_BINARY__COMPILATION_MODE:-}"
    logf_debug "binary target WORKSPACE %s" "${DOTNET_BINARY__WORKSPACE:-}"
    logf_debug "binary target BUILD_FILE_PATH %s" "${DOTNET_BINARY__BUILD_FILE_PATH:-}"
    logf_debug "binary target dotnet executable binary %s" "${DOTNET_BINARY__DOTNET_EXECUTABLE:-}"
fi

# Info logs
if [ "${DOTNET_BINARY__LOG_INFO:-}" ]; then
    if [ "${BAZEL_TARGET:-}" ]; then
        logf_info "BAZEL_TARGET %s" "${BAZEL_TARGET:-}"
    fi
    logf_info "binary target %s" "${DOTNET_BINARY__TARGET:-}"
    logf_info "RUNFILES %s" "$RUNFILES"
    logf_info "execroot %s" "$execroot"
    logf_info "PWD %s" "$PWD"
fi

# ==============================================================================
# Run the main program
# ==============================================================================
export DOTNET_MULTILEVEL_LOOKUP="false"
export DOTNET_NOLOGO="1"
export DOTNET_CLI_TELEMETRY_OPTOUT="1"
export DOTNET_ROOT="$(dirname $DOTNET_BINARY__DOTNET_EXECUTABLE)"
export DOTNET_CLI_HOME="$(dirname $DOTNET_BINARY__DOTNET_EXECUTABLE)"

if [ "${DOTNET_BINARY__LOG_INFO:-}" ]; then
    logf_info "$(echo -n "running" "$DOTNET_BINARY__DOTNET_WRAPPER" -- "$entry_point" ${ARGS[@]+"${ARGS[@]}"})"
fi

set +e

if [ "${STDOUT_CAPTURE:-}" ] && [ "${STDERR_CAPTURE:-}" ]; then
    "$DOTNET_BINARY__DOTNET_WRAPPER" exec "$entry_point" ${ARGS[@]+"${ARGS[@]}"} <&0 >>"$STDOUT_CAPTURE" 2>>"$STDERR_CAPTURE" &
elif [ "${STDOUT_CAPTURE:-}" ]; then
    "$DOTNET_BINARY__DOTNET_WRAPPER" exec "$entry_point" ${ARGS[@]+"${ARGS[@]}"} <&0 >>"$STDOUT_CAPTURE" &
elif [ "${STDERR_CAPTURE:-}" ]; then
    "$DOTNET_BINARY__DOTNET_WRAPPER" exec "$entry_point" ${ARGS[@]+"${ARGS[@]}"} <&0 2>>"$STDERR_CAPTURE" &
else
    "$DOTNET_BINARY__DOTNET_WRAPPER" exec "$entry_point" ${ARGS[@]+"${ARGS[@]}"} <&0 &
fi

# ==============================================================================
# Wait for program to finish
# ==============================================================================

readonly child=$!
# Bash does not forward termination signals to any child process when
# running in docker so need to manually trap and forward the signals
_term() { kill -TERM "${child}" 2>/dev/null; }
_int() { kill -INT "${child}" 2>/dev/null; }
trap _term SIGTERM
trap _int SIGINT
wait "$child"
# Remove trap after first signal has been receieved and wait for child to exit
# (first wait returns immediatel if SIGTERM is received while waiting). Second
# wait is a no-op if child has already terminated.
trap - SIGTERM SIGINT
wait "$child"

RESULT="$?"
set -e

# ==============================================================================
# Mop up after main program
# ==============================================================================

if [ "${DOTNET_BINARY__EXPECTED_EXIT_CODE:-}" ]; then
    if [ "$RESULT" != "$DOTNET_BINARY__EXPECTED_EXIT_CODE" ]; then
        logf_error "expected exit code to be '%s', but got '%s'" "$DOTNET_BINARY__EXPECTED_EXIT_CODE" "$RESULT"
        if [ $RESULT -eq 0 ]; then
            # This exit code is handled specially by Bazel:
            # https://github.com/bazelbuild/bazel/blob/486206012a664ecb20bdb196a681efc9a9825049/src/main/java/com/google/devtools/build/lib/util/ExitCode.java#L44
            readonly BAZEL_EXIT_TESTS_FAILED=3;
            exit $BAZEL_EXIT_TESTS_FAILED
        fi
        exit $RESULT
    else
        exit 0
    fi
fi

if [ "${DOTNET_BINARY__EXIT_CODE_OUTPUT_FILE:-}" ]; then
    # Exit zero if the exit code was captured
    echo -n "$RESULT" > "$DOTNET_BINARY__EXIT_CODE_OUTPUT_FILE"
    exit 0
else
    exit $RESULT
fi

