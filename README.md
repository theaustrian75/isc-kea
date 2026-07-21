# ISC Kea containers

Alpine 3.24 images for **kea-dhcp4** (HA + lease-cmds) and **kea-dhcp-ddns**.

Config and TLS material are mounted at runtime. The process drops to configurable `KEA_UID`/`KEA_GID` via `setpriv`.

## Images

| Dockerfile | Packages | GHCR |
|---|---|---|
| `Dockerfile.kea-dhcp4` | `kea-dhcp4`, `kea-hook-ha`, `kea-hook-lease-cmds` | `ghcr.io/theaustrian75/isc-kea/kea-dhcp4` |
| `Dockerfile.kea-dhcp-ddns` | `kea-dhcp-ddns` | `ghcr.io/theaustrian75/isc-kea/kea-dhcp-ddns` |

Tags: `latest` (default branch), `main`, `sha-*`, and `v*` releases. Multi-arch (`amd64` / `arm64`).

Build args / runtime env (both images):

| Variable | Default | Purpose |
|---|---|---|
| `KEA_UID` | `100` | Numeric UID after privilege drop |
| `KEA_GID` | `101` | Numeric GID after privilege drop |
| `TZ` | `UTC` | IANA timezone |
| `SKIP_CONFIG_TEST` | `false` | Skip `kea-*-t` before start |

## Build & test

```bash
docker build --tag isc-kea/kea-dhcp4:test --file Dockerfile.kea-dhcp4 .
docker build --tag isc-kea/kea-dhcp-ddns:test --file Dockerfile.kea-dhcp-ddns .

tests/test-container.sh isc-kea/kea-dhcp4:test kea-dhcp4
tests/test-container.sh isc-kea/kea-dhcp-ddns:test kea-dhcp-ddns
tests/test-ha.sh isc-kea/kea-dhcp4:test
tests/test-cert-expiry.sh
```

CI mirrors [jumpcloud-ldap-proxy](https://github.com/theaustrian75/jumpcloud-ldap-proxy): validate → per-arch GHCR push → multi-arch merge.

## Compose / Quadlet

```bash
cp .env.example .env
# put kea-*.json (+ certs) under the configured config dirs
docker compose up -d
```

Quadlet units: `kea-dhcp4.container`, `kea-dhcp-ddns.container` (set `User=0` so the entrypoint can chown, then drops to `KEA_UID`/`KEA_GID`). Keep tmpfs `uid`/`gid` in sync with those env values.

Example configs (including HA + TLS paths): `config/examples/`.

## PKI

Private keys are gitignored. See [docs/PKI.md](docs/PKI.md).

```bash
./scripts/pki-init-ca.sh
./scripts/pki-issue-host.sh odin
./scripts/check-cert-expiry.sh   # fails if a leaf expires within 30 days
```

## Runtime volumes

**kea-dhcp4:** `/etc/kea`, `/var/lib/kea`, `/run/kea`  
**kea-dhcp-ddns:** `/etc/kea`, `/run/kea`
