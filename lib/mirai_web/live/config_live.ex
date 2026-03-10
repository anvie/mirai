defmodule MiraiWeb.ConfigLive do
  use MiraiWeb, :live_view

  def mount(_params, _session, socket) do
    config_yml = read_file_safe("data/config.yml")
    dotenv = read_file_safe("data/.env")

    {:ok, assign(socket, config_yml: config_yml, dotenv: dotenv, active_tab: "config")}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  def handle_event("save", %{"file" => "config.yml", "content" => content}, socket) do
    File.write!("data/config.yml", content)
    case Mirai.Config.Server.reload() do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "config.yml saved and configuration hot-reloaded successfully!")
         |> assign(config_yml: content)}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reload config: #{inspect(reason)}")}
    end
  end

  def handle_event("save", %{"file" => ".env", "content" => content}, socket) do
    File.write!("data/.env", content)
    case Mirai.Config.Server.reload() do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, ".env saved and configuration hot-reloaded successfully!")
         |> assign(dotenv: content)}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reload config: #{inspect(reason)}")}
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 style="margin-top: 0;">Configuration Editor</h1>
      <p>Edit the raw configuration files below. Changes take effect immediately without restarting the server.</p>

      <%= if Phoenix.Flash.get(@flash, :info) do %>
        <p class="alert alert-info" style="padding: 10px; background-color: #d1fae5; color: #065f46; border-radius: 5px; margin-bottom: 20px;" role="alert"
          phx-click="lv:clear-flash" phx-value-key="info"><%= Phoenix.Flash.get(@flash, :info) %></p>
      <% end %>

      <%= if Phoenix.Flash.get(@flash, :error) do %>
        <p class="alert alert-danger" style="padding: 10px; background-color: #fee2e2; color: #991b1b; border-radius: 5px; margin-bottom: 20px;" role="alert"
          phx-click="lv:clear-flash" phx-value-key="error"><%= Phoenix.Flash.get(@flash, :error) %></p>
      <% end %>

      <div style="margin-bottom: 20px; border-bottom: 1px solid #e5e7eb;">
        <button phx-click="switch_tab" phx-value-tab="config" style={"padding: 10px 20px; background: none; border: none; font-size: 1rem; cursor: pointer; border-bottom: 3px solid #{if @active_tab == "config", do: "#3b82f6", else: "transparent"}; color: #{if @active_tab == "config", do: "#111827", else: "#6b7280"}; font-weight: #{if @active_tab == "config", do: "bold", else: "normal"};"}>
          config.yml
        </button>
        <button phx-click="switch_tab" phx-value-tab="env" style={"padding: 10px 20px; background: none; border: none; font-size: 1rem; cursor: pointer; border-bottom: 3px solid #{if @active_tab == "env", do: "#3b82f6", else: "transparent"}; color: #{if @active_tab == "env", do: "#111827", else: "#6b7280"}; font-weight: #{if @active_tab == "env", do: "bold", else: "normal"};"}>
          .env
        </button>
      </div>

      <%= if @active_tab == "config" do %>
        <form phx-submit="save">
          <input type="hidden" name="file" value="config.yml" />
          <textarea name="content" rows="20" style="width: 100%; font-family: monospace; padding: 15px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 14px; background: white; resize: vertical;"><%= @config_yml %></textarea>
          <div style="margin-top: 15px;">
            <button type="submit" style="background: #2563eb; color: white; padding: 10px 20px; border: none; border-radius: 5px; font-weight: bold; cursor: pointer;">Save config.yml</button>
          </div>
        </form>
      <% else %>
        <form phx-submit="save">
          <input type="hidden" name="file" value=".env" />
          <textarea name="content" rows="15" style="width: 100%; font-family: monospace; padding: 15px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 14px; background: white; resize: vertical;"><%= @dotenv %></textarea>
          <div style="margin-top: 15px;">
            <button type="submit" style="background: #2563eb; color: white; padding: 10px 20px; border: none; border-radius: 5px; font-weight: bold; cursor: pointer;">Save .env</button>
          </div>
        </form>
      <% end %>

    </div>
    """
  end

  defp read_file_safe(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end
end
