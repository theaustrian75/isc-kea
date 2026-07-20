# ISC Kea containers

Alpine-based images for **kea-dhcp4** (with HA + lease-cmds hooks) and **kea-dhcp-ddns**.

Config and TLS material are **not** baked into the images — mount `/etc/kea` at runtime.

## Images

| Dockerfile | Packages | GHCR |
|---|---|---|
| `Dockerfile.kea-dhcp4` | `kea-dhcp4`, `kea-hook-ha`, `kea-hook-lease-cmds` | `ghcr.io/theaustrian75/isc-kea/kea-dhcp4` |
| `Dockerfile.kea-dhcp-ddns` | `kea-dhcp-ddns` | `ghcr.io/theaustrian75/isc-kea/kea-dhcp-ddns` |

Tags: `latest` (default branch), `main`, `sha-<git>`, and `v*` release tags. Multi-arch (`amd64` / `arm64`).

## Build & test

```bash
make build          # build both
make test           # build + smoke-test both (same checks as CI validate)
make shellcheck     # lint entrypoints and scripts
```

Requires Docker (or set `DOCKER=podman`).

## CI pipeline

Mirrors [jumpcloud-ldap-proxy](https://github.com/theaustrian75/jumpcloud-ldap-proxy):

1. **validate** — ShellCheck, compose config assertions, image build, `tests/test-container.sh`
2. **docker** — native `amd64` / `arm64` builds pushed to GHCR (skipped on PRs)
3. **docker-merge** — multi-arch manifests

## Compose

```bash
cp .env.example .env   # adjust image tags / config bind mounts
# put kea-*.json (and certs) under the configured config dirs
docker compose up -d
```

## Publish (private registry)

`build-latest.sh` still builds multi-arch manifests with Podman for `registry.klausk.xyz` (Podman secret `dn-registry-password`). CI publishes to GHCR; use the script when you need the dragonsnest registry.

## PKI

Internal CA + host certs live under `pki/` but **private keys are gitignored**. See [docs/PKI.md](docs/PKI.md).

```bash
./scripts/pki-init-ca.sh
./scripts/pki-issue-host.sh odin
```

## Runtime volumes

**kea-dhcp4:** `/etc/kea`, `/var/lib/kea`, `/run/kea`  
**kea-dhcp-ddns:** `/etc/kea`, `/run/kea`
