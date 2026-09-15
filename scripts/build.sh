#!/bin/sh
#
# Build the JavaScript modules
#

set -eux

cd "$(dirname "$0")"/..

WASM_PACK_ARGS="${WASM_PACK_ARGS:-}"

# eggomi fork: strip local filesystem paths out of the artifact.
#
# `tracing` bakes file!() into the binary, so without this every log site ships
# the absolute path it was compiled from. A local build of this fork embedded
# "C:\Users\thoma\.cargo\git\checkouts\..." 713 times in a .wasm that is served
# publicly. Upstream's CI build has none of this only because its paths are
# throwaway, so the leak reappears for anyone who rebuilds on a real machine.
#
# Remapping also makes the build reproducible across machines: the artifact no
# longer depends on where the source happened to live.
CARGO_HOME_DIR="${CARGO_HOME:-$HOME/.cargo}"
REMAP="--remap-path-prefix=${CARGO_HOME_DIR}=/cargo"
REMAP="${REMAP} --remap-path-prefix=$(pwd)=/build"
REMAP="${REMAP} --remap-path-prefix=${HOME}=/home"
RUSTFLAGS="${RUSTFLAGS:-} ${REMAP}"
export RUSTFLAGS

# Generate the JavaScript bindings
# --no-pack disables generation of a `package.json` file, as we're managing it ourselves.
wasm-pack build --no-pack --target bundler --scope matrix-org --out-dir pkg --weak-refs "${WASM_PACK_ARGS}"

# This will generate the following files in the `pkg` directory for us:
#   - matrix_sdk_crypto_wasm.d.ts: TypeScript declarations of the bindings
#   - matrix_sdk_crypto_wasm.js: logic to load the WASM module
#   - matrix_sdk_crypto_wasm_bg.js: the JS <-> WASM glue
#   - matrix_sdk_crypto_wasm_bg.wasm: the actual WASM module
#   - matrix_sdk_crypto_wasm_bg.wasm.d.ts: types for the exports of the WASM module

# We're not interested in the loading logic, as it doesn't work well on all platforms, so we ship our own loader.
rm pkg/matrix_sdk_crypto_wasm.js

# The JS <-> WASM glue uses ESM syntax, so we want to create a CommonJS version of it
babel pkg/matrix_sdk_crypto_wasm_bg.js --out-dir pkg --out-file-extension .cjs --plugins @babel/plugin-transform-modules-commonjs
