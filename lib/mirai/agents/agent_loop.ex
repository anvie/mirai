defmodule Mirai.AgentLoop do
  @moduledoc """
  The agent loop: intake → context → inference → tools → reply → persist
  """

  defstruct [
    :session_pid,
    :agent_id,
    :messages,
    :reply_context,
    :context,
    :model_config,
    depth: 0
  ]

  # Main entry point from Agent Worker
  def run(session_pid, agent_id, messages, reply_context) do
    loop = %__MODULE__{
      session_pid: session_pid,
      agent_id: agent_id,
      messages: messages,
      reply_context: reply_context
    }

    with {:ok, loop} <- build_context(loop),
         {:ok, _loop} <- execute_loop(loop) do
      {:ok, "success"}
    end
  end

  defp build_context(loop) do
    # STUB: Retrieve agent's specific instructions or system prompt from config
    system_prompt = %{
      role: "system",
      content: """
      You are Mirai, an intelligent AI assistant built on Elixir/OTP.
      Keep your answers concise and helpful.

      IMPORTANT RULES:
      - For conversational messages (greetings, questions, chitchat), respond with plain text ONLY. Do NOT call any tools.
      - Only use tools when the user explicitly asks you to read/write files, execute commands, or manage sessions.
      - Never call tools speculatively or in a loop. If a tool result is sufficient, stop and respond to the user.
      """
    }

    # Inject system prompt at the beginning of the messages list
    messages_with_system = [system_prompt | loop.messages]
    {:ok, %{loop | messages: messages_with_system}}
  end

  # Execute loop
  defp execute_loop(loop) do
    # Show "typing..." indicator in Telegram
    if loop.reply_context do
      case loop.reply_context do
        %{channel: :telegram, chat_id: chat_id} ->
          Telegex.send_chat_action(chat_id, "typing")
        _ -> :ok
      end
    end

    loop
    |> call_model()
    |> handle_response()
  end

  defp call_model(loop) do
    require Logger

    # Only pass tools on the first call. After tool results come back,
    # omit tools to force the model to respond with text.
    tools = if loop.depth == 0 do
      Mirai.Tools.Registry.get_all_schemas()
    else
      []
    end

    openrouter_key = System.get_env("OPENROUTER_API_KEY") |> non_blank()
    anthropic_key = System.get_env("ANTHROPIC_API_KEY") |> non_blank()
    default_provider = Application.get_env(:mirai, :agents)[:default_provider] || "anthropic"

    result =
      cond do
        openrouter_key && default_provider == "openrouter" ->
          Logger.info("Calling OpenRouter model for agent #{loop.agent_id}...")
          Mirai.Models.OpenRouter.chat_completion(loop.messages, tools: tools, api_key: openrouter_key)

        anthropic_key && default_provider == "anthropic" ->
          Logger.info("Calling Anthropic model for agent #{loop.agent_id}...")
          Mirai.Models.Anthropic.chat_completion(loop.messages, tools: tools, api_key: anthropic_key)

        openrouter_key ->
          Logger.info("Calling fallback OpenRouter model for agent #{loop.agent_id}...")
          Mirai.Models.OpenRouter.chat_completion(loop.messages, tools: tools, api_key: openrouter_key)

        true ->
          Logger.info("Calling fallback Anthropic model for agent #{loop.agent_id}...")
          Mirai.Models.Anthropic.chat_completion(loop.messages, tools: tools, api_key: anthropic_key)
      end

    case result do
      {:ok, content_blocks} ->
        {:ok, loop, content_blocks}
      {:error, reason} ->
        Logger.error("Model failure: #{inspect(reason)}")
        {:error, loop, "I'm sorry, my language model encountered an error: #{inspect(reason)}"}
    end
  end

  defp handle_response({:error, loop, error_text}) do
    finalize({:ok, loop, error_text})
  end

  defp handle_response({:ok, loop, content_blocks}) do
    # 1. First, append the assistant's complete response to the memory context so
    # the model knows it asked for tools.
    assistant_msg = %{role: "assistant", content: content_blocks}
    loop = %{loop | messages: loop.messages ++ [assistant_msg]}

    # 2. Check for tool uses
    tool_uses = Enum.filter(content_blocks, fn block -> block["type"] == "tool_use" end)

    if Enum.empty?(tool_uses) do
      # 3a. No tools. Find the text block and finalize.
      text_block = Enum.find(content_blocks, fn b -> b["type"] == "text" end)
      final_text = if text_block, do: text_block["text"], else: ""
      finalize({:ok, loop, final_text})
    else
      # 3b. Execute tools and continue loop (with depth check)
      max_depth = 3

      require Logger
      Logger.info("Tool loop depth: #{loop.depth}/#{max_depth}, tools requested: #{Enum.map(tool_uses, & &1["name"]) |> Enum.join(", ")}")

      if loop.depth >= max_depth do
        Logger.warning("Agent loop hit max recursion depth (#{max_depth}), stopping.")
        text_block = Enum.find(content_blocks, fn b -> b["type"] == "text" end)
        final_text = if text_block, do: text_block["text"], else: "I've reached my processing limit for tool calls. Here's what I found so far."
        finalize({:ok, loop, final_text})
      else
        loop = execute_tools(loop, tool_uses)
        loop = %{loop | depth: loop.depth + 1}
        execute_loop(loop)
      end
    end
  end

  defp execute_tools(loop, tool_uses) do
    # Execute all tools requested by the model (sequentially for now, could be parallel)
    tool_results = Enum.map(tool_uses, fn tool_use ->
      name = tool_use["name"]
      id = tool_use["id"]
      params = tool_use["input"] || %{}

      require Logger
      params_str = inspect(params, limit: 3, printable_limit: 120)
      params_str = if String.length(params_str) > 150, do: String.slice(params_str, 0, 150) <> "…", else: params_str
      Logger.info("Tool call: #{name}(#{params_str})")

      # Use the workspace from config server
      workspace = Application.get_env(:mirai, :workspace_dir) || "~/.mirai/workspace"
      context = %{workspace: workspace}

      # Call the registry dispatcher
      content_str = case Mirai.Tools.Registry.execute_tool(name, params, context) do
        {:ok, result} -> result
        {:error, reason} -> "Error: #{reason}"
      end

      # Format back as tool_result for Anthropic
      %{
        type: "tool_result",
        tool_use_id: id,
        content: content_str
      }
    end)

    # Append the results as a "user" message containing the tool outputs
    user_msg = %{role: "user", content: tool_results}
    %{loop | messages: loop.messages ++ [user_msg]}
  end

  defp finalize({:ok, loop, final_text}) do
    require Logger

    # 1. Update session history
    Mirai.Sessions.Worker.append_assistant_reply(loop.session_pid, final_text)

    # 2. Send reply directly to the channel (NOT back through the gateway!)
    case loop.reply_context do
      %{channel: :telegram, chat_id: chat_id} ->
        case Telegex.send_message(chat_id, final_text) do
          {:ok, _msg} ->
            Logger.info("Reply sent to Telegram chat #{chat_id}")
          {:error, reason} ->
            Logger.error("Failed to send Telegram reply: #{inspect(reason)}")
        end

      other ->
        Logger.warning("No outbound handler for channel: #{inspect(other)}")
    end

    {:ok, loop}
  end

  # Tool execution
  def execute_tool(loop, tool_call) do
    case Registry.lookup(Mirai.Tools.Registry, tool_call.name) do
      [{_pid, tool_module}] ->
        tool_module.execute(tool_call.params, loop.context)
      [] ->
        {:error, :tool_not_found}
    end
  end

  defp non_blank(nil), do: nil
  defp non_blank(""), do: nil
  defp non_blank(val), do: val
end
