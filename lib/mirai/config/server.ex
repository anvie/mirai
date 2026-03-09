defmodule Mirai.Config.Server do
  use GenServer
  require Logger

  @default_workspace "~/.mirai/workspace"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    config_file = Path.expand("data/config.yml")

    # 1. Read YAML
    if not File.exists?(config_file) do
      Logger.error("CRITICAL: Initial Configuration missing. You MUST stop the server and run `mix mirai.setup` first to generate your keys and configuration.", ansi_color: :red)
      # Sleep forcefully to give them time to read before supervisor restats it, though ideally we'd application.stop
      Process.sleep(5000)
      System.halt(1)
    end

    yaml_config = case YamlElixir.read_from_file(config_file) do
      {:ok, config} -> config
      {:error, _} -> %{}
    end

    # 2. Extract System Config
    system_config = yaml_config["system"] || %{}
    workspace_dir = Map.get(system_config, "workspace_dir", @default_workspace)
                    |> Path.expand()
    log_level = String.to_atom(Map.get(system_config, "log_level", "info"))
    admin_user_id = Map.get(system_config, "admin_user_id", nil)

    # 3. Extract Agents/Mesh Config
    agents_config = yaml_config["agents"] || %{}
    mesh_config = yaml_config["mesh"] || %{}

    # 4. Push to Application Env for global access
    Application.put_env(:mirai, :workspace_dir, workspace_dir)
    Application.put_env(:mirai, :admin_user_id, admin_user_id)
    Application.put_env(:mirai, :agents,
      default_provider: Map.get(agents_config, "default_provider", "anthropic")
    )
    Application.put_env(:mirai, :mesh,
      node_name: Map.get(mesh_config, "node_name", "mirai_primary")
    )

    # 5. Configure Telegex bot token from OS environment
    telegram_token = System.get_env("TELEGRAM_BOT_TOKEN")
    if telegram_token && telegram_token != "" do
      Application.put_env(:telegex, :token, telegram_token)
      Logger.info("Telegram bot token configured.")
    else
      Logger.warning("TELEGRAM_BOT_TOKEN not set — Telegram polling will fail.")
    end

    # 6. Initialization
    File.mkdir_p!(workspace_dir)
    Logger.configure(level: log_level)
    Logger.info("Mirai Configuration loaded from data/config.yml. Workspace: #{workspace_dir}")

    {:ok, %{workspace_dir: workspace_dir, loaded_from: config_file}}
  end
end
