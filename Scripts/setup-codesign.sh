#!/bin/sh
# setup-codesign.sh — Create a self-signed code-signing certificate so that
# macOS TCC permissions (Calendar, Reminders, etc.) survive app rebuilds.
#
# Run once:  ./Scripts/setup-codesign.sh
#
# What it does:
#   1. Generates a self-signed certificate with CN "FocusFlow Development"
#   2. Imports it into your login keychain with codesign trust
#   3. Cleans up temporary files
#
# After running, all build scripts (run.sh, build-dmg.sh, install-and-register-smart.sh)
# will automatically detect and use this certificate instead of ad-hoc signing.

set -eu

CERT_NAME="FocusFlow Development"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMPDIR_CERT="$(mktemp -d)"
PKCS12_PASS="focusflow-codesign-temp-pass"
trap 'rm -rf "$TMPDIR_CERT"' EXIT

GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
info() { printf "${BLUE}ℹ${NC} %s\n" "$1"; }
err()  { printf "${RED}✗${NC} %s\n" "$1" >&2; exit 1; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }

# Check if certificate already exists
if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
    ok "Certificate \"$CERT_NAME\" already exists in your keychain."
    info "All build scripts will use it automatically."
    exit 0
fi

info "Creating self-signed code-signing certificate \"$CERT_NAME\"..."

# Generate certificate config
cat > "$TMPDIR_CERT/cert.cfg" << EOF
[ req ]
distinguished_name = req_dn
prompt = no
[ req_dn ]
CN = $CERT_NAME
O  = FocusFlow
[ extensions ]
basicConstraints = CA:false
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

# Generate key and self-signed certificate (10-year validity)
openssl req -x509 -newkey rsa:2048 \
    -keyout "$TMPDIR_CERT/key.pem" \
    -out "$TMPDIR_CERT/cert.pem" \
    -days 3650 -nodes \
    -config "$TMPDIR_CERT/cert.cfg" \
    -extensions extensions \
    2>/dev/null || err "Failed to generate certificate"

# Package as PKCS12
openssl pkcs12 -export \
    -out "$TMPDIR_CERT/cert.p12" \
    -inkey "$TMPDIR_CERT/key.pem" \
    -in "$TMPDIR_CERT/cert.pem" \
    -passout pass:"$PKCS12_PASS" \
    2>/dev/null || err "Failed to create PKCS12 bundle"

# Import into login keychain with codesign trust
security import "$TMPDIR_CERT/cert.p12" \
    -k "$KEYCHAIN" \
    -T /usr/bin/codesign \
    -f pkcs12 \
    -P "$PKCS12_PASS" \
    2>/dev/null || err "Failed to import certificate into keychain"

# Trust the certificate for code signing
security add-trusted-cert -d -r trustRoot \
    -k "$KEYCHAIN" \
    "$TMPDIR_CERT/cert.pem" \
    2>/dev/null || warn "Could not set trust automatically. You may need to trust it manually in Keychain Access."

# Allow codesign to use the key without password prompts
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "" "$KEYCHAIN" \
    2>/dev/null || warn "Could not set partition list. You may be prompted for keychain password on first sign."

ok "Certificate \"$CERT_NAME\" created and imported."

# Verify
if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
    ok "Verified: certificate is available for code signing."
else
    warn "Certificate was imported but not found in code signing identities."
    info "Open Keychain Access → login → My Certificates, find \"$CERT_NAME\","
    info "double-click → Trust → Code Signing → Always Trust."
fi

info ""
info "Done! All FocusFlow build scripts will now use this certificate."
info "macOS will remember Calendar/Reminder permissions across rebuilds."
