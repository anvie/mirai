defmodule Mirai.Sessions.Worker do
  use GenServer
  require Logger

  defstruct [
    :session_key,
    :agent_id,
    :messages,        # In-memory message history [%{role: "user" | "assistant", content: string()}]
    :reply_context    # Information needed to route replies (e.g. channel, chat_id)
  ]

  def start_link(opts) do
    session_key = Keyword.fetch!(opts, :session_key)
    name = {:via, Registry, {Mirai.Tools.Registry, {:session, session_key}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    session_key = Keyword.get(opts, :session_key)

    # Simple parse of agent_id from session key (agent:agent_id:...)
    [_, agent_id | _] = String.split(session_key, ":")

    Logger.info("Session started: #{session_key}")

    # Load past history if any
    past_messages = case Mirai.Sessions.Store.load_session(session_key) do
      {:ok, history} -> history
      _ -> []
    end

    Logger.info("Session #{session_key} loaded #{length(past_messages)} previous messages.")

    {:ok, %__MODULE__{
      session_key: session_key,
      agent_id: agent_id,
      messages: past_messages,
      reply_context: nil
    }}
  end

  # Session operations
  def append_message(pid, %Mirai.Envelope{} = envelope) do
    GenServer.cast(pid, {:append, envelope})
  end

  # Used by agents to write back assistant replies into history
  def append_assistant_reply(pid, text) do
    GenServer.cast(pid, {:append_reply, text})
  end

  def get_history(pid) do
    GenServer.call(pid, :get_history)
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  def clear_history(pid) do
    GenServer.call(pid, :clear_history)
  end

  @impl true
  def handle_cast({:append, envelope}, state) do
    # 1. Update reply context for routing responses
    reply_context = %{
      channel: envelope.channel,
      chat_id: envelope.chat_id,
      sender_id: Map.get(envelope.metadata, :sender_id)
    }

    # 2. Append to history map and disk
    new_message = %{role: "user", content: envelope.message.text}
    new_history = state.messages ++ [new_message]

    Mirai.Sessions.Store.append_transcript(state.session_key, new_message)

    # 3. Trigger Agent Run asynchronously
    agent_id = state.agent_id
    _session_pid = self()

    # Ensure agent is running
    agent_pid = case Registry.lookup(Mirai.Tools.Registry, {:agent, agent_id}) do
      [{pid, _}] -> pid
      [] ->
        {:ok, new_pid} = DynamicSupervisor.start_child(
          Mirai.Agents.Supervisor,
          {Mirai.Agents.Worker, [agent_id: agent_id]}
        )
        new_pid
    end

    Mirai.Agents.Worker.run(agent_pid, self(), new_history, reply_context)

    {:noreply, %{state | messages: new_history, reply_context: reply_context}}
  end

  @impl true
  def handle_cast({:append_reply, text}, state) do
    new_message = %{role: "assistant", content: text}

    Mirai.Sessions.Store.append_transcript(state.session_key, new_message)

    # Token estimation (crude proxy: 1 token ~= 4 chars)
    # This prevents unbounded growth until a real tokenizer is added in Phase 2/3
    current_tokens = Enum.map(state.messages, &(String.length(&1.content) / 4)) |> Enum.sum()

    if current_tokens > 8000 do
      Logger.warning("Session #{state.session_key} is exceeding typical context windows (~#{current_tokens} tokens). Compaction needed.")
    end

    {:noreply, %{state | messages: state.messages ++ [new_message]}}
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, state.messages, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:clear_history, _from, state) do
    Logger.info("Session #{state.session_key} history cleared.")
    Mirai.Sessions.Store.delete_session(state.session_key)
    {:reply, :ok, %{state | messages: []}}
  end
end
