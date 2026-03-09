defmodule Mirai.Sessions.Store do
  @moduledoc """
  Session persistence using JSONL append-only logs for transcripts.
  """
  require Logger

  # Determine workspace from Config instead of hardcoding, but fallback to tmp for now if none.
  defp get_workspace_dir() do
    # STUB: For now, grab it from Config Server if implemented, or fallback
    workspace = Application.get_env(:mirai, :workspace_dir, "~/.mirai/workspace")
    expanded = Path.expand(workspace)
    File.mkdir_p!(expanded)
    expanded
  end

  defp get_transcript_path(session_key) do
    # Sanitize session key for filesystem
    safe_key = String.replace(session_key, ~r/[^a-zA-Z0-9_-]/, "_")
    Path.join([get_workspace_dir(), "sessions", "#{safe_key}.jsonl"])
  end

  @doc """
  Loads the session directly from disk.
  Returns `{:ok, messages}` or `{:ok, []}` if no file found.
  """
  def load_session(session_key) do
    path = get_transcript_path(session_key)

    if File.exists?(path) do
      try do
        lines = File.read!(path) |> String.split("\n", trim: true)

        messages = Enum.map(lines, fn line ->
          case Jason.decode(line, keys: :atoms) do
            {:ok, msg} -> msg
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

        {:ok, messages}
      rescue
        e ->
          Logger.error("Failed to load session #{session_key}: #{inspect(e)}")
          {:ok, []}
      end
    else
      {:ok, []}
    end
  end

  @doc """
  Appends a single JSON representation of an Envelope or Message to the JSONL log.
  """
  def append_transcript(session_key, entry) when is_map(entry) do
    path = get_transcript_path(session_key)

    # Ensure dir exists
    Path.dirname(path) |> File.mkdir_p!()

    case Jason.encode(entry) do
      {:ok, json} ->
        # Use simple File.write with [:append] for now.
        # In a very high-concurrency setup, we'd pipe this to a dedicated file server process.
        case File.write(path, json <> "\n", [:append]) do
          :ok -> :ok
          {:error, reason} ->
            Logger.error("Failed to append transcript to #{path}: #{inspect(reason)}")
            {:error, reason}
        end
      {:error, reason} ->
        Logger.error("Failed to encode transcript entry: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Deletes the on-disk transcript for a session.
  """
  def delete_session(session_key) do
    path = get_transcript_path(session_key)
    if File.exists?(path), do: File.rm(path)
    :ok
  end
end
