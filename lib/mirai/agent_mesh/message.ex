defmodule Mirai.AgentMesh.Message do
  @moduledoc """
  Defines the format for inter-agent asynchronous communication over the global
  Erlang distribution or local pub/sub.
  """

  @type agent_ref :: %{
    agent_id: String.t(),
    session_id: String.t(),
    node: atom()
  }

  @type t :: %__MODULE__{
    id: String.t(),
    from: agent_ref(),
    to: agent_ref() | nil,
    payload: map() | list() | String.t(),
    context: map(),          # Inherited capabilities/flags
    timestamp: DateTime.t()
  }

  defstruct [
    :id,
    :from,
    :to,
    :payload,
    :context,
    :timestamp
  ]

  @doc """
  Create a new AgentMesh Message struct.
  """
  def new(from_agent_id, session_id, to_agent_id, payload, context \\ %{}) do
    %__MODULE__{
      id: "amn_#{System.unique_integer([:positive])}",
      from: %{
        agent_id: from_agent_id,
        session_id: session_id,
        node: node()
      },
      to: %{
        agent_id: to_agent_id,
        session_id: nil, # determined at routing time if not provided
        node: nil
      },
      payload: payload,
      context: context,
      timestamp: DateTime.utc_now()
    }
  end
end
