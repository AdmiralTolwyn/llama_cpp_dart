#!/usr/bin/env bash
# Shared macOS framework layout/signing recipe.
#
# Xcode's macOS Validate phase rejects the iOS-style "shallow" framework
# layout (executable + Headers/ + Info.plist all at the top level). macOS
# frameworks must use the classic Apple "versioned bundle" layout:
#
#   Llama.framework/Versions/A/{Llama, Headers/, Resources/Info.plist}
#   Llama.framework/Versions/Current -> A
#   Llama.framework/Llama            -> Versions/Current/Llama
#   Llama.framework/Headers          -> Versions/Current/Headers
#   Llama.framework/Resources        -> Versions/Current/Resources
#
# This file is sourced (not executed) by both darwin/create_xcframework.sh
# (building a fresh macOS slice from a freshly-built binary) and
# darwin/repackage_macos_slice.sh (converting an already-built shallow
# framework into this layout). Both callers already `set -euo pipefail`,
# so a failing step here aborts the caller too — do not swallow errors.
#
# Deliberately NOT duplicated a third time: any script that needs this
# layout/sign recipe sources this file instead of re-implementing it.

# macos_versionize_and_sign FRAMEWORK_DIR FRAMEWORK_NAME EXECUTABLE_NAME
#
# Preconditions: $FRAMEWORK_DIR/Versions/A/$EXECUTABLE_NAME,
# $FRAMEWORK_DIR/Versions/A/Headers/ and
# $FRAMEWORK_DIR/Versions/A/Resources/Info.plist already exist (the caller
# is responsible for populating Versions/A — the binary copy/lipo step and
# the Info.plist contents differ between a fresh build and a repackage, so
# those stay with the caller). This function only does the part that is
# identical either way: lay the versioned symlinks, fix the install name to
# point at the versioned path, strip any existing signature, and re-sign
# the whole bundle ad hoc.
macos_versionize_and_sign() {
  local FRAMEWORK_DIR="$1" FRAMEWORK_NAME="$2" EXECUTABLE_NAME="$3"
  local VERSIONED_BIN="$FRAMEWORK_DIR/Versions/A/$EXECUTABLE_NAME"

  if [[ ! -f "$VERSIONED_BIN" ]]; then
    echo "❌  macos_versionize_and_sign: expected $VERSIONED_BIN to already exist" >&2
    exit 1
  fi

  # Versioned symlinks (relative targets, matching Apple's own frameworks).
  ln -sfh "A" "$FRAMEWORK_DIR/Versions/Current"
  ln -sfh "Versions/Current/$EXECUTABLE_NAME" "$FRAMEWORK_DIR/$EXECUTABLE_NAME"
  ln -sfh "Versions/Current/Headers" "$FRAMEWORK_DIR/Headers"
  ln -sfh "Versions/Current/Resources" "$FRAMEWORK_DIR/Resources"

  # Install name must point at the versioned path, not the shallow iOS one.
  /usr/bin/codesign --remove-signature "$VERSIONED_BIN" 2>/dev/null || true
  install_name_tool -id "@rpath/${FRAMEWORK_NAME}.framework/Versions/A/${EXECUTABLE_NAME}" "$VERSIONED_BIN"

  # Ad-hoc sign the whole bundle (not just the binary) — Validate wants a
  # bundle-level signature, and this matches the proven repackaging recipe.
  /usr/bin/codesign --force --sign - --timestamp=none "$FRAMEWORK_DIR"
}
