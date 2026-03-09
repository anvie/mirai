# Mirai (未来) - Distributed AI Agent Platform

**Project Name:** Mirai (未来 — "future" in Japanese)  
**Version:** 0.1.0 (Spec Draft)  
**Author:** Robin Syihab  
**Date:** 2026-03-09  
**Status:** Planning / Design Phase

---

## 1. Executive Summary

Mirai adalah distributed AI agent platform berbasis Elixir/OTP, terinspirasi dari OpenClaw dengan penambahan fitur:

- **Fault-tolerant messaging** — supervisor trees untuk self-healing
- **Distributed agents** — native node-to-node communication dengan async messaging
- **Massive concurrency** — jutaan lightweight processes
- **Hot code reload** — update tanpa downtime
- **Real-time streaming** — Phoenix Channels / LiveView
- **Inter-agent communication** — async message passing antar agents dengan context preservation
- **Modular memory system** — pluggable backends (QRAS, QMD, SQLite, etc.)
- **Conditional ACL** — context-aware access control per user/group

---

## 2. Architecture Overview

### 2.0 Key Differentiators from OpenClaw

| Feature | OpenClaw | Mirai |
|---------|----------|-------|
| Runtime | Node.js (single-threaded event loop) | BEAM VM (preemptive scheduling) |
| Concurrency | Async/await + workers | Millions of lightweight processes |
| Distribution | Manual via config | Native Erlang distribution |
| Inter-agent | Via sessions_send (sync-ish) | Native async message passing |
| Memory | File-based (JSONL) | Pluggable backends |
| ACL | Config-based allowlists | Conditional context + dynamic rules |
| Fault tolerance | Process manager restart | Supervisor trees, "let it crash" |

### 2.1 High-Level Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        Mirai Node                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │   Gateway   │  │   Agent     │  │   Session   │             │
│  │  Supervisor │  │  Supervisor │  │  Supervisor │             │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
│         │                │                │                     │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐             │
│  │  Channel    │  │   Agent     │  │   Session   │             │
│  │  Workers    │  │   Workers   │  │   Workers   │             │
│  │ (GenServer) │  │ (GenServer) │  │ (GenServer) │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│         │                │                │                     │
│         └────────────────┼────────────────┘                     │
│                          │                                      │
│                   ┌──────▼──────┐                               │
│                   │   Message   │                               │
│                   │    Router   │                               │
│                   │  (Registry) │                               │
│                   └─────────────┘                               │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │    Tool     │  │    Cron     │  │   Plugin    │             │
│  │  Registry   │  │  Scheduler  │  │   Manager   │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└─────────────────────────────────────────────────────────────────┘
                              │
                    Distributed Erlang
                              │
┌─────────────────────────────▼───────────────────────────────────┐
│                    Other Mirai Nodes                        │
│              (agents dapat berkomunikasi antar node)             │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 OTP Application Tree

```
mirai (Application)
├── Mirai.Supervisor (root)
│   ├── Mirai.Config.Server (GenServer) — config hot reload
│   ├── Mirai.Gateway.Supervisor
│   │   ├── Mirai.Gateway.Server (GenServer) — main gateway
│   │   ├── Mirai.Gateway.WebSocket (Cowboy/Bandit)
│   │   └── Mirai.Gateway.HTTP (Phoenix)
│   │
│   ├── Mirai.Channels.Supervisor (DynamicSupervisor)
│   │   ├── Mirai.Channels.WhatsApp.Worker
│   │   ├── Mirai.Channels.Telegram.Worker
│   │   ├── Mirai.Channels.Discord.Worker
│   │   ├── Mirai.Channels.Slack.Worker
│   │   └── ... (dynamic per-account workers)
│   │
│   ├── Mirai.Agents.Supervisor (DynamicSupervisor)
│   │   ├── Mirai.Agents.Worker (per agentId)
│   │   └── ... (dynamic agent workers)
│   │
│   ├── Mirai.Sessions.Supervisor (DynamicSupervisor)
│   │   ├── Mirai.Sessions.Worker (per sessionKey)
│   │   └── ... (dynamic session workers)
│   │
│   ├── Mirai.Tools.Registry (Registry + GenServers)
│   ├── Mirai.Cron.Scheduler (GenServer + Quantum)
│   ├── Mirai.Plugins.Manager (DynamicSupervisor)
│   └── Mirai.Metrics.Collector (Telemetry)
```

---

## 3. Core Components

### 3.1 Gateway Server

**Module:** `Mirai.Gateway.Server`  
**Behaviour:** `GenServer`

Responsibilities:
- Maintain provider connections
- Route inbound messages to agents
- Expose WebSocket API (typed protocol)
- Handle pairing/authentication
- Emit events (agent, chat, presence, health, heartbeat, cron)

```elixir
defmodule Mirai.Gateway.Server do
  use GenServer
  
  defstruct [
    :config,
    :channels,      # Map of channel_id => pid
    :agents,        # Map of agent_id => pid
    :sessions,      # Registry reference
    :pairing_store, # ETS table
    :health_state
  ]
  
  # Client API
  def start_link(opts)
  def send_message(gateway, message)
  def get_health(gateway)
  def route_inbound(gateway, envelope)
  
  # Callbacks
  def handle_call({:route, envelope}, _from, state)
  def handle_cast({:broadcast, event}, state)
  def handle_info({:channel_event, event}, state)
end
```

### 3.2 Channel Workers

**Module:** `Mirai.Channels.Worker`  
**Behaviour:** `GenServer`

Setiap channel (WhatsApp, Telegram, Discord, dll) adalah GenServer terpisah.

```elixir
defmodule Mirai.Channels.Worker do
  use GenServer
  
  @callback connect(config :: map()) :: {:ok, state} | {:error, reason}
  @callback disconnect(state) :: :ok
  @callback send_message(state, message) :: {:ok, message_id} | {:error, reason}
  @callback handle_inbound(state, raw_event) :: {:ok, envelope} | :ignore
  
  defstruct [
    :channel_type,   # :whatsapp | :telegram | :discord | ...
    :account_id,
    :connection,     # channel-specific connection state
    :gateway_pid,
    :config
  ]
end
```

**Channel Implementations:**

| Channel | Library/Approach |
|---------|-----------------|
| WhatsApp | Port ke Elixir dari Baileys, atau gunakan WebSocket bridge ke Node.js |
| Telegram | `telegex` atau `ex_gram` |
| Discord | `nostrum` |
| Slack | `slack_elixir` atau custom WebSocket |
| Signal | Bridge ke `signal-cli` via Port |
| iMessage | Bridge ke AppleScript/Shortcuts via Port |

### 3.3 Agent Workers

**Module:** `Mirai.Agents.Worker`  
**Behaviour:** `GenServer`

Setiap agent adalah isolated process dengan:
- Own workspace path
- Own session store
- Own auth profiles
- Own model config

```elixir
defmodule Mirai.Agents.Worker do
  use GenServer
  
  defstruct [
    :agent_id,
    :name,
    :workspace,       # Path ke workspace
    :agent_dir,       # Path ke agent state
    :model_config,    # Primary + fallbacks
    :tools_config,    # Allow/deny lists
    :sandbox_config,
    :session_registry # Registry untuk sessions agent ini
  ]
  
  # Run agent loop
  def run(agent, %Envelope{} = envelope, opts \\ [])
  
  # Get agent state
  def get_config(agent)
  def get_workspace(agent)
end
```

### 3.4 Session Workers

**Module:** `Mirai.Sessions.Worker`  
**Behaviour:** `GenServer`

Setiap session adalah stateful process:

```elixir
defmodule Mirai.Sessions.Worker do
  use GenServer
  
  defstruct [
    :session_key,
    :session_id,
    :agent_id,
    :messages,        # In-memory message history
    :transcript_path, # JSONL file path
    :origin,          # Routing metadata
    :updated_at,
    :token_usage,
    :run_queue        # Queue untuk serialized runs
  ]
  
  # Session operations
  def append_message(session, message)
  def get_history(session, opts \\ [])
  def compact(session, summary)
  def reset(session)
  
  # Run queue
  def enqueue_run(session, run_fn)
  def get_queue_depth(session)
end
```

### 3.5 Agent Loop (Core Runtime)

**Module:** `Mirai.AgentLoop`

The agentic loop — heart of the system:

```elixir
defmodule Mirai.AgentLoop do
  @moduledoc """
  The agent loop: intake → context → inference → tools → reply → persist
  """
  
  defstruct [
    :run_id,
    :session,
    :agent,
    :model,
    :messages,
    :tools,
    :stream_pid,    # Process receiving stream events
    :abort_ref      # Reference for cancellation
  ]
  
  # Main entry point
  def run(session, message, opts \\ []) do
    with {:ok, loop} <- init_loop(session, message, opts),
         {:ok, loop} <- build_context(loop),
         {:ok, loop} <- resolve_model(loop),
         {:ok, result} <- execute_loop(loop) do
      {:ok, result}
    end
  end
  
  # Execute with streaming
  defp execute_loop(loop) do
    loop
    |> call_model()
    |> handle_response()
    |> maybe_execute_tools()
    |> maybe_continue_loop()
    |> finalize()
  end
  
  # Tool execution
  defp execute_tool(loop, tool_call) do
    tool_module = Mirai.Tools.Registry.get(tool_call.name)
    tool_module.execute(tool_call.params, loop.context)
  end
end
```

### 3.6 Model Providers

**Module:** `Mirai.Models.Provider`  
**Behaviour definition:**

```elixir
defmodule Mirai.Models.Provider do
  @callback chat_completion(messages, opts) :: {:ok, response} | {:error, reason}
  @callback stream_completion(messages, opts, callback) :: {:ok, stream_ref} | {:error, reason}
  @callback cancel_stream(stream_ref) :: :ok
  @callback get_token_count(messages) :: {:ok, count} | {:error, reason}
end
```

**Implementations:**

| Provider | Module |
|----------|--------|
| Anthropic | `Mirai.Models.Anthropic` |
| OpenAI | `Mirai.Models.OpenAI` |
| OpenRouter | `Mirai.Models.OpenRouter` |
| Google | `Mirai.Models.Google` |
| Local (Ollama) | `Mirai.Models.Ollama` |

### 3.7 Tool Registry

**Module:** `Mirai.Tools.Registry`

