defmodule Mirai.Tools.Write do
  @behaviour Mirai.Tools.Tool

  @impl true
  def name, do: "write"

  @impl true
  def description, do: "Create or overwrite a file with given contents in the AI's workspace. If you want to modify, you should usually rewrite the whole file."

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        path: %{
          type: "string",
          description: "Relative path where the file should be saved"
        },
        content: %{
          type: "string",
          description: "The complete file contents to write"
        }
      },
      required: ["path", "content"]
    }
  end

  @impl true
  def execute(%{"path" => path, "content" => content}, context) do
    workspace = Map.get(context, :workspace, "~/.mirai/workspace") |> Path.expand()
    target_path = Path.expand(path, workspace)

    if not String.starts_with?(target_path, workspace) do
      {:error, "Access denied: path #{path} is outside the workspace."}
    else
      Path.dirname(target_path) |> File.mkdir_p!()
      case File.write(target_path, content) do
        :ok -> {:ok, "Successfully wrote #{byte_size(content)} bytes to #{path}"}
        {:error, reason} -> {:error, "Failed to write: #{inspect(reason)}"}
      end
    end
  end
end
