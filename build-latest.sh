#!/usr/bin/env bash
# Multi-arch build + push to the private dragonsnest registry.
# Opt-in only — CI publishes to GHCR by default.
#
#   PUSH_PRIVATE_REGISTRY=1 ./build-latest.sh
#
# Requires: podman, Podman secret dn-registry-password
set -euo pipefail

if [[ "${PUSH_PRIVATE_REGISTRY:-}" != "1" ]]; then
  echo "Refusing to push to the private registry." >&2
  echo "CI publishes multi-arch images to GHCR on main/tag pushes." >&2
  echo "Set PUSH_PRIVATE_REGISTRY=1 to build and push to registry.klausk.xyz." >&2
  exit 1
fi

REGISTRY="${REGISTRY:-registry.klausk.xyz:8443}"
REPOSITORY="${REPOSITORY:-repositories/dragonsnest}"
TAG="${TAG:-latest}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "(1) Login as dn-registry"
podman login -u dn-registry --secret dn-registry-password "${REGISTRY}/${REPOSITORY}"

echo "(2) Building and pushing manifests"
for DOCKERFILE in "${ROOT}"/Dockerfile.*; do
  IMAGE="${DOCKERFILE##*.}"
  REF="${REGISTRY}/${REPOSITORY}/${IMAGE}:${TAG}"

  echo "  --> ${REF}"
  podman manifest rm "${REF}" 2>/dev/null || true
  podman build \
    --format docker \
    --platform linux/amd64,linux/arm64 \
    --manifest "${REF}" \
    --file "${DOCKERFILE}" \
    "${ROOT}"
  podman manifest push --all "${REF}"
done

echo "(3) Logout"
podman logout "${REGISTRY}/${REPOSITORY}"
echo "Done."