Tools sebagai modules dengan behaviour:

```elixir
defmodule Mirai.Tools.Tool do
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback parameters() :: map()  # JSON Schema
  @callback execute(params :: map(), context :: map()) :: {:ok, result} | {:error, reason}
end

# Built-in tools
defmodule Mirai.Tools.Read do
  @behaviour Mirai.Tools.Tool
  
  def name, do: "read"
  def description, do: "Read file contents"
  def parameters, do: %{...}
  
  def execute(%{"path" => path}, context) do
    # Sandbox-aware file reading
    with {:ok, resolved} <- resolve_path(path, context.workspace),
         {:ok, content} <- File.read(resolved) do
      {:ok, content}
    end
  end
end
```

**Core Tools:**

| Tool | Description |
|------|-------------|
| `read` | Read file contents |
| `write` | Write file contents |
| `edit` | Edit file (search/replace) |
| `exec` | Execute shell commands (via Port) |
| `web_search` | Search the web |
| `web_fetch` | Fetch URL content |
| `browser` | Browser automation (via Playwright port or Wallaby) |
| `message` | Send messages via channels |
| `cron` | Manage scheduled jobs |
| `sessions_spawn` | Spawn sub-agents |
| `sessions_send` | Send to other sessions |
| `memory_search` | Search memory files |

---

## 4. Distributed Architecture

### 4.1 Node-to-Node Communication

Leverage Erlang distribution untuk multi-node deployment:

```elixir
# Node A: Agent "home"
Mirai.Agents.Worker.run(:home, envelope)

# Node B: Agent "work" dapat dipanggil dari Node A
:rpc.call(:"mirai@nodeB", Mirai.Agents.Worker, :run, [:work, envelope])

# Atau dengan transparent distribution via Registry
Mirai.Agents.call({:via, :global, {:agent, "work"}}, {:run, envelope})
```

### 4.2 Cluster Formation

```elixir
# config/runtime.exs
config :libcluster,
  topologies: [
    mirai: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45892,
        if_addr: "0.0.0.0",
        multicast_addr: "230.1.1.251"
      ]
    ]
  ]
```

### 4.3 Agent Distribution Strategies

| Strategy | Description |
|----------|-------------|
| **Local** | Semua agents di satu node |
| **Pinned** | Agent X selalu di Node Y |
| **Load-balanced** | Agents didistribusi berdasarkan load |
| **Geo** | Agents dekat dengan user (latency) |

---

## 5. Message Flow

### 5.1 Inbound Message Flow

```
[Channel Worker] 
    │ raw event
    ▼
[Envelope Parser] → normalize ke %Envelope{}
    │
    ▼
[Gateway Router] → lookup binding rules
    │
    ▼
[Agent Worker] → resolve session
    │
    ▼
[Session Worker] → enqueue run
    │
    ▼
[Agent Loop] → context → model → tools → reply
    │
    ▼
[Gateway Router] → route reply
    │
    ▼
[Channel Worker] → send to platform
```

### 5.2 Message Envelope

```elixir
defmodule Mirai.Envelope do
  @type t :: %__MODULE__{
    id: String.t(),
    channel: atom(),
    account_id: String.t(),
    chat_type: :direct | :group | :channel | :thread,
    chat_id: String.t(),
    sender: %{
      id: String.t(),
      name: String.t() | nil,
      username: String.t() | nil
    },
    message: %{
      id: String.t(),
      text: String.t() | nil,
      attachments: [attachment()],
      reply_to: String.t() | nil,
      timestamp: DateTime.t()
    },
    metadata: map()
  }
  
  defstruct [:id, :channel, :account_id, :chat_type, :chat_id, 
             :sender, :message, :metadata]
end
```

---

## 6. Configuration

### 6.1 Config Schema (JSON5 compatible)

```elixir
# config/mirai.exs atau ~/.mirai/config.exs

config :mirai,
  agents: %{
    defaults: %{
      workspace: "~/.mirai/workspace",
      model: %{
        primary: "anthropic/claude-sonnet-4-5",
        fallbacks: ["openai/gpt-5.2"]
      },
      timeout_seconds: 600
    },
    list: [
      %{id: "main", workspace: "~/.mirai/workspace"},
      %{id: "coding", workspace: "~/.mirai/workspace-coding"}
    ]
  },
  
  bindings: [
    %{agent_id: "main", match: %{channel: :whatsapp}},
    %{agent_id: "coding", match: %{channel: :telegram}}
  ],
  
  channels: %{
    whatsapp: %{
      enabled: true,
      dm_policy: :pairing,
      allow_from: ["+15551234567"]
    },
    telegram: %{
      enabled: true,
      bot_token: {:system, "TELEGRAM_BOT_TOKEN"}
    }
  },
  
  session: %{
    dm_scope: :per_channel_peer,
    reset: %{mode: :daily, at_hour: 4}
  },
  
  tools: %{
    allow: :all,
    deny: [],
    elevated: ["+15551234567"]  # Senders dengan elevated access
  }
```

### 6.2 Hot Config Reload

```elixir
defmodule Mirai.Config.Server do
  use GenServer
  
  def reload do
    GenServer.call(__MODULE__, :reload)
  end
  
  def handle_call(:reload, _from, state) do
    with {:ok, new_config} <- load_config(),
         :ok <- validate_config(new_config),
         :ok <- apply_config(new_config) do
      {:reply, :ok, %{state | config: new_config}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
end
```

---

## 7. Session Management

### 7.1 Session Keys

Format: `agent:<agentId>:<scope>:<identifier>`

| Scope | Pattern | Example |
|-------|---------|---------|
| Main DM | `agent:main:main` | Single conversation |
| Per-peer | `agent:main:dm:<peerId>` | Per sender |
| Per-channel-peer | `agent:main:telegram:dm:123456` | Per channel+sender |
| Group | `agent:main:whatsapp:group:120363...@g.us` | Per group |
| Subagent | `agent:main:subagent:<uuid>` | Background run |
| Cron | `cron:<jobId>` | Scheduled job |

### 7.2 Session Lifecycle

```
┌─────────────┐     inbound      ┌─────────────┐
│   Idle      │ ───────────────▶ │   Active    │
└─────────────┘                  └──────┬──────┘
      ▲                                 │
      │         reset/expire            │
      └─────────────────────────────────┘
                     │
                     ▼
              ┌─────────────┐
              │  Archived   │
              └─────────────┘
```

### 7.3 Session Persistence

```elixir
defmodule Mirai.Sessions.Store do
  @moduledoc """
  Session persistence dengan DETS atau SQLite
  """
  
  # Session metadata
  def save_session(session_key, metadata)
  def load_session(session_key)
  def list_sessions(filters \\ [])
  def delete_session(session_key)
  
  # Transcript (JSONL append-only log)
  def append_transcript(session_key, entry)
  def read_transcript(session_key, opts \\ [])
  def rotate_transcript(session_key)
end
```

---

## 8. Tools Implementation

### 8.1 Exec Tool (Shell Commands)

```elixir
defmodule Mirai.Tools.Exec do
  @behaviour Mirai.Tools.Tool
  
  def execute(%{"command" => cmd} = params, context) do
    opts = [
      cd: context.workspace,
      env: build_env(context),
      timeout: params["timeout"] || 30_000
    ]
    
    if params["pty"] do
      execute_pty(cmd, opts)
    else
      execute_simple(cmd, opts)
    end
  end
  
  defp execute_simple(cmd, opts) do
    case System.cmd("sh", ["-c", cmd], opts) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, %{output: output, exit_code: code}}
    end
  end
  
  defp execute_pty(cmd, opts) do
    # Use :pty_server or external PTY library
    ExPTY.spawn("sh", ["-c", cmd], opts)
  end
end
```

### 8.2 Browser Tool

Options:
1. **Wallaby** — Elixir browser automation (ChromeDriver/Selenium)
2. **Playwright Port** — Bridge ke Playwright via Port
3. **Hound** — Alternative browser automation

```elixir
defmodule Mirai.Tools.Browser do
  @behaviour Mirai.Tools.Tool
  
  # Using Wallaby
  def execute(%{"action" => "navigate", "url" => url}, _context) do
    session = Wallaby.start_session()
    session |> Wallaby.Browser.visit(url)
    {:ok, %{status: "navigated", url: url}}
  end
  
  def execute(%{"action" => "snapshot"}, _context) do
    # Get page accessibility tree
    {:ok, snapshot}
  end
end
```

### 8.3 Sub-agent Spawning

```elixir
defmodule Mirai.Tools.SessionsSpawn do
  @behaviour Mirai.Tools.Tool
  
  def execute(%{"task" => task} = params, context) do
    opts = [
      agent_id: params["agentId"] || context.agent_id,
      model: params["model"],
      thinking: params["thinking"],
      timeout: params["runTimeoutSeconds"],
      thread: params["thread"] || false,
      cleanup: params["cleanup"] || :keep
    ]
    
    # Spawn as supervised Task
    {:ok, pid} = Mirai.Subagents.Supervisor.start_child(task, opts)
    
    # Return immediately, let subagent announce when done
    {:ok, %{run_id: inspect(pid), status: "spawned"}}
  end
end
```

---

## 9. Cron & Scheduling

### 9.1 Quantum Integration

```elixir
defmodule Mirai.Cron.Scheduler do
  use Quantum, otp_app: :mirai
  
  # Dynamic job management
  def add_job(job_config) do
    job = build_job(job_config)
    new_job(job)
  end
  
  def remove_job(job_id) do
    delete_job(String.to_atom(job_id))
  end
  
  defp build_job(%{schedule: schedule, payload: payload} = config) do
    %Quantum.Job{
      name: String.to_atom(config.id),
      schedule: parse_schedule(schedule),
      task: fn -> execute_payload(payload) end
    }
  end
end
```

### 9.2 Job Types

| Type | Description |
|------|-------------|
| `system_event` | Inject text into session |
| `agent_turn` | Run agent with message (isolated) |
| `webhook` | POST to URL |
| `announce` | Send to chat channel |

---

## 10. Inter-Agent Communication (AgentMesh)

### 10.1 Overview

**AgentMesh** adalah sistem komunikasi antar-agent yang:
- Async by default — sender tidak block menunggu response
- Context-preserving — conversation context bisa di-pass antar agent
- Location-transparent — agent bisa di node yang sama atau berbeda
- Fault-tolerant — message queue persisted, retry on failure

