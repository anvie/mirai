#!/usr/bin/env bash
set -e

# ─── Mirai Inter-Node Communication Test ───
# This script starts two Mirai nodes and verifies they can communicate.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

pass() { echo -e "  ${GREEN}✅ PASS${NC}: $1"; }
fail() { echo -e "  ${RED}❌ FAIL${NC}: $1"; FAILURES=$((FAILURES + 1)); }
info() { echo -e "  ${YELLOW}⏳${NC} $1"; }

FAILURES=0

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   🧪 Mirai Cluster Communication Test    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: Start cluster ──
info "Starting test cluster (alpha + beta)..."
docker compose up -d 2>&1 | tail -2

# ── Step 2: Wait for nodes to boot ──
info "Waiting for nodes to compile and start (this may take a minute)..."
sleep 5

# Wait for alpha to be ready
for i in $(seq 1 60); do
  if docker exec mirai_alpha sh -c "elixir --name probe@alpha --cookie mirai_cluster_test -e 'IO.puts(:ok)'" > /dev/null 2>&1; then
    break
  fi
  sleep 2
done

# Wait for beta to be ready
for i in $(seq 1 60); do
  if docker exec mirai_beta sh -c "elixir --name probe2@beta --cookie mirai_cluster_test -e 'IO.puts(:ok)'" > /dev/null 2>&1; then
    break
  fi
  sleep 2
done

info "Nodes should be ready. Running tests..."
echo ""

# ── Test 1: Connect alpha → beta ──
echo -e "${BOLD}Test 1: Node.connect(mirai@beta) from alpha${NC}"
CONNECT_RESULT=$(docker exec mirai_alpha sh -c \
  "elixir --name tester1@alpha --cookie mirai_cluster_test -e '
    result = Node.connect(:\"mirai@beta\")
    IO.puts(result)
  '" 2>/dev/null | tail -1)

if [ "$CONNECT_RESULT" = "true" ]; then
  pass "Node alpha connected to beta"
else
  fail "Node alpha could not connect to beta (got: $CONNECT_RESULT)"
fi

# ── Test 2: Verify Node.list on alpha sees beta ──
echo -e "${BOLD}Test 2: Node.list() from alpha${NC}"
NODE_LIST=$(docker exec mirai_alpha sh -c \
  "elixir --name tester2@alpha --cookie mirai_cluster_test -e '
    Node.connect(:\"mirai@beta\")
    Process.sleep(500)
    IO.puts(inspect(Node.list()))
  '" 2>/dev/null | tail -1)

if echo "$NODE_LIST" | grep -q "mirai@beta"; then
  pass "Node.list() contains :\"mirai@beta\""
else
  fail "Node.list() does not contain beta (got: $NODE_LIST)"
fi

# ── Test 3: RPC call to beta → Node.self() ──
echo -e "${BOLD}Test 3: :rpc.call(mirai@beta, Node, :self, [])${NC}"
RPC_RESULT=$(docker exec mirai_alpha sh -c \
  "elixir --name tester3@alpha --cookie mirai_cluster_test -e '
    Node.connect(:\"mirai@beta\")
    Process.sleep(500)
    result = :rpc.call(:\"mirai@beta\", Node, :self, [])
    IO.puts(result)
  '" 2>/dev/null | tail -1)

if [ "$RPC_RESULT" = "mirai@beta" ]; then
  pass ":rpc.call returned :\"mirai@beta\""
else
  fail ":rpc.call returned unexpected result (got: $RPC_RESULT)"
fi

# ── Test 4: RPC call to beta → NodeRegistry.list_nodes() ──
echo -e "${BOLD}Test 4: :rpc.call(mirai@beta, Mirai.Dashboard.NodeRegistry, :list_nodes, [])${NC}"
REGISTRY_RESULT=$(docker exec mirai_alpha sh -c \
  "elixir --name tester4@alpha --cookie mirai_cluster_test -e '
    Node.connect(:\"mirai@beta\")
    Process.sleep(500)
    result = :rpc.call(:\"mirai@beta\", Mirai.Dashboard.NodeRegistry, :list_nodes, [])
    IO.puts(inspect(result))
  '" 2>/dev/null | tail -1)

if echo "$REGISTRY_RESULT" | grep -q "local_mirai_1"; then
  pass "Beta's NodeRegistry returned node data"
else
  fail "Beta's NodeRegistry returned unexpected data (got: $REGISTRY_RESULT)"
fi

# ── Summary ──
echo ""
echo -e "${BOLD}════════════════════════════════════════════${NC}"
if [ $FAILURES -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}All tests passed! 🎉${NC}"
else
  echo -e "  ${RED}${BOLD}$FAILURES test(s) failed.${NC}"
fi
echo -e "${BOLD}════════════════════════════════════════════${NC}"
echo ""

# ── Cleanup ──
info "Stopping test cluster..."
docker compose down 2>&1 | tail -1
echo -e "  ${GREEN}Done.${NC}"
echo ""

exit $FAILURES
