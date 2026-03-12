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
    workspace = Application.get_env(:mirai, :workspace_dir) || "~/.mirai/workspace"
    workspace = Path.expand(workspace)

    soul_path = Path.join(workspace, "SOUL.md")
    tools_path = Path.join(workspace, "TOOLS.md")

    soul_content =
      if File.exists?(soul_path) do
        File.read!(soul_path)
      else
        "You are Mirai, an intelligent AI assistant\nKeep your answers concise and helpful. Respond in the same language as the user."
      end

    builtin_tools_content = """
    BUILTIN TOOLS:
    - execute_command: Run shell commands. Example `{"command": "ls -la"}`
    - write_file: Create/overwrite files in the workspace. Example `{"path": "config.json", "content": "{}"}`
    - read_file: Read file contents. Example `{"path": "config.json"}`
    - send_file: Send a file from the workspace to the user's chat. Example `{"path": "image.png", "caption": "Here is the chart"}`
    - sessions_spawn: Spawn a background subagent to work on a task asynchronously. The subagent runs independently and cannot reply directly to this execution. Example `{"task": "Analyze these logs", "agent_id": "log_expert"}`
    - sessions_send: Send a message from the current agent to another agent's session asynchronously. You can optionally route to a specific node by supplying `node`, otherwise it defaults to broadcasting to the cluster. Example `{"to_agent_id": "bob", "payload": "Please review this.", "node": "node2@host"}`

    IMPORTANT RULES:
    - For conversational messages (greetings, questions, chitchat), respond with plain text ONLY. Do NOT call any tools.
    - Only use tools when the user explicitly asks you to read/write files, execute commands, or manage sessions.
    - Never call tools speculatively or in a loop. If a tool result is sufficient, stop and respond to the user.
    - When the user asks you to create a file AND send/deliver it, use write_file first, then send_file with the same path.
    - When the user says "kirim", "send", "deliver", or asks for a file to be sent to them, always use the send_file tool.
    """

    user_tools_content =
      if File.exists?(tools_path) do
        content = File.read!(tools_path) |> String.trim()
        if content != "", do: "\n\nUSER CUSTOM TOOLS:\n" <> content, else: ""
      else
        ""
      end

    tools_content = String.trim(builtin_tools_content) <> user_tools_content

    system_prompt = %{
      role: "system",
      content: String.trim(soul_content) <> "\n\n" <> String.trim(tools_content)
    }

    # Inject system prompt at the beginning of the messages list
    messages_with_system = [system_prompt | loop.messages]
    {:ok, %{loop | messages: messages_with_system}}
  end

  # Execute loop
  defp execute_loop(loop) do
    # Show "typing..." indicator
    if loop.reply_context, do: Mirai.Channels.Outbound.send_typing(loop.reply_context)

    loop
    |> call_model()
    |> handle_response()
  end

  defp call_model(loop) do
    require Logger

    # omit tools to force the model to respond with text.
    tools = if loop.depth == 0 do
      Mirai.Tools.Registry.get_all_schemas()
    else
      []
    end

    openrouter_key = Application.get_env(:mirai, :openrouter_api_key) |> non_blank()
    anthropic_key = Application.get_env(:mirai, :anthropic_api_key) |> non_blank()
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
      final_text = if text_block, do: text_block["text"], else: nil
      final_text = if final_text && String.trim(final_text) != "", do: final_text, else: "(No response generated)"
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
    reasoning_on = reasoning_enabled?(loop)

    tool_results = Enum.map(tool_uses, fn tool_use ->
      name = tool_use["name"]
      id = tool_use["id"]
      params = tool_use["input"] || %{}

      require Logger
      params_str = inspect(params, limit: 3, printable_limit: 120)
      params_str = if String.length(params_str) > 150, do: String.slice(params_str, 0, 150) <> "…", else: params_str
      Logger.info("Tool call: #{name}(#{params_str})")

      # Send reasoning: tool call
      if reasoning_on do
        send_reasoning(loop, "🔧 *Tool:* `#{name}`\n```\n#{params_str}\n```")
      end

      workspace = Application.get_env(:mirai, :workspace_dir) || "~/.mirai/workspace"
      chat_id = get_in(loop, [Access.key(:reply_context), Access.key(:chat_id)])
      channel = get_in(loop, [Access.key(:reply_context), Access.key(:channel)])
      context = %{workspace: workspace, chat_id: chat_id, channel: channel}

      content_str = case Mirai.Tools.Registry.execute_tool(name, params, context) do
        {:ok, result} -> result
        {:error, reason} -> "Error: #{reason}"
      end

      # Send reasoning: tool result (truncated)
      if reasoning_on do
        truncated = if String.length(content_str) > 300, do: String.slice(content_str, 0, 300) <> "\n…(truncated)", else: content_str
        send_reasoning(loop, "📋 *Result:*\n```\n#{truncated}\n```")
      end

      %{
        type: "tool_result",
        tool_use_id: id,
        content: content_str
      }
    end)

    user_msg = %{role: "user", content: tool_results}
    %{loop | messages: loop.messages ++ [user_msg]}
  end

  defp finalize({:ok, loop, final_text}) do
    require Logger

    # 1. Update session history
    Mirai.Sessions.Worker.append_assistant_reply(loop.session_pid, final_text)

    # 2. Send reply via channel-agnostic dispatcher (skip if empty)
    if final_text && String.trim(final_text) != "" do
      case Mirai.Channels.Outbound.send_text(loop.reply_context, final_text) do
        {:ok, _} -> Logger.info("Reply sent to #{loop.reply_context.channel} chat #{loop.reply_context.chat_id}")
        {:error, reason} -> Logger.error("Failed to send reply: #{inspect(reason)}")
      end
    else
      Logger.warning("Skipped sending empty reply")
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

  defp reasoning_enabled?(loop) do
    sender_id = get_in(loop, [Access.key(:reply_context), Access.key(:sender_id)])
    sender_id && Mirai.UserPrefs.get(sender_id, :reasoning, false)
  end

  defp send_reasoning(loop, text) do
    if loop.reply_context do
      Mirai.Channels.Outbound.send_text(loop.reply_context, text, parse_mode: "Markdown")
    end
  end
end
