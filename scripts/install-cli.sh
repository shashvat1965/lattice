#!/bin/bash
# Links the lattice CLI that ships inside Lattice.app onto the PATH.
# The binary itself is never copied: it must stay inside the signed bundle so macOS
# attributes the Accessibility grant to Lattice.app, not to a loose executable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${LATTICE_BUNDLE:-$ROOT/build/Lattice.app}"
BIN_DIR="${LATTICE_BIN_DIR:-/usr/local/bin}"
LINK="$BIN_DIR/lattice"

# On a case-insensitive volume Contents/MacOS/lattice is the app binary itself, so bundle.sh
# places the CLI in Contents/Helpers instead. Pick whichever one is the real CLI.
BINARY="$BUNDLE/Contents/MacOS/lattice"
if [ -x "$BUNDLE/Contents/MacOS/Lattice" ] && [ -x "$BINARY" ] \
   && [ "$BINARY" -ef "$BUNDLE/Contents/MacOS/Lattice" ]; then
  BINARY="$BUNDLE/Contents/Helpers/lattice"
fi

if [ ! -x "$BINARY" ]; then
  echo "No CLI in $BUNDLE — run ./scripts/bundle.sh first." >&2
  exit 1
fi

if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$BINARY" ]; then
  echo "Already linked: $LINK → $BINARY"
  echo "Run: lattice doctor"
  exit 0
fi

if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
  echo "$LINK exists and isn't a symlink — refusing to overwrite it." >&2
  exit 1
fi

if [ ! -d "$BIN_DIR" ]; then
  echo "$BIN_DIR doesn't exist — creating it with sudo."
  sudo mkdir -p "$BIN_DIR"
  sudo chown "$(id -u):$(id -g)" "$BIN_DIR" 2>/dev/null || true
fi

if [ -w "$BIN_DIR" ]; then
  ln -sfn "$BINARY" "$LINK"
  echo "Linked $LINK → $BINARY"
else
  echo "$BIN_DIR isn't writable by $(whoami) — using sudo."
  sudo ln -sfn "$BINARY" "$LINK"
  echo "Linked $LINK → $BINARY (via sudo)"
fi

echo "Run: lattice doctor"