### 10.2 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AgentMesh                             │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Agent A   │    │   Agent B   │    │   Agent C   │     │
│  │  (local)    │    │  (local)    │    │  (remote)   │     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘     │
│         │                  │                  │             │
│         └──────────────────┼──────────────────┘             │
│                            │                                │
│                   ┌────────▼────────┐                       │
│                   │   Message Bus   │                       │
│                   │   (Registry +   │                       │
│                   │    PubSub)      │                       │
│                   └────────┬────────┘                       │
│                            │                                │
│              ┌─────────────┼─────────────┐                  │
│              │             │             │                  │
│         ┌────▼────┐   ┌────▼────┐   ┌────▼────┐            │
│         │ Mailbox │   │ Mailbox │   │ Mailbox │            │
│         │    A    │   │    B    │   │    C    │            │
│         └─────────┘   └─────────┘   └─────────┘            │
└─────────────────────────────────────────────────────────────┘
                              │
                    Distributed Erlang
                              │
                    ┌─────────▼─────────┐
                    │   Other Nodes     │
                    │   (remote agents) │
                    └───────────────────┘
```

### 10.3 Message Types

```elixir
defmodule Mirai.AgentMesh.Message do
  @type t :: %__MODULE__{
    id: String.t(),
    from: agent_ref(),
    to: agent_ref(),
    type: message_type(),
    payload: map(),
    context: context() | nil,
    reply_to: String.t() | nil,
    timestamp: DateTime.t(),
    ttl: pos_integer() | nil,
    priority: :low | :normal | :high | :urgent
  }
  
  @type message_type :: 
    :request |      # Expects response
    :cast |         # Fire-and-forget
    :response |     # Reply to request
    :broadcast |    # To all subscribers
    :delegate       # Hand off task with context
  
  @type context :: %{
    conversation_id: String.t(),
    messages: [map()],
    metadata: map()
  }
  
  defstruct [:id, :from, :to, :type, :payload, :context, 
             :reply_to, :timestamp, :ttl, :priority]
end
```

### 10.4 Communication Patterns

#### 10.4.1 Fire-and-Forget (Cast)

```elixir
# Agent A sends task to Agent B, doesn't wait
Mirai.AgentMesh.cast(:agent_b, %{
  task: "process_document",
  document_id: "doc_123"
})
```

#### 10.4.2 Request-Response (Call with Timeout)

```elixir
# Agent A asks Agent B, waits for response
{:ok, result} = Mirai.AgentMesh.call(:agent_b, %{
  task: "analyze_sentiment",
  text: "This is great!"
}, timeout: 30_000)
```

#### 10.4.3 Delegate with Context

```elixir
# Agent A hands off conversation to Agent B
Mirai.AgentMesh.delegate(:agent_b, %{
  task: "continue_conversation",
  instruction: "User needs technical help"
}, context: %{
  conversation_id: "conv_123",
  messages: current_messages,
  user_id: "user_456"
})
```

#### 10.4.4 Broadcast to Topic

```elixir
# Publish to all agents subscribed to "alerts"
Mirai.AgentMesh.broadcast("alerts", %{
  type: "system_alert",
  message: "High load detected"
})

# Subscribe to topic
Mirai.AgentMesh.subscribe("alerts")
```

### 10.5 Context Preservation

When delegating or forwarding conversations:

```elixir
defmodule Mirai.AgentMesh.Context do
  @moduledoc """
  Preserves conversation context across agent handoffs.
  """
  
  defstruct [
    :conversation_id,
    :session_key,
    :messages,          # Recent message history
    :summary,           # Compacted summary of older messages
    :user_id,
    :channel,
    :metadata,
    :handoff_chain      # Track delegation path
  ]
  
  @doc """
  Create context snapshot for handoff.
  """
  def snapshot(session, opts \\ []) do
    %__MODULE__{
      conversation_id: session.id,
      session_key: session.key,
      messages: take_recent(session.messages, opts[:limit] || 20),
      summary: session.compaction_summary,
      user_id: session.user_id,
      channel: session.channel,
      handoff_chain: []
    }
  end
  
  @doc """
  Merge received context into local session.
  """
  def merge(local_session, received_context) do
    # Append handoff chain
    chain = received_context.handoff_chain ++ [received_context.from_agent]
    
    %{local_session |
      inherited_context: received_context,
      handoff_chain: chain
    }
  end
end
```

### 10.6 Async Response Handling

```elixir
defmodule Mirai.AgentMesh.ResponseHandler do
  use GenServer
  
  @doc """
  Register callback for async response.
  """
  def await_response(message_id, callback, opts \\ []) do
    timeout = opts[:timeout] || 60_000
    
    # Store callback
    :ets.insert(:pending_responses, {message_id, callback, timeout})
    
    # Schedule timeout
    Process.send_after(self(), {:response_timeout, message_id}, timeout)
  end
  
  @doc """
  Handle incoming response.
  """
  def handle_info({:agent_response, %{reply_to: message_id} = response}, state) do
    case :ets.lookup(:pending_responses, message_id) do
      [{^message_id, callback, _}] ->
        # Execute callback with response
        callback.(response)
        :ets.delete(:pending_responses, message_id)
      [] ->
        # Response arrived after timeout or no callback
        :ok
    end
    {:noreply, state}
  end
end
```

### 10.7 Tool: agent_send

Exposed to LLM as a tool:

```elixir
defmodule Mirai.Tools.AgentSend do
  @behaviour Mirai.Tools.Tool
  
  def name, do: "agent_send"
  
  def description do
    """
    Send a message to another agent. Supports:
    - cast: fire-and-forget
    - call: wait for response
    - delegate: hand off with full context
    """
  end
  
  def parameters do
    %{
      type: "object",
      properties: %{
        to: %{type: "string", description: "Target agent ID"},
        message: %{type: "string", description: "Message/task to send"},
        mode: %{type: "string", enum: ["cast", "call", "delegate"]},
        include_context: %{type: "boolean", default: false},
        wait_response: %{type: "boolean", default: false},
        timeout_seconds: %{type: "integer", default: 30}
      },
      required: ["to", "message"]
    }
  end
  
  def execute(params, context) do
    mode = params["mode"] || "cast"
    
    msg_context = if params["include_context"] do
      Mirai.AgentMesh.Context.snapshot(context.session)
    else
      nil
    end
    
    case mode do
      "cast" ->
        Mirai.AgentMesh.cast(params["to"], %{
          task: params["message"],
          context: msg_context
        })
        {:ok, %{status: "sent", mode: "async"}}
        
      "call" ->
        timeout = (params["timeout_seconds"] || 30) * 1000
        case Mirai.AgentMesh.call(params["to"], %{task: params["message"]}, timeout: timeout) do
          {:ok, response} -> {:ok, response}
          {:error, :timeout} -> {:error, "Agent did not respond in time"}
        end
        
      "delegate" ->
        Mirai.AgentMesh.delegate(params["to"], %{
          task: params["message"]
        }, context: msg_context)
        {:ok, %{status: "delegated", to: params["to"]}}
    end
  end
end
```

---

## 11. Modular Memory System

### 11.1 Overview

Memory system yang pluggable dengan berbagai backend:

| Backend | Use Case | Persistence | Search |
|---------|----------|-------------|--------|
| **ETS** | Fast cache, ephemeral | No | Key lookup |
| **DETS** | Simple persistence | Yes | Key lookup |
| **QRAS** | Semantic search | Yes | Vector + hybrid |
| **QMD** | Markdown-native | Yes | Full-text + semantic |
| **SQLite** | Structured queries | Yes | SQL |
| **PostgreSQL** | Scalable, concurrent | Yes | SQL + pgvector |
| **Mnesia** | Distributed, native | Yes | Pattern matching |

### 11.2 Memory Behaviour

```elixir
defmodule Mirai.Memory.Backend do
  @moduledoc """
  Behaviour for pluggable memory backends.
  """
  
  @type memory_id :: String.t()
  @type user_id :: String.t()
  @type content :: String.t() | map()
  @type metadata :: map()
  @type search_opts :: keyword()
  
  # Lifecycle
  @callback init(config :: map()) :: {:ok, state} | {:error, reason}
  @callback terminate(state) :: :ok
  
  # CRUD operations
  @callback store(state, user_id, content, metadata) :: 
    {:ok, memory_id} | {:error, reason}
  
  @callback retrieve(state, memory_id) :: 
    {:ok, content, metadata} | {:error, :not_found}
  
  @callback update(state, memory_id, content, metadata) :: 
    {:ok, memory_id} | {:error, reason}
  
  @callback delete(state, memory_id) :: :ok | {:error, reason}
  
  # Search
  @callback search(state, user_id, query :: String.t(), search_opts) ::
    {:ok, [%{id: memory_id, content: content, score: float(), metadata: metadata}]}
  
  # Bulk operations
  @callback list(state, user_id, opts :: keyword()) ::
    {:ok, [%{id: memory_id, content: content, metadata: metadata}]}
  
  @callback clear(state, user_id) :: :ok
  
  # Optional: semantic operations
  @callback embed(state, content) :: {:ok, vector :: [float()]} | {:error, reason}
  
  @optional_callbacks [embed: 2]
end
```

### 11.3 QRAS Backend

```elixir
defmodule Mirai.Memory.QRAS do
  @behaviour Mirai.Memory.Backend
  
  defstruct [:collection, :qdrant_url, :ollama_host, :embed_model]
  
  @impl true
  def init(config) do
    state = %__MODULE__{
      collection: config[:collection] || "mirai-memory",
      qdrant_url: config[:qdrant_url] || "http://localhost:6333",
      ollama_host: config[:ollama_host] || "http://localhost:11434",
      embed_model: config[:embed_model] || "bge-m3:567m"
    }
    
    # Ensure collection exists
    ensure_collection(state)
    {:ok, state}
  end
  
  @impl true
  def store(state, user_id, content, metadata) do
    # Generate embedding
    {:ok, vector} = embed(state, content)
    
    # Store in Qdrant
    point = %{
      id: generate_id(),
      vector: vector,
      payload: %{
        user_id: user_id,
        content: content,
        metadata: metadata,
        timestamp: DateTime.utc_now()
      }
    }
    
    case Qdrant.upsert_points(state.qdrant_url, state.collection, [point]) do
      :ok -> {:ok, point.id}
      error -> error
    end
  end
  
  @impl true
  def search(state, user_id, query, opts) do
    limit = opts[:limit] || 10
    min_score = opts[:min_score] || 0.5
    
    # Generate query embedding
    {:ok, query_vector} = embed(state, query)
    
    # Search with filter
    filter = %{
      must: [%{key: "user_id", match: %{value: user_id}}]
    }
    
    case Qdrant.search(state.qdrant_url, state.collection, query_vector, 
                       limit: limit, filter: filter, score_threshold: min_score) do
      {:ok, results} ->
        formatted = Enum.map(results, fn r ->
          %{
            id: r.id,
            content: r.payload["content"],
            score: r.score,
            metadata: r.payload["metadata"]
          }
        end)
        {:ok, formatted}
      error -> error
    end
  end
  
  @impl true
  def embed(state, content) do
    Ollama.embed(state.ollama_host, state.embed_model, content)
  end
