#!/bin/bash
# Prepares the consumer-facing release artifact for the REMOTE SPM binary target:
# strips dSYMs (≈90% of the size), zips with ditto (preserves symlinks /
# code-signing layout), computes the SPM checksum, and prints the Package.swift
# block to paste.
#
# Usage:
#   bash scripts/package-xcframework.sh <version-tag>     # e.g. llama-b9488-1
#
# Outputs (under dist/):
#   dist/llama.xcframework.zip        (~15-25 MB; upload as a release asset)
#   dist/llama.dSYMs.zip              (optional, for crash symbolication)
set -euo pipefail

VERSION="${1:?usage: package-xcframework.sh <version-tag>  (e.g. llama-b9488-1)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Frameworks/llama.xcframework"
WORK="$ROOT/dist/work"
DIST="$ROOT/dist"

[ -d "$SRC" ] || { echo "ERROR: $SRC not found — run scripts/build-xcframework.sh first." >&2; exit 1; }

rm -rf "$WORK" "$DIST/llama.xcframework.zip" "$DIST/llama.dSYMs.zip"
mkdir -p "$WORK" "$DIST"

# --- Copy + strip dSYMs from the shipped framework ---
cp -R "$SRC" "$WORK/llama.xcframework"
# Stash the dSYMs into a separate archive, then remove them from the shipped copy.
DSYM_TMP="$WORK/dSYMs"
mkdir -p "$DSYM_TMP"
while IFS= read -r -d '' d; do
  rel="${d#"$WORK"/llama.xcframework/}"
  mkdir -p "$DSYM_TMP/$(dirname "$rel")"
  mv "$d" "$DSYM_TMP/$rel"
done < <(find "$WORK/llama.xcframework" -type d -name dSYMs -print0)

# --- Drop the now-dangling DebugSymbolsPath keys from the xcframework Info.plist ---
# Each AvailableLibraries entry declares `DebugSymbolsPath = dSYMs`. After the
# stripping above that path no longer exists, and Xcode validates it strictly →
# "Missing path .../dSYMs ... DebugSymbolsPath" build failures for remote
# consumers. Remove the key from every slice (debug symbols ship separately in
# llama.dSYMs.zip for anyone who needs symbolication).
PLIST="$WORK/llama.xcframework/Info.plist"
i=0
while /usr/libexec/PlistBuddy -c "Print :AvailableLibraries:$i:DebugSymbolsPath" "$PLIST" >/dev/null 2>&1; do
  /usr/libexec/PlistBuddy -c "Delete :AvailableLibraries:$i:DebugSymbolsPath" "$PLIST"
  i=$((i + 1))
done
echo "=== Removed DebugSymbolsPath from $i slice(s) ==="

# --- Zip with ditto (preserves the macOS Versions/Current symlink) ---
echo "=== Zipping stripped xcframework ==="
ditto -c -k --keepParent "$WORK/llama.xcframework" "$DIST/llama.xcframework.zip"
if [ -d "$DSYM_TMP" ] && [ -n "$(ls -A "$DSYM_TMP" 2>/dev/null)" ]; then
  ditto -c -k --keepParent "$DSYM_TMP" "$DIST/llama.dSYMs.zip"
fi

CHECKSUM="$(swift package compute-checksum "$DIST/llama.xcframework.zip")"
SIZE="$(du -h "$DIST/llama.xcframework.zip" | awk '{print $1}')"

cat <<EOF

=== Done ===
Artifact : $DIST/llama.xcframework.zip ($SIZE)
dSYMs    : $DIST/llama.dSYMs.zip (optional, for symbolication)

1) Publish the asset (do NOT overwrite an existing tag — cut a new one):
     git tag $VERSION && git push --tags
     gh release create $VERSION "$DIST/llama.xcframework.zip" "$DIST/llama.dSYMs.zip" \\
        --title "llama.cpp ($VERSION)" --notes "stripped xcframework + dSYMs"

2) Paste into Package.swift:
     let remoteURL = "https://github.com/ChipCracker/LlamaKit/releases/download/$VERSION/llama.xcframework.zip"
     let remoteChecksum = "$CHECKSUM"

(External consumers then resolve the tiny remote zip; local devs keep using
 Frameworks/llama.xcframework or LLAMAKIT_LOCAL_XCFRAMEWORK=1.)
EOF
