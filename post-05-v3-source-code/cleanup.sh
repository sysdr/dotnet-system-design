#!/usr/bin/env bash
# cleanup.sh — Stop Hyperscale Log Monitoring containers and prune unused Docker resources.
# Usage: bash cleanup.sh
# Windows: Git Bash or WSL. PowerShell users can also run: docker compose down; bash cleanup.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
PROJECT_NAME="post-05-v3-source-code"

echo "========================================================"
echo " Hyperscale Log Monitoring — Docker cleanup"
echo "========================================================"

if command -v docker >/dev/null 2>&1; then
    echo ""
    echo "-- Stopping Docker Compose stack -----------------------"
    if [ -f "${COMPOSE_FILE}" ]; then
        docker compose -f "${COMPOSE_FILE}" down --remove-orphans -v 2>/dev/null || true
    fi

    echo "-- Stopping related containers -------------------------"
    for name in otel-collector user-service order-service; do
        ids="$(docker ps -aq --filter "name=${name}" 2>/dev/null || true)"
        if [ -n "${ids}" ]; then
            echo "  Removing containers matching: ${name}"
            echo "${ids}" | xargs docker rm -f 2>/dev/null || true
        fi
    done

    echo "-- Removing project images -----------------------------"
    docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
        | grep "^${PROJECT_NAME}-" \
        | while read -r image; do
            [ -n "${image}" ] && docker rmi -f "${image}" 2>/dev/null || true
          done

    echo "-- Pruning unused Docker resources ---------------------"
    docker container prune -f
    docker image prune -f
    docker network prune -f
    docker volume prune -f
else
    echo "Docker not found — skipping container cleanup."
fi

echo ""
echo "Cleanup complete."
echo "========================================================"
