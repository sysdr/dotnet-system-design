#!/usr/bin/env bash
# verify.sh — Post 1 acceptance criteria (bash/WSL2)
# Windows users: run verify.ps1 in PowerShell 7 instead (preferred).
# Usage: bash verify.sh [aspire|compose]  (default: compose)

set -euo pipefail
MODE="${1:-compose}"
PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

check() {
    local desc="$1" cmd="$2" expect="$3"
    printf "  Checking: %s ... " "$desc"
    actual=$(eval "$cmd" 2>&1) || true
    if echo "$actual" | grep -q "$expect"; then
        echo -e "${GREEN}PASS${NC}"; ((PASS++))
    else
        echo -e "${RED}FAIL${NC}"
        echo -e "    ${YELLOW}Expected:${NC} $expect  ${YELLOW}Got:${NC} $(echo "$actual" | head -1)"
        ((FAIL++))
    fi
}

check_gt() {
    local desc="$1" cmd="$2"
    printf "  Checking: %s ... " "$desc"
    actual=$(eval "$cmd" 2>&1 | tr -d '[:space:]') || actual=0
    if [ "${actual:-0}" -gt 0 ] 2>/dev/null; then
        echo -e "${GREEN}PASS${NC} (got $actual)"; ((PASS++))
    else
        echo -e "${RED}FAIL${NC} (expected > 0, got $actual)"; ((FAIL++))
    fi
}

echo ""
echo "========================================================"
echo " Hyperscale Log Monitoring — Post 1 Verification (bash)"
echo " Mode: $MODE · Use verify.ps1 on Windows"
echo "========================================================"
echo ""

if [ "$MODE" = "compose" ]; then
    check "user-service healthy" \
        "docker inspect --format='{{.State.Health.Status}}' user-service" "healthy"
    check "order-service healthy" \
        "docker inspect --format='{{.State.Health.Status}}' order-service" "healthy"
    check "user-service /health → 200" \
        "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health" "200"
fi

check "otel-collector healthy" \
    "docker inspect --format='{{.State.Health.Status}}' otel-collector" "healthy"

[ "$MODE" = "compose" ] && curl -s http://localhost:8080/users/ping > /dev/null || true
sleep 6

check_gt "OTel Collector received LogRecord" \
    "docker logs otel-collector 2>&1 | grep -c 'LogRecord'"

check "LogRecord has service.name=user-service" \
    "docker logs otel-collector 2>&1 | grep -c 'user-service'" "[1-9]"

check "zPages reachable at localhost:55679" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:55679/debug/pipelinez" "200"

echo ""
echo "========================================================"
if [ "$FAIL" -eq 0 ]; then
    echo -e " ${GREEN}All $((PASS)) checks passed. Post 1 complete.${NC}"
    echo ""
    echo " Next: run the Manual Exploration steps in README.md"
else
    echo -e " ${RED}$FAIL of $((PASS+FAIL)) checks failed.${NC}"
    echo " See docs/troubleshooting.md"
    exit 1
fi
echo "========================================================"
echo ""
