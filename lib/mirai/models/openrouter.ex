defmodule Mirai.Models.OpenRouter do
  @behaviour Mirai.Models.Provider
  require Logger

  @api_url "https://openrouter.ai/api/v1/chat/completions"
  @default_model "anthropic/claude-3-5-sonnet:beta"

  @impl true
  def chat_completion(messages, opts \\ []) do
    api_key = Keyword.get(opts, :api_key) || System.get_env("OPENROUTER_API_KEY")

    unless api_key do
      {:error, "API key not found"}
    else
      model = Keyword.get(opts, :model) || System.get_env("OPENROUTER_MODEL") || @default_model

      # Translate tools to OpenAI format
      tools = Keyword.get(opts, :tools, [])
      openrouter_tools = Enum.map(tools, fn t ->
        %{
          type: "function",
          function: %{
            name: t.name,
            description: t.description,
            parameters: t.input_schema
          }
        }
      end)

      # Translate messages to OpenAI format
      formatted_messages = translate_messages(messages)

      payload = %{
        model: model,
        messages: formatted_messages
      }

      payload = if openrouter_tools != [], do: Map.put(payload, :tools, openrouter_tools), else: payload

      request_url = Keyword.get(opts, :api_url, @api_url)

      req_opts = [
        url: request_url,
        json: payload,
        headers: [
          {"Authorization", "Bearer #{api_key}"},
          {"HTTP-Referer", "https://github.com/mirai"},
          {"X-Title", "Mirai"},
          {"content-type", "application/json"}
        ]
      ]

      case Req.post(req_opts) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          # Return the entire content block list so AgentLoop can parse tool uses
          try do
            message = hd(body["choices"])["message"]
            content = message["content"]
            tool_calls = message["tool_calls"] || []

            content_blocks = []
            content_blocks = if content && content != "", do: [%{"type" => "text", "text" => content}] ++ content_blocks, else: content_blocks

            tool_blocks = Enum.map(tool_calls, fn tc ->
              raw_name = tc["function"]["name"] || ""
              raw_args = tc["function"]["arguments"] || "{}"

              # Some models put args in the name, e.g. "write_file report.md"
              # Split and recover
              {name, extra_arg} = case String.split(raw_name, " ", parts: 2) do
                [n, extra] -> {n, extra}
                [n] -> {n, nil}
              end

              args = case Jason.decode(raw_args) do
                {:ok, parsed} when is_map(parsed) -> parsed
                _ -> %{}
              end

              # If model put filename in tool name, try to inject it into args
              args = if extra_arg && map_size(args) > 0 do
                cond do
                  name in ["write_file", "read_file", "send_file"] && !Map.has_key?(args, "path") ->
                    Map.put(args, "path", extra_arg)
                  true -> args
                end
              else
                args
              end

              %{
                "type" => "tool_use",
                "id" => tc["id"],
                "name" => name,
                "input" => args
              }
            end)

            {:ok, content_blocks ++ tool_blocks}
          rescue
            e ->
              Logger.error("Failed parsing OpenRouter response: #{inspect(e)}")
              {:error, "Unexpected API response format"}
          end

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error("OpenRouter API Error [#{status}]: #{inspect(body)}")
          {:error, "API returned status #{status}"}

        {:error, exception} ->
          Logger.error("OpenRouter Request Failed: #{inspect(exception)}")
          {:error, exception}
      end
    end
  end

  defp translate_messages(messages) do
    messages
    |> Enum.flat_map(fn msg ->
      role = get_field(msg, :role)

      case role do
        "system" ->
          [%{role: "system", content: get_field(msg, :content)}]

        "user" ->
          content = get_field(msg, :content)
          if is_list(content) do
            # Check if it's a tool_result list
            first = List.first(content)
            if first && get_field(first, :type) == "tool_result" do
              Enum.map(content, fn res ->
                %{
                  role: "tool",
                  tool_call_id: get_field(res, :tool_use_id),
                  content: to_string(get_field(res, :content))
                }
              end)
            else
              [%{role: "user", content: inspect(content)}]
            end
          else
            [%{role: "user", content: content}]
          end

        "assistant" ->
          content = get_field(msg, :content)
          if is_list(content) do
            text_block = Enum.find(content, fn b -> get_field(b, :type) == "text" end)
            text = if text_block, do: get_field(text_block, :text), else: nil
            tool_uses = Enum.filter(content, fn b -> get_field(b, :type) == "tool_use" end)

            if tool_uses == [] do
              [%{role: "assistant", content: text || ""}]
            else
              tool_calls = Enum.map(tool_uses, fn t ->
                input = get_field(t, :input) || %{}
                %{
                  type: "function",
                  id: get_field(t, :id),
                  function: %{
                    name: get_field(t, :name),
                    arguments: Jason.encode!(input)
                  }
                }
              end)

              base = %{role: "assistant", tool_calls: tool_calls}
              base = if text, do: Map.put(base, :content, text), else: Map.put(base, :content, nil)
              [base]
            end
          else
            [%{role: "assistant", content: content}]
          end

        _ ->
          []
      end
    end)
  end

  # Robust field accessor: works with both atom and string keys
  defp get_field(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  @impl true
  def stream_completion(_messages, _opts, _callback) do
    {:error, :not_implemented}
  end

  @impl true
  def cancel_stream(_stream_ref) do
    :ok
  end

  @impl true
  def get_token_count(_messages) do
    {:ok, 0}
  end
end
