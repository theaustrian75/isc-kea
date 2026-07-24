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

# Optional TLS material: require every /etc/kea/certs/... path referenced in config.
# Allows separate control vs HA cert trees (e.g. certs/control and certs/ha).
tls_paths=$(grep -Eo '/etc/kea/certs/[^"[:space:]]+' "$CONFIG" 2>/dev/null | sort -u || true)
if [ -n "$tls_paths" ]; then
  while IFS= read -r tls_file; do
    [ -n "$tls_file" ] || continue
    if [ ! -f "$tls_file" ]; then
      echo "Required TLS file is missing: $tls_file (referenced in $CONFIG)" >&2
      exit 1
    fi
    if [ ! -r "$tls_file" ]; then
      echo "Required TLS file is not readable by uid $(id -u): $tls_file" >&2
      exit 1
    fi
  done <<EOF
$tls_paths
EOF
fi

mkdir -p /run/kea
# Quadlet/podman can set tmpfs uid=/gid= at mount time; Compose/Docker cannot.
# Chown here (needs CAP_CHOWN) so the dropped-privilege process can write sockets.
chmod 0750 /run/kea 2>/dev/null || true
chown "${KEA_UID}:${KEA_GID}" /run/kea 2>/dev/null || true

if [ "$NEED_LEASE_DIR" = true ]; then
  mkdir -p /var/lib/kea
  chown "${KEA_UID}:${KEA_GID}" /var/lib/kea 2>/dev/null || true
fi

if [ "$SKIP_CONFIG_TEST" = false ]; then
  if ! setpriv --reuid="$KEA_UID" --regid="$KEA_GID" --clear-groups -- \
    "$BIN" -t "$CONFIG"; then
    echo "Configuration check failed for $CONFIG" >&2
    exit 1
  fi
fi

rm -f "$PID_FILE"

# Drop root, then exec. After setuid, Linux clears effective caps on exec unless
# they are ambient. Ambient raises require the process NOT to have no_new_privs
# (so kea-dhcp4 compose/Quadlet must omit no-new-privileges).
case "$KEA_ROLE" in
  kea-dhcp4)
    exec setpriv --reuid="$KEA_UID" --regid="$KEA_GID" --clear-groups \
      --inh-caps=-all,+net_bind_service,+net_raw \
      --ambient-caps=-all,+net_bind_service,+net_raw \
      -- "$BIN" -c "$CONFIG"
    ;;
  *)
    exec setpriv --reuid="$KEA_UID" --regid="$KEA_GID" --clear-groups -- \
      "$BIN" -c "$CONFIG"
    ;;
esac
