#!/usr/bin/env bash
# Runs a .NET test under coverlet.console for `bazel coverage`:
#
#   coverlet.sh <dotnet> <test.dll> <assemblies> [test arguments...]
#
# <assemblies> lists the runfiles paths of the DLLs to instrument, the ones
# --instrumentation_filter selects. coverlet does not fit Bazel as it is, and
# this script bridges four gaps:
#
# * coverlet instruments an assembly by rewriting it in place, and the runfiles
#   are read-only links into Bazel's outputs. The test runs from a copy of the
#   runfiles tree made of links, where only the assemblies to instrument are
#   real, writable copies. The tree keeps its shape, so the deps.json paths
#   still resolve.
# * The source paths a PDB names are those of the compile sandbox, gone by test
#   time, and coverlet skips an assembly whose sources it cannot find. That
#   check is off: which sources are reported is Bazel's call, made by the
#   coverage merger from --instrumentation_filter.
# * Bazel's merger reads every *.dat file under $COVERAGE_DIR, so the report
#   goes there, with source paths relative to the execution root.
# * LCOV's FN and FNDA lines are "<line>,<name>", and C# method names carry
#   commas (generic arguments), which the merger rejects. They become spaces.
#
# The exit status is the test's.

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

set -o pipefail -o errexit -o nounset

dotnet="$1"
test_dll="$2"
assemblies="$3"
shift 3

if [[ -z "${RUNFILES_DIR:-}" || -z "${COVERAGE_DIR:-}" || -z "${TEST_TMPDIR:-}" ]]; then
  echo "coverlet: RUNFILES_DIR, COVERAGE_DIR and TEST_TMPDIR have to be set, as bazel coverage does" >&2
  exit 1
fi

instrument=()
while IFS= read -r rel || [[ -n "$rel" ]]; do
  [[ -n "$rel" ]] && instrument+=("$rel")
done <"$assemblies"

# Nothing the filter selects: the test runs as under bazel test.
if [[ ${#instrument[@]} -eq 0 ]]; then
  exec "$dotnet" exec "$test_dll" "$@"
fi

coverlet="$(rlocation TEMPLATED_coverlet)"
runfiles="$(cd "$RUNFILES_DIR" && pwd -P)"
case "$test_dll" in
"$RUNFILES_DIR"/*) rel_dll="${test_dll#"$RUNFILES_DIR"/}" ;;
"$runfiles"/*) rel_dll="${test_dll#"$runfiles"/}" ;;
*)
  echo "coverlet: $test_dll is not under the runfiles tree $RUNFILES_DIR" >&2
  exit 1
  ;;
esac

work="$TEST_TMPDIR/dotnet_coverage"
shadow="$work/runfiles"
rm -rf "$work"
mkdir -p "$shadow"

# The copy starts as one link per top-level runfiles entry, so it costs a few
# links however many files the runfiles hold (the .NET runtime alone is
# thousands). Only the directories on the way to an assembly to instrument
# become real. Links point at the original runfiles paths, so they resolve
# whether those are links (local sandboxes) or files (remote execution).
for entry in "$runfiles"/* "$runfiles"/.[!.]*; do
  [[ -e "$entry" || -L "$entry" ]] || continue
  ln -s "$entry" "$shadow/${entry##*/}"
done

# Makes the directory $1 (relative to the runfiles root) real in the copy,
# walking down from its root: each component still linked to its original
# becomes a directory of links to the original's children. Going top-down
# keeps every write inside the copy.
materialize_dir() {
  local rest="$1" rel="" comp cur child
  while [[ -n "$rest" ]]; do
    comp="${rest%%/*}"
    if [[ "$rest" == */* ]]; then
      rest="${rest#*/}"
    else
      rest=""
    fi
    [[ -n "$comp" ]] || continue
    rel="${rel:+$rel/}$comp"
    cur="$shadow/$rel"
    if [[ -L "$cur" ]]; then
      rm "$cur"
      mkdir "$cur"
      for child in "$runfiles/$rel"/* "$runfiles/$rel"/.[!.]*; do
        [[ -e "$child" || -L "$child" ]] || continue
        ln -s "$child" "$cur/${child##*/}"
      done
    fi
  done
}

include=()
for rel in "${instrument[@]}"; do
  pdb="${rel%.dll}.pdb"
  if [[ ! -e "$runfiles/$rel" || ! -e "$runfiles/$pdb" ]]; then
    echo "coverlet: $rel or its PDB is missing from the runfiles, not instrumenting it" >&2
    continue
  fi
  dir="${rel%/*}"
  materialize_dir "$dir"
  for f in "$rel" "$pdb"; do
    rm -f "$shadow/$f"
    cp "$runfiles/$f" "$shadow/$f"
    chmod u+w "$shadow/$f"
  done
  include+=(--include-directory "$shadow/$dir")
done

# The test starts where Bazel starts it: the workspace's directory in the runfiles.
workdir="${TEST_WORKSPACE:-_main}"
materialize_dir "$workdir"

# coverlet takes the test's command line as one string.
target_args="exec \"$shadow/$rel_dll\""
for arg in "$@"; do
  arg="${arg//\\/\\\\}"
  arg="${arg//\"/\\\"}"
  target_args="$target_args \"$arg\""
done

out="$work/out"
mkdir -p "$out"
status=0
(
  cd "$shadow/$workdir"
  "$coverlet" "$shadow/$rel_dll" \
    --target "$dotnet" \
    --targetargs "$target_args" \
    ${include[@]+"${include[@]}"} \
    --exclude-assemblies-without-sources None \
    --format lcov \
    --output "$out/"
) || status=$?

info=""
for f in "$out"/*.info; do
  [[ -e "$f" ]] && info="$f" && break
done
if [[ -n "$info" ]]; then
  if [[ -n "${TEST_UNDECLARED_OUTPUTS_DIR:-}" ]]; then
    cp "$info" "$TEST_UNDECLARED_OUTPUTS_DIR/coverlet.info"
  fi
  # A path-mapped compile names sources "./pkg/File.cs"; any other names the
  # absolute path of its execution root. Both become "pkg/File.cs".
  sed -E -e 's#^SF:.*/execroot/[^/]+/#SF:#' -e 's#^SF:\./#SF:#' "$info" |
    awk '/^FN(DA)?:/ { i = index($0, ","); head = substr($0, 1, i); name = substr($0, i + 1); gsub(/,/, " ", name); print head name; next } { print }' \
      >"$COVERAGE_DIR/coverlet.dat"
fi

exit "$status"
