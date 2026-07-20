#!/bin/sh
# Shared entrypoint for kea-dhcp4 and kea-dhcp-ddns images.
# KEA_ROLE is baked by the Dockerfile; KEA_UID/KEA_GID are overridable at runtime.
set -eu

KEA_ROLE="${KEA_ROLE:?KEA_ROLE must be set by the image}"
KEA_UID="${KEA_UID:-100}"
KEA_GID="${KEA_GID:-101}"
TZ="${TZ:-UTC}"
SKIP_CONFIG_TEST="${SKIP_CONFIG_TEST:-false}"

case "$KEA_ROLE" in
  kea-dhcp4)
    BIN=/usr/sbin/kea-dhcp4
    CONFIG=/etc/kea/kea-dhcp4.json
    PID_FILE=/run/kea/kea-dhcp4.kea-dhcp4.pid
    NEED_LEASE_DIR=true
    ;;
  kea-dhcp-ddns)
    BIN=/usr/sbin/kea-dhcp-ddns
    CONFIG=/etc/kea/kea-dhcp-ddns.json
    PID_FILE=/run/kea/kea-dhcp-ddns.kea-dhcp-ddns.pid
    NEED_LEASE_DIR=false
    ;;
  *)
    echo "KEA_ROLE must be kea-dhcp4 or kea-dhcp-ddns (got: $KEA_ROLE)" >&2
    exit 1
    ;;
esac

validate_id() {
  variable=$1
  value=$2
  case "$value" in
    *[!0-9]*|"")
      echo "$variable must be a non-zero numeric ID" >&2
      exit 1
      ;;
  esac
  if [ "$value" -eq 0 ]; then
    echo "$variable must be a non-zero numeric ID" >&2
    exit 1
  fi
}

validate_id KEA_UID "$KEA_UID"
validate_id KEA_GID "$KEA_GID"

case "$TZ" in
  /*|*..*|*[!a-zA-Z0-9_+./-]*|"")
    echo "TZ must be an installed IANA timezone (for example America/New_York)" >&2
    exit 1
    ;;
esac
if [ ! -f "/usr/share/zoneinfo/$TZ" ]; then
  echo "TZ is not installed: $TZ" >&2
  exit 1
fi
export TZ

case "$SKIP_CONFIG_TEST" in
  true|false) ;;
  *)
    echo "SKIP_CONFIG_TEST must be true or false" >&2
    exit 1
    ;;
esac

if [ ! -f "$CONFIG" ]; then
  echo "Required configuration file is missing: $CONFIG (mount /etc/kea)" >&2
  exit 1
fi
if [ ! -r "$CONFIG" ]; then
  echo "Required configuration file is not readable by uid $(id -u): $CONFIG" >&2
  exit 1
fi

# Optional TLS material: if the paths appear in config as /etc/kea/certs/*, require them.
if grep -Eq '/etc/kea/certs/' "$CONFIG" 2>/dev/null; then
  for tls_file in /etc/kea/certs/ca.pem /etc/kea/certs/cert.pem /etc/kea/certs/key.pem; do
    if [ ! -f "$tls_file" ]; then
      echo "Required TLS file is missing: $tls_file (config references /etc/kea/certs/)" >&2
      exit 1
    fi
    if [ ! -r "$tls_file" ]; then
      echo "Required TLS file is not readable by uid $(id -u): $tls_file" >&2
      exit 1
    fi
  done
fi

mkdir -p /run/kea
chmod 0750 /run/kea
chown "${KEA_UID}:${KEA_GID}" /run/kea

if [ "$NEED_LEASE_DIR" = true ]; then
  mkdir -p /var/lib/kea
  chown "${KEA_UID}:${KEA_GID}" /var/lib/kea
fi

if [ "$SKIP_CONFIG_TEST" = false ]; then
  if ! setpriv --reuid="$KEA_UID" --regid="$KEA_GID" --clear-groups -- \
    "$BIN" -t "$CONFIG"; then
    echo "Configuration check failed for $CONFIG" >&2
    exit 1
  fi
fi

rm -f "$PID_FILE"

# Drop to the configured identity. Caps (NET_BIND_SERVICE / NET_RAW) stay effective.
exec setpriv --reuid="$KEA_UID" --regid="$KEA_GID" --clear-groups -- \
  "$BIN" -c "$CONFIG"
