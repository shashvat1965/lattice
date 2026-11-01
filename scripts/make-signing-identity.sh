#!/bin/bash
# Creates a stable code-signing identity for local Lattice builds.
#
# Why: an ad-hoc signature (`codesign -s -`) is pinned to the exact binary hash, so macOS
# forgets the Accessibility grant after every rebuild. A self-signed certificate keeps the
# same designated requirement ("identifier com.shashvat.lattice and certificate root = ...")
# across rebuilds, so the grant survives. Nothing is notarised or distributed; the identity
# lives in its own small keychain and is used only by ./scripts/bundle.sh.
#
# The keychain password is a fixed, non-secret value: it protects a throwaway signing key
# from casual misuse, not anything of yours.
set -euo pipefail

NAME="${LATTICE_SIGN_NAME:-Lattice Dev Signing}"
KEYCHAIN="${LATTICE_SIGN_KEYCHAIN:-$HOME/Library/Keychains/lattice-signing.keychain-db}"
PASS="${LATTICE_SIGN_KEYCHAIN_PASSWORD:-lattice}"
CERT_OUT="$HOME/Library/Application Support/Lattice/lattice-signing.pem"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

have_identity() {
  [ -f "$KEYCHAIN" ] && security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$NAME\""
}

trusted() {
  security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NAME\""
}

explain_trust() {
  mkdir -p "$(dirname "$CERT_OUT")"
  security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$CERT_OUT" 2>/dev/null || true
  cat <<EOF

The identity is imported but not trusted yet. Trust it once (it is self-signed and used
only on this Mac), then run ./scripts/bundle.sh:

  sudo security add-trusted-cert -d -r trustRoot -p codeSign \\
    -k /Library/Keychains/System.keychain "$CERT_OUT"

Without that step codesign waits on a keychain prompt on every build.
EOF
}

if have_identity; then
  security unlock-keychain -p "$PASS" "$KEYCHAIN" >/dev/null 2>&1 || true
  echo "Identity already present: $NAME ($KEYCHAIN)"
  trusted || { explain_trust; exit 1; }
  exit 0
fi

echo "Creating '$NAME'..."
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$NAME/O=Lattice/C=US" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" >/dev/null 2>&1

openssl pkcs12 -export -legacy \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout "pass:$PASS" >/dev/null 2>&1

security create-keychain -p "$PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$PASS" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" \
  -T /usr/bin/codesign -A >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KEYCHAIN" >/dev/null

mkdir -p "$(dirname "$CERT_OUT")"
cp "$WORK/cert.pem" "$CERT_OUT"

echo "Verifying..."
security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME" || {
  echo "The identity was imported but is not usable for signing." >&2
  exit 1
}

if ! trusted; then
  explain_trust
  exit 1
fi

echo "Done. ./scripts/bundle.sh will pick it up automatically."
