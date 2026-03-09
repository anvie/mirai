defmodule Mirai.Metrics.Collector do
  use GenServer

  def start_link(opts) do
     # STUB: telemetry telemetry_metrics
     GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end
end
