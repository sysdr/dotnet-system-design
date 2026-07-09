#!/usr/bin/env bash
# cleanup.sh — Stop Aspire/dotnet services, tear down containers, prune unused Docker resources.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Stopping Aspire AppHost and freeing ports (Windows)..."
if command -v pwsh >/dev/null 2>&1 && [[ -f stop.ps1 ]]; then
  pwsh -NoProfile -File stop.ps1 || true
elif command -v powershell >/dev/null 2>&1 && [[ -f stop.ps1 ]]; then
  powershell -NoProfile -File stop.ps1 || true
fi

echo "==> Stopping docker compose stack..."
if command -v docker >/dev/null 2>&1; then
  docker compose down --remove-orphans 2>/dev/null || true

  echo "==> Removing project containers..."
  for name in otel-collector user-service order-service; do
    ids="$(docker ps -aq --filter "name=^${name}$" 2>/dev/null || true)"
    if [[ -n "${ids}" ]]; then
      docker rm -f ${ids} 2>/dev/null || true
    fi
  done

  echo "==> Pruning stopped containers..."
  docker container prune -f

  echo "==> Pruning dangling images..."
  docker image prune -f

  echo "==> Pruning unused networks..."
  docker network prune -f

  echo "==> Pruning unused Docker resources (volumes excluded)..."
  docker system prune -f

  echo "==> Remaining containers:"
  docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" || true
else
  echo "Docker not found — skipping container cleanup."
fi

echo "==> Cleanup complete."
