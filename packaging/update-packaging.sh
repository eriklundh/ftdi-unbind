#!/usr/bin/env bash
# packaging/update-packaging.sh — update packaging manifests for a new release.
#
# Usage:
#   bash packaging/update-packaging.sh <tag>
#   bash packaging/update-packaging.sh v0.2.0
#
# Run this from the repo root after the GitHub Release is published.
# The script downloads the two release artifacts, verifies SHA256SUMS,
# and updates:
#   packaging/homebrew/ftdi-unbind.rb
#   packaging/winget/Compelcon.FtdiUnbind/<version>/  (new directory)

set -euo pipefail

TAG="${1:?Usage: $0 <tag> (e.g. v0.2.0)}"
VER="${TAG#v}"
REPO="compelcon/ftdi-unbind"
BASE_URL="https://github.com/$REPO/releases/download/$TAG"
WIN_ZIP="ftdi-tools-${TAG}-windows-x64.zip"
UNIX_TAR="ftdi-tools-${TAG}-linux-macos.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Fetching release artifacts for $TAG ..."
curl -fsSL "$BASE_URL/SHA256SUMS"   -o "$TMPDIR/SHA256SUMS"
curl -fsSL "$BASE_URL/$WIN_ZIP"     -o "$TMPDIR/$WIN_ZIP"
curl -fsSL "$BASE_URL/$UNIX_TAR"    -o "$TMPDIR/$UNIX_TAR"

echo "Verifying checksums ..."
(cd "$TMPDIR" && sha256sum --check --ignore-missing SHA256SUMS)

WIN_SHA="$(sha256sum "$TMPDIR/$WIN_ZIP"  | awk '{print $1}')"
TAR_SHA="$(sha256sum "$TMPDIR/$UNIX_TAR" | awk '{print $1}')"
echo "  windows: $WIN_SHA"
echo "  unix:    $TAR_SHA"

# ── Update Homebrew formula ────────────────────────────────────────────────────

FORMULA="$SCRIPT_DIR/homebrew/ftdi-unbind.rb"
echo "Updating $FORMULA ..."
sed -i \
  -e "s|releases/download/v[0-9.]*/ftdi-tools-v[0-9.]*-linux-macos.tar.gz|releases/download/$TAG/$UNIX_TAR|g" \
  -e "s|sha256 \"[a-f0-9]*\"|sha256 \"$TAR_SHA\"|g" \
  -e "s|version \"[0-9.]*\"|version \"$VER\"|g" \
  "$FORMULA"
echo "  done."

# ── Create winget version directory ──────────────────────────────────────────

SRC_VER="$SCRIPT_DIR/winget/Compelcon.FtdiUnbind"
# Find the most recent existing version to copy from.
PREV_VER="$(ls "$SRC_VER" | sort -V | tail -1)"
NEW_VER_DIR="$SRC_VER/$VER"

if [[ -d "$NEW_VER_DIR" ]]; then
  echo "winget version dir already exists: $NEW_VER_DIR"
else
  echo "Creating winget version dir: $NEW_VER_DIR ..."
  cp -r "$SRC_VER/$PREV_VER" "$NEW_VER_DIR"
  # Rename files to new version.
  for f in "$NEW_VER_DIR"/*; do
    mv "$f" "${f/$PREV_VER/$VER}"
  done
fi

# Patch version, URL, and SHA256 in all three files.
for f in "$NEW_VER_DIR"/*.yaml; do
  sed -i \
    -e "s|PackageVersion: [0-9.]*|PackageVersion: $VER|g" \
    -e "s|releases/download/v[0-9.]*/ftdi-tools-v[0-9.]*-windows-x64.zip|releases/download/$TAG/$WIN_ZIP|g" \
    -e "s|InstallerSha256: [A-Fa-f0-9]*\|InstallerSha256: PLACEHOLDER_SHA256_UPDATED_BY_RELEASE_WORKFLOW|InstallerSha256: $WIN_SHA|g" \
    -e "s|/tag/v[0-9.]*|/tag/$TAG|g" \
    "$f"
done
echo "  done."

echo ""
echo "All done for $TAG."
echo ""
echo "Next steps:"
echo "  1. Review changed files (git diff packaging/)"
echo "  2. Copy packaging/homebrew/ftdi-unbind.rb to the tap repo and push."
echo "  3. Submit packaging/winget/Compelcon.FtdiUnbind/$VER/ to winget-pkgs"
echo "     (or run: wingetcreate update Compelcon.FtdiUnbind --version $VER --urls $BASE_URL/$WIN_ZIP --submit)"
