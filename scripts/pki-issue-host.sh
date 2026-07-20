#!/usr/bin/env bash
# Issue a host cert for Kea TLS (HA / control-agent / DDNS) under ./pki/<host>/
# Usage: ./scripts/pki-issue-host.sh <host-dir>
# Example: ./scripts/pki-issue-host.sh odin
set -euo pipefail

HOST="${1:?usage: $0 <host-dir e.g. odin|tyr>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKI="$ROOT/pki"
HOSTDIR="$PKI/$HOST"

if [[ ! -f "$HOSTDIR/openssl.cnf" ]]; then
  echo "Missing $HOSTDIR/openssl.cnf" >&2
  exit 1
fi
if [[ ! -f "$PKI/Thor_CA.key" || ! -f "$PKI/Thor_CA.pem" ]]; then
  echo "CA missing. Run ./scripts/pki-init-ca.sh first." >&2
  exit 1
fi

umask 077
cd "$PKI"

# New key + CSR
openssl req -new -nodes \
  -config "$HOSTDIR/openssl.cnf" \
  -keyout "$HOSTDIR/${HOST}.key" \
  -out "$HOSTDIR/${HOST}.csr"

# Sign with CA; SAN/EKU from host openssl.cnf via -extfile
openssl ca -batch -config openssl.cnf \
  -extensions v3_kea \
  -extfile "$HOSTDIR/openssl.cnf" \
  -in "$HOSTDIR/${HOST}.csr" \
  -out "$HOSTDIR/${HOST}.pem"

chmod 600 "$HOSTDIR/${HOST}.key"
chmod 644 "$HOSTDIR/${HOST}.pem"
rm -f "$HOSTDIR/${HOST}.csr"

echo "Issued:"
echo "  $HOSTDIR/${HOST}.key"
echo "  $HOSTDIR/${HOST}.pem"
openssl x509 -in "$HOSTDIR/${HOST}.pem" -noout -subject -issuer -dates -ext subjectAltName
echo
echo "Mount at runtime (do not bake into the image), e.g.:"
echo "  ${HOST}.pem  -> /etc/kea/certs/${HOST}.pem"
echo "  ${HOST}.key  -> /etc/kea/certs/${HOST}.key"
echo "  Thor_CA.pem  -> /etc/kea/certs/ca.pem"
