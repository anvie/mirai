defmodule Mirai.UserPrefs do
  @moduledoc """
  Simple ETS-backed per-user preferences (e.g. reasoning toggle).
  """

  @table :mirai_user_prefs

  def init do
    :ets.new(@table, [:named_table, :public, :set])
  end

  def get(user_id, key, default \\ false) do
    case :ets.lookup(@table, {user_id, key}) do
      [{_, val}] -> val
      [] -> default
    end
  end

  def set(user_id, key, value) do
    :ets.insert(@table, {{user_id, key}, value})
  end

  def toggle(user_id, key) do
    current = get(user_id, key, false)
    new_val = !current
    set(user_id, key, new_val)
    new_val
  end
end