end
```

### 11.4 QMD Backend (Markdown-Native)

```elixir
defmodule Mirai.Memory.QMD do
  @behaviour Mirai.Memory.Backend
  @moduledoc """
  Markdown-native memory with daily logs and long-term memory file.
  Compatible with OpenClaw/ClawLite workspace structure.
  """
  
  defstruct [:workspace_path, :index_backend]
  
  @impl true
  def init(config) do
    state = %__MODULE__{
      workspace_path: config[:workspace_path],
      index_backend: config[:index_backend] || :full_text  # or :semantic
    }
    {:ok, state}
  end
  
  @impl true
  def store(state, user_id, content, metadata) do
    # Determine file based on metadata
    file_path = case metadata[:type] do
      :daily -> daily_log_path(state, user_id)
      :long_term -> memory_file_path(state, user_id)
      _ -> daily_log_path(state, user_id)
    end
    
    # Append to markdown file
    entry = format_entry(content, metadata)
    File.write(file_path, entry, [:append])
    
    # Update index
    index_entry(state, user_id, content, metadata)
    
    {:ok, generate_id()}
  end
  
  @impl true
  def search(state, user_id, query, opts) do
    case state.index_backend do
      :full_text -> search_full_text(state, user_id, query, opts)
      :semantic -> search_semantic(state, user_id, query, opts)
    end
  end
  
  defp daily_log_path(state, user_id) do
    date = Date.to_iso8601(Date.utc_today())
    Path.join([state.workspace_path, "users", user_id, "memory", "#{date}.md"])
  end
  
  defp memory_file_path(state, user_id) do
    Path.join([state.workspace_path, "users", user_id, "MEMORY.md"])
  end
