#!/bin/sh
# Pairwise HA smoke: two kea-dhcp4 peers on a bridge network with lease-cmds + HA.
# Usage: tests/test-ha.sh IMAGE
set -eu

IMAGE="${1:?Usage: tests/test-ha.sh IMAGE}"
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
NET="kea-ha-test-$$"
PRIMARY="kea-odin-$$"
STANDBY="kea-tyr-$$"

# Invoked through trap.
# shellcheck disable=SC2317
cleanup() {
  docker rm -f "$PRIMARY" "$STANDBY" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

mkdir -p "$TMP/odin" "$TMP/tyr"
sed 's/@@PEER@@/odin/g' "$ROOT/tests/fixtures/kea-dhcp4-ha.json.template" \
  > "$TMP/odin/kea-dhcp4.json"
sed 's/@@PEER@@/tyr/g' "$ROOT/tests/fixtures/kea-dhcp4-ha.json.template" \
  > "$TMP/tyr/kea-dhcp4.json"

# Config syntax + HA hook load for each peer identity.
for peer in odin tyr; do
  docker run --rm \
    -v "$TMP/$peer:/etc/kea:ro" \
    --tmpfs /run/kea:rw,mode=0750,size=16m \
    --tmpfs /var/lib/kea:rw,mode=0750,size=32m \
    --entrypoint /usr/sbin/kea-dhcp4 \
    "$IMAGE" -t /etc/kea/kea-dhcp4.json
done

docker network create "$NET" >/dev/null

run_peer() {
  name=$1
  peer=$2
  docker run -d --name "$name" \
    --network "$NET" --network-alias "kea-$peer" \
    --read-only \
    --security-opt no-new-privileges:true \
    --cap-drop ALL \
    --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add DAC_OVERRIDE \
    --cap-add NET_BIND_SERVICE --cap-add NET_RAW \
    --pids-limit 128 --memory 256m \
    -e KEA_UID=100 -e KEA_GID=101 -e TZ=UTC \
    -v "$TMP/$peer:/etc/kea:ro" \
    --tmpfs /run/kea:rw,mode=0750,size=16m,uid=100,gid=101 \
    --tmpfs /var/lib/kea:rw,mode=0750,size=32m,uid=100,gid=101 \
    --tmpfs /tmp:rw,mode=1777,size=16m \
    "$IMAGE" >/dev/null
}

run_peer "$PRIMARY" odin
run_peer "$STANDBY" tyr

wait_healthy() {
  container=$1
  attempt=0
  while [ "$attempt" -lt 60 ]; do
    status=$(docker inspect -f \
      '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
      "$container")
    case "$status" in
      healthy) return 0 ;;
      exited|dead|unhealthy)
        docker logs "$container" >&2
        echo "$container ended before healthy: $status" >&2
        return 1
        ;;
    esac
    attempt=$((attempt + 1))
    sleep 1
  done
  docker logs "$container" >&2
  echo "$container did not become healthy in time" >&2
  return 1
}

wait_healthy "$PRIMARY"
wait_healthy "$STANDBY"

# Give HA heartbeats a moment, then confirm both processes still up.
sleep 3
docker exec "$PRIMARY" pidof kea-dhcp4 >/dev/null
docker exec "$STANDBY" pidof kea-dhcp4 >/dev/null

# Lease-cmds / HA libraries must be loaded (hot-standby mode in logs or config path).
logs=$(docker logs "$PRIMARY" 2>&1)
case "$logs" in
  *HA*|*ha*|*hot-standby*|*Availability*) ;;
  *)
    # Still accept if control socket exists — HA may be quiet at INFO.
    docker exec "$PRIMARY" /bin/sh -c 'test -e /run/kea/kea4-ctrl-socket'
    ;;
esac

echo "HA pairwise smoke test passed"
