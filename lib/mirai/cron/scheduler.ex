defmodule Mirai.Cron.Scheduler do
  # use Quantum, otp_app: :mirai

  def start_link(opts) do
     # STUB, real quantum impl later
     GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  use GenServer

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end
end