end
```

### 11.5 Memory Manager (Switchable)

```elixir
defmodule Mirai.Memory.Manager do
  use GenServer
  
  @doc """
  Start memory manager with configured backend.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    backend_module = get_backend_module(opts[:backend] || :qmd)
    {:ok, backend_state} = backend_module.init(opts[:config] || %{})
    
    {:ok, %{
      backend: backend_module,
      backend_state: backend_state
    }}
  end
  
  # Delegate all operations to backend
  def store(user_id, content, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:store, user_id, content, metadata})
  end
  
  def search(user_id, query, opts \\ []) do
    GenServer.call(__MODULE__, {:search, user_id, query, opts})
  end
  
  def handle_call({:store, user_id, content, metadata}, _from, state) do
    result = state.backend.store(state.backend_state, user_id, content, metadata)
    {:reply, result, state}
  end
  
  def handle_call({:search, user_id, query, opts}, _from, state) do
    result = state.backend.search(state.backend_state, user_id, query, opts)
    {:reply, result, state}
  end
  
  # Hot-swap backend
  def switch_backend(new_backend, config) do
    GenServer.call(__MODULE__, {:switch_backend, new_backend, config})
  end
  
  def handle_call({:switch_backend, new_backend, config}, _from, state) do
    # Terminate old backend
    state.backend.terminate(state.backend_state)
    
    # Initialize new backend
    backend_module = get_backend_module(new_backend)
    {:ok, new_state} = backend_module.init(config)
    
    {:reply, :ok, %{state | backend: backend_module, backend_state: new_state}}
  end
  
  defp get_backend_module(:qras), do: Mirai.Memory.QRAS
  defp get_backend_module(:qmd), do: Mirai.Memory.QMD
  defp get_backend_module(:sqlite), do: Mirai.Memory.SQLite
  defp get_backend_module(:postgres), do: Mirai.Memory.Postgres
  defp get_backend_module(:ets), do: Mirai.Memory.ETS
end
```

### 11.6 Configuration

```elixir
# config/mirai.exs
config :mirai, Mirai.Memory.Manager,
  backend: :qras,
  config: %{
    collection: "mirai-memory",
    qdrant_url: "http://localhost:6333",
    ollama_host: "http://192.168.1.7:11434",
    embed_model: "bge-m3:567m"
  }

# Or for QMD (file-based)
config :mirai, Mirai.Memory.Manager,
  backend: :qmd,
  config: %{
    workspace_path: "~/.mirai/workspace",
    index_backend: :semantic  # or :full_text
  }
```

---

## 12. Access Control with Conditional Context (ACL)

### 12.1 Overview

ACL system yang mendukung:
- **User-level permissions** — per-user tool/feature access
- **Group-level permissions** — shared permissions untuk groups
- **Conditional context** — context injection berdasarkan rules
- **Dynamic rules** — rules bisa berubah runtime
- **Admin bypass** — admins skip restrictions

### 12.2 ACL Schema

```elixir
defmodule Mirai.ACL do
  @moduledoc """
  Access Control List with conditional context injection.
  """
  
  defmodule Rule do
    @type t :: %__MODULE__{
      id: String.t(),
      match: match_spec(),
      permissions: permissions(),
      context_inject: [context_injection()],
      priority: integer()
    }
    
    @type match_spec :: %{
      optional(:user_id) => String.t() | [String.t()] | :any,
      optional(:group_id) => String.t() | [String.t()] | :any,
      optional(:channel) => atom() | [atom()] | :any,
      optional(:time_range) => {Time.t(), Time.t()},
      optional(:day_of_week) => [integer()],  # 1-7
      optional(:custom) => (context -> boolean())
    }
    
    @type permissions :: %{
      optional(:tools) => %{
        allow: [String.t()] | :all,
        deny: [String.t()]
      },
      optional(:agents) => %{
        allow: [String.t()] | :all,
        deny: [String.t()]
      },
      optional(:features) => %{
        allow: [atom()] | :all,
        deny: [atom()]
      },
      optional(:rate_limit) => %{
        requests_per_minute: pos_integer(),
        tokens_per_day: pos_integer()
      }
    }
    
    @type context_injection :: %{
      type: :prepend | :append | :system,
      content: String.t() | (context -> String.t()),
      condition: (context -> boolean()) | nil
    }
    
    defstruct [:id, :match, :permissions, :context_inject, priority: 0]
  end
end
```

### 12.3 ACL Engine

```elixir
defmodule Mirai.ACL.Engine do
  use GenServer
  
  @doc """
  Check if action is allowed for given context.
  """
  def allowed?(action, context) do
    GenServer.call(__MODULE__, {:check, action, context})
  end
  
  @doc """
  Get context injections for given context.
  """
  def get_context_injections(context) do
    GenServer.call(__MODULE__, {:get_injections, context})
  end
  
  @doc """
  Get effective permissions for context.
  """
  def get_permissions(context) do
    GenServer.call(__MODULE__, {:get_permissions, context})
  end
  
  # Implementation
  
  def handle_call({:check, action, context}, _from, state) do
    # Check admin bypass first
    if is_admin?(context.user_id, state) do
      {:reply, true, state}
    else
      permissions = compute_permissions(context, state.rules)
      result = check_action(action, permissions)
      {:reply, result, state}
    end
  end
  
  def handle_call({:get_injections, context}, _from, state) do
    injections = state.rules
    |> Enum.filter(&matches?(&1.match, context))
    |> Enum.sort_by(& &1.priority, :desc)
    |> Enum.flat_map(& &1.context_inject)
    |> Enum.filter(fn injection ->
      case injection.condition do
        nil -> true
        condition_fn -> condition_fn.(context)
      end
    end)
    |> Enum.map(&resolve_injection(&1, context))
    
    {:reply, injections, state}
  end
  
  defp matches?(match_spec, context) do
    Enum.all?(match_spec, fn {key, pattern} ->
      match_field?(key, pattern, context)
    end)
  end
  
  defp match_field?(:user_id, pattern, context) do
    case pattern do
      :any -> true
      list when is_list(list) -> context.user_id in list
      id -> context.user_id == id
    end
  end
  
  defp match_field?(:time_range, {start_time, end_time}, context) do
    now = Time.utc_now()
    Time.compare(now, start_time) in [:gt, :eq] and
    Time.compare(now, end_time) in [:lt, :eq]
  end
  
  defp match_field?(:custom, condition_fn, context) do
    condition_fn.(context)
  end
  
  defp resolve_injection(injection, context) do
    content = case injection.content do
      fun when is_function(fun) -> fun.(context)
      static -> static
    end
    
    %{type: injection.type, content: content}
  end
end
```

### 12.4 Conditional Context Examples

```elixir
# config/acl_rules.exs

[
  # Admin rule — full access, no restrictions
  %Mirai.ACL.Rule{
    id: "admin_bypass",
    match: %{user_id: ["tg_123456", "wa_628xxx"]},
    permissions: %{
      tools: %{allow: :all, deny: []},
      features: %{allow: :all, deny: []}
    },
    context_inject: [
      %{
        type: :prepend,
        content: "You are speaking with an admin. Full access granted."
      }
    ],
    priority: 100
  },
  
  # Work hours rule — inject work context during office hours
  %Mirai.ACL.Rule{
    id: "work_hours",
    match: %{
      time_range: {~T[09:00:00], ~T[17:00:00]},
      day_of_week: [1, 2, 3, 4, 5]  # Mon-Fri
    },
    permissions: %{},
    context_inject: [
      %{
        type: :prepend,
        content: fn ctx ->
          "Current time: #{DateTime.utc_now()}. User is likely at work."
        end
      }
    ],
    priority: 10
  },
  
  # Guest user — limited tools
  %Mirai.ACL.Rule{
    id: "guest_limited",
    match: %{
      custom: fn ctx -> 
        not Mirai.ACL.Engine.is_verified?(ctx.user_id)
      end
    },
    permissions: %{
      tools: %{
        allow: ["read", "web_search", "web_fetch"],
        deny: ["exec", "write", "edit", "browser", "cron"]
      },
      rate_limit: %{
        requests_per_minute: 10,
        tokens_per_day: 50_000
      }
    },
    context_inject: [
      %{
        type: :system,
        content: """
        This is a guest user with limited access.
        Do not execute system commands or modify files.
        """
      }
    ],
    priority: 5
  },
  
  # VIP user — extra context and higher limits
  %Mirai.ACL.Rule{
    id: "vip_user",
    match: %{
      user_id: ["tg_vip1", "tg_vip2"],
      custom: fn ctx -> ctx.subscription == :premium end
    },
    permissions: %{
      tools: %{allow: :all, deny: []},
      rate_limit: %{
        requests_per_minute: 60,
        tokens_per_day: 500_000
      }
    },
    context_inject: [
      %{
        type: :prepend,
        content: fn ctx ->
          user_prefs = Mirai.Memory.Manager.search(ctx.user_id, "preferences", limit: 5)
          "User preferences: #{inspect(user_prefs)}"
        end
      }
    ],
    priority: 50
  },
  
  # Group-specific context
  %Mirai.ACL.Rule{
    id: "family_group",
    match: %{group_id: "wa_family123@g.us"},
    permissions: %{
      tools: %{
        allow: ["read", "web_search", "web_fetch", "memory_search"],
        deny: ["exec", "write", "browser"]
      }
    },
    context_inject: [
      %{
        type: :system,
        content: """
        This is a family group chat. Be friendly and family-appropriate.
        No technical jargon. Keep responses concise.
        """
      }
    ],
    priority: 20
  }
]
```

### 12.5 Integration with Agent Loop

```elixir
defmodule Mirai.AgentLoop do
  def run(session, message, opts \\ []) do
    context = build_context(session, message)
    
    # Get ACL permissions and injections
    permissions = Mirai.ACL.Engine.get_permissions(context)
    injections = Mirai.ACL.Engine.get_context_injections(context)
    
    # Filter available tools based on permissions
    available_tools = filter_tools(permissions.tools)
    
    # Build system prompt with injections
    system_prompt = build_system_prompt(session, injections)
    
    # Check rate limits
    case check_rate_limit(context, permissions.rate_limit) do
      :ok ->
        execute_loop(%{
          session: session,
          message: message,
          system_prompt: system_prompt,
          tools: available_tools,
          permissions: permissions
        })
        
      {:error, :rate_limited} ->
        {:error, "Rate limit exceeded. Please wait."}
    end
  end
  
  defp build_system_prompt(session, injections) do
    base_prompt = load_base_prompt(session)
    
    # Apply injections in order
    Enum.reduce(injections, base_prompt, fn injection, prompt ->
      case injection.type do
        :prepend -> injection.content <> "\n\n" <> prompt
        :append -> prompt <> "\n\n" <> injection.content
        :system -> prompt <> "\n\n## System Note\n" <> injection.content
      end
    end)
  end
end
```

### 12.6 Per-User Workspace Isolation

```elixir
defmodule Mirai.Workspace do
  @moduledoc """
  Per-user workspace isolation (like ClawLite).
  """
  
  @doc """
  Get or create user workspace directory.
  """
  def ensure_user_workspace(base_path, user_id) do
    user_path = Path.join([base_path, "users", user_id])
    
    # Create directory structure
    File.mkdir_p!(Path.join(user_path, "memory"))
    
    # Create default files if not exist
    ensure_file(Path.join(user_path, "USER.md"), default_user_md(user_id))
    ensure_file(Path.join(user_path, "MEMORY.md"), default_memory_md())
    
    user_path
  end
  
  @doc """
  Load user-specific context files.
  """
  def load_user_context(user_path) do
    %{
      user_md: read_file(Path.join(user_path, "USER.md")),
      memory_md: read_file(Path.join(user_path, "MEMORY.md")),
      daily_log: read_daily_log(user_path)
    }
  end
  
  @doc """
  Load shared context (SOUL.md, AGENTS.md) + user context.
  """
  def load_full_context(base_path, user_id) do
    user_path = ensure_user_workspace(base_path, user_id)
    
    shared = %{
      soul_md: read_file(Path.join(base_path, "SOUL.md")),
      agents_md: read_file(Path.join(base_path, "AGENTS.md"))
    }
    
    user = load_user_context(user_path)
    
    Map.merge(shared, user)
  end
end
```

---

## 13. Plugins & Hooks

### 10.1 Plugin Behaviour

```elixir
defmodule Mirai.Plugin do
  @callback init(config :: map()) :: {:ok, state} | {:error, reason}
  @callback handle_hook(hook :: atom(), payload :: map(), state) :: 
    {:ok, payload} | {:halt, response} | {:error, reason}
  @callback terminate(reason, state) :: :ok
  
  @optional_callbacks [terminate: 2]
end
```

### 10.2 Available Hooks

| Phase | Hook |
|-------|------|
| Pre-model | `before_model_resolve` |
| Pre-prompt | `before_prompt_build` |
| Pre-agent | `before_agent_start` |
| Post-agent | `agent_end` |
| Pre-tool | `before_tool_call` |
| Post-tool | `after_tool_call` |
| Compaction | `before_compaction`, `after_compaction` |
| Message | `message_received`, `message_sending`, `message_sent` |
| Session | `session_start`, `session_end` |
| Gateway | `gateway_start`, `gateway_stop` |

### 10.3 Plugin Example

```elixir
defmodule MyPlugin do
  @behaviour Mirai.Plugin
  
  def init(config) do
    {:ok, %{config: config}}
  end
  
  def handle_hook(:before_prompt_build, payload, state) do
    # Inject custom context
    updated = Map.update(payload, :prepend_context, [], fn ctx ->
      ["Custom context: #{state.config.greeting}" | ctx]
    end)
    {:ok, updated}
  end
  
  def handle_hook(_hook, payload, _state), do: {:ok, payload}
end
```

---

## 11. Phoenix Integration

### 11.1 Web Interface

```elixir
defmodule MiraiWeb.Router do
  use Phoenix.Router
  
  pipeline :api do
    plug :accepts, ["json"]
    plug MiraiWeb.AuthPlug
  end
  
  scope "/api", MiraiWeb do
    pipe_through :api
    
    # Sessions
    get "/sessions", SessionController, :list
    get "/sessions/:key", SessionController, :show
    post "/sessions/:key/send", SessionController, :send
    
    # Agents
    get "/agents", AgentController, :list
    post "/agents/:id/run", AgentController, :run
    
    # Config
    get "/config", ConfigController, :show
    patch "/config", ConfigController, :update
    
    # Health
    get "/health", HealthController, :show
  end
end
```

### 11.2 WebSocket Protocol

```elixir
defmodule MiraiWeb.GatewaySocket do
  use Phoenix.Socket
  
  channel "gateway:*", MiraiWeb.GatewayChannel
  
  def connect(%{"token" => token}, socket, _connect_info) do
    case verify_token(token) do
      {:ok, client_id} -> {:ok, assign(socket, :client_id, client_id)}
      :error -> :error
    end
  end
end

defmodule MiraiWeb.GatewayChannel do
  use Phoenix.Channel
  
  def join("gateway:main", _params, socket) do
    {:ok, socket}
  end
  
  def handle_in("agent", %{"message" => msg} = params, socket) do
    case Mirai.Gateway.run_agent(params) do
      {:ok, run_id} ->
        # Stream events back
        {:reply, {:ok, %{run_id: run_id}}, socket}
      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end
end
```

### 11.3 LiveView Control Panel

```elixir
defmodule MiraiWeb.DashboardLive do
  use Phoenix.LiveView
  
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to telemetry events
      Phoenix.PubSub.subscribe(Mirai.PubSub, "gateway:events")
    end
    
    {:ok, assign(socket,
      sessions: Mirai.Sessions.list_recent(),
      agents: Mirai.Agents.list(),
      health: Mirai.Gateway.health()
    )}
  end
  
  def handle_info({:gateway_event, event}, socket) do
    # Real-time updates
    {:noreply, update_from_event(socket, event)}
  end
end
```

---

## 12. Observability

### 12.1 Telemetry Events

```elixir
defmodule Mirai.Telemetry do
  def setup do
    events = [
      [:mirai, :agent, :start],
      [:mirai, :agent, :stop],
      [:mirai, :tool, :start],
      [:mirai, :tool, :stop],
      [:mirai, :model, :request],
      [:mirai, :model, :response],
      [:mirai, :channel, :inbound],
      [:mirai, :channel, :outbound]
    ]
    
    :telemetry.attach_many("elixir-claw-metrics", events, &handle_event/4, nil)
  end
  
  def handle_event([:mirai, :agent, :stop], measurements, metadata, _config) do
    # Record to Prometheus/StatsD
    :telemetry.execute([:mirai, :agent, :duration], 
      %{duration: measurements.duration},
      %{agent_id: metadata.agent_id, status: metadata.status})
  end
end
```

### 12.2 Prometheus Metrics

```elixir
defmodule Mirai.Metrics do
  use Prometheus.Metric
  
  def setup do
    Counter.declare(
      name: :mirai_agent_runs_total,
      help: "Total agent runs",
      labels: [:agent_id, :status]
    )
    
    Histogram.declare(
      name: :mirai_agent_duration_seconds,
      help: "Agent run duration",
      labels: [:agent_id],
      buckets: [0.1, 0.5, 1, 5, 10, 30, 60, 120, 300]
    )
    
    Gauge.declare(
      name: :mirai_sessions_active,
      help: "Active sessions",
      labels: [:agent_id]
    )
  end
end
```

---

## 13. Security

### 13.1 Authentication

```elixir
defmodule Mirai.Auth do
  # Gateway token auth
  def verify_gateway_token(token) do
    case get_config(:gateway_token) do
      nil -> :ok  # No token configured
      expected -> if secure_compare(token, expected), do: :ok, else: :error
    end
  end
  
  # Pairing flow
  def generate_pairing_code(device_id) do
    code = :crypto.strong_rand_bytes(4) |> Base.encode32(padding: false)
    store_pairing(device_id, code)
    code
  end
  
  def verify_pairing(device_id, code) do
    case get_pairing(device_id) do
      ^code -> {:ok, generate_device_token(device_id)}
      _ -> :error
    end
  end
end
```

### 13.2 Sandboxing

```elixir
defmodule Mirai.Sandbox do
  @moduledoc """
  Sandboxing via Docker atau Firecracker
  """
  
  def execute_sandboxed(command, opts) do
    container_id = get_or_create_container(opts[:agent_id])
    
    docker_cmd = [
      "docker", "exec", container_id,
      "sh", "-c", command
    ]
    
    System.cmd(hd(docker_cmd), tl(docker_cmd), opts)
  end
  
  defp get_or_create_container(agent_id) do
    case lookup_container(agent_id) do
      nil -> create_container(agent_id)
      id -> id
    end
  end
end
```

---

## 14. Testing Strategy

### 14.1 Unit Tests

```elixir
defmodule Mirai.AgentLoopTest do
  use ExUnit.Case, async: true
  
  describe "run/3" do
    test "executes simple message" do
      session = build(:session)
      message = "Hello"
      
      assert {:ok, result} = Mirai.AgentLoop.run(session, message)
      assert result.status == :completed
    end
    
    test "handles tool calls" do
      session = build(:session)
      message = "Read file.txt"
      
      assert {:ok, result} = Mirai.AgentLoop.run(session, message)
      assert length(result.tool_calls) > 0
    end
  end
end
```

### 14.2 Integration Tests

```elixir
defmodule Mirai.IntegrationTest do
  use ExUnit.Case
  
  @tag :integration
  test "full message flow through gateway" do
    # Start gateway
    {:ok, gateway} = Mirai.Gateway.start_link()
    
    # Simulate inbound
    envelope = build(:envelope, text: "Hello")
    
    # Route and wait for response
    assert {:ok, response} = Mirai.Gateway.route_and_wait(gateway, envelope)
    assert response.text != nil
  end
end
```

### 14.3 Property-Based Tests

```elixir
defmodule Mirai.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "session keys are deterministic" do
    check all channel <- member_of([:whatsapp, :telegram, :discord]),
              peer_id <- string(:alphanumeric),
              agent_id <- string(:alphanumeric, min_length: 1) do
      
      key1 = Mirai.Sessions.build_key(agent_id, channel, peer_id)
      key2 = Mirai.Sessions.build_key(agent_id, channel, peer_id)
      
      assert key1 == key2
    end
  end
end
```

---

## 15. Deployment

### 15.1 Release Configuration

```elixir
# mix.exs
def project do
  [
    app: :mirai,
    version: "0.1.0",
    elixir: "~> 1.18",
    releases: [
      mirai: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar]
      ]
    ]
  ]
end
```

### 15.2 Docker

```dockerfile
# Dockerfile
FROM elixir:1.18-alpine AS builder

WORKDIR /app
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
COPY . .
RUN MIX_ENV=prod mix release

FROM alpine:3.19
RUN apk add --no-cache libstdc++ ncurses-libs
COPY --from=builder /app/_build/prod/rel/mirai ./
CMD ["bin/mirai", "start"]
```

### 15.3 Systemd Service

```ini
# /etc/systemd/system/mirai.service
[Unit]
Description=Mirai Gateway
After=network.target

[Service]
Type=simple
User=mirai
Environment=MIX_ENV=prod
Environment=RELEASE_NODE=mirai@127.0.0.1
WorkingDirectory=/opt/mirai
ExecStart=/opt/mirai/bin/mirai start
ExecStop=/opt/mirai/bin/mirai stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

---

## 16. Migration Path from OpenClaw

### 16.1 Data Migration

| OpenClaw | Mirai |
|----------|------------|
| `~/.openclaw/openclaw.json` | `~/.mirai/config.exs` |
| `~/.openclaw/agents/<id>/sessions/` | `~/.mirai/agents/<id>/sessions/` |
| `~/.openclaw/workspace/` | `~/.mirai/workspace/` |
| `~/.openclaw/credentials/` | `~/.mirai/credentials/` |

### 16.2 Config Converter

```elixir
defmodule Mirai.Migration do
  def convert_openclaw_config(json_path) do
    {:ok, content} = File.read(json_path)
    {:ok, config} = Jason.decode(content)
    
    elixir_config = %{
      agents: convert_agents(config["agents"]),
      channels: convert_channels(config["channels"]),
      bindings: convert_bindings(config["bindings"]),
      session: convert_session(config["session"]),
      tools: convert_tools(config["tools"])
    }
    
    {:ok, elixir_config}
  end
end
```

---

## 17. Development Roadmap

### Phase 1: Core (4-6 weeks)
- [ ] Project setup (mix, deps, CI)
- [ ] Config system
- [ ] Gateway server
- [ ] Session management
- [ ] Agent loop (basic)
- [ ] Model providers (Anthropic, OpenAI)

### Phase 2: Channels (3-4 weeks)
- [ ] Telegram integration
- [ ] Discord integration
- [ ] WhatsApp bridge (via existing Node.js Baileys)
- [ ] Channel routing

### Phase 3: Tools (3-4 weeks)
- [ ] Core tools (read, write, edit, exec)
- [ ] Web tools (search, fetch)
- [ ] Session tools (spawn, send)
- [ ] Tool registry

### Phase 4: Advanced (4-6 weeks)
- [ ] Sub-agents
- [ ] Cron scheduler
- [ ] Plugins/hooks
- [ ] Phoenix web UI
- [ ] LiveView dashboard

### Phase 5: Distribution (2-3 weeks)
- [ ] Multi-node clustering
- [ ] Agent distribution
- [ ] State synchronization

### Phase 6: Production (2-3 weeks)
- [ ] Release packaging
- [ ] Docker images
- [ ] Documentation
- [ ] Migration tools

---

## 18. Dependencies

```elixir
# mix.exs
defp deps do
  [
    # Core
    {:jason, "~> 1.4"},
    {:yaml_elixir, "~> 2.9"},
    
    # HTTP
    {:req, "~> 0.5"},
    {:finch, "~> 0.18"},
    
    # WebSocket
    {:websockex, "~> 0.4"},
    {:gun, "~> 2.0"},
    
    # Web Framework
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 0.20"},
    {:bandit, "~> 1.2"},
    
    # Channels
    {:nostrum, "~> 0.8"},      # Discord
    {:telegex, "~> 1.5"},      # Telegram
    
    # Scheduling
    {:quantum, "~> 3.5"},
    
    # Clustering
    {:libcluster, "~> 3.3"},
    {:horde, "~> 0.8"},
    
    # Telemetry
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 0.6"},
    {:telemetry_poller, "~> 1.0"},
    
    # Storage
    {:ecto_sqlite3, "~> 0.15"},
    
    # Testing
    {:ex_machina, "~> 2.7", only: :test},
    {:mox, "~> 1.1", only: :test},
    {:stream_data, "~> 0.6", only: :test}
  ]
end
```

---

## 19. Design Decisions (Resolved)

| Question | Decision | Rationale |
|----------|----------|-----------|
| WhatsApp | **Port Baileys to Elixir** | Full control, no Node.js dependency |
| Sandbox | **Docker containers** | Industry standard, well-supported |
| State Persistence | SQLite (single-node) / PostgreSQL (multi-node) | Flexibility |
| Model Streaming | **Phoenix Channels + GenStage** | Backpressure + real-time |
| Plugin Distribution | **Git repos + Mix tasks** | Easy install/uninstall |

## 19.1 Baileys Port Strategy (WhatsAppEx)

Port library Baileys (TypeScript) ke Elixir native.

**Module name:** `WhatsAppEx`

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     WhatsAppEx                          │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │   Socket    │  │   Crypto    │  │   Proto     │     │
│  │  (WebSocket)│  │  (Noise,    │  │  (Protobuf) │     │
│  │             │  │   Signal)   │  │             │     │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘     │
│         └────────────────┼────────────────┘             │
│                          │                              │
│                   ┌──────▼──────┐                       │
│                   │   Session   │                       │
│                   │   Manager   │                       │
│                   └──────┬──────┘                       │
│                          │                              │
│         ┌────────────────┼────────────────┐             │
│         │                │                │             │
│    ┌────▼────┐     ┌─────▼─────┐    ┌─────▼─────┐      │
│    │ Messages│     │  Groups   │    │  Media    │      │
│    └─────────┘     └───────────┘    └───────────┘      │
└─────────────────────────────────────────────────────────┘
```

### Key Components to Port

| Baileys (TS) | WhatsAppEx (Elixir) | Notes |
|--------------|---------------------|-------|
| `makeWASocket` | `WhatsAppEx.connect/1` | GenServer-based |
| `@whiskeysockets/baileys/WAProto` | `WhatsAppEx.Proto` | Use `protobuf-elixir` |
| Noise Protocol | `WhatsAppEx.Crypto.Noise` | Port or use `noise_protocol` |
| Signal Protocol | `WhatsAppEx.Crypto.Signal` | Port `libsignal-protocol-javascript` |
| Binary codec | `WhatsAppEx.Binary` | Port WABinary encoding |

### Elixir Advantages

```elixir
defmodule WhatsAppEx do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end
  
  def init(opts) do
    state = %{
      auth: load_auth(opts[:auth_dir]),
      socket: nil,
      callbacks: opts[:callbacks] || %{}
    }
    
    # Auto-reconnect via supervisor
    {:ok, state, {:continue, :connect}}
  end
  
  def handle_continue(:connect, state) do
    case connect_websocket(state) do
      {:ok, socket} -> 
        {:noreply, %{state | socket: socket}}
      {:error, _} ->
        # Supervisor will restart
        {:stop, :connection_failed, state}
    end
  end
  
  # Message handling with pattern matching
  def handle_info({:ws_message, %{"type" => "message", "data" => data}}, state) do
    message = WhatsAppEx.Proto.decode_message(data)
    
    case message do
      %{type: :text, from: from, content: content} ->
        notify_callback(:on_message, {from, content}, state)
      
      %{type: :image, from: from, media: media} ->
        notify_callback(:on_media, {from, media}, state)
      
      %{type: :reaction, from: from, emoji: emoji} ->
        notify_callback(:on_reaction, {from, emoji}, state)
    end
    
    {:noreply, state}
  end
end
```

### Porting Phases

1. **Phase 1:** WebSocket + Auth (QR, pairing)
2. **Phase 2:** Protobuf messages (send/receive text)
3. **Phase 3:** Media (images, documents, voice)
4. **Phase 4:** Groups, reactions, receipts
5. **Phase 5:** Calls, status, advanced features

### Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:websockex, "~> 0.4"},           # WebSocket client
    {:protobuf, "~> 0.12"},           # Protobuf encoding
    {:curve25519, "~> 1.0"},          # Curve25519 for Signal
    {:aes_cmac, "~> 0.1"},            # AES-CMAC
    {:hkdf, "~> 0.2"},                # HKDF key derivation
  ]
end
```

---

## 19.2 Docker Sandbox Implementation

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Mirai Host                            │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────┐   │
│  │              Sandbox Manager                     │   │
│  │              (GenServer)                         │   │
│  └────────────────────┬────────────────────────────┘   │
│                       │                                 │
│         ┌─────────────┼─────────────┐                  │
│         │             │             │                  │
│    ┌────▼────┐   ┌────▼────┐   ┌────▼────┐            │
│    │ Agent A │   │ Agent B │   │ Agent C │            │
│    │Container│   │Container│   │Container│            │
│    └─────────┘   └─────────┘   └─────────┘            │
│                                                        │
│    Docker Network: mirai_sandbox                       │
└─────────────────────────────────────────────────────────┘
```

### Sandbox Manager

```elixir
defmodule Mirai.Sandbox.Manager do
  use GenServer
  
  @container_image "mirai-sandbox:latest"
  @network "mirai_sandbox"
  
  defstruct [:containers, :config]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    # Ensure network exists
    ensure_network(@network)
    
    {:ok, %__MODULE__{
      containers: %{},
      config: opts[:config] || %{}
    }}
  end
  
  @doc """
  Get or create sandbox container for agent.
  """
  def get_container(agent_id) do
    GenServer.call(__MODULE__, {:get_container, agent_id})
  end
  
  @doc """
  Execute command in sandbox.
  """
  def exec(agent_id, command, opts \\ []) do
    GenServer.call(__MODULE__, {:exec, agent_id, command, opts}, opts[:timeout] || 30_000)
  end
  
  def handle_call({:get_container, agent_id}, _from, state) do
    case Map.get(state.containers, agent_id) do
      nil ->
        {:ok, container_id} = create_container(agent_id, state.config)
        new_state = put_in(state.containers[agent_id], container_id)
        {:reply, {:ok, container_id}, new_state}
      
      container_id ->
        {:reply, {:ok, container_id}, state}
    end
  end
  
  def handle_call({:exec, agent_id, command, opts}, _from, state) do
    {:ok, container_id} = get_or_create(agent_id, state)
    
    result = docker_exec(container_id, command, opts)
    {:reply, result, state}
  end
  
  defp create_container(agent_id, config) do
    workspace_path = get_workspace_path(agent_id)
    
    args = [
      "run", "-d",
      "--name", "mirai-#{agent_id}",
      "--network", @network,
      "--memory", config[:memory_limit] || "512m",
      "--cpus", config[:cpu_limit] || "1",
      "-v", "#{workspace_path}:/workspace:rw",
      "-w", "/workspace",
      "--user", "1000:1000",
      "--security-opt", "no-new-privileges",
      @container_image
    ]
    
    case System.cmd("docker", args) do
      {container_id, 0} -> {:ok, String.trim(container_id)}
      {error, _} -> {:error, error}
    end
  end
  
  defp docker_exec(container_id, command, opts) do
    timeout = opts[:timeout] || 30_000
    
    args = ["exec", container_id, "sh", "-c", command]
    
    task = Task.async(fn ->
      System.cmd("docker", args, stderr_to_stdout: true)
    end)
    
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {output, 0}} -> {:ok, output}
      {:ok, {output, code}} -> {:error, %{output: output, exit_code: code}}
      nil -> {:error, :timeout}
    end
  end
end
```

### Sandbox Dockerfile

```dockerfile
# Dockerfile.sandbox
FROM ubuntu:24.04

# Install common tools
RUN apt-get update && apt-get install -y \
    curl wget git jq \
    python3 python3-pip \
    nodejs npm \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 sandbox
USER sandbox
WORKDIR /workspace

# Keep container running
CMD ["sleep", "infinity"]
```

### Per-Agent Sandbox Config

```elixir
# config/mirai.exs
config :mirai, :sandbox,
  enabled: true,
  image: "mirai-sandbox:latest",
  defaults: %{
    memory_limit: "512m",
    cpu_limit: "1",
    timeout: 30_000
  },
  per_agent: %{
    "coding" => %{
      memory_limit: "2g",
      cpu_limit: "2",
      extra_mounts: ["/data/models:/models:ro"]
    },
    "family" => %{
      memory_limit: "256m",
      cpu_limit: "0.5"
    }
  }
```

---

## 19.3 Multi-Node Monitoring Dashboard

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Mirai Dashboard                              │
│                   (Phoenix LiveView)                             │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   Dashboard UI                           │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       │   │
│  │  │ Nodes   │ │ Agents  │ │Sessions │ │ Metrics │       │   │
│  │  │ Overview│ │ Status  │ │ Monitor │ │ Graphs  │       │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                    Phoenix PubSub                               │
│                              │                                  │
│         ┌────────────────────┼────────────────────┐            │
│         │                    │                    │            │
│    ┌────▼────┐          ┌────▼────┐          ┌────▼────┐      │
│    │ Node A  │          │ Node B  │          │ Node C  │      │
│    │ (local) │          │ (remote)│          │ (remote)│      │
│    └─────────┘          └─────────┘          └─────────┘      │
└─────────────────────────────────────────────────────────────────┘
```

### Node Registry

```elixir
defmodule Mirai.Dashboard.NodeRegistry do
  use GenServer
  
  @heartbeat_interval 5_000  # 5 seconds
  @node_timeout 30_000       # 30 seconds
  
  defstruct [:nodes, :authorized_tokens]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    schedule_heartbeat()
    
    {:ok, %__MODULE__{
      nodes: %{},
      authorized_tokens: load_authorized_tokens(opts)
    }}
  end
  
  @doc """
  Register a node with authorization token.
  """
  def register_node(node_info, token) do
    GenServer.call(__MODULE__, {:register, node_info, token})
  end
  
  @doc """
  Get all registered nodes.
  """
  def list_nodes do
    GenServer.call(__MODULE__, :list)
  end
  
  @doc """
  Get node by ID.
  """
  def get_node(node_id) do
    GenServer.call(__MODULE__, {:get, node_id})
  end
  
  def handle_call({:register, node_info, token}, _from, state) do
    if authorized?(token, state.authorized_tokens) do
      node = %{
        id: node_info.id,
        name: node_info.name,
        host: node_info.host,
        erlang_node: node_info.erlang_node,
        agents: node_info.agents,
        status: :online,
        last_heartbeat: DateTime.utc_now(),
        metrics: %{}
      }
      
      new_state = put_in(state.nodes[node.id], node)
      
      # Connect Erlang nodes if remote
      if node_info.erlang_node do
        Node.connect(node_info.erlang_node)
      end
      
      broadcast_node_update(node)
      {:reply, {:ok, node.id}, new_state}
    else
      {:reply, {:error, :unauthorized}, state}
    end
  end
  
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.nodes), state}
  end
  
  def handle_info(:heartbeat, state) do
    now = DateTime.utc_now()
    
    # Check for stale nodes
    updated_nodes = Enum.map(state.nodes, fn {id, node} ->
      age = DateTime.diff(now, node.last_heartbeat, :millisecond)
      
      new_status = cond do
        age > @node_timeout -> :offline
        age > @heartbeat_interval * 2 -> :degraded
        true -> :online
      end
      
      if new_status != node.status do
        broadcast_node_update(%{node | status: new_status})
      end
      
      {id, %{node | status: new_status}}
    end)
    |> Map.new()
    
    schedule_heartbeat()
    {:noreply, %{state | nodes: updated_nodes}}
  end
  
  defp broadcast_node_update(node) do
    Phoenix.PubSub.broadcast(Mirai.PubSub, "dashboard:nodes", {:node_update, node})
  end
  
  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
  end
end
```

### Dashboard LiveView

```elixir
defmodule MiraiWeb.DashboardLive do
  use Phoenix.LiveView
  
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mirai.PubSub, "dashboard:nodes")
      Phoenix.PubSub.subscribe(Mirai.PubSub, "dashboard:metrics")
    end
    
    {:ok, assign(socket,
      nodes: Mirai.Dashboard.NodeRegistry.list_nodes(),
      selected_node: nil,
      metrics: %{},
      agents: [],
      sessions: []
    )}
  end
  
  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <aside class="sidebar">
        <h2>Nodes</h2>
        <ul class="node-list">
          <%= for node <- @nodes do %>
            <li class={"node-item #{node.status}"} phx-click="select_node" phx-value-id={node.id}>
              <span class="status-dot"></span>
              <span class="node-name"><%= node.name %></span>
              <span class="agent-count"><%= length(node.agents) %> agents</span>
            </li>
          <% end %>
        </ul>
        <button phx-click="add_node" class="add-node-btn">+ Add Node</button>
      </aside>
      
      <main class="content">
        <%= if @selected_node do %>
          <.node_detail node={@selected_node} metrics={@metrics} />
        <% else %>
          <.overview nodes={@nodes} />
        <% end %>
      </main>
    </div>
    """
  end
  
  def handle_event("select_node", %{"id" => node_id}, socket) do
    node = Mirai.Dashboard.NodeRegistry.get_node(node_id)
    metrics = fetch_node_metrics(node)
    
    {:noreply, assign(socket, selected_node: node, metrics: metrics)}
  end
  
  def handle_event("add_node", _params, socket) do
    {:noreply, push_event(socket, "open_modal", %{modal: "add_node"})}
  end
  
  def handle_info({:node_update, node}, socket) do
    nodes = update_node_in_list(socket.assigns.nodes, node)
    {:noreply, assign(socket, nodes: nodes)}
  end
  
  def handle_info({:metrics_update, node_id, metrics}, socket) do
    if socket.assigns.selected_node && socket.assigns.selected_node.id == node_id do
      {:noreply, assign(socket, metrics: metrics)}
    else
      {:noreply, socket}
    end
  end
  
  # Components
  
  defp node_detail(assigns) do
    ~H"""
    <div class="node-detail">
      <header>
        <h1><%= @node.name %></h1>
        <span class={"status-badge #{@node.status}"}><%= @node.status %></span>
      </header>
      
      <section class="metrics-grid">
        <.metric_card title="CPU" value={"#{@metrics[:cpu_percent] || 0}%"} />
        <.metric_card title="Memory" value={"#{@metrics[:memory_mb] || 0} MB"} />
        <.metric_card title="Active Sessions" value={@metrics[:active_sessions] || 0} />
        <.metric_card title="Requests/min" value={@metrics[:requests_per_minute] || 0} />
      </section>
      
      <section class="agents">
        <h2>Agents</h2>
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>Status</th>
              <th>Sessions</th>
              <th>Last Activity</th>
            </tr>
          </thead>
          <tbody>
            <%= for agent <- @node.agents do %>
              <tr>
                <td><%= agent.id %></td>
                <td><%= agent.status %></td>
                <td><%= agent.session_count %></td>
                <td><%= format_time(agent.last_activity) %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </section>
    </div>
    """
  end
