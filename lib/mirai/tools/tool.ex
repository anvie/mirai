defmodule Mirai.Tools.Tool do
  @moduledoc """
  Behaviour for Mirai Agent Tools.
  """

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback parameters() :: map()
  @callback execute(params :: map(), context :: map()) :: {:ok, String.t()} | {:error, String.t()}
end
