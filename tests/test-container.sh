#!/bin/sh
# Build-independent container smoke tests. Pass the image reference and role.
# Usage: tests/test-container.sh IMAGE ROLE
# ROLE is kea-dhcp4 or kea-dhcp-ddns.
set -eu

IMAGE="${1:?Usage: tests/test-container.sh IMAGE ROLE}"
ROLE="${2:?Usage: tests/test-container.sh IMAGE ROLE}"
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
CONTAINER="isc-kea-${ROLE}-test-$$"
TMP_ROOT=$(mktemp -d)

# Invoked through trap.
# shellcheck disable=SC2317
cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

case "$ROLE" in
  kea-dhcp4)
    PKG=kea-dhcp4
    BIN=/usr/sbin/kea-dhcp4
    CONFIG_NAME=kea-dhcp4.json
    EXTRA_HOOKS='kea-hook-ha kea-hook-lease-cmds'
    ;;
  kea-dhcp-ddns)
    PKG=kea-dhcp-ddns
    BIN=/usr/sbin/kea-dhcp-ddns
    CONFIG_NAME=kea-dhcp-ddns.json
    EXTRA_HOOKS=
    ;;
  *)
    echo "unknown role: $ROLE" >&2
    exit 1
    ;;
esac

echo "==> Smoke-testing $IMAGE ($ROLE)"

# Entrypoint must be present and executable.
docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
  'test -x /usr/local/bin/entrypoint.sh'

# Required packages installed.
# shellcheck disable=SC2086
docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
  "apk info -e $PKG $EXTRA_HOOKS"

# Binary reports a version.
version=$(docker run --rm --entrypoint "$BIN" "$IMAGE" -v 2>&1 || true)
if [ -z "$version" ]; then
  echo "ERROR: $BIN produced no version output" >&2
  exit 1
fi
echo "    version: $version"

# Config / runtime volume paths exist.
docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
  'test -d /etc/kea && test -d /run/kea'

# Image must not contain TLS private keys or the Thor CA key material.
if docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
  'find / \( -name "*.key" -o -name "Thor_CA*" \) 2>/dev/null | grep -q .'; then
  echo "ERROR: private key / CA material found inside image" >&2
  exit 1
fi

assert_failure() {
  expected=$1
  shift
  if output=$("$@" 2>&1); then
    echo "Expected command to fail: $*" >&2
    exit 1
  fi
  case "$output" in
    *"$expected"*) ;;
    *)
      printf 'Expected failure containing %s, got:\n%s\n' "$expected" "$output" >&2
      exit 1
      ;;
  esac
}

# Missing config must fail via the entrypoint.
assert_failure "$CONFIG_NAME" \
  docker run --rm "$IMAGE"

# Prepare a writable config + state tree for a hardened runtime smoke start.
mkdir -p "$TMP_ROOT/etc" "$TMP_ROOT/lib" "$TMP_ROOT/run"
cp "$ROOT/tests/fixtures/$CONFIG_NAME" "$TMP_ROOT/etc/$CONFIG_NAME"
chmod 755 "$TMP_ROOT" "$TMP_ROOT/etc" "$TMP_ROOT/lib" "$TMP_ROOT/run"
chmod 644 "$TMP_ROOT/etc/$CONFIG_NAME"

# Config syntax check.
docker run --rm \
  -v "$TMP_ROOT/etc:/etc/kea:ro" \
  --entrypoint "$BIN" \
  "$IMAGE" -t "/etc/kea/$CONFIG_NAME"

# Production-like constraints: read-only root, dropped caps, tmpfs for state.
case "$ROLE" in
  kea-dhcp4)
    docker run -d --name "$CONTAINER" \
      --read-only \
      --security-opt no-new-privileges:true \
      --cap-drop ALL \
      --cap-add NET_BIND_SERVICE \
      --cap-add NET_RAW \
      --pids-limit 128 \
      --memory 256m \
      -v "$TMP_ROOT/etc:/etc/kea:ro" \
      --tmpfs /run/kea:rw,mode=0755,size=16m \
      --tmpfs /var/lib/kea:rw,mode=0755,size=32m \
      --tmpfs /tmp:rw,mode=1777,size=16m \
      "$IMAGE" >/dev/null
    ;;
  kea-dhcp-ddns)
    docker run -d --name "$CONTAINER" \
      --read-only \
      --security-opt no-new-privileges:true \
      --cap-drop ALL \
      --cap-add NET_BIND_SERVICE \
      --pids-limit 128 \
      --memory 256m \
      -v "$TMP_ROOT/etc:/etc/kea:ro" \
      --tmpfs /run/kea:rw,mode=0755,size=16m \
      --tmpfs /tmp:rw,mode=1777,size=16m \
      "$IMAGE" >/dev/null
    ;;
esac

attempt=0
while [ "$attempt" -lt 30 ]; do
  status=$(docker inspect -f '{{.State.Status}}' "$CONTAINER")
  case "$status" in
    running)
      if docker exec "$CONTAINER" /bin/sh -c "pidof $(basename "$BIN") >/dev/null"; then
        echo "Hardened container smoke test passed ($ROLE)"
        exit 0
      fi
      ;;
    exited|dead)
      docker logs "$CONTAINER" >&2
      echo "Container exited before becoming ready ($ROLE)" >&2
      exit 1
      ;;
  esac
  attempt=$((attempt + 1))
  sleep 1
done

docker logs "$CONTAINER" >&2
echo "Container did not become ready within 30 seconds ($ROLE)" >&2
exit 1
