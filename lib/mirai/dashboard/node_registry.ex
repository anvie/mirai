defmodule Mirai.Dashboard.NodeRegistry do
  use GenServer

  @heartbeat_interval 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_heartbeat()

    # Register self as a node
    self_node = %{
      id: "local_mirai_1",
      name: "Mirai Primary Node",
      host: "localhost",
      status: "online",
      last_heartbeat: DateTime.utc_now(),
      metrics: gather_metrics()
    }

    {:ok, %{nodes: %{self_node.id => self_node}}}
  end

  def list_nodes do
    GenServer.call(__MODULE__, :list)
  end

  def get_node(id) do
    GenServer.call(__MODULE__, {:get, id})
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.nodes), state}
  end

  def handle_call({:get, id}, _from, state) do
    {:reply, Map.get(state.nodes, id), state}
  end

  def handle_info(:heartbeat, state) do
    # Update our own metrics
    self_node = state.nodes["local_mirai_1"]
    updated_node = %{self_node |
      last_heartbeat: DateTime.utc_now(),
      metrics: gather_metrics()
    }

    new_state = %{state | nodes: %{"local_mirai_1" => updated_node}}

    # Broadcast to Phoenix LiveView
    Phoenix.PubSub.broadcast(Mirai.PubSub, "dashboard:nodes", {:node_update, updated_node})

    schedule_heartbeat()
    {:noreply, new_state}
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
  end

  defp gather_metrics do
    # STUB: we will query the supervisor for real agent counts
    active_sessions = DynamicSupervisor.count_children(Mirai.Sessions.Supervisor).active
    active_agents = DynamicSupervisor.count_children(Mirai.Agents.Supervisor).active

    %{
      cpu_percent: 15, # stub
      memory_mb: 256, # stub
      active_sessions: active_sessions,
      active_agents: active_agents
    }
  end
end
