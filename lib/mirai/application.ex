defmodule Mirai.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    print_banner()
    Mirai.UserPrefs.init()

    children = [
      Mirai.Config.Server,
      {Phoenix.PubSub, name: Mirai.PubSub},
      Mirai.Cron.Scheduler,
      Mirai.Metrics.Collector,
      {Registry, keys: :unique, name: Mirai.Tools.Registry},
      {DynamicSupervisor, name: Mirai.Channels.Supervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: Mirai.Agents.Supervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: Mirai.Sessions.Supervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: Mirai.Plugins.Manager, strategy: :one_for_one},
      Mirai.Gateway.Supervisor,
      Mirai.Dashboard.NodeRegistry,
      Mirai.AgentMesh.Router,
      MiraiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: Mirai.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp print_banner do
    env = Mix.env()
    hot_reload = if env == :dev, do: "✅ ON (exsync)", else: "❌ OFF"
    port = Application.get_env(:mirai, MiraiWeb.Endpoint)[:port] |> to_string()

    IO.puts("""

    ╔══════════════════════════════════════════╗
    ║            🤖 MIRAI ENGINE               ║
    ╠══════════════════════════════════════════╣
    ║  Mode:        #{String.pad_trailing(to_string(env), 25)} ║
    ║  Hot Reload:  #{String.pad_trailing(hot_reload, 25)} ║
    ║  Port:        #{String.pad_trailing(port, 25)} ║
    ║  Node:        #{String.pad_trailing(to_string(Node.self()), 25)} ║
    ╚══════════════════════════════════════════╝
    """)
  end
end
