# Example TLS layout expected by the entrypoint when configs reference /etc/kea/certs/.
# Copy real PEMs from pki/ (never commit private keys):
#
#   ca.pem   <- pki/Thor_CA.pem
#   cert.pem <- pki/<host>/<host>.pem
#   key.pem  <- pki/<host>/<host>.key
#
# Mount the parent config directory read-only at /etc/kea.
