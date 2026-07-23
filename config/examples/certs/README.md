# Example TLS layout

Mount separate trees for the HTTPS **control** socket and **HA** peers:

| Host path (compose default) | Container path |
|---|---|
| `./certs/kea-dhcp4/control` | `/etc/kea/certs/control` |
| `./certs/kea-dhcp4/ha` | `/etc/kea/certs/ha` |
| `./certs/kea-dhcp-ddns/control` | `/etc/kea/certs/control` |

Each tree needs `ca.pem`, `cert.pem`, and `key.pem` (copy from your PKI; never commit private keys).

Typical mapping from `pki/`:

- `ca.pem` ← `Example_CA.pem`
- `cert.pem` / `key.pem` ← `pki/<host>/<host>.pem` and `.key`

In `kea-dhcp4-ha.json`:

- control socket → `/etc/kea/certs/control/*` (port **8001**)
- HA hook → `/etc/kea/certs/ha/*` (peer URLs port **8000**)

Point both compose cert dirs at the same host directory if you want one shared leaf.