end
```

### Node Authorization

```elixir
defmodule Mirai.Dashboard.Auth do
  @moduledoc """
  Authorization for node registration and dashboard access.
  """
  
  @doc """
  Generate a new node registration token.
  """
  def generate_node_token(opts \\ []) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64()
    expires_at = DateTime.add(DateTime.utc_now(), opts[:expires_in] || 86400, :second)
    
    store_token(token, %{
      type: :node,
      created_at: DateTime.utc_now(),
      expires_at: expires_at,
      created_by: opts[:created_by]
    })
    
    token
  end
  
  @doc """
  Verify node token.
  """
  def verify_node_token(token) do
    case get_token(token) do
      nil -> {:error, :invalid_token}
      meta ->
        if DateTime.compare(DateTime.utc_now(), meta.expires_at) == :lt do
          {:ok, meta}
        else
          {:error, :token_expired}
        end
    end
  end
  
  @doc """
  Generate dashboard access token for admin.
  """
  def generate_dashboard_token(user_id, opts \\ []) do
    Phoenix.Token.sign(MiraiWeb.Endpoint, "dashboard_auth", %{
      user_id: user_id,
      permissions: opts[:permissions] || [:read, :write]
    })
  end
  
  @doc """
  Verify dashboard token.
  """
  def verify_dashboard_token(token) do
    case Phoenix.Token.verify(MiraiWeb.Endpoint, "dashboard_auth", token, max_age: 86400) do
      {:ok, claims} -> {:ok, claims}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### CLI for Adding Nodes

