#!/usr/bin/env bash
# cleanup.sh — Stop Aspire/Docker resources and remove local build artifacts.
# Usage: bash cleanup.sh
# Windows: Git Bash or WSL. PowerShell users can run: bash cleanup.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "== Stopping .NET / Aspire processes =="

stop_windows_process() {
  local name="$1"
  if command -v taskkill >/dev/null 2>&1; then
    taskkill //F //IM "${name}.exe" >/dev/null 2>&1 || true
  elif command -v pkill >/dev/null 2>&1; then
    pkill -f "$name" >/dev/null 2>&1 || true
  fi
}

for proc in AppHost UserService OrderService Aspire.Dashboard dcpctrl dcpproc; do
  stop_windows_process "$proc"
done

echo "== Stopping Docker Compose stack =="
if command -v docker >/dev/null 2>&1; then
  docker compose down --remove-orphans >/dev/null 2>&1 || true

  echo "== Removing project containers =="
  for pattern in otel-collector user-service order-service; do
    ids="$(docker ps -aq --filter "name=${pattern}" 2>/dev/null || true)"
    if [ -n "$ids" ]; then
      # shellcheck disable=SC2086
      docker rm -f $ids >/dev/null 2>&1 || true
    fi
  done

  echo "== Pruning unused Docker resources =="
  docker container prune -f >/dev/null 2>&1 || true
  docker network prune -f >/dev/null 2>&1 || true
  docker image prune -f >/dev/null 2>&1 || true
else
  echo "Docker not found — skipping container cleanup."
fi

echo "== Removing .NET build artifacts =="
if command -v dotnet >/dev/null 2>&1; then
  dotnet clean "$ROOT/src/AppHost/AppHost.csproj" -v q >/dev/null 2>&1 || true
fi

find "$ROOT" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} + 2>/dev/null || true

echo "== Cleanup complete =="
echo "Safe to git push. Run: dotnet run --project src/AppHost"
