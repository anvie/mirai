defmodule Mirai.Tools.Exec do
  @behaviour Mirai.Tools.Tool

  @impl true
  def name, do: "execute_command"

  @impl true
  def description, do: "Execute a shell command inside the workspace directory. Use this to run bash commands, list files, compile code, etc."

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        command: %{
          type: "string",
          description: "The complete shell command to execute"
        },
        timeout: %{
          type: "integer",
          description: "Optional timeout in milliseconds. Defaults to 30000"
        }
      },
      required: ["command"]
    }
  end

  @impl true
  def execute(%{"command" => cmd}, context) do
    workspace = Map.get(context, :workspace, "~/.mirai/workspace") |> Path.expand()

    opts = [
      cd: workspace,
      stderr_to_stdout: true
    ]

    try do
      case System.cmd("sh", ["-c", cmd], opts) do
        {output, 0} ->
          {:ok, output}
        {output, code} ->
          final_output = if output == "", do: "Process exited with code #{code}", else: output
          {:error, "Exit #{code}: #{final_output}"}
      end
    rescue
      e -> {:error, "Execution failed: #{inspect(e)}"}
    end
  end
end
