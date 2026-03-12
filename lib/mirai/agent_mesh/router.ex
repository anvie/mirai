defmodule Mirai.AgentMesh.Router do
  @moduledoc """
  Subscribes to Phoenix.PubSub to handle cross-node agent communication.
  It listens to both the global mesh topic and its specific node topic.
  """

  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    # Subscribe to the global topic for unknown locations
    Phoenix.PubSub.subscribe(Mirai.PubSub, "agent_mesh:global")
    # Subscribe to the node-specific topic for targeted messages
    Phoenix.PubSub.subscribe(Mirai.PubSub, "agent_mesh:#{node()}")

    Logger.info("AgentMesh.Router started and subscribed to PubSub topics on node #{node()}")
    {:ok, %{}}
  end

  @impl true
  def handle_info(%Mirai.AgentMesh.Message{} = mesh_msg, state) do
    target_agent_id = mesh_msg.to.agent_id
    
    # Check if the target agent has an active session locally
    # Note: agents might have multiple sessions, but we'll default to the standard mesh or global session key based on ID
    target_session_key = "agent:#{target_agent_id}:mesh:direct:global"

    pid = case Registry.lookup(Mirai.Tools.Registry, {:session, target_session_key}) do
      [{pid, _}] -> pid
      [] ->
        # For this PoC, if we receive it explicitly targeted at this node, or globally,
        # we will spawn the agent if it doesn't exist to ensure delivery.
        # In a fully distributed horde cluster, we might only spawn if this is the designated node.
        Logger.info("AgentMesh.Router: Spawning new session for agent #{target_agent_id} on node #{node()}")
        {:ok, new_pid} = DynamicSupervisor.start_child(
          Mirai.Sessions.Supervisor,
          {Mirai.Sessions.Worker, [session_key: target_session_key]}
        )
        new_pid
    end

    # Send mock envelope so the agent session worker processes it
    from_agent_id = mesh_msg.from.agent_id
    mock_env = %Mirai.Envelope{
      id: mesh_msg.id,
      channel: :agent_mesh,
      chat_id: target_session_key,
      chat_type: :direct,
      sender: %{id: from_agent_id, name: "Agent #{from_agent_id} (Node: #{mesh_msg.from.node})", username: from_agent_id},
      message: %{
        id: mesh_msg.id,
        text: "Incoming AgentMesh Message: #{mesh_msg.payload}",
        attachments: [],
        reply_to: nil,
        timestamp: mesh_msg.timestamp
      },
      metadata: %{}
    }

    Mirai.Sessions.Worker.append_message(pid, mock_env)
    Logger.debug("AgentMesh.Router: Processed incoming message for agent #{target_agent_id}")

    {:noreply, state}
  end

  # Catch-all for other PubSub noise if any
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
