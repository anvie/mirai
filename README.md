# Mirai

Mirai (未来) is a distributed AI agent platform built on Elixir/OTP. Powered by the BEAM virtual machine's actor model, Mirai agents can communicate seamlessly across multiple nodes - enabling a truly distributed agentic AI mesh where agents collaborate, delegate tasks, and share context regardless of which machine they run on.

## Why Elixir?

Mirai leverages Elixir's unique strengths that no other language can match for AI agent orchestration:

- **Distributed by Nature** - Agents are lightweight processes (actors) that communicate via message passing. Spin up agents on separate nodes and they find each other automatically via `libcluster`. No REST APIs, no message queues - just native BEAM distribution.
- **Inter-Agent Communication** - Agent A on Node 1 can send a task to Agent B on Node 2 as easily as calling a local function. The BEAM handles serialization, routing, and delivery transparently.
- **Fault Tolerant** - Each agent runs in its own isolated process with supervisor trees. If one agent crashes, others continue unaffected. Supervisors automatically restart failed agents - self-healing by design.
- **Massively Concurrent** - The BEAM can run millions of lightweight processes on a single machine. Each user session, agent, and tool execution runs in its own process with zero thread management.
- **Horizontal Scaling** - Need more capacity? Add another node. Agents automatically discover peers and distribute workload across the cluster. No reconfiguration needed.

## Quick Start

### 1. Run the Setup Wizard
```bash
docker run -it --rm -v $(pwd):/app -w /app elixir:1.16 \
  sh -c "mix local.hex --force && mix local.rebar --force && mix deps.get && mix mirai.setup"
```

### 2. Start the Engine
```bash
# Development (hot reload enabled)
docker-compose up

# Production
MIX_ENV=prod docker-compose up
```

## Features

### AI Agent
- **Tool Calling Engine** - `execute_command`, `read_file`, `write_file`, `send_file`
- **Smart Loop** - depth-limited tool recursion (max 3 iterations) with auto-fallback to text
- **Channel-Agnostic** - all outbound messaging (text, typing indicators, file uploads) routed through `Mirai.Channels.Outbound`
- **System Prompt** - configurable per-agent instructions with tool usage guidance

### Channels
- **Telegram** - full integration with typing indicators and file sending via Bot API
- **WhatsApp** - Business API support for text and document messages (via Graph API)

### Slash Commands
| Command | Description |
|---------|-------------|
| `/clear` | Clear conversation memory |
| `/model` | Show current AI model |
| `/model <name>` | Switch model at runtime |
| `/reasoning` | Toggle verbose reasoning output |
| `/status` | Show system status & uptime |
| `/help` | List all commands |

### Infrastructure
- **Hot Code Reloading** - `exsync` auto-recompiles on file changes in dev mode
- **Persistent Sessions** - JSONL-backed conversation history per user
- **Per-User Preferences** - ETS-backed toggles (e.g. reasoning mode)
- **LiveView Dashboard** - cluster analytics at `http://localhost:4000`
- **Onboarding Wizard** - `mix mirai.setup` for guided configuration
- **OpenRouter / Anthropic** - multi-provider LLM support

## Architecture

```
                        ┌─────────────────────────────┐
                        │       BEAM Cluster           │
                        │   (libcluster auto-discovery)│
                        └──────────┬──────────────────┘
               ┌───────────────────┼───────────────────┐
               ▼                   ▼                   ▼
        ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
        │   Node 1    │    │   Node 2    │    │   Node 3    │
        │             │    │             │    │             │
        │ Agent "main"│◄──►│ Agent "code"│◄──►│ Agent "ops" │
        │ Session A   │    │ Session B   │    │ Session C   │
        │ Telegram Ch │    │ WhatsApp Ch │    │ Dashboard   │
        └─────────────┘    └─────────────┘    └─────────────┘
              │                   │
    message passing        message passing
    (native BEAM)          (native BEAM)
              │                   │
         ┌────┴────┐         ┌───┴────┐
         │ User 1  │         │ User 2 │
         │Telegram │         │WhatsApp│
         └─────────┘         └────────┘

Per-Node Flow:
  User Message → Channel Worker → Gateway → Session → Agent Loop
                                                        → LLM API
                                                        → Tools
                                                      → Outbound (reply)
```

Agents communicate across nodes transparently - `GenServer.call({:agent, :"node2@host"}, msg)` works exactly like a local call. The BEAM handles all networking, serialization, and failure detection.

## Running Tests
```bash
docker run -it --rm -v $(pwd):/app -w /app elixir:1.16 \
  sh -c "mix local.hex --force && mix local.rebar --force && mix deps.get && mix test"
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `MIX_ENV` | `dev` (default) or `prod` |
| `PORT` | Web dashboard port (default: 4000) |
| `TELEGRAM_BOT_TOKEN` | Telegram Bot API token |
| `OPENROUTER_API_KEY` | OpenRouter API key |
| `OPENROUTER_MODEL` | Model name (e.g. `google/gemini-3.1-flash-lite-preview`) |
| `WHATSAPP_API_TOKEN` | WhatsApp Business API token |
| `WHATSAPP_PHONE_NUMBER_ID` | WhatsApp phone number ID |
