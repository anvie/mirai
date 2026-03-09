defmodule Mirai.Tools.SendFile do
  @behaviour Mirai.Tools.Tool

  @impl true
  def name, do: "send_file"

  @impl true
  def description, do: "Send a file from the workspace to the user. Use this after creating/writing a file that the user requested."

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        path: %{
          type: "string",
          description: "Relative path to the file in the workspace to send"
        },
        caption: %{
          type: "string",
          description: "Optional caption for the file"
        }
      },
      required: ["path"]
    }
  end

  @impl true
  def execute(%{"path" => path} = params, context) do
    workspace = Map.get(context, :workspace, "~/.mirai/workspace") |> Path.expand()
    target_path = Path.expand(path, workspace)
    caption = Map.get(params, "caption", "")

    cond do
      not String.starts_with?(target_path, workspace) ->
        {:error, "Access denied: path #{path} is outside the workspace."}

      not File.exists?(target_path) ->
        {:error, "File not found: #{path}"}

      true ->
        reply_context = %{
          channel: Map.get(context, :channel),
          chat_id: Map.get(context, :chat_id)
        }

        case Mirai.Channels.Outbound.send_file(reply_context, target_path, caption) do
          {:ok, _} -> {:ok, "File '#{Path.basename(target_path)}' sent successfully."}
          {:error, reason} -> {:error, "Failed to send file: #{inspect(reason)}"}
        end
    end
  end
end
