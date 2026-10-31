#!/bin/bash
# Fast iteration loop: build, bundle, relaunch, tail logs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/bundle.sh" "${1:-debug}" >/dev/null || exit 1

pkill -f "Lattice.app/Contents/MacOS/Lattice" 2>/dev/null || true
sleep 0.3
open "$ROOT/build/Lattice.app"

if [ "${TAIL:-0}" = "1" ]; then
  touch "$HOME/Library/Logs/Lattice/lattice.log"
  tail -f "$HOME/Library/Logs/Lattice/lattice.log"
fi
