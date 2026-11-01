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
swift build -c "$CONFIG" --scratch-path "$ROOT/.build" --product Lattice 2>&1 | sed 's/^/  /'
# The CLI has its own scratch path: "Lattice" and "lattice" differ only by case, and on the
# default case-insensitive APFS volume both link to the same file name in one build directory.
swift build -c "$CONFIG" --scratch-path "$ROOT/.build-cli" --product lattice 2>&1 | sed 's/^/  /'

BIN="$(swift build -c "$CONFIG" --scratch-path "$ROOT/.build" --product Lattice --show-bin-path)/Lattice"
CLI_BIN="$(swift build -c "$CONFIG" --scratch-path "$ROOT/.build-cli" --product lattice --show-bin-path)/lattice"
test -f "$BIN" || { echo "build produced no binary"; exit 1; }
test -f "$CLI_BIN" || { echo "build produced no CLI binary"; exit 1; }

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lattice"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/App/Lattice.icns" ]; then
  cp "$ROOT/App/Lattice.icns" "$APP/Contents/Resources/Lattice.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Lattice" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# The CLI belongs in Contents/MacOS/lattice. On a case-insensitive volume (the default APFS
# layout) that name is the same file as Contents/MacOS/Lattice, the app itself, so both cannot
# exist. Detect the alias and use Apple's nested-helpers location instead.
if [ -e "$APP/Contents/MacOS/lattice" ]; then
  CLI_DEST="$APP/Contents/Helpers/lattice"
  echo "  case-insensitive volume: CLI goes to Contents/Helpers/lattice"
else
  CLI_DEST="$APP/Contents/MacOS/lattice"
fi
mkdir -p "$(dirname "$CLI_DEST")"
cp "$CLI_BIN" "$CLI_DEST"

# Prefer a stable signing identity so Accessibility grants survive rebuilds.
# (Ad-hoc signatures are pinned to a cdhash, which changes on every build.)
SIGN_ID="${LATTICE_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)"/\1/p' | head -1)}"
SIGN_KEYCHAIN="${LATTICE_SIGN_KEYCHAIN:-$HOME/Library/Keychains/lattice-signing.keychain-db}"
KEYCHAIN_ARGS=()
if [ -z "$SIGN_ID" ] && [ -f "$SIGN_KEYCHAIN" ] \
   && security find-identity -p codesigning "$SIGN_KEYCHAIN" 2>/dev/null | grep -q "Lattice Dev Signing"; then
  SIGN_ID="Lattice Dev Signing"
  KEYCHAIN_ARGS=(--keychain "$SIGN_KEYCHAIN")
  security unlock-keychain -p "${LATTICE_SIGN_KEYCHAIN_PASSWORD:-lattice}" "$SIGN_KEYCHAIN" >/dev/null 2>&1 || true
fi
if [ -n "$SIGN_ID" ]; then
  echo "  signing as: $SIGN_ID"
  # No hardened runtime here: it adds nothing for a locally-run utility and has bitten
  # Accessibility grants on some macOS builds.
  codesign --force --deep "${KEYCHAIN_ARGS[@]}" --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"
else
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP"
fi

# macOS ties an Accessibility grant to the exact code that was approved, so a rebuild makes an
# existing toggle stale (it still looks ON but is ignored). Clearing it makes the next launch
# ask cleanly — but it also means you must re-grant after every build, so it is opt-in:
#   LATTICE_RESET_GRANT=1 ./scripts/bundle.sh release
if [ "${LATTICE_RESET_GRANT:-0}" = "1" ]; then
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  echo "  accessibility grant cleared (LATTICE_RESET_GRANT=1)"
else
  echo "  note: if Accessibility looks enabled but Lattice says it is off, toggle it off and on"
fi

# Thermo-nuclear hygiene: nothing but our own binary ships in the bundle.
echo "▸ Verifying the signed bundle…"
codesign --verify --deep --strict "$APP"
"$CLI_DEST" version >/dev/null
echo "  nested CLI signs and runs after codesign"

echo "▸ Bundle ready: $APP"
du -sh "$APP" | sed 's/^/  /'
