# AGENTS.md

## Cursor Cloud specific instructions

This repo builds two hardened Alpine Docker images — `kea-dhcp4` (ISC Kea DHCPv4
with HA + lease-cmds hooks) and `kea-dhcp-ddns` (Kea DHCP-DDNS). They are
headless network daemons (no GUI/web UI); verify them from the terminal via the
Kea HTTP control channel. There is no language package manager — everything is
driven by Docker plus a few shell scripts. Standard build/test/run commands live
in `README.md`; the notes below only cover non-obvious Cursor Cloud caveats.

### Starting Docker (required each session)

The Docker engine, buildx/compose plugins, `shellcheck`, `jq`, and `openssl` are
baked into the environment snapshot, but the Docker **daemon is not auto-started**.
Start it once per session before building/running anything:

```bash
sudo dockerd >/tmp/dockerd.log 2>&1 &   # or run in a tmux session
sudo chmod 666 /var/run/docker.sock     # let the ubuntu user talk to docker without sudo
```

`/etc/docker/daemon.json` is preconfigured for this VM (`fuse-overlayfs` storage
driver + `containerd-snapshotter: false`, needed on Docker 29) and iptables is
set to the legacy backend. Do not change those or the daemon may fail to start.

### `docker run --memory` does NOT work here (cgroup limitation)

This VM's cgroup v2 root is delegated by the host as `domain threaded`, so the
`memory` (and `io`) **domain** controllers cannot be delegated to any child
cgroup. Consequences:

- Plain `docker run`, `docker build`, `docker compose up`, and `--pids-limit`
  (a threaded controller) all work normally.
- Any `docker run --memory ...` fails with:
  `cannot enter cgroupv2 "/sys/fs/cgroup/docker" with domain controllers -- it is in threaded mode`.
- Therefore `tests/test-container.sh` and `tests/test-ha.sh` fail at their
  hardened `docker run -d ... --memory 256m` step. This is an environment
  constraint, not a repo bug — do not "fix" it by editing the test scripts.

What still runs green in this environment: `shellcheck ...`,
`docker build` (both Dockerfiles), `tests/test-cert-expiry.sh`, and the CI
"validate example configs" step (`docker run --entrypoint /usr/sbin/kea-dhcp4 -t ...`,
no `--memory`).

### Running via `docker compose` with a read-only rootfs

The containers run `read_only: true` and bind-mount the config dir at `/etc/kea`,
then bind-mount cert dirs at `/etc/kea/certs/control` (and `/etc/kea/certs/ha`
for dhcp4). Because `/etc/kea` is itself a read-only bind mount, those nested
cert mountpoints must already exist inside the config dir, otherwise
`docker compose up` fails with `read-only file system` while creating the
mountpoint. Create them before starting:

```bash
mkdir -p "$KEA_DHCP4_CONFIG_DIR"/certs/control "$KEA_DHCP4_CONFIG_DIR"/certs/ha
```

(`.env`, `/config/kea-dhcp4/`, and `/certs/` are gitignored, so local run
scaffolding never lands in the repo. `.env.example` already points the
`*_CONFIG_DIR` / `*_CERT_DIR` vars at `/tmp/...` paths.)

### Control channel (how to verify a running server)

Kea 3.x has a built-in HTTP control channel (no separate control-agent). With
the example/fixture configs it listens on `http://127.0.0.1:8001/` (dhcp4).
`healthcheck.sh` POSTs `status-get`. To exercise core DHCP lease management
(the `lease-cmds` hook this image bundles), POST JSON commands, e.g.:

```bash
curl -sS -X POST -H 'Content-Type:application/json' \
  -d '{"command":"lease4-add","service":["dhcp4"],"arguments":{"ip-address":"192.0.2.50","hw-address":"1a:2b:3c:4d:5e:6f","hostname":"demo"}}' \
  http://127.0.0.1:8001/
curl -sS -X POST -H 'Content-Type:application/json' \
  -d '{"command":"lease4-get-all","service":["dhcp4"],"arguments":{"subnets":[1]}}' \
  http://127.0.0.1:8001/
```

A `lease-cmds` command requires the config to load
`/usr/lib/kea/hooks/libdhcp_lease_cmds.so` (the shipped fixture in
`tests/fixtures/kea-dhcp4.json` does not; add it if you need lease-cmds).
