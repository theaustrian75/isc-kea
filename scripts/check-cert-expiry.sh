#!/usr/bin/env bash
# Fail if any PEM leaf/CA cert expires within WARN_DAYS (default 30).
# Usage: scripts/check-cert-expiry.sh [WARN_DAYS] [pem...]
# If no PEM paths are given, checks pki/**/*.pem when present.
set -euo pipefail

WARN_DAYS="${1:-30}"
shift || true

case "$WARN_DAYS" in
  *[!0-9]*|"")
    echo "WARN_DAYS must be a non-negative integer" >&2
    exit 1
    ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
shopt -s nullglob
PEMS=("$@")
if [[ ${#PEMS[@]} -eq 0 ]]; then
  PEMS=("$ROOT"/pki/*.pem "$ROOT"/pki/*/*.pem "$ROOT"/pki/certs/*.pem)
fi

if [[ ${#PEMS[@]} -eq 0 ]]; then
  echo "No PEM files to check (pki leaves are gitignored — run locally against issued certs)."
  exit 0
fi

now=$(date +%s)
cutoff=$((now + WARN_DAYS * 86400))
failed=0

for pem in "${PEMS[@]}"; do
  [[ -f "$pem" ]] || continue
  # Skip pure private-key files mistakenly named .pem
  if ! openssl x509 -in "$pem" -noout -enddate >/dev/null 2>&1; then
    continue
  fi
  end_raw=$(openssl x509 -in "$pem" -noout -enddate)
  end_ts=$(date -d "${end_raw#notAfter=}" +%s)
  subject=$(openssl x509 -in "$pem" -noout -subject)
  if (( end_ts < now )); then
    echo "EXPIRED: $pem ($subject) $end_raw" >&2
    failed=1
  elif (( end_ts < cutoff )); then
    echo "EXPIRING_SOON (<${WARN_DAYS}d): $pem ($subject) $end_raw" >&2
    failed=1
  else
    echo "OK: $pem ($subject) $end_raw"
  fi
done

exit "$failed"
