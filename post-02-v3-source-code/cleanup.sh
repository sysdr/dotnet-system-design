#!/usr/bin/env bash
# cleanup.sh — Stop project services and remove unused Docker resources
# Hyperscale Log Monitoring Masterclass · Post 2
#
# Usage (from project root):
#   bash cleanup.sh
#   bash cleanup.sh --prune-images   # also remove dangling/unused images

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PRUNE_IMAGES=false
if [[ "${1:-}" == "--prune-images" ]]; then
  PRUNE_IMAGES=true
fi

echo "========================================================"
echo " Post 2 cleanup — stopping services and Docker resources"
echo "========================================================"

# ── Stop .NET Aspire / AppHost processes (best-effort) ─────────────────────
if command -v pkill >/dev/null 2>&1; then
  for proc in AppHost Aspire.Dashboard UserService OrderService dcpctrl; do
    pkill -f "$proc" 2>/dev/null || true
  done
fi

# ── Docker Compose stack ───────────────────────────────────────────────────
if command -v docker >/dev/null 2>&1; then
  if [[ -f docker-compose.yml ]]; then
    echo "→ docker compose down --remove-orphans"
    docker compose down --remove-orphans 2>/dev/null \
      || docker-compose down --remove-orphans 2>/dev/null \
      || true
  fi

  echo "→ Removing project containers (if any remain)"
  for name in otel-collector user-service order-service; do
    docker rm -f "$name" 2>/dev/null || true
  done

  # Aspire names containers otel-collector-<suffix>
  while IFS= read -r cid; do
    [[ -n "$cid" ]] && docker rm -f "$cid" 2>/dev/null || true
  done < <(docker ps -aq --filter "name=otel-collector" 2>/dev/null || true)

  echo "→ Removing stopped containers"
  docker container prune -f 2>/dev/null || true

  echo "→ Removing unused networks"
  docker network prune -f 2>/dev/null || true

  if [[ "$PRUNE_IMAGES" == true ]]; then
    echo "→ Removing dangling images"
    docker image prune -f 2>/dev/null || true
    echo "→ Removing unused images (not referenced by any container)"
    docker image prune -a -f 2>/dev/null || true
  else
    echo "→ Removing dangling images only (use --prune-images for full image prune)"
    docker image prune -f 2>/dev/null || true
  fi

  echo "→ Removing unused build cache (optional reclaim)"
  docker builder prune -f 2>/dev/null || true
else
  echo "Docker not found — skipped Docker cleanup."
fi

# ── Local build artifacts ────────────────────────────────────────────────
echo "→ Removing bin/ and obj/ folders"
find "$SCRIPT_DIR" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} + 2>/dev/null || true

echo ""
echo "Cleanup complete."
echo "To start fresh:"
echo "  dotnet run --project src/AppHost --launch-profile https"
echo "  — or —"
echo "  docker compose up --build -d"
