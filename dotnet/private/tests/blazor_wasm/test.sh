#! /usr/bin/env bash
# A published Blazor WebAssembly application is a static site. Nothing here
# runs it - that needs a browser - so this checks the shape the runtime relies
# on: assemblies rewritten as WebAssembly modules, the runtime beside them, and
# a boot configuration naming both.

set -eou pipefail

root="dotnet/private/tests/blazor_wasm/publish"

# A published application reaches only a fraction of the assemblies the runtime
# pack ships, so exceeding this means trimming stopped working.
max_assemblies=80
www="$root/wwwroot"
framework="$www/_framework"
failures=0

expect_file() {
    if [[ -f "$1" ]]; then
        echo "ok: $1"
    else
        echo "FAILED: missing $1"
        failures=$((failures + 1))
    fi
}

expect_in_boot() {
    if grep -q -- "$1" "$framework/dotnet.js"; then
        echo "ok: boot configuration names $1"
    else
        echo "FAILED: boot configuration does not name $1"
        failures=$((failures + 1))
    fi
}

# The page, the starter script it loads, and the runtime that script starts.
expect_file "$www/index.html"
expect_file "$framework/blazor.webassembly.js"
expect_file "$framework/dotnet.js"
expect_file "$framework/dotnet.native.wasm"
expect_file "$framework/dotnet.runtime.js"

# The application's own code, and a framework assembly it could not run without.
expect_file "$framework/app.wasm"
expect_file "$framework/System.Private.CoreLib.wasm"

# A browser will only load these if they really are WebAssembly modules, which
# is the whole reason for the Webcil conversion.
for module in "$framework/app.wasm" "$framework/System.Private.CoreLib.wasm"; do
    if [[ "$(head -c 4 "$module" | od -An -tx1 | tr -d ' \n')" == "0061736d" ]]; then
        echo "ok: $module is a WebAssembly module"
    else
        echo "FAILED: $module is not a WebAssembly module"
        failures=$((failures + 1))
    fi
done

# The runtime fetches what the boot configuration tells it to, so an assembly
# missing from there is an assembly the application never sees.
expect_in_boot "app.wasm"
expect_in_boot "System.Private.CoreLib.wasm"
expect_in_boot "dotnet.native.wasm"

# The runtime hands each resource's hash to `fetch` as a subresource integrity.
# An empty one is not a missing optimisation: the browser rejects `sha256-` as
# malformed and refuses to load the application. Nothing about the build fails
# when they are absent, so it is checked here.
if grep -q '"sha256-"' "$framework/dotnet.js"; then
    echo "FAILED: the boot configuration carries empty integrity hashes"
    failures=$((failures + 1))
else
    echo "ok: every boot resource carries an integrity hash"
fi

# Compression and the endpoint manifest come from the ordinary static web asset
# pipeline, so the framework is served like anything else.
expect_file "$framework/app.wasm.br"
expect_file "$root/app.staticwebassets.endpoints.json"

kept=$(find "$framework" -name '*.wasm' ! -name 'dotnet.native.wasm' | wc -l | tr -d ' ')
if [[ "$kept" -le "$max_assemblies" ]]; then
    echo "ok: trimmed to $kept assemblies"
else
    echo "FAILED: $kept assemblies survived, expected at most $max_assemblies"
    failures=$((failures + 1))
fi

exit $failures
