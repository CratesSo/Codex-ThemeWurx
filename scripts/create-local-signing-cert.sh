#!/usr/bin/env bash
set -euo pipefail

cert_name="${CODEX_THEME_BAR_SIGNING_IDENTITY:-Codex ThemeWurx Local}"
keychain="${CODEX_THEME_BAR_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
pkcs12_password="$(openssl rand -hex 24)"
tmpdir="$(mktemp -d)"
trap '/usr/bin/trash "$tmpdir"' EXIT

if security find-identity -v -p codesigning "$keychain" | grep -Fq "$cert_name"; then
	echo "Code-signing identity already exists: $cert_name"
	exit 0
fi

cat >"$tmpdir/openssl.cnf" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = codesign
prompt = no

[ req_distinguished_name ]
CN = $cert_name

[ codesign ]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
subjectKeyIdentifier = hash
EOF

openssl req \
	-new \
	-newkey rsa:2048 \
	-nodes \
	-x509 \
	-days 3650 \
	-keyout "$tmpdir/cert.key" \
	-out "$tmpdir/cert.crt" \
	-config "$tmpdir/openssl.cnf" \
	-sha256

openssl pkcs12 \
	-export \
	-inkey "$tmpdir/cert.key" \
	-in "$tmpdir/cert.crt" \
	-out "$tmpdir/cert.p12" \
	-passout "pass:$pkcs12_password"

security import "$tmpdir/cert.p12" \
	-k "$keychain" \
	-P "$pkcs12_password" \
	-T /usr/bin/codesign \
	-T /usr/bin/security

security set-key-partition-list \
	-S apple-tool:,apple:,codesign: \
	-s \
	-k "${KEYCHAIN_PASSWORD:-}" \
	"$keychain" || {
	echo "Imported $cert_name."
	echo "Automatic key access setup failed. Builds may still sign normally; if they prompt or fail, rerun with KEYCHAIN_PASSWORD set."
}

echo "Created code-signing identity: $cert_name"
