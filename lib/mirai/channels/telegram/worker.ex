defmodule Mirai.Channels.Telegram.Worker do
  use GenServer
  require Logger

  @behaviour Mirai.Channels.Worker

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Telegram worker started")
    send(self(), :poll)
    {:ok, %{offset: 0}}
  end

  @impl true
  def handle_info(:poll, state) do
    new_offset =
      case Telegex.get_updates(offset: state.offset, timeout: 5) do
        {:ok, []} ->
          state.offset

        {:ok, updates} ->
          Enum.each(updates, &process_update/1)

          max_id = updates |> Enum.map(& &1.update_id) |> Enum.max()
          max_id + 1

        {:error, reason} ->
          Logger.error("Failed to fetch Telegram updates: #{inspect(reason)}")
          state.offset
      end

    Process.send_after(self(), :poll, 1000)
    {:noreply, %{state | offset: new_offset}}
  end

  defp process_update(%Telegex.Type.Update{message: %Telegex.Type.Message{} = msg} = update) do
    text = msg.text || ""
    chat_id = to_string(msg.chat.id)
    Logger.info("Received message: #{inspect(text)}")

    # ── Slash commands ──
    case parse_command(text) do
      {:command, cmd, _args} ->
        handle_command(cmd, chat_id, msg)

      :not_command ->
        # Normal message → route to gateway
        envelope = %Mirai.Envelope{
          id: to_string(msg.message_id),
          channel: :telegram,
          account_id: "telegram_bot",
          chat_type: if(msg.chat.type == "private", do: :direct, else: :group),
          chat_id: chat_id,
          sender: %{
            id: to_string(msg.from.id),
            name: msg.from.first_name,
            username: msg.from.username
          },
          message: %{
            id: to_string(msg.message_id),
            text: text,
            attachments: [],
            reply_to: nil,
            timestamp: DateTime.from_unix!(msg.date)
          },
          metadata: %{update_id: update.update_id, sender_id: to_string(msg.from.id)}
        }

        Mirai.Gateway.Server.route_inbound(envelope)
    end
  end

  defp process_update(_), do: :ok

  # ── Command parsing ──

  defp parse_command("/" <> rest) do
    [cmd | args] = String.split(rest, " ", trim: true)
    # Strip @botname suffix (e.g. /clear@MiraiBot)
    cmd = cmd |> String.split("@") |> hd() |> String.downcase()
    {:command, cmd, args}
  end

  defp parse_command(_), do: :not_command

  # ── Command handlers ──

  defp handle_command("clear", chat_id, msg) do
    session_key = "agent:main:telegram:direct:#{msg.from.id}"

    case Registry.lookup(Mirai.Tools.Registry, {:session, session_key}) do
      [{pid, _}] ->
        Mirai.Sessions.Worker.clear_history(pid)
        Telegex.send_message(chat_id, "🧹 Memory cleared! Starting fresh.")
      [] ->
        Telegex.send_message(chat_id, "🧹 No active session to clear.")
    end
  end

  defp handle_command("status", chat_id, _msg) do
    provider = Application.get_env(:mirai, :agents)[:default_provider] || "anthropic"
    model = System.get_env("OPENROUTER_MODEL") || "(default)"
    uptime = :erlang.statistics(:wall_clock) |> elem(0) |> div(1000)
    mins = div(uptime, 60)
    secs = rem(uptime, 60)

    Telegex.send_message(chat_id, """
    📊 *Mirai Status*
    • Provider: `#{provider}`
    • Model: `#{model}`
    • Uptime: #{mins}m #{secs}s
    • Node: `#{Node.self()}`
    """, parse_mode: "Markdown")
  end

  defp handle_command("model", chat_id, _msg) do
    provider = Application.get_env(:mirai, :agents)[:default_provider] || "anthropic"
    model = System.get_env("OPENROUTER_MODEL") || "(default)"
    Telegex.send_message(chat_id, "🤖 Provider: `#{provider}`\nModel: `#{model}`", parse_mode: "Markdown")
  end

  defp handle_command("reasoning", chat_id, msg) do
    user_id = to_string(msg.from.id)
    new_val = Mirai.UserPrefs.toggle(user_id, :reasoning)
    emoji = if new_val, do: "🔍", else: "🔇"
    status = if new_val, do: "ON — I'll show my thought process", else: "OFF — silent mode"
    Telegex.send_message(chat_id, "#{emoji} Reasoning: *#{status}*", parse_mode: "Markdown")
  end

  defp handle_command("help", chat_id, _msg) do
    Telegex.send_message(chat_id, """
    🤖 *Mirai Commands*

    /clear — Clear conversation memory
    /reasoning — Toggle reasoning view
    /status — Show system status & uptime
    /model — Show current AI model
    /help — Show this help
    """, parse_mode: "Markdown")
  end

  defp handle_command(unknown, chat_id, _msg) do
    Telegex.send_message(chat_id, "❓ Unknown command: /#{unknown}\nType /help to see available commands.")
  end

  # ── Mirai.Channels.Worker callbacks ──

  @impl Mirai.Channels.Worker
  def connect(_config), do: {:ok, %{}}

  @impl Mirai.Channels.Worker
  def disconnect(_state), do: :ok

  @impl Mirai.Channels.Worker
  def send_message(_state, %{chat_id: chat_id, text: text}) do
    case Telegex.send_message(chat_id, text) do
      {:ok, %Telegex.Type.Message{message_id: id}} -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Mirai.Channels.Worker
  def handle_inbound(_state, _raw_event), do: :ignore
end
