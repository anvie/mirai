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

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      channels: %{},
      agents: %{}
    }

    # Auto-start Telegram worker if token is present
    if System.get_env("TELEGRAM_BOT_TOKEN") do
      DynamicSupervisor.start_child(
        Mirai.Channels.Supervisor,
        {Mirai.Channels.Telegram.Worker, []}
      )
    end

    {:ok, state}
  end

  # Simple echo routing for testing
  def route_inbound(%Mirai.Envelope{} = envelope) do
    GenServer.cast(__MODULE__, {:route, envelope})
  end

  @impl true
  def handle_cast({:route, envelope}, state) do
    # 1. Determine session key
    session_key = derive_session_key(envelope)

    # 2. Find or start the Session worker
    pid = case Registry.lookup(Mirai.Tools.Registry, {:session, session_key}) do
      [{pid, _}] -> pid
      [] ->
        # Start a new session worker
        {:ok, new_pid} = DynamicSupervisor.start_child(
          Mirai.Sessions.Supervisor,
          {Mirai.Sessions.Worker, [session_key: session_key]}
        )
        new_pid
    end

    # 3. Forward the envelope to the session
    Mirai.Sessions.Worker.append_message(pid, envelope)

    {:noreply, state}
  end

  defp derive_session_key(envelope) do
    # Format: "agent:<agent_id>:<channel>:<chat_type>:<chat_id>"
    # For now, default agent_id to "main"
    "agent:main:#{envelope.channel}:#{envelope.chat_type}:#{envelope.chat_id}"
  end
end
