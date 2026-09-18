#!/usr/bin/env bash
set -euo pipefail

# darwin/repackage_macos_slice.sh
#
# Converts an ALREADY-BUILT shallow macOS Llama.framework (the iOS-style
# layout create_xcframework.sh's old single build_slice() used to lay out
# for every platform, macOS included — see darwin/macos_framework_layout.sh
# for why that layout fails macOS's Validate phase) into the Apple
# versioned-bundle layout, without recompiling anything, then reassembles
# ios/Llama.xcframework around it.
#
# This is the standalone/repackaging twin of build_macos_slice() in
# create_xcframework.sh: same versioning + install-name + signing steps,
# shared via darwin/macos_framework_layout.sh rather than copied a third
# time. The two differ only in where the macOS slice's bytes come from —
# build_macos_slice() copies them out of a fresh build directory,
# this script copies them out of an existing framework and rewrites its
# Info.plist keys in place (MinimumOSVersion -> LSMinimumSystemVersion,
# + CFBundleSupportedPlatforms) instead of regenerating it from the
# template, so it preserves whatever identifier/version the existing
# framework actually carries.
#
# Usage:
#   darwin/repackage_macos_slice.sh [XCFRAMEWORK_DIR] [EXPECTED_SHA256]
#
# XCFRAMEWORK_DIR defaults to ios/Llama.xcframework relative to the repo
# root (the committed artifact). Pass a scratch copy's path to exercise
# this script without touching the tree.
#
# EXPECTED_SHA256 defaults to the sha256 of the macOS binary committed at
# fork ref 203a063a7f5cdb20537e789a95585af67ba8b37d. The script refuses to
# run against a different input unless a matching hash is supplied
# explicitly, so it never silently repackages a binary nobody verified.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"

XCFRAMEWORK_DIR="${1:-$REPO_ROOT/ios/Llama.xcframework}"
EXPECTED_SHA256="${2:-5964069fbeb193ed0eb8b13a8e78e1c17ac6c54efc44d029326f8b02445f0b06}"

FRAMEWORK_NAME="Llama"
EXECUTABLE_NAME="Llama"
MACOS_SLICE_ID="macos-arm64"
IOS_DEVICE_SLICE_ID="ios-arm64"
IOS_SIM_SLICE_ID="ios-arm64_x86_64-simulator"

MACOS_FW="$XCFRAMEWORK_DIR/$MACOS_SLICE_ID/$FRAMEWORK_NAME.framework"
IOS_DEVICE_FW="$XCFRAMEWORK_DIR/$IOS_DEVICE_SLICE_ID/$FRAMEWORK_NAME.framework"
IOS_SIM_FW="$XCFRAMEWORK_DIR/$IOS_SIM_SLICE_ID/$FRAMEWORK_NAME.framework"

# shellcheck source=./macos_framework_layout.sh
source "$HERE/macos_framework_layout.sh"

###############################################################################
# sanity checks
###############################################################################
[[ -d "$MACOS_FW" ]]      || { echo "❌  not found: $MACOS_FW" >&2; exit 1; }
[[ -d "$IOS_DEVICE_FW" ]] || { echo "❌  not found: $IOS_DEVICE_FW" >&2; exit 1; }
[[ -d "$IOS_SIM_FW" ]]    || { echo "❌  not found: $IOS_SIM_FW" >&2; exit 1; }

if [[ -e "$MACOS_FW/Versions" || -L "$MACOS_FW/$EXECUTABLE_NAME" ]]; then
  echo "❌  $MACOS_FW already looks versioned (Versions/ or a $EXECUTABLE_NAME symlink present) — refusing to run" >&2
  exit 1
fi

[[ -f "$MACOS_FW/$EXECUTABLE_NAME" ]] || { echo "❌  expected a shallow binary at $MACOS_FW/$EXECUTABLE_NAME" >&2; exit 1; }
[[ -f "$MACOS_FW/Info.plist" ]]       || { echo "❌  expected $MACOS_FW/Info.plist" >&2; exit 1; }

BEFORE_SHA="$(shasum -a 256 "$MACOS_FW/$EXECUTABLE_NAME" | awk '{print $1}')"
BEFORE_SIZE="$(stat -f%z "$MACOS_FW/$EXECUTABLE_NAME")"
echo "before: sha256=$BEFORE_SHA size=$BEFORE_SIZE"

if [[ "$BEFORE_SHA" != "$EXPECTED_SHA256" ]]; then
  echo "❌  input sha256 mismatch: got $BEFORE_SHA, expected $EXPECTED_SHA256" >&2
  exit 1
fi

###############################################################################
# scratch workspace (never the tree itself until the very last step)
###############################################################################
WORK="$(mktemp -d "${TMPDIR:-/tmp}/repackage_macos_slice.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

