#!/usr/bin/env bash
# Smoke-test a built Kea image: packages present, entrypoint executable, binary --version.
set -euo pipefail

IMAGE="${1:?usage: $0 <image> <kea-dhcp4|kea-dhcp-ddns>}"
ROLE="${2:?usage: $0 <image> <kea-dhcp4|kea-dhcp-ddns>}"

DOCKER="${DOCKER:-docker}"

case "$ROLE" in
  kea-dhcp4)
    PKG=kea-dhcp4
    BIN=/usr/sbin/kea-dhcp4
    ;;
  kea-dhcp-ddns)
    PKG=kea-dhcp-ddns
    BIN=/usr/sbin/kea-dhcp-ddns
    ;;
  *)
    echo "unknown role: $ROLE" >&2
    exit 1
    ;;
esac

echo "==> Inspecting $IMAGE ($ROLE)"

# Entrypoint must be present and executable
$DOCKER run --rm --entrypoint /bin/sh "$IMAGE" -c \
  'test -x /usr/local/bin/entrypoint.sh'

# Package installed
$DOCKER run --rm --entrypoint /bin/sh "$IMAGE" -c \
  "apk info -e $PKG"

# Binary exists and reports a version
VERSION="$($DOCKER run --rm --entrypoint "$BIN" "$IMAGE" -v 2>&1 || true)"
if [[ -z "$VERSION" ]]; then
  echo "ERROR: $BIN produced no version output" >&2
  exit 1
fi
echo "    version: $VERSION"

# Config volume paths exist as directories (VOLUME mounts)
$DOCKER run --rm --entrypoint /bin/sh "$IMAGE" -c \
  'test -d /etc/kea && test -d /run/kea'

# Image should NOT contain TLS private keys (certs are mounted at runtime)
if $DOCKER run --rm --entrypoint /bin/sh "$IMAGE" -c \
  'find / -name "*.key" -o -name "Thor_CA*" 2>/dev/null | grep -q .'; then
  echo "ERROR: private key / CA material found inside image" >&2
  exit 1
fi

echo "OK: $IMAGE"
