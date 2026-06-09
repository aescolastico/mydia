#!/usr/bin/env bash
set -euo pipefail

# Lint every WASM plugin crate under plugins/.
#
# Plugins compile to wasm32-unknown-unknown (pure Rust guests, no WASI), so we
# check them against that target rather than the host. This keeps plugin commits
# off the native NIF toolchain entirely — the native p2p crate links against
# system libraries and is irrelevant to a plugin change.
#
# Usage: scripts/check-plugins.sh [--fix]
#   (default) cargo fmt --check + cargo clippy -D warnings
#   --fix     cargo fmt (rewrite) instead of --check

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLUGINS_DIR="$PROJECT_ROOT/plugins"
TARGET="wasm32-unknown-unknown"

FMT_MODE="--check"
if [ "${1:-}" = "--fix" ]; then
  FMT_MODE=""
fi

if [ ! -d "$PLUGINS_DIR" ]; then
  echo "No plugins/ directory; nothing to check."
  exit 0
fi

# The wasm32 target ships with the pinned nix toolchain (devShells.rust). When
# running outside nix with a host rustup, add it once: rustup target add $TARGET
if command -v rustup >/dev/null 2>&1 &&
   ! rustup target list --installed 2>/dev/null | grep -qx "$TARGET"; then
  echo "Rust target $TARGET is not installed. Run:"
  echo "  rustup target add $TARGET"
  echo "  (or lint via: nix develop .#rust -c scripts/check-plugins.sh)"
  exit 1
fi

found=0
for manifest in "$PLUGINS_DIR"/*/Cargo.toml; do
  [ -e "$manifest" ] || continue
  found=1
  crate_dir="$(dirname "$manifest")"
  echo "==> $(basename "$crate_dir")"

  # shellcheck disable=SC2086
  cargo fmt --manifest-path "$manifest" -- $FMT_MODE
  cargo clippy --manifest-path "$manifest" \
    --release --target "$TARGET" -- -D warnings
done

if [ "$found" -eq 0 ]; then
  echo "No plugin crates found under plugins/."
fi
