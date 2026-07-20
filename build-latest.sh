#!/usr/bin/env bash
# Multi-arch build + push to the private registry.
# Requires: podman, logged-in credentials via Podman secret dn-registry-password
set -euo pipefail

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
