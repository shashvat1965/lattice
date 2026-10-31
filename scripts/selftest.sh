#!/bin/bash
# Runs Lattice's self-test and prints the diagnostics report.
# Works without Accessibility permission (it says so and skips window work).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/build/Lattice.app/Contents/MacOS/Lattice"

if [ ! -x "$BIN" ]; then
  echo "No bundle. Run ./scripts/bundle.sh release first." >&2
  exit 1
fi

echo "▸ signature"
codesign -dv "$BIN" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature" | sed 's/^/  /'
codesign -d -r- "$BIN" 2>&1 | sed -n '/designated/,$p' | sed 's/^/  /'

echo
echo "▸ self-test"
LATTICE_SELFTEST=1 "$BIN" 2>&1 | sed 's/^/  /'

echo
echo "▸ log tail"
tail -20 "$HOME/Library/Logs/Lattice/lattice.log" 2>/dev/null | sed 's/^/  /'
