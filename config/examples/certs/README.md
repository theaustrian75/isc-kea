# TLS layout for the `/etc/kea/certs` volume mount.
#
# Compose defaults:
#   ./certs/kea-dhcp4      -> /etc/kea/certs  (kea-dhcp4)
#   ./certs/kea-dhcp-ddns  -> /etc/kea/certs  (kea-dhcp-ddns)
#
# Required filenames (see entrypoint + config/examples/kea-dhcp4-ha.json):
#
#   ca.pem   <- pki/Thor_CA.pem
#   cert.pem <- pki/<host>/<host>.pem
#   key.pem  <- pki/<host>/<host>.key
#
# Keep JSON under *_CONFIG_DIR and PEMs under *_CERT_DIR so keys stay out of
# the config tree. Never commit private keys.
