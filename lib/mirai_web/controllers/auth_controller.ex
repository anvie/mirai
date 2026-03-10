defmodule MiraiWeb.AuthController do
  use MiraiWeb, :controller

  def login_page(conn, _params) do
    render(conn, :login, layout: false)
  end

  def login(conn, %{"user" => %{"username" => username, "password" => password}}) do
    # Hardcoded authentication as per spec
    if username == "root" and password == "mirai" do
      conn
      |> put_session(:authenticated, true)
      |> configure_session(renew: true)
      |> redirect(to: "/")
    else
      conn
      |> put_flash(:error, "Invalid username or password.")
      |> redirect(to: "/login")
    end
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Successfully logged out.")
    |> redirect(to: "/login")
  end
end
