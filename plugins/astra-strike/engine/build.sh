#!/usr/bin/env bash
# Build and install the Astra Strike engine.
#
# The binary is written to ./bin (gitignored) so nothing is dropped into the
# shell's QML directory that Quickshell might try to load. Target dir is kept
# in the cargo cache, not in the config tree.
set -euo pipefail

cd "$(dirname "$0")"

export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/astra-strike-target}"

cargo build --release

mkdir -p bin
install -m755 "$CARGO_TARGET_DIR/release/astra-strike" bin/astra-strike

echo "built: $(pwd)/bin/astra-strike ($(stat -c%s bin/astra-strike) bytes)"
