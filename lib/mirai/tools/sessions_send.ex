defmodule Mirai.Tools.SessionsSend do
  @behaviour Mirai.Tools.Tool

  @impl true
  def name, do: "sessions_send"

  @impl true
  def description, do: "Send a message from the current agent to another agent's session asynchronously."

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        to_agent_id: %{
          type: "string",
          description: "The Agent ID to route the message to."
        },
        payload: %{
          type: "string",
          description: "The message contents or instructions to send."
        }
      },
      required: ["to_agent_id", "payload"]
    }
  end

  @impl true
  def execute(%{"to_agent_id" => to_agent_id, "payload" => payload}, context) do
    # Generate the struct
    # We grab the current agent id out of context if it exists (or fallback to 'unknown')
    from_agent_id = Map.get(context, :agent_id, "unknown")
    session_id = Map.get(context, :session_id, "unknown")

    mesh_msg = Mirai.AgentMesh.Message.new(from_agent_id, session_id, to_agent_id, payload)

    # Broadcast or route the message.
    # Currently for local monolithic operation, we just use a generic local session
    # key for that agent to wake it up. If using Libcluster, this would map to a PubSub broadcast.
    target_session_key = "agent:#{to_agent_id}:mesh:direct:global"

    pid = case Registry.lookup(Mirai.Tools.Registry, {:session, target_session_key}) do
      [{pid, _}] -> pid
      [] ->
        {:ok, new_pid} = DynamicSupervisor.start_child(
          Mirai.Sessions.Supervisor,
          {Mirai.Sessions.Worker, [session_key: target_session_key]}
        )
        new_pid
    end

    # Send mock envelope
    mock_env = %Mirai.Envelope{
      id: mesh_msg.id,
      channel: :agent_mesh,
      chat_id: target_session_key,
      chat_type: :direct,
      sender: %{id: from_agent_id, name: "Agent #{from_agent_id}", username: from_agent_id},
      message: %{
        id: mesh_msg.id,
        text: "Incoming AgentMesh Message: #{payload}",
        attachments: [],
        reply_to: nil,
        timestamp: mesh_msg.timestamp
      },
      metadata: %{}
    }

    Mirai.Sessions.Worker.append_message(pid, mock_env)

    {:ok, "Message #{mesh_msg.id} dispatched to #{to_agent_id}"}
  end
end
