defmodule Mirai.Tools.Read do
  @behaviour Mirai.Tools.Tool

  @impl true
  def name, do: "read"

  @impl true
  def description, do: "Read the contents of a file inside the AI's workspace."

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        path: %{
          type: "string",
          description: "Relative path to the file to read, e.g. 'src/main.js' or 'notes.txt'"
        }
      },
      required: ["path"]
    }
  end

  @impl true
  def execute(%{"path" => path}, context) do
    # Simple sandbox path resolution to ensure we don't escape workspace
    workspace = Map.get(context, :workspace, "~/.mirai/workspace") |> Path.expand()
    target_path = Path.expand(path, workspace)

    # Path traversal protection
    if not String.starts_with?(target_path, workspace) do
      {:error, "Access denied: path #{path} is outside the workspace."}
    else
      case File.read(target_path) do
        {:ok, content} -> {:ok, content}
        {:error, :enoent} -> {:error, "File not found"}
        {:error, reason} -> {:error, "Failed to read: #{inspect(reason)}"}
      end
    end
  end
end