```bash
# Generate registration token
$ mirai dashboard token:generate --expires 24h
Token: mrt_abc123...
Expires: 2026-03-10T06:30:00Z

# On remote node, register with dashboard
$ mirai node register \
    --dashboard-url https://dashboard.example.com \
    --token mrt_abc123... \
    --name "production-node-1"
```

---

## 19.4 Plugin System (Easy Install/Uninstall)

### Plugin Structure

```
~/.mirai/plugins/
├── my_plugin/
│   ├── mix.exs
│   ├── lib/
│   │   └── my_plugin.ex
│   ├── priv/
│   │   └── assets/
│   └── plugin.json
└── another_plugin/
    └── ...
```

### plugin.json Manifest

```json
{
  "name": "my_plugin",
  "version": "1.0.0",
  "description": "A sample plugin",
  "author": "robin",
  "mirai_version": ">=0.1.0",
  "hooks": ["before_agent_start", "after_tool_call"],
  "tools": ["my_custom_tool"],
  "config_schema": {
    "api_key": {"type": "string", "required": true, "secret": true},
    "timeout": {"type": "integer", "default": 30}
  },
  "dependencies": []
}
```

### Plugin Manager

```elixir
defmodule Mirai.Plugins.Manager do
  use GenServer
  
  @plugins_dir "~/.mirai/plugins"
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Install plugin from git repo.
  """
  def install(source) do
    GenServer.call(__MODULE__, {:install, source}, 60_000)
  end
  
  @doc """
  Uninstall plugin by name.
  """
  def uninstall(name) do
    GenServer.call(__MODULE__, {:uninstall, name})
  end
  
  @doc """
  List installed plugins.
  """
  def list do
    GenServer.call(__MODULE__, :list)
  end
  
  @doc """
  Enable/disable plugin.
  """
  def set_enabled(name, enabled) do
    GenServer.call(__MODULE__, {:set_enabled, name, enabled})
  end
  
  # Installation
  
  def handle_call({:install, source}, _from, state) do
    result = with {:ok, plugin_dir} <- download_plugin(source),
                  {:ok, manifest} <- load_manifest(plugin_dir),
                  :ok <- validate_manifest(manifest),
                  :ok <- compile_plugin(plugin_dir),
                  :ok <- register_plugin(manifest, plugin_dir) do
      {:ok, manifest.name}
    end
    
    {:reply, result, state}
  end
  
  def handle_call({:uninstall, name}, _from, state) do
    result = with {:ok, plugin} <- get_plugin(name),
                  :ok <- unload_plugin(plugin),
                  :ok <- remove_plugin_dir(plugin.dir) do
      :ok
    end
    
    {:reply, result, state}
  end
  
  defp download_plugin(source) do
    cond do
      String.starts_with?(source, "http") or String.starts_with?(source, "git@") ->
        # Git clone
        name = extract_repo_name(source)
        dest = Path.join([@plugins_dir, name]) |> Path.expand()
        
        case System.cmd("git", ["clone", "--depth", "1", source, dest]) do
          {_, 0} -> {:ok, dest}
          {error, _} -> {:error, error}
        end
      
      String.contains?(source, "/") ->
        # GitHub shorthand: user/repo
        download_plugin("https://github.com/#{source}.git")
      
      true ->
        # Official plugin registry
        download_plugin("https://github.com/mirai-plugins/#{source}.git")
    end
  end
  
  defp compile_plugin(plugin_dir) do
    # Compile as a dependency
    File.cd!(plugin_dir, fn ->
      case System.cmd("mix", ["deps.get"]) do
        {_, 0} ->
          case System.cmd("mix", ["compile"]) do
            {_, 0} -> :ok
            {error, _} -> {:error, error}
          end
        {error, _} -> {:error, error}
      end
    end)
  end
  
  defp register_plugin(manifest, plugin_dir) do
    # Load compiled beams into runtime
    ebin_path = Path.join(plugin_dir, "_build/prod/lib/#{manifest.name}/ebin")
    Code.prepend_path(ebin_path)
    
    # Register hooks
    Enum.each(manifest.hooks, fn hook ->
      Mirai.Plugins.Hooks.register(hook, manifest.name, manifest.module)
    end)
    
    # Register tools
    Enum.each(manifest.tools, fn tool ->
      Mirai.Tools.Registry.register(tool, manifest.module)
    end)
    
    :ok
  end
end
```

