defmodule Mirai.Config.Server do
  use GenServer
  require Logger

  @default_workspace "~/.mirai/workspace"

  # Client API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  # Callbacks
  @impl true
  def init(_opts) do
    config_file = Path.expand("data/config.yml")
    do_load(config_file, true)
  end

  @impl true
  def handle_call(:reload, _from, state) do
    Logger.info("Hot-reloading configuration...")
    case do_load(state.loaded_from, false) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      error -> {:reply, error, state}
    end
  end

  defp do_load(config_file, is_init) do

    # 1. Read YAML
    if not File.exists?(config_file) do
      Logger.error("CRITICAL: Initial Configuration missing. You MUST stop the server and run `mix mirai.setup` first to generate your keys and configuration.", ansi_color: :red)
      if is_init do
        Process.sleep(5000)
        System.halt(1)
      end
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

    # 5. Configure Telegex bot token from OS environment or .env directly
    # Re-read .env to easily pick up hot-reloads
    env_file = Path.expand("data/.env")
    if File.exists?(env_file) do
      File.read!(env_file)
      |> String.split("\n", trim: true)
      |> Enum.each(fn line ->
        case String.split(line, "=", parts: 2) do
          [k, v] -> System.put_env(String.trim(k), String.trim(v))
          _ -> :ok
        end
      end)
    end

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
