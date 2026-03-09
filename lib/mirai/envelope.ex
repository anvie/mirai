defmodule Mirai.Envelope do
  @type chat_type :: :direct | :group | :channel | :thread
  @type attachment :: map()

  @type t :: %__MODULE__{
    id: String.t(),
    channel: atom(),
    account_id: String.t(),
    chat_type: chat_type(),
    chat_id: String.t(),
    sender: %{
      id: String.t(),
      name: String.t() | nil,
      username: String.t() | nil
    },
    message: %{
      id: String.t(),
      text: String.t() | nil,
      attachments: [attachment()],
      reply_to: String.t() | nil,
      timestamp: DateTime.t()
    },
    metadata: map()
  }

  defstruct [:id, :channel, :account_id, :chat_type, :chat_id,
             :sender, :message, :metadata]
end
