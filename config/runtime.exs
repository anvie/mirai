import Config

if config_env() != :test do
  config_path = Path.expand("../config.yaml", __DIR__)

  yaml_config =
    if File.exists?(config_path) do
      Application.ensure_all_started(:yaml_elixir)
      YamlElixir.read_from_file!(config_path)
    else
      %{}
    end

  port = Map.get(yaml_config, "port", 4000)
  
  default_secret = "xK7Fq2R9sLmN3pJv8wYzA5bD0eHtUi6OcGf1MnQaSdWjXoZlCkIgBrEyPuTvmh4xK7Fq2R9sLmN3pJv8wYzA5bD0eHtUi6OcGf1MnQaSdWjXoZlCkIgBrEyPuTvmh4"
  secret_key_base = Map.get(yaml_config, "secret_key_base", default_secret)
  
  node_password = Map.get(yaml_config, "node_password", "mirai_admin")

  config :mirai, MiraiWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  config :mirai, :node_password, node_password
end
