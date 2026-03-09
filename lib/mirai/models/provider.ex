defmodule Mirai.Models.Provider do
  @callback chat_completion(messages :: list(), opts :: keyword()) :: {:ok, response :: term()} | {:error, reason :: term()}
  @callback stream_completion(messages :: list(), opts :: keyword(), callback :: function()) :: {:ok, stream_ref :: term()} | {:error, reason :: term()}
  @callback cancel_stream(stream_ref :: term()) :: :ok
  @callback get_token_count(messages :: list()) :: {:ok, count :: non_neg_integer()} | {:error, reason :: term()}
end
