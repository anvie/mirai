#!/usr/bin/env bash
set -e

# ─── Mirai Inter-Node ExUnit Integration Test ───
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

info() { echo -e "  ${YELLOW}⏳${NC} $1"; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   🧪 Mirai Cluster Communication Test    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: Start cluster ──
info "Starting test cluster (alpha + beta)..."
docker compose up -d 2>&1 | tail -2

# ── Step 2: Wait for nodes to be ready ──
info "Waiting for nodes to compile and start (cached builds ~15s, fresh ~90s)..."

for i in $(seq 1 60); do
  a=$(docker exec mirai_alpha epmd -names 2>/dev/null | grep mirai || true)
  b=$(docker exec mirai_beta epmd -names 2>/dev/null | grep mirai || true)
  if [ -n "$a" ] && [ -n "$b" ]; then
    break
  fi
  if [ "$i" = "60" ]; then
    echo -e "  ${RED}Timeout waiting for nodes to start${NC}"
    docker compose logs --tail=10
    docker compose down
    exit 1
  fi
  sleep 3
done
info "Both nodes are up!"
echo ""

# ── Step 3: Run ExUnit integration test inside Alpha ──
info "Executing ExUnit integration test suite from inside mirai_alpha..."
echo -e "${BOLD}════════════════════════════════════════════${NC}"

# We run this using 'elixir' directly to execute the script in the context of the connected node.
set +e
docker exec mirai_alpha elixir --sname tester --cookie mirai_cluster_test test_cluster/integration_test.exs
EXIT_CODE=$?
set -e

echo -e "${BOLD}════════════════════════════════════════════${NC}"
if [ $EXIT_CODE -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}ExUnit Integration Tests Passed! 🎉${NC}"
else
  echo -e "  ${RED}${BOLD}ExUnit Integration Tests Failed. (Exit Code: $EXIT_CODE)${NC}"
  echo -e "  ${YELLOW}Fetching logs from beta...${NC}"
  docker compose logs beta | tail -n 50
fi
echo ""

# ── Cleanup ──
info "Stopping test cluster..."
docker compose down 2>&1 | tail -1
echo -e "  ${GREEN}Done.${NC}"
echo ""

exit $EXIT_CODE