### CLI Commands

```bash
# Install from GitHub
$ mirai plugin install robin/my-awesome-plugin
Installing robin/my-awesome-plugin...
✓ Downloaded
✓ Compiled
✓ Registered hooks: before_agent_start, after_tool_call
✓ Registered tools: my_custom_tool
Plugin 'my-awesome-plugin' installed successfully!

# Install from official registry
$ mirai plugin install weather
Installing mirai-plugins/weather...
✓ Plugin 'weather' installed successfully!

# Install from URL
$ mirai plugin install https://github.com/user/plugin.git

# List plugins
$ mirai plugin list
NAME                VERSION  STATUS   HOOKS                    TOOLS
my-awesome-plugin   1.0.0    enabled  before_agent_start (2)   my_custom_tool
weather             2.1.0    enabled  -                        get_weather

# Disable plugin
$ mirai plugin disable my-awesome-plugin
Plugin 'my-awesome-plugin' disabled.

# Enable plugin
$ mirai plugin enable my-awesome-plugin
Plugin 'my-awesome-plugin' enabled.

# Uninstall
$ mirai plugin uninstall my-awesome-plugin
Uninstalling 'my-awesome-plugin'...
✓ Hooks unregistered
✓ Tools unregistered
✓ Files removed
Plugin 'my-awesome-plugin' uninstalled.

# Update plugin
$ mirai plugin update my-awesome-plugin
Updating 'my-awesome-plugin'...
✓ Updated from 1.0.0 to 1.1.0

# Update all plugins
$ mirai plugin update --all
```

### Hot Reload Support

```elixir
defmodule Mirai.Plugins.HotReload do
  @moduledoc """
  Hot reload plugins without restarting Mirai.
  """
  
  def reload(plugin_name) do
    with {:ok, plugin} <- Mirai.Plugins.Manager.get_plugin(plugin_name),
         :ok <- unload_modules(plugin),
         :ok <- recompile(plugin.dir),
         :ok <- load_modules(plugin) do
      Logger.info("Plugin #{plugin_name} hot-reloaded")
      :ok
    end
  end
  
  defp unload_modules(plugin) do
    Enum.each(plugin.modules, fn mod ->
      :code.purge(mod)
      :code.delete(mod)
    end)
    :ok
  end
  
  defp load_modules(plugin) do
    ebin_path = Path.join(plugin.dir, "_build/prod/lib/#{plugin.name}/ebin")
    
    Path.wildcard(Path.join(ebin_path, "*.beam"))
    |> Enum.each(fn beam_file ->
      module = beam_file |> Path.basename(".beam") |> String.to_atom()
      {:module, ^module} = Code.ensure_loaded(module)
    end)
    
    :ok
  end
end
```

---

## 20. References

- [OpenClaw Documentation](https://docs.openclaw.ai)
- [Elixir OTP Design Principles](https://www.erlang.org/doc/design_principles/des_princ.html)
- [Phoenix Framework](https://www.phoenixframework.org/)
- [Distributed Erlang](https://www.erlang.org/doc/reference_manual/distributed.html)
- [Nostrum (Discord)](https://github.com/Kraigie/nostrum)
- [Telegex (Telegram)](https://github.com/telegex/telegex)
