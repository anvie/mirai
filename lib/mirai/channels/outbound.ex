defmodule Mirai.Channels.Outbound do
  @moduledoc """
  Channel-agnostic outbound message dispatcher.
  All outbound messaging (text, files, typing indicators) goes through here.
  """
  require Logger

  @doc "Send a text message to the user."
  def send_text(reply_context, text, opts \\ []) do
    channel = Map.get(reply_context, :channel)
    chat_id = Map.get(reply_context, :chat_id)
    dispatch(:send_text, channel, chat_id, %{text: text, opts: opts})
  end

  @doc "Send a typing/processing indicator."
  def send_typing(reply_context) do
    channel = Map.get(reply_context, :channel)
    chat_id = Map.get(reply_context, :chat_id)
    dispatch(:send_typing, channel, chat_id, %{})
  end

  @doc "Send a file to the user."
  def send_file(reply_context, file_path, caption \\ "") do
    channel = Map.get(reply_context, :channel)
    chat_id = Map.get(reply_context, :chat_id)
    dispatch(:send_file, channel, chat_id, %{file_path: file_path, caption: caption})
  end

  # ── Telegram ──

  defp dispatch(:send_text, :telegram, chat_id, %{text: text, opts: opts}) do
    case Telegex.send_message(chat_id, text, opts) do
      {:ok, _msg} -> {:ok, :sent}
      {:error, reason} ->
        Logger.error("Telegram send_text failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp dispatch(:send_typing, :telegram, chat_id, _) do
    Telegex.send_chat_action(chat_id, "typing")
    :ok
  end

  defp dispatch(:send_file, :telegram, chat_id, %{file_path: file_path, caption: caption}) do
    token = Application.get_env(:mirai, :telegram_bot_token)
    url = "https://api.telegram.org/bot#{token}/sendDocument"

    args = [
      "-s", "-X", "POST", url,
      "-F", "chat_id=#{chat_id}",
      "-F", "document=@#{file_path}",
      "-F", "caption=#{caption}"
    ]

    case System.cmd("curl", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"ok" => true}} -> {:ok, :sent}
          {:ok, %{"ok" => false, "description" => desc}} -> {:error, desc}
          _ -> {:ok, :sent}
        end
      {output, code} ->
        {:error, "curl failed (exit #{code}): #{String.slice(output, 0, 200)}"}
    end
  end

  # ── WhatsApp ──

  defp dispatch(:send_text, :whatsapp, chat_id, %{text: text}) do
    token = Application.get_env(:mirai, :whatsapp_api_token)
    phone_id = Application.get_env(:mirai, :whatsapp_phone_number_id)
    url = "https://graph.facebook.com/v18.0/#{phone_id}/messages"

    payload = Jason.encode!(%{
      messaging_product: "whatsapp",
      to: chat_id,
      type: "text",
      text: %{body: text}
    })

    args = [
      "-s", "-X", "POST", url,
      "-H", "Authorization: Bearer #{token}",
      "-H", "Content-Type: application/json",
      "-d", payload
    ]

    case System.cmd("curl", args, stderr_to_stdout: true) do
      {_, 0} -> {:ok, :sent}
      {err, _} -> {:error, "WhatsApp send failed: #{String.slice(err, 0, 200)}"}
    end
  end

  defp dispatch(:send_typing, :whatsapp, _chat_id, _), do: :ok

  defp dispatch(:send_file, :whatsapp, chat_id, %{file_path: file_path, caption: caption}) do
    token = Application.get_env(:mirai, :whatsapp_api_token)
    phone_id = Application.get_env(:mirai, :whatsapp_phone_number_id)
    upload_url = "https://graph.facebook.com/v18.0/#{phone_id}/media"

    upload_args = [
      "-s", "-X", "POST", upload_url,
      "-H", "Authorization: Bearer #{token}",
      "-F", "file=@#{file_path}",
      "-F", "messaging_product=whatsapp",
      "-F", "type=#{mime_type(file_path)}"
    ]

    case System.cmd("curl", upload_args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"id" => media_id}} ->
            send_url = "https://graph.facebook.com/v18.0/#{phone_id}/messages"
            payload = Jason.encode!(%{
              messaging_product: "whatsapp",
              to: chat_id,
              type: "document",
              document: %{id: media_id, caption: caption, filename: Path.basename(file_path)}
            })

            send_args = [
              "-s", "-X", "POST", send_url,
              "-H", "Authorization: Bearer #{token}",
              "-H", "Content-Type: application/json",
              "-d", payload
            ]

            case System.cmd("curl", send_args, stderr_to_stdout: true) do
              {_, 0} -> {:ok, :sent}
              {err, _} -> {:error, "WhatsApp send failed: #{String.slice(err, 0, 200)}"}
            end

          {:ok, %{"error" => %{"message" => msg}}} ->
            {:error, "WhatsApp upload error: #{msg}"}

          _ ->
            {:error, "WhatsApp upload failed: #{String.slice(output, 0, 200)}"}
        end
      {output, code} ->
        {:error, "curl failed (exit #{code}): #{String.slice(output, 0, 200)}"}
    end
  end

  # ── Fallback ──

  defp dispatch(action, channel, _chat_id, _data) do
    Logger.warning("No outbound handler for #{action} on channel #{inspect(channel)}")
    {:error, "Channel #{inspect(channel)} does not support #{action}"}
  end

  # ── Helpers ──

  defp mime_type(path) do
    case Path.extname(path) |> String.downcase() do
      ".pdf"  -> "application/pdf"
      ".md"   -> "text/markdown"
      ".txt"  -> "text/plain"
      ".json" -> "application/json"
      ".csv"  -> "text/csv"
      ".png"  -> "image/png"
      ".jpg"  -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".zip"  -> "application/zip"
      _       -> "application/octet-stream"
    end
  end
end
