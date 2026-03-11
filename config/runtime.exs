import Config

if config_env() != :test do
  config_path = System.get_env("MIRAI_CONFIG_PATH") || Path.expand("../config.yaml", __DIR__)

  yaml_config =
    if File.exists?(config_path) do
      Application.ensure_all_started(:yaml_elixir)
      YamlElixir.read_from_file!(config_path)
    else
      %{}
    end

  server_config = yaml_config["server"] || %{}
  port = Map.get(server_config, "port", 4000)

  default_secret = "xK7Fq2R9sLmN3pJv8wYzA5bD0eHtUi6OcGf1MnQaSdWjXoZlCkIgBrEyPuTvmh4xK7Fq2R9sLmN3pJv8wYzA5bD0eHtUi6OcGf1MnQaSdWjXoZlCkIgBrEyPuTvmh4"
  secret_key_base = Map.get(server_config, "secret_key_base", default_secret)

  node_password = Map.get(server_config, "node_password", "mirai_admin")

  config :mirai, MiraiWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  config :mirai, :node_password, node_password
end
