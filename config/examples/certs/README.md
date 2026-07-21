# TLS layout under `/etc/kea/certs/` — control API and HA use separate trees.
#
# Compose defaults (dhcp4):
#   ./certs/kea-dhcp4/control -> /etc/kea/certs/control
#   ./certs/kea-dhcp4/ha      -> /etc/kea/certs/ha
#
# Compose defaults (dhcp-ddns — control only):
#   ./certs/kea-dhcp-ddns/control -> /etc/kea/certs/control
#
# Each tree needs:
#
#   ca.pem   <- pki/Thor_CA.pem  (or a dedicated CA per role if you split CAs)
#   cert.pem <- pki/<host>/<host>.pem
#   key.pem  <- pki/<host>/<host>.key
#
# Example kea-dhcp4-ha.json paths:
#   control socket -> /etc/kea/certs/control/{ca,cert,key}.pem  (port 8001)
#   HA hook        -> /etc/kea/certs/ha/{ca,cert,key}.pem       (peer URLs :8000)
#
# You can point CONTROL and HA env dirs at the same host path if you want one
# shared leaf. Never commit private keys.
