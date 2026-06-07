#!/bin/bash
# Package platform exports into standalone zip archives.
# Each archive bundles the executable with a copy of data/ (all JSON tables)
# and user documentation at the base, placed in the build directory root.
set -euo pipefail

BUILD="${1:-build}"

# Linux
if [ -f "$BUILD/linux/Humanish-linux-amd64" ]; then
  tmp="$(mktemp -d)"
  cp "$BUILD/linux/Humanish-linux-amd64" "$tmp/"
  cp -r data "$tmp/"
  cp docs/user/quick-start.md docs/user/user-reference.md "$tmp/"
  (cd "$tmp" && zip -r "$OLDPWD/$BUILD/Humanish-linux-amd64.zip" .)
  rm -rf "$tmp"
  echo "Created $BUILD/Humanish-linux-amd64.zip"
fi

# Windows
if [ -f "$BUILD/windows/Humanish-windows-amd64.exe" ]; then
  tmp="$(mktemp -d)"
  cp "$BUILD/windows/Humanish-windows-amd64.exe" "$tmp/"
  cp -r data "$tmp/"
  cp docs/user/quick-start.md docs/user/user-reference.md "$tmp/"
  (cd "$tmp" && zip -r "$OLDPWD/$BUILD/Humanish-windows-amd64.zip" .)
  rm -rf "$tmp"
  echo "Created $BUILD/Humanish-windows-amd64.zip"
fi

# macOS — extract the Godot-exported zip, add data/docs, re-zip
if [ -f "$BUILD/macos/Humanish-macos.zip" ]; then
  tmp="$(mktemp -d)"
  unzip -q "$BUILD/macos/Humanish-macos.zip" -d "$tmp"
  cp -r data "$tmp/"
  cp docs/user/quick-start.md docs/user/user-reference.md "$tmp/"
  (cd "$tmp" && zip -r "$OLDPWD/$BUILD/Humanish-macos.zip" .)
  rm -rf "$tmp"
  echo "Created $BUILD/Humanish-macos.zip"
fi

# Checksums for the final archives
(cd "$BUILD" && sha256sum Humanish-*.zip > SHA256SUMS)
echo "Generated $BUILD/SHA256SUMS"
