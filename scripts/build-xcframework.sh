#!/bin/bash
# Builds llama.xcframework (llama.cpp + ggml/Metal) for Apple platforms and
# places it at Frameworks/llama.xcframework for the local SPM binary target.
#
# Uses llama.cpp's official build-xcframework.sh → a real `llama.framework` with
# a module map (Swift module `llama`). Metal shaders are embedded
# (GGML_METAL_EMBED_LIBRARY=ON), so no .metallib has to ship separately.
#
# Usage:
#   bash scripts/build-xcframework.sh           # build (all Apple slices)
#   bash scripts/build-xcframework.sh --clean   # remove build artifacts
#
# Output: Frameworks/llama.xcframework
set -euo pipefail

# Pinned llama.cpp tag: the wrapped C API (Sources/LlamaKit/Engine/LlamaEngine.swift)
# is verified against this. To update, bump the tag and re-check the symbols
# against the xcframework's Headers/llama.h.
LLAMA_TAG="b9488"
LLAMA_REPO="https://github.com/ggml-org/llama.cpp"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/third_party/llama.cpp"
OUT="$ROOT/Frameworks/llama.xcframework"

if [ "${1:-}" = "--clean" ]; then
  rm -rf "$SRC/build-apple" "$SRC/build-ios" "$SRC/build-ios-sim" \
         "$SRC/build-macos" "$SRC/build-visionos" "$SRC/build-visionos-sim" \
         "$SRC/build-tvos-device" "$SRC/build-tvos-sim" "$OUT"
  echo "Cleaned."
  exit 0
fi

# --- 1) Fetch llama.cpp sources (shallow, pinned tag) ---
if [ ! -f "$SRC/build-xcframework.sh" ]; then
  echo "=== Cloning llama.cpp @ $LLAMA_TAG into $SRC ==="
  rm -rf "$SRC"
  git clone --depth 1 --branch "$LLAMA_TAG" "$LLAMA_REPO" "$SRC"
fi

# --- 2) Run the official xcframework script ---
echo "=== Building llama.xcframework (first build takes several minutes) ==="
( cd "$SRC" && bash ./build-xcframework.sh )

PRODUCED="$SRC/build-apple/llama.xcframework"
if [ ! -d "$PRODUCED" ]; then
  echo "ERROR: expected artifact not found: $PRODUCED" >&2
  exit 1
fi

# --- 3) Copy into Frameworks/ ---
echo "=== Copying to $OUT ==="
mkdir -p "$ROOT/Frameworks"
rm -rf "$OUT"
cp -R "$PRODUCED" "$OUT"

echo "=== Done ==="
echo "Framework: $OUT"
echo "Next: 'swift build' (auto-uses the local xcframework), or publish with scripts/package-xcframework.sh"
ls "$OUT"
