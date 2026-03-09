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

  def start_link(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    name = {:via, Registry, {Mirai.Tools.Registry, {:agent, agent_id}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    agent_id = Keyword.get(opts, :agent_id)
    {:ok, %__MODULE__{agent_id: agent_id}}
  end

  # Run agent loop asynchronously
  def run(agent_pid, session_pid, messages, reply_context) do
    GenServer.cast(agent_pid, {:run, session_pid, messages, reply_context})
  end

  @impl true
  def handle_cast({:run, session_pid, messages, reply_context}, state) do
    # Execute the actual reasoning loop inside a separate process to avoid blocking
    # the Agent Worker's mailbox for concurrent requests (if applicable)
    Task.start(fn ->
      case Mirai.AgentLoop.run(session_pid, state.agent_id, messages, reply_context) do
        {:ok, _result} ->
          # Final response sent handled by finalize/1 inside AgentLoop,
          # but we could track completion here.
          :ok
        {:error, reason} ->
          require Logger
          Logger.error("AgentLoop failed: #{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end

  # Get agent state
  def get_config(_agent) do
    %{
      # STUB
    }
  end

  def get_workspace(%__MODULE__{workspace: workspace}), do: workspace
end
