# Mirai Cluster Communication Test

This directory contains a self-contained test environment for verifying inter-node communication between Mirai BEAM nodes.

## What It Tests

1. **Node Discovery** — `Node.connect/1` between two nodes in the same Docker network
2. **Node Listing** — `Node.list/0` returns the connected peer
3. **Cross-Node RPC** — `:rpc.call/4` to a remote node's `Node.self/0`
4. **Cross-Node GenServer** — `:rpc.call/4` to a remote node's `Mirai.Dashboard.NodeRegistry`

## Quick Start

```bash
# Run all tests (start, test, cleanup)
./run_test.sh

# Or manually start the cluster
docker compose up -d

# Then manually connect from alpha's console
docker exec -it mirai_alpha iex --name shell@alpha --cookie mirai_cluster_test --remsh mirai@alpha
# In the IEx shell:
#   Node.connect(:"mirai@beta")
#   Node.list()
#   :rpc.call(:"mirai@beta", Node, :self, [])

# Cleanup
docker compose down
```

## Architecture

```
┌─────────────────────┐     ┌─────────────────────┐
│   mirai_alpha        │     │   mirai_beta         │
│   mirai@alpha        │◄───►│   mirai@beta         │
│   Port: 4001         │     │   Port: 4002         │
│   config_alpha.yaml  │     │   config_beta.yaml   │
└─────────────────────┘     └─────────────────────┘
         │                           │
         └───── Docker Network ──────┘
              (default bridge)
         Cookie: mirai_cluster_test
```
