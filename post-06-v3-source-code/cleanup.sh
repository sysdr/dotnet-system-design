#!/usr/bin/env bash
# cleanup.sh — stop lesson containers and remove unused Docker resources
# Usage:
#   bash ./cleanup.sh
#   # or from Git Bash:
#   ./cleanup.sh

set -euo pipefail

echo ""
echo "=== Lesson Docker cleanup ==="

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. Install/start Docker Desktop, then retry."
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo ""
echo "1) Stopping docker compose stack (if present)..."
if [[ -f docker-compose.yml ]]; then
  docker compose down --remove-orphans 2>/dev/null || true
else
  echo "   no docker-compose.yml — skipped"
fi

echo ""
echo "2) Force-removing known lesson containers..."
for name in otel-collector user-service order-service; do
  if docker ps -aq --filter "name=^${name}$" | grep -q .; then
    echo "   docker rm -f $name"
    docker rm -f "$name" >/dev/null 2>&1 || true
  else
    echo "   $name — not found"
  fi
done

# Aspire / compose often create name-prefixed collectors
otel_ids="$(docker ps -aq --filter "name=otel-collector" 2>/dev/null || true)"
if [[ -n "${otel_ids}" ]]; then
  echo "   removing remaining otel-collector* containers..."
  # shellcheck disable=SC2086
  docker rm -f ${otel_ids} >/dev/null 2>&1 || true
fi

echo ""
echo "3) Removing stopped containers..."
docker container prune -f

echo ""
echo "4) Removing unused networks..."
docker network prune -f

echo ""
echo "5) Removing unused (dangling) volumes..."
docker volume prune -f

echo ""
echo "6) Removing unused images..."
docker image prune -af

echo ""
echo "7) Final unused-resource sweep..."
docker system prune -af

echo ""
echo "=== Cleanup complete ==="
echo "Remaining containers:"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" || true
echo ""
echo "Remaining images:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" || true
echo ""
