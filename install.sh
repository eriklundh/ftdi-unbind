#!/usr/bin/env bash
# install.sh — install or uninstall ftdi-unbind / ftdi-bind
# Author Erik Lundh, The Joy of Engineering, erik.lundh@ingenjorsgladje.se
#
# Usage:
#   bash install.sh [--prefix <dir>] [--uninstall]
#
# Default prefix: /usr/local/bin (writable by the current user, or sudo is
# used automatically when the directory is not writable).
#
# Examples:
#   bash install.sh                          # install to /usr/local/bin
#   bash install.sh --prefix ~/.local/bin    # install to ~/local/bin (no sudo)
#   bash install.sh --uninstall              # remove from /usr/local/bin
#   bash install.sh --prefix ~/.local/bin --uninstall

set -euo pipefail

TOOLS=(ftdi-unbind ftdi-bind)
PREFIX=/usr/local/bin
UNINSTALL=0

# ── Parse arguments ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="${2:?--prefix requires an argument}"
      shift 2 ;;
    --uninstall)
      UNINSTALL=1
      shift ;;
    -h|--help)
      sed -n '/^# install.sh/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1 ;;
  esac
done

# ── Locate source scripts ─────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/macos-linux"

for tool in "${TOOLS[@]}"; do
  if [[ ! -f "$SRC_DIR/$tool" ]]; then
    echo "Error: $SRC_DIR/$tool not found." >&2
    echo "Run this script from the ftdi-unbind repo root." >&2
    exit 1
  fi
done

# ── Helpers ───────────────────────────────────────────────────────────────────

run_maybe_sudo() {
  if [[ -w "$(dirname "$1")" ]]; then
    "$@"
  else
    echo "  (needs sudo for $PREFIX)"
    sudo "$@"
  fi
}

# ── Uninstall ─────────────────────────────────────────────────────────────────

if [[ $UNINSTALL -eq 1 ]]; then
  echo "Removing ftdi tools from $PREFIX ..."
  for tool in "${TOOLS[@]}"; do
    dest="$PREFIX/$tool"
    if [[ -f "$dest" ]]; then
      run_maybe_sudo rm -f "$dest"
      echo "  removed $dest"
    else
      echo "  not found (skipping): $dest"
    fi
  done
  echo "Done."
  exit 0
fi

# ── Install ───────────────────────────────────────────────────────────────────

mkdir -p "$PREFIX" 2>/dev/null || true

echo "Installing ftdi tools to $PREFIX ..."
for tool in "${TOOLS[@]}"; do
  src="$SRC_DIR/$tool"
  dest="$PREFIX/$tool"
  run_maybe_sudo install -m 755 "$src" "$dest"
  echo "  installed $dest"
done

echo ""
echo "Done. Verify with: ftdi-unbind --about"

# Remind the user if the prefix isn't on PATH.
if ! echo ":$PATH:" | grep -q ":$PREFIX:"; then
  echo ""
  echo "Note: $PREFIX is not in your PATH."
  echo "Add this to your shell profile (~/.bashrc or ~/.zshrc):"
  echo "  export PATH=\"$PREFIX:\$PATH\""
fi
