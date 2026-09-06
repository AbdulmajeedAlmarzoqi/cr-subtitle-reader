#!/bin/bash
# Creates a self-signed code-signing identity in the login keychain and prints its name.
#
# Why: macOS ties Automation (Apple Events) permissions to the app's code-signing identity.
# An ad-hoc signature is a new identity on every build, so every update makes users allow
# Safari and VoiceOver access again. Signing every release with the same certificate keeps the
# designated requirement stable, and the permissions survive updates. A Developer ID
# certificate does the same (and enables notarization); use CODESIGN_IDENTITY for it.
#
#   ./scripts/make-signing-identity.sh            # creates "CR Subtitle Reader Developer" if missing
#   CODESIGN_IDENTITY="CR Subtitle Reader Developer" ./scripts/build-app.sh
set -euo pipefail
NAME=${1:-"CR Subtitle Reader Developer"}
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
	echo "identity already exists: $NAME"
	exit 0
fi
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -config "$WORK/openssl.cnf" \
	-keyout "$WORK/key.pem" -out "$WORK/cert.pem" >/dev/null 2>&1
openssl pkcs12 -export -legacy -out "$WORK/identity.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
	-passout pass:crsr -name "$NAME" >/dev/null 2>&1 || \
openssl pkcs12 -export -out "$WORK/identity.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
	-passout pass:crsr -name "$NAME" >/dev/null 2>&1
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P crsr -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# Trust the certificate for code signing (user trust settings; macOS may ask for your password).
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" 2>/dev/null || true
security find-identity -v -p codesigning | grep "\"$NAME\"" || { echo "identity not usable"; exit 1; }
echo "created identity: $NAME"
