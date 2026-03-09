defmodule Mirai.Channels.Worker do
  use GenServer

  @type state :: map()
  
  @callback connect(config :: map()) :: {:ok, state()} | {:error, term()}
  @callback disconnect(state :: state()) :: :ok
  @callback send_message(state :: state(), message :: term()) :: {:ok, message_id :: term()} | {:error, reason :: term()}
  @callback handle_inbound(state :: state(), raw_event :: term()) :: {:ok, envelope :: term()} | :ignore

  defstruct [
    :channel_type,   # :whatsapp | :telegram | :discord | ...
    :account_id,
    :connection,     # channel-specific connection state
    :gateway_pid,
    :config
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    {:ok, %__MODULE__{config: opts}}
  end
end
