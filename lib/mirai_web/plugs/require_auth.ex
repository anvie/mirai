defmodule MiraiWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :authenticated) do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access the dashboard.")
      |> redirect(to: "/login")
      |> halt()
    end
  end
end
