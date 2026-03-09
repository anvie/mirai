defmodule Mirai.Models.Anthropic do
  @behaviour Mirai.Models.Provider
  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @default_model "claude-3-5-sonnet-20241022"

  @impl true
  def chat_completion(messages, opts \\ []) do
    api_key = Keyword.get(opts, :api_key) || System.get_env("ANTHROPIC_API_KEY")

    unless api_key do
      {:error, "API key not found"}
    else
      model = Keyword.get(opts, :model, @default_model)
      max_tokens = Keyword.get(opts, :max_tokens, 1024)

      # Anthropic API format requires a specific message structure
      formatted_messages = Enum.map(messages, fn msg ->
        %{role: msg.role, content: msg.content}
      end)

      # Extract system prompt if present (Anthropic treats it separately)
      {system_msgs, other_msgs} = Enum.split_with(formatted_messages, fn m -> m.role == "system" end)
      system_prompt = Enum.map(system_msgs, & &1.content) |> Enum.join("\n")

      tools = Keyword.get(opts, :tools, [])

      payload = %{
        model: model,
        max_tokens: max_tokens,
        messages: other_msgs,
        system: system_prompt
      }

      # Only add tools if provided
      payload = if tools != [], do: Map.put(payload, :tools, tools), else: payload

      req_opts = [
        url: @api_url,
        json: payload,
        headers: [
          {"x-api-key", api_key},
          {"anthropic-version", "2023-06-01"},
          {"content-type", "application/json"}
        ]
      ]

      case Req.post(req_opts) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          # Return the entire content block list so AgentLoop can parse tool uses
          try do
            content_blocks = body["content"]
            {:ok, content_blocks}
          rescue
            _ -> {:error, "Unexpected API response format"}
          end

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error("Anthropic API Error [#{status}]: #{inspect(body)}")
          {:error, "API returned status #{status}"}

        {:error, exception} ->
          Logger.error("Anthropic Request Failed: #{inspect(exception)}")
          {:error, exception}
      end
    end
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
    # STUB: Token counting not implemented for Anthropic locally yet
    {:ok, 0}
  end
end
