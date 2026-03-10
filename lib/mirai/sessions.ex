defmodule Mirai.Sessions do
  @moduledoc """
  Context module for managing and observing active Interlink chat sessions.
  """

  @doc """
  Returns a list of all active session worker states across the local node.
  """
  def list_active_sessions do
    # Find all PIDs registered under the {:session, key} format
    Registry.select(Mirai.Tools.Registry, [{{{:session, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {_key, pid} ->
      try do
        Mirai.Sessions.Worker.get_state(pid)
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    # Sort by number of messages descending as a proxy for "most active"
    |> Enum.sort_by(fn state -> length(state.messages) end, :desc)
  end

  @doc """
  Gets the state of a specific session by its key.
  """
  def get_session(session_key) do
    case Registry.lookup(Mirai.Tools.Registry, {:session, session_key}) do
      [{pid, _}] ->
        try do
          Mirai.Sessions.Worker.get_state(pid)
        catch
          :exit, _ -> nil
        end
      [] -> nil
    end
  end
end
