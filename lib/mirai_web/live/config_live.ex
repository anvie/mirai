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
    <div class="max-w-4xl space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-slate-900 tracking-tight">Configuration Editor</h1>
        <p class="text-sm text-slate-500 mt-1">Edit the raw configuration files below. Changes take effect on "Save" immediately without restarting the server.</p>
      </div>

      <%= if Phoenix.Flash.get(@flash, :info) do %>
        <div class="p-4 rounded-lg bg-emerald-50 text-emerald-700 text-sm border border-emerald-100 flex items-start gap-3 cursor-pointer" phx-click="lv:clear-flash" phx-value-key="info">
          <svg class="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
          <span><%= Phoenix.Flash.get(@flash, :info) %></span>
        </div>
      <% end %>

      <%= if Phoenix.Flash.get(@flash, :error) do %>
        <div class="p-4 rounded-lg bg-red-50 text-red-700 text-sm border border-red-100 flex items-start gap-3 cursor-pointer" phx-click="lv:clear-flash" phx-value-key="error">
          <svg class="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
          <span><%= Phoenix.Flash.get(@flash, :error) %></span>
        </div>
      <% end %>

      <div class="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden">
        <!-- Tabs -->
        <div class="flex border-b border-slate-200 bg-slate-50 px-4">
          <button phx-click="switch_tab" phx-value-tab="config" class={"px-6 py-4 text-sm font-medium border-b-2 transition-colors focus:outline-none #{if @active_tab == "config", do: "border-blue-500 text-blue-600", else: "border-transparent text-slate-500 hover:text-slate-700 hover:border-slate-300"}"}>
            <div class="flex items-center gap-2">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/></svg>
              config.yml
            </div>
          </button>
          <button phx-click="switch_tab" phx-value-tab="env" class={"px-6 py-4 text-sm font-medium border-b-2 transition-colors focus:outline-none #{if @active_tab == "env", do: "border-blue-500 text-blue-600", else: "border-transparent text-slate-500 hover:text-slate-700 hover:border-slate-300"}"}>
            <div class="flex items-center gap-2">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/></svg>
              .env
            </div>
          </button>
        </div>

        <!-- Editor Area -->
        <div class="p-6">
          <%= if @active_tab == "config" do %>
            <form phx-submit="save" class="space-y-4">
              <input type="hidden" name="file" value="config.yml" />
              <div class="relative">
                <textarea name="content" rows="22" spellcheck="false" class="w-full font-mono text-sm leading-relaxed p-4 bg-slate-900 text-slate-100 rounded-lg border border-slate-800 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-y"><%= @config_yml %></textarea>
                <div class="absolute top-3 right-4 px-2 py-1 rounded bg-slate-800 text-slate-400 text-[10px] font-bold tracking-wider uppercase pointer-events-none">YAML</div>
              </div>
              <div class="flex justify-end">
                <button type="submit" class="inline-flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white px-5 py-2.5 rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-4 focus:ring-blue-500/20 shadow-sm">
                  <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"/></svg>
                  Save Configuration
                </button>
              </div>
            </form>
          <% else %>
            <form phx-submit="save" class="space-y-4">
              <input type="hidden" name="file" value=".env" />
              <div class="relative">
                <textarea name="content" rows="18" spellcheck="false" class="w-full font-mono text-sm leading-relaxed p-4 bg-slate-900 text-slate-100 rounded-lg border border-slate-800 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-y"><%= @dotenv %></textarea>
                <div class="absolute top-3 right-4 px-2 py-1 rounded bg-slate-800 text-slate-400 text-[10px] font-bold tracking-wider uppercase pointer-events-none">ENV</div>
              </div>
              <div class="flex justify-end">
                <button type="submit" class="inline-flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white px-5 py-2.5 rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-4 focus:ring-blue-500/20 shadow-sm">
                  <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"/></svg>
                  Save Environment
                </button>
              </div>
            </form>
          <% end %>
        </div>
      </div>
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
