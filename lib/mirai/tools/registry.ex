defmodule Mirai.Tools.Registry do
  @moduledoc """
  Hardcoded registry mapping for the core Mirai AI tools.
  (In the future, this might be dynamic or per-agent).
  """

  @core_tools [
    Mirai.Tools.Exec,
    Mirai.Tools.Read,
    Mirai.Tools.Write,
    Mirai.Tools.SendFile,
    Mirai.Tools.SessionsSpawn,
    Mirai.Tools.SessionsSend
  ]

  @doc """
  Returns a list of tool schema maps formatted for large language models (specifically Anthropic style).
  """
  def get_all_schemas do
    Enum.map(@core_tools, fn module ->
      %{
        name: module.name(),
        description: module.description(),
        input_schema: module.parameters()
      }
    end)
  end

  @doc """
  Executes a tool by its registered name.
  """
  def execute_tool(name, params, context) do
    case Enum.find(@core_tools, fn mod -> mod.name() == name end) do
      nil -> {:error, "Tool not found: #{name}"}
      module -> module.execute(params, context)
    end
  end
end
