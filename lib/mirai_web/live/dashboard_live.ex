defmodule MiraiWeb.DashboardLive do
  use MiraiWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mirai.PubSub, "dashboard:nodes")
    end

    node_id = "local_#{Node.self() |> to_string() |> String.replace("@", "_")}"
    current_node = Mirai.Dashboard.NodeRegistry.list_nodes() |> Enum.find(& &1.id == node_id)
                   || Mirai.Dashboard.NodeRegistry.list_nodes() |> List.first()

    {:ok, assign(socket,
      node: current_node,
      metrics: (if current_node, do: current_node.metrics, else: %{})
    )}
  end

  def handle_info({:node_update, updated_node}, socket) do
    if socket.assigns.node && socket.assigns.node.id == updated_node.id do
      {:noreply, assign(socket, node: updated_node, metrics: updated_node.metrics)}
    else
      {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if @node do %>
        <div>
          <h1 class="text-2xl font-bold text-slate-900 tracking-tight"><%= @node.name %></h1>
          <p class="text-sm text-slate-500 mt-1">Overall System Status — Last heartbeat: <span class="font-mono bg-slate-100 px-1 py-0.5 rounded"><%= @node.last_heartbeat %></span></p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 flex flex-col justify-between">
            <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-2">CPU Usage</h3>
            <div class="text-4xl font-bold text-slate-900 tracking-tight"><%= @metrics.cpu_percent %><span class="text-2xl text-slate-400">%</span></div>
          </div>
          <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 flex flex-col justify-between">
            <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-2">Memory</h3>
            <div class="text-4xl font-bold text-slate-900 tracking-tight"><%= @metrics.memory_mb %><span class="text-lg text-slate-400 ml-1">MB</span></div>
          </div>
          <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 flex flex-col justify-between">
            <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-2">Active Agents</h3>
            <div class="text-4xl font-bold text-slate-900 tracking-tight"><%= @metrics.active_agents %></div>
          </div>
          <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 flex flex-col justify-between">
            <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-2">Sessions</h3>
            <div class="text-4xl font-bold text-slate-900 tracking-tight"><%= @metrics.active_sessions %></div>
          </div>
        </div>

        <div class="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden mt-8">
          <div class="px-6 py-4 border-b border-slate-200 bg-slate-50/50">
            <h2 class="text-lg font-semibold text-slate-800">Node Information</h2>
          </div>
          <table class="w-full text-left border-collapse">
            <thead class="bg-slate-50 border-b border-slate-200 text-xs font-semibold text-slate-500 uppercase tracking-wider">
              <tr>
                <th class="px-6 py-4">Property</th>
                <th class="px-6 py-4">Value</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100 text-sm">
              <tr class="hover:bg-slate-50 transition-colors">
                <td class="px-6 py-4 font-medium text-slate-900">Node ID</td>
                <td class="px-6 py-4 text-slate-600 font-mono text-xs"><%= @node.id %></td>
              </tr>
              <tr class="hover:bg-slate-50 transition-colors">
                <td class="px-6 py-4 font-medium text-slate-900">Internal Host</td>
                <td class="px-6 py-4 text-slate-600 font-mono text-xs"><%= @node.host %></td>
              </tr>
              <tr class="hover:bg-slate-50 transition-colors">
                <td class="px-6 py-4 font-medium text-slate-900">Status</td>
                <td class="px-6 py-4">
                  <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-bold uppercase tracking-wider #{if @node.status == "online", do: "bg-emerald-100 text-emerald-800", else: "bg-red-100 text-red-800"}"}>
                    <%= @node.status %>
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

      <% else %>
        <div class="text-center py-20 bg-white rounded-xl shadow-sm border border-slate-200">
          <svg class="mx-auto h-12 w-12 text-slate-300 animate-pulse" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"/></svg>
          <h1 class="mt-4 text-xl font-semibold text-slate-900">Discovering Node...</h1>
          <p class="mt-2 text-sm text-slate-500">Awaiting status broadcast from the cluster.</p>
        </div>
      <% end %>
    </div>
    """
  end
end
