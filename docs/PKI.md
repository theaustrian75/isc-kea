# PKI for Kea TLS

This tree is a small OpenSSL “Example Internal CA” used for Kea mutual TLS (HA peer auth, control sockets, DDNS as configured). Leaf certs are issued for ~**825 days** (see `default_days` in `openssl.cnf`).

## What belongs in git vs what does not

| Path | In git? | Why |
|---|---|---|
| `pki/**/openssl.cnf` | yes | Non-secret templates (CN/SAN) |
| `Example_CA.pem` | optional | Public trust anchor — safe to distribute, still treat as internal |
| `*.key`, leaf `*.pem`, `index.txt`, `serial`, `certs/` | **no** | Private keys + CA database |

`.gitignore` already excludes keys and CA state. If this repo was ever pushed with keys present, **rotate the CA and all leaf certs**.

## Recommended operating model

### 1. Keep the CA offline (preferred)

- Generate `Example_CA.key` on an air-gapped or admin-only host (or a USB stick / HSM).
- Store the CA key in a secret manager (Vault, 1Password vault, age-encrypted file on encrypted disk) — **not** next to the Kea hosts if you can avoid it.
- Only the **CA cert** (`Example_CA.pem`) and each host’s **own** key+cert go onto `dhcp1` / `dhcp2`.
- Issue / renew leaves on the CA host, then copy artifacts out.

### 2. Mount certs at runtime — never bake into images

These Dockerfiles intentionally omit TLS material. Prefer separate trees for
the HTTPS **control** socket and **HA** peers (they can still share one CA):

```text
/etc/kea/certs/control/ca.pem
/etc/kea/certs/control/cert.pem
/etc/kea/certs/control/key.pem
/etc/kea/certs/ha/ca.pem
/etc/kea/certs/ha/cert.pem
/etc/kea/certs/ha/key.pem
```

Wire those paths in `kea-*.json` (`trust-anchor`, `cert-file`, `key-file` on
the control socket and in the HA hook). Compose/Quadlet mount host dirs onto
`/etc/kea/certs/control` and `/etc/kea/certs/ha`.

### 3. Renewal (825-day leaves)

`renew_client_certs_every_825_days.txt` is a reminder: calendar renewals against your leaf `notAfter` dates.

Practical approach:

1. Re-run `./scripts/pki-issue-host.sh <host>` (or re-sign with a new CSR if you rotate keys).
2. Install new leaf on the host; keep the same CA trust anchor unless rotating the CA.
3. Reload/restart Kea; verify HA peers still authenticate.
4. Optionally revoke the old serial in `index.txt` and publish a CRL if you start relying on revocation (Kea typically uses trust-anchor + leaf validity — CRL is optional).

Automate reminders (systemd timer, calendar event). Full ACME is usually overkill for a two-node OOB HA pair unless you already run an internal ACME CA (e.g. step-ca).

### 4. If you want secrets “in repo” anyway

Use **SOPS + age** (or git-crypt) so only ciphertext is committed:

```bash
# example shape — not committed as plaintext
pki-secrets/
  Example_CA.key.age
  dhcp1/dhcp1.key.age
```

Decrypt only on the CA/admin machine or via CI with a protected environment secret. Prefer Vault/Podman secrets over encrypted-git for the CA key.

### 5. What not to do

- Do **not** `COPY` keys into Dockerfiles or bake them into images.
- Do **not** commit `Example_CA.key`.
- Do **not** share one leaf key across dhcp1 and dhcp2 — each peer needs its own identity for mTLS.
- Do **not** use the public web PKI for internal HA; keep this private CA.

## Scripts

```bash
./scripts/pki-init-ca.sh           # create CA (refuses overwrite)
./scripts/pki-issue-host.sh dhcp1  # key + CSR + sign → pki/dhcp1/
./scripts/pki-issue-host.sh dhcp2
```

Host SANs/IPs live in `pki/<host>/openssl.cnf` — edit those when addressing changes.

## Example hosts (from configs)

| Host | CN / DNS | IP |
|---|---|---|
| dhcp1 | `dhcp1.example.com` | `192.0.2.10` |
| dhcp2 | `dhcp2.example.com` | `192.0.2.11` |
