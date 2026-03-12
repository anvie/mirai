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
        },
        node: %{
          type: "string",
          description: "Optional. The specific node name to route to (e.g. 'node1@localhost'). If omitted, it will broadcast to all nodes in the mesh."
        }
      },
      required: ["to_agent_id", "payload"]
    }
  end

  @impl true
  def execute(%{"to_agent_id" => to_agent_id, "payload" => payload} = params, context) do
    # Generate the struct
    # We grab the current agent id out of context if it exists (or fallback to 'unknown')
    from_agent_id = Map.get(context, :agent_id, "unknown")
    session_id = Map.get(context, :session_id, "unknown")
    target_node = Map.get(params, "node", nil)

    # Convert node string to atom if provided
    target_node_atom = if target_node, do: String.to_atom(target_node), else: nil

    mesh_msg = Mirai.AgentMesh.Message.new(from_agent_id, session_id, to_agent_id, payload, target_node_atom)

    topic = if target_node_atom do
      "agent_mesh:#{target_node_atom}"
    else
      "agent_mesh:global"
    end

    Phoenix.PubSub.broadcast(Mirai.PubSub, topic, mesh_msg)

    {:ok, "Message #{mesh_msg.id} dispatched to #{to_agent_id} (Topic: #{topic})"}
  end
end
