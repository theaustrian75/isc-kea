#!/usr/bin/env bash
# Create (or refresh layout for) the Thor internal CA under ./pki
# Does NOT overwrite an existing CA key/cert.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKI="$ROOT/pki"
cd "$PKI"

umask 077

mkdir -p certs crl
touch index.txt
[[ -f serial ]] || echo '1000' > serial
[[ -f index.txt.attr ]] || echo 'unique_subject = no' > index.txt.attr

if [[ -f Thor_CA.key || -f Thor_CA.pem ]]; then
  echo "CA already exists (Thor_CA.key / Thor_CA.pem). Refusing to overwrite."
  echo "Remove them manually if you intend to start a new CA."
  exit 1
fi

openssl req -new -x509 -days 3650 -config openssl.cnf \
  -keyout Thor_CA.key -out Thor_CA.pem \
  -extensions v3_ca

chmod 600 Thor_CA.key
chmod 644 Thor_CA.pem

echo "Created:"
echo "  $PKI/Thor_CA.key  (keep offline / in a secret store)"
echo "  $PKI/Thor_CA.pem  (distribute to Kea nodes as trust anchor)"
openssl x509 -in Thor_CA.pem -noout -subject -dates
