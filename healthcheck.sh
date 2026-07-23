#!/bin/sh
# Probe the Kea HTTP(S) control channel with status-get.
# Prefer this over a bare unix-socket existence check: the API must answer.
#
# Env (optional):
#   KEA_HEALTHCHECK_URL   default http://127.0.0.1:8001/ (dhcp4) or :8002/ (d2)
#   KEA_HEALTHCHECK_INSECURE  true|false — pass curl -k for HTTPS lab certs (default true)
set -eu

KEA_ROLE="${KEA_ROLE:?}"
case "$KEA_ROLE" in
  kea-dhcp4)
    BIN=kea-dhcp4
    SERVICE=dhcp4
    DEFAULT_URL="http://127.0.0.1:8001/"
    ;;
  kea-dhcp-ddns)
    BIN=kea-dhcp-ddns
    SERVICE=d2
    DEFAULT_URL="http://127.0.0.1:8002/"
    ;;
  *)
    exit 1
    ;;
esac

pidof "$BIN" >/dev/null || exit 1

URL="${KEA_HEALTHCHECK_URL:-$DEFAULT_URL}"
INSECURE="${KEA_HEALTHCHECK_INSECURE:-true}"

CURL_OPTS="-sS --max-time 3 -X POST -H Content-Type:application/json"
case "$INSECURE" in
  true) CURL_OPTS="$CURL_OPTS -k" ;;
  false) ;;
  *)
    echo "KEA_HEALTHCHECK_INSECURE must be true or false" >&2
    exit 1
    ;;
esac

# shellcheck disable=SC2086
body=$(curl $CURL_OPTS \
  -d "{\"command\":\"status-get\",\"service\":[\"${SERVICE}\"]}" \
  "$URL") || exit 1

# Accept either a bare result object or a one-element list from the agent.
printf '%s' "$body" | grep -Eq '"result"[[:space:]]*:[[:space:]]*0' || exit 1
exit 0
