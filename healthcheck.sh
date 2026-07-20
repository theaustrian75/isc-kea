#!/bin/sh
# HEALTHCHECK helper — control-socket readiness only (not upstream/HA reachability).
set -eu

KEA_ROLE="${KEA_ROLE:?}"
case "$KEA_ROLE" in
  kea-dhcp4)
    BIN=kea-dhcp4
    SOCKET=/run/kea/kea4-ctrl-socket
    ;;
  kea-dhcp-ddns)
    BIN=kea-dhcp-ddns
    SOCKET=/run/kea/kea-ddns-ctrl-socket
    ;;
  *)
    exit 1
    ;;
esac

pidof "$BIN" >/dev/null || exit 1
# Socket appears after Kea finishes startup; tolerate a brief window.
test -S "$SOCKET" || test -e "$SOCKET" || exit 1
exit 0
