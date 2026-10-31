#!/bin/bash
# Builds Lattice.app — a single, self-contained bundle. No environment is required
# beyond Xcode's command line tools, and nothing is installed outside the app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Lattice.app"
BUNDLE_ID="com.shashvat.lattice"

cd "$ROOT"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG" --product Lattice 2>&1 | sed 's/^/  /'

BIN="$(swift build -c "$CONFIG" --product Lattice --show-bin-path)/Lattice"
test -f "$BIN" || { echo "build produced no binary"; exit 1; }

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lattice"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/App/Lattice.icns" ]; then
  cp "$ROOT/App/Lattice.icns" "$APP/Contents/Resources/Lattice.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Lattice" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# Prefer a stable signing identity so Accessibility grants survive rebuilds.
# (Ad-hoc signatures are pinned to a cdhash, which changes on every build.)
SIGN_ID="${LATTICE_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)"/\1/p' | head -1)}"
if [ -n "$SIGN_ID" ]; then
  echo "  signing as: $SIGN_ID"
  codesign --force --deep --sign "$SIGN_ID" --identifier "$BUNDLE_ID" --options runtime "$APP" 2>/dev/null \
    || codesign --force --deep --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"
else
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP"
fi

# Thermo-nuclear hygiene: nothing but our own binary ships in the bundle.
echo "▸ Bundle ready: $APP"
du -sh "$APP" | sed 's/^/  /'
