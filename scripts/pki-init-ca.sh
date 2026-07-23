#!/usr/bin/env bash
# Create (or refresh layout for) the Example Internal CA under ./pki
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

if [[ -f Example_CA.key || -f Example_CA.pem ]]; then
  echo "CA already exists (Example_CA.key / Example_CA.pem). Refusing to overwrite."
  echo "Remove them manually if you intend to start a new CA."
  exit 1
fi

openssl req -new -x509 -days 3650 -config openssl.cnf \
  -keyout Example_CA.key -out Example_CA.pem \
  -extensions v3_ca

chmod 600 Example_CA.key
chmod 644 Example_CA.pem

echo "Created:"
echo "  $PKI/Example_CA.key  (keep offline / in a secret store)"
echo "  $PKI/Example_CA.pem  (distribute to Kea nodes as trust anchor)"
openssl x509 -in Example_CA.pem -noout -subject -dates
