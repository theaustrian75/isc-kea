# Local PKI (Example Internal CA)

Configs in this directory are safe to track in git. **Private keys and issued PEMs are not.**

See [../docs/PKI.md](../docs/PKI.md) for handling recommendations.

```bash
../scripts/pki-init-ca.sh
../scripts/pki-issue-host.sh dhcp1
../scripts/pki-issue-host.sh dhcp2
```
