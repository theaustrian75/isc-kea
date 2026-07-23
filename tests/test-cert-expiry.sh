#!/bin/sh
# Unit-test scripts/check-cert-expiry.sh with synthetic PEMs.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
# Invoked through trap.
# shellcheck disable=SC2317
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj "/CN=expiring-soon" \
  -keyout "$TMP/soon.key" -out "$TMP/soon.pem" >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
  -subj "/CN=fresh" \
  -keyout "$TMP/fresh.key" -out "$TMP/fresh.pem" >/dev/null 2>&1

if "$ROOT/scripts/check-cert-expiry.sh" 30 "$TMP/fresh.pem"; then
  :
else
  echo "expected fresh cert to pass" >&2
  exit 1
fi

if "$ROOT/scripts/check-cert-expiry.sh" 30 "$TMP/soon.pem"; then
  echo "expected soon-expiring cert to fail" >&2
  exit 1
fi

# No args and empty pki leaves should succeed (nothing to check in CI checkout).
"$ROOT/scripts/check-cert-expiry.sh" 30

echo "Cert expiry checker passed"
