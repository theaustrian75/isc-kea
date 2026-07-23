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
| `KEA_HEALTHCHECK_URL` | `http://127.0.0.1:8001/` or `:8002/` | Control-channel URL for `status-get` |
| `KEA_HEALTHCHECK_INSECURE` | `true` | Pass `curl -k` for lab HTTPS certs |

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
# kea-*.json           -> *_CONFIG_DIR
# control ca/cert/key  -> *_CONTROL_CERT_DIR  (/etc/kea/certs/control)
# HA ca/cert/key       -> *_HA_CERT_DIR       (/etc/kea/certs/ha, dhcp4 only)
docker compose up -d
```

Control and HA can use different leaves (or point both env dirs at the same host path). See `config/examples/certs/README.md`.

Quadlet units: `kea-dhcp4.container`, `kea-dhcp-ddns.container` (set `User=0` so the entrypoint can chown, then drops to `KEA_UID`/`KEA_GID`). Quadlet `Tmpfs=` may set `uid`/`gid` to match; Compose cannot (Docker rejects those options), so compose relies on entrypoint `chown`.

Example configs (including HA + TLS paths): `config/examples/`.

## PKI

Kea HA peer transport uses **mutual TLS**: each node presents a client certificate and validates the peer against a private trust anchor. Public CAs such as **Let's Encrypt** and **ZeroSSL** are not suitable for that path:

- They issue **server** certificates for publicly validated hostnames, not internal mTLS identities (private DNS, RFC1918 / documentation IPs, OOB management names).
- They do not hand you a CA you control as `trust-anchor` for peer verification the way Kea HA expects.
- ACME challenges and short lifetimes are a poor fit for closed management networks that should not depend on the public internet to renew HA links.

Use the private **Example Internal CA** under `pki/` instead (details in [docs/PKI.md](docs/PKI.md)). Private keys are gitignored.

```bash
./scripts/pki-init-ca.sh
./scripts/pki-issue-host.sh dhcp1
./scripts/check-cert-expiry.sh   # fails if a leaf expires within 30 days
```

## Runtime volumes

**kea-dhcp4:** `/etc/kea`, `/etc/kea/certs/control`, `/etc/kea/certs/ha`, `/var/lib/kea`, `/run/kea`  
**kea-dhcp-ddns:** `/etc/kea`, `/etc/kea/certs/control`, `/run/kea`
