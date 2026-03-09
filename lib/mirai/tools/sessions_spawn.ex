defmodule Mirai.Tools.SessionsSpawn do
  @behaviour Mirai.Tools.Tool

  @impl true
  def name, do: "sessions_spawn"

  @impl true
  def description, do: "Spawn a background subagent to work on a task asynchronously. The subagent runs independently and cannot reply directly to this execution."

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        task: %{
          type: "string",
          description: "Instructions for the subagent to execute"
        },
        agent_id: %{
          type: "string",
          description: "Optional custom agent config ID to use (e.g. 'coder_agent'). Defaults to 'subagent'."
        }
      },
      required: ["task"]
    }
  end

  @impl true
  def execute(%{"task" => task} = params, _context) do
    agent_id = Map.get(params, "agent_id", "subagent")

    # We create a unique session key for this background task.
    # It lives purely in memory/disk and has no chat client attached.
    session_id = "bg_#{System.unique_integer([:positive])}"
    session_key = "agent:#{agent_id}:background:system:#{session_id}"

    case DynamicSupervisor.start_child(
      Mirai.Sessions.Supervisor,
      {Mirai.Sessions.Worker, [session_key: session_key]}
    ) do
      {:ok, pid} ->
        # Send a mock internal message to wake it up
        mock_env = %Mirai.Envelope{
          id: "sys_#{System.unique_integer([:positive])}",
          channel: :system,
          chat_id: session_id,
          chat_type: :background,
          sender: %{id: "system", name: "System", username: "system"},
          message: %{
            id: "msg_#{System.unique_integer([:positive])}",
            text: task,
            attachments: [],
            reply_to: nil,
            timestamp: DateTime.utc_now()
          },
          metadata: %{}
        }

        Mirai.Sessions.Worker.append_message(pid, mock_env)

        {:ok, "Successfully spawned background agent #{agent_id} in session #{session_id}"}

      {:error, reason} ->
        {:error, "Failed to spawn subagent: #{inspect(reason)}"}
    end
  end
end
