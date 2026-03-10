defmodule MiraiWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MiraiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", MiraiWeb do
    pipe_through :browser

    get "/login", AuthController, :login_page
    post "/login", AuthController, :login
    post "/logout", AuthController, :logout
  end

  scope "/", MiraiWeb do
    pipe_through [:browser, MiraiWeb.Plugs.RequireAuth]

    live "/", DashboardLive, :index
    live "/nodes", NodesLive, :index
    live "/config", ConfigLive, :index
  end
end
