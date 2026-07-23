#!/bin/sh
# Pairwise HA smoke: two kea-dhcp4 peers on a bridge network with lease-cmds + HA.
# Kea HA peer URLs must be IP literals (hostnames are rejected).
# Usage: tests/test-ha.sh IMAGE
set -eu

IMAGE="${1:?Usage: tests/test-ha.sh IMAGE}"
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
NET="kea-ha-test-$$"
PRIMARY="kea-dhcp1-$$"
STANDBY="kea-dhcp2-$$"
DHCP1_IP=172.30.97.10
DHCP2_IP=172.30.97.11

# Invoked through trap.
# shellcheck disable=SC2317
cleanup() {
  docker rm -f "$PRIMARY" "$STANDBY" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

render() {
  peer=$1
  sed -e "s/@@PEER@@/${peer}/g" \
      -e "s/@@DHCP1_IP@@/${DHCP1_IP}/g" \
      -e "s/@@DHCP2_IP@@/${DHCP2_IP}/g" \
      "$ROOT/tests/fixtures/kea-dhcp4-ha.json.template"
}

mkdir -p "$TMP/dhcp1" "$TMP/dhcp2"
render dhcp1 > "$TMP/dhcp1/kea-dhcp4.json"
render dhcp2 > "$TMP/dhcp2/kea-dhcp4.json"

# Config syntax + HA hook load for each peer identity.
for peer in dhcp1 dhcp2; do
  docker run --rm \
    -v "$TMP/$peer:/etc/kea:ro" \
    --tmpfs /run/kea:rw,mode=0750,size=16m \
    --tmpfs /var/lib/kea:rw,mode=0750,size=32m \
    --entrypoint /usr/sbin/kea-dhcp4 \
    "$IMAGE" -t /etc/kea/kea-dhcp4.json
done

docker network create --subnet=172.30.97.0/24 "$NET" >/dev/null

run_peer() {
  name=$1
  peer=$2
  ip=$3
  docker run -d --name "$name" \
    --network "$NET" --ip "$ip" \
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

run_peer "$PRIMARY" dhcp1 "$DHCP1_IP"
run_peer "$STANDBY" dhcp2 "$DHCP2_IP"

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

sleep 3
docker exec "$PRIMARY" pidof kea-dhcp4 >/dev/null
docker exec "$STANDBY" pidof kea-dhcp4 >/dev/null
docker exec "$PRIMARY" /bin/sh -c 'test -e /run/kea/kea4-ctrl-socket'
docker exec "$STANDBY" /bin/sh -c 'test -e /run/kea/kea4-ctrl-socket'

echo "HA pairwise smoke test passed"
