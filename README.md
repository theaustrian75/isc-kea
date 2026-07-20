# ISC Kea containers

Alpine-based images for **kea-dhcp4** (with HA + lease-cmds hooks) and **kea-dhcp-ddns**.

Config and TLS material are **not** baked into the images — mount `/etc/kea` (and related volumes) at runtime.

## Images

| Dockerfile | Packages | Ports |
|---|---|---|
| `Dockerfile.kea-dhcp4` | `kea-dhcp4`, `kea-hook-ha`, `kea-hook-lease-cmds` | 67/tcp+udp |
| `Dockerfile.kea-dhcp-ddns` | `kea-dhcp-ddns` | 53001/udp |

## Build & test

```bash
make build          # build both
make test           # build + smoke-test both
```

Requires Docker (or set `DOCKER=podman`).

CI (GitHub Actions) builds each image, runs smoke tests, then verifies a multi-arch (`amd64`/`arm64`) build.

## Publish (local registry)

`build-latest.sh` builds multi-arch manifests with Podman and pushes to `registry.klausk.xyz`. It expects a Podman secret `dn-registry-password`. Prefer running that only on a trusted builder — the script also prunes unused images aggressively.

## PKI

Internal CA + host certs for Kea TLS live under `pki/` but **private keys are gitignored**. See [docs/PKI.md](docs/PKI.md).

```bash
./scripts/pki-init-ca.sh          # once
./scripts/pki-issue-host.sh odin  # per host (odin, tyr, …)
```

## Runtime volumes

**kea-dhcp4:** `/etc/kea`, `/var/lib/kea`, `/run/kea`  
**kea-dhcp-ddns:** `/etc/kea`, `/run/kea`