VERSIONED_MACOS_FW="$WORK/$MACOS_SLICE_ID/$FRAMEWORK_NAME.framework"
mkdir -p "$VERSIONED_MACOS_FW/Versions/A/Headers"
mkdir -p "$VERSIONED_MACOS_FW/Versions/A/Resources"

cp "$MACOS_FW/$EXECUTABLE_NAME" "$VERSIONED_MACOS_FW/Versions/A/$EXECUTABLE_NAME"
cp -R "$MACOS_FW/Headers/." "$VERSIONED_MACOS_FW/Versions/A/Headers/"

###############################################################################
# rewrite the EXISTING Info.plist's keys in place (preserve identifier/version)
###############################################################################
PLIST="$VERSIONED_MACOS_FW/Versions/A/Resources/Info.plist"
cp "$MACOS_FW/Info.plist" "$PLIST"

MIN_OS="$(plutil -extract MinimumOSVersion raw "$PLIST" 2>/dev/null || echo "12.0")"
plutil -remove MinimumOSVersion "$PLIST" 2>/dev/null || true
plutil -insert LSMinimumSystemVersion -string "$MIN_OS" "$PLIST"
plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' "$PLIST"
plutil -lint "$PLIST"

###############################################################################
# versioned symlinks, install name fix-up, strip + ad-hoc bundle signature
# (shared recipe — see darwin/macos_framework_layout.sh)
###############################################################################
macos_versionize_and_sign "$VERSIONED_MACOS_FW" "$FRAMEWORK_NAME" "$EXECUTABLE_NAME"

AFTER_SHA="$(shasum -a 256 "$VERSIONED_MACOS_FW/Versions/A/$EXECUTABLE_NAME" | awk '{print $1}')"
AFTER_SIZE="$(stat -f%z "$VERSIONED_MACOS_FW/Versions/A/$EXECUTABLE_NAME")"
echo "after:  sha256=$AFTER_SHA size=$AFTER_SIZE"

echo "--- codesign --verify --deep --strict (standalone versioned slice) ---"
codesign --verify --deep --strict --verbose=4 "$VERSIONED_MACOS_FW"

###############################################################################
# reassemble ios/Llama.xcframework: versioned macOS slice + iOS slices
# copied UNCHANGED, keeping the folder name Llama.framework inside each
# per-platform subdirectory — xcodebuild derives the binary name from the
# folder basename, and a renamed folder silently breaks -create-xcframework
###############################################################################
IOS_DEVICE_IN="$WORK/$IOS_DEVICE_SLICE_ID/$FRAMEWORK_NAME.framework"
IOS_SIM_IN="$WORK/$IOS_SIM_SLICE_ID/$FRAMEWORK_NAME.framework"
mkdir -p "$(dirname "$IOS_DEVICE_IN")" "$(dirname "$IOS_SIM_IN")"
cp -R "$IOS_DEVICE_FW" "$IOS_DEVICE_IN"
cp -R "$IOS_SIM_FW" "$IOS_SIM_IN"

OUT_XCFW="$WORK/$FRAMEWORK_NAME.xcframework"
echo "--- xcodebuild -create-xcframework ---"
xcodebuild -create-xcframework \
  -framework "$IOS_DEVICE_IN" \
  -framework "$IOS_SIM_IN" \
  -framework "$VERSIONED_MACOS_FW" \
  -output "$OUT_XCFW"

echo "--- codesign --verify --deep --strict (assembled macos-arm64 slice) ---"
codesign --verify --deep --strict --verbose=4 \
  "$OUT_XCFW/$MACOS_SLICE_ID/$FRAMEWORK_NAME.framework"

###############################################################################
# the iOS slices must come out byte-identical to what was in the tree —
# diff against the assembled output, before the tree's originals are gone
###############################################################################
echo "--- diff -r ios-arm64 (original vs assembled) ---"
diff -r "$IOS_DEVICE_FW" "$OUT_XCFW/$IOS_DEVICE_SLICE_ID/$FRAMEWORK_NAME.framework"
echo "diff exit: $?"

echo "--- diff -r ios-arm64_x86_64-simulator (original vs assembled) ---"
diff -r "$IOS_SIM_FW" "$OUT_XCFW/$IOS_SIM_SLICE_ID/$FRAMEWORK_NAME.framework"
echo "diff exit: $?"

###############################################################################
# only now replace the target directory
###############################################################################
rm -rf "$XCFRAMEWORK_DIR"
mv "$OUT_XCFW" "$XCFRAMEWORK_DIR"
# the EXIT trap still cleans up $WORK's leftover per-slice input dirs

echo "--- plutil -p regenerated Info.plist ---"
plutil -p "$XCFRAMEWORK_DIR/Info.plist"

echo "✅  repackaged: $XCFRAMEWORK_DIR"
