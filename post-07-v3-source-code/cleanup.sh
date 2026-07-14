#!/usr/bin/env bash
# cleanup.sh — Stop Post 7 containers and reclaim unused Docker resources.
# Usage: bash cleanup.sh
# Windows (Git Bash / WSL): bash ./cleanup.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo ""
echo "========================================================"
echo " Post 7 Docker cleanup"
echo "========================================================"
echo ""

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found on PATH."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker engine is not running."
  echo "Start Docker Desktop, then re-run: bash ./cleanup.sh"
  exit 1
fi

echo "-- Compose / named collectors ------------------------"
if [[ -f docker-compose.yml ]]; then
  docker compose down --remove-orphans 2>/dev/null || true
fi

# Aspire / manual otel collector containers
mapfile -t OTEL_IDS < <(docker ps -aq --filter "name=otel" 2>/dev/null || true)
if ((${#OTEL_IDS[@]})); then
  echo "  Removing otel containers: ${OTEL_IDS[*]}"
  docker rm -f "${OTEL_IDS[@]}" >/dev/null 2>&1 || true
else
  echo "  No otel containers"
fi

# Any leftover aspire / dcp containers for this stack
mapfile -t ASPIRE_IDS < <(docker ps -aq --filter "name=aspire" --filter "name=post-07" 2>/dev/null || true)
if ((${#ASPIRE_IDS[@]})); then
  echo "  Removing aspire/post-07 containers: ${ASPIRE_IDS[*]}"
  docker rm -f "${ASPIRE_IDS[@]}" >/dev/null 2>&1 || true
fi

echo ""
echo "-- Stop all running containers -----------------------"
RUNNING="$(docker ps -q 2>/dev/null || true)"
if [[ -n "${RUNNING}" ]]; then
  docker stop ${RUNNING} >/dev/null
  echo "  Stopped running containers"
else
  echo "  None running"
fi

echo ""
echo "-- Remove stopped containers -------------------------"
docker container prune -f

echo ""
echo "-- Remove unused images ------------------------------"
docker image prune -af

echo ""
echo "-- Remove unused networks / volumes / build cache ----"
docker network prune -f
docker volume prune -f
docker builder prune -af 2>/dev/null || true
# Final sweep (dangling + unused images/containers/networks/volumes)
docker system prune -af --volumes >/dev/null

echo ""
echo "-- Disk summary --------------------------------------"
docker system df || true

echo ""
echo "========================================================"
echo " Cleanup complete."
echo "========================================================"
echo ""
