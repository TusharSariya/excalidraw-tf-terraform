#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONTAINER_NAME="${LOCALSTACK_CONTAINER_NAME:-staging-localstack-localstack}"
IMAGE="${LOCALSTACK_IMAGE:-localstack/localstack:2026.05.0}"
VOLUME="${LOCALSTACK_VOLUME:-localstack_staging-localstack-data}"
EDGE_PORT="${LOCALSTACK_EDGE_PORT:-4566}"

if docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  echo "LocalStack already running: ${CONTAINER_NAME}"
  exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  docker start "$CONTAINER_NAME" >/dev/null
else
  docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${EDGE_PORT}:4566" \
    -e DEBUG="${DEBUG:-0}" \
    -e PERSISTENCE="${PERSISTENCE:-1}" \
    -e LOCALSTACK_AUTH_TOKEN="${LOCALSTACK_AUTH_TOKEN:-}" \
    -v "${VOLUME}:/var/lib/localstack" \
    -v "/var/run/docker.sock:/var/run/docker.sock" \
    "$IMAGE" >/dev/null
fi

echo "Waiting for LocalStack at http://localhost:${EDGE_PORT}/_localstack/health"
for _ in {1..60}; do
  if curl -fsS "http://localhost:${EDGE_PORT}/_localstack/health" >/dev/null 2>&1; then
    echo "LocalStack is ready: ${CONTAINER_NAME}"
    exit 0
  fi
  sleep 2
done

echo "Timed out waiting for LocalStack." >&2
docker logs "$CONTAINER_NAME" --tail 80 >&2 || true
exit 1
