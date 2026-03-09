defmodule MiraiWeb.ErrorHTML do
  @moduledoc """
  Fallback error pages for the Mirai web interface.
  """

  use Phoenix.Component

  def render(template, _assigns) do
    status_code = template |> String.split(".") |> hd()

    assigns = %{status_code: status_code}

    ~H"""
    <!DOCTYPE html>
    <html>
      <head><title>Mirai - Error <%= @status_code %></title></head>
      <body style="font-family: sans-serif; text-align: center; padding: 60px;">
        <h1>🤖 Mirai Error <%= @status_code %></h1>
        <p>Something went wrong. Please check the server logs.</p>
      </body>
    </html>
    """
  end
end
