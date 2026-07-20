#!/bin/sh
# Build-independent container smoke tests. Pass the image reference and role.
# Usage: tests/test-container.sh IMAGE ROLE
set -eu

IMAGE="${1:?Usage: tests/test-container.sh IMAGE ROLE}"
ROLE="${2:?Usage: tests/test-container.sh IMAGE ROLE}"
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
CONTAINER="isc-kea-${ROLE}-test-$$"
TMP_ROOT=$(mktemp -d)
RUNTIME_UID=12345
RUNTIME_GID=12346

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

docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
  'test -x /usr/local/bin/entrypoint.sh && test -x /usr/local/bin/healthcheck.sh'

# shellcheck disable=SC2086
docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
  "apk info -e $PKG $EXTRA_HOOKS"

version=$(docker run --rm --entrypoint "$BIN" "$IMAGE" -v 2>&1 || true)
if [ -z "$version" ]; then
  echo "ERROR: $BIN produced no version output" >&2
  exit 1
fi
echo "    version: $version"

default_settings=$(docker run --rm --entrypoint /bin/sh "$IMAGE" \
  -c 'printf "%s:%s %s" "$KEA_UID" "$KEA_GID" "$TZ"')
if [ "$default_settings" != "100:101 UTC" ]; then
  echo "Expected defaults '100:101 UTC', got '$default_settings'" >&2
  exit 1
fi

docker image inspect "$IMAGE" |
  jq -e '.[0].Config.Healthcheck.Test == ["CMD", "/usr/local/bin/healthcheck.sh"]' >/dev/null

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

assert_failure "Required configuration file is missing" \
  docker run --rm "$IMAGE"

assert_failure "KEA_UID must be a non-zero numeric ID" \
  docker run --rm -e KEA_UID=0 "$IMAGE"

assert_failure "KEA_GID must be a non-zero numeric ID" \
  docker run --rm -e KEA_GID=abc \
  -v "$ROOT/tests/fixtures/$CONFIG_NAME:/etc/kea/$CONFIG_NAME:ro" "$IMAGE"

assert_failure "TZ must be an installed IANA timezone" \
  docker run --rm -e 'TZ=America/New York' \
  -v "$ROOT/tests/fixtures/$CONFIG_NAME:/etc/kea/$CONFIG_NAME:ro" "$IMAGE"

mkdir -p "$TMP_ROOT/etc" "$TMP_ROOT/lib" "$TMP_ROOT/run"
cp "$ROOT/tests/fixtures/$CONFIG_NAME" "$TMP_ROOT/etc/$CONFIG_NAME"
chmod 755 "$TMP_ROOT" "$TMP_ROOT/etc" "$TMP_ROOT/lib"
chmod 750 "$TMP_ROOT/run"
chmod 644 "$TMP_ROOT/etc/$CONFIG_NAME"

COMMON_RUN="--read-only
  --security-opt no-new-privileges:true
  --cap-drop ALL
  --cap-add CHOWN
  --cap-add SETUID
  --cap-add SETGID
  --cap-add DAC_OVERRIDE
  --cap-add NET_BIND_SERVICE
  --pids-limit 128
  --memory 256m
  -e KEA_UID=$RUNTIME_UID
  -e KEA_GID=$RUNTIME_GID
  -e TZ=UTC
  -v $TMP_ROOT/etc:/etc/kea:ro
  --tmpfs /run/kea:rw,mode=0750,size=16m,uid=$RUNTIME_UID,gid=$RUNTIME_GID
  --tmpfs /tmp:rw,mode=1777,size=16m"

# shellcheck disable=SC2086
case "$ROLE" in
  kea-dhcp4)
    docker run -d --name "$CONTAINER" \
      $COMMON_RUN \
      --cap-add NET_RAW \
      --tmpfs /var/lib/kea:rw,mode=0750,size=32m,uid="$RUNTIME_UID",gid="$RUNTIME_GID" \
      "$IMAGE" >/dev/null
    ;;
  kea-dhcp-ddns)
    docker run -d --name "$CONTAINER" \
      $COMMON_RUN \
      "$IMAGE" >/dev/null
    ;;
esac

attempt=0
while [ "$attempt" -lt 45 ]; do
  status=$(docker inspect -f \
    '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
    "$CONTAINER")
  case "$status" in
    healthy)
      runtime_settings=$(docker exec "$CONTAINER" /bin/sh -c '
        pid=$(pidof '"$(basename "$BIN")"') || exit 1
        uid=$(awk "/^Uid:/{print \$2; exit}" /proc/"$pid"/status)
        gid=$(awk "/^Gid:/{print \$2; exit}" /proc/"$pid"/status)
        printf "%s:%s" "$uid" "$gid"
      ')
      if [ "$runtime_settings" != "${RUNTIME_UID}:${RUNTIME_GID}" ]; then
        echo "Expected process identity '${RUNTIME_UID}:${RUNTIME_GID}', got '${runtime_settings}'" >&2
        docker logs "$CONTAINER" >&2
        exit 1
      fi
      echo "Hardened container smoke test passed ($ROLE)"
      exit 0
      ;;
    exited|dead|unhealthy)
      docker logs "$CONTAINER" >&2
      echo "Container ended before becoming healthy ($ROLE): $status" >&2
      exit 1
      ;;
  esac
  attempt=$((attempt + 1))
  sleep 1
done

docker logs "$CONTAINER" >&2
echo "Container did not become healthy within 45 seconds ($ROLE)" >&2
exit 1
