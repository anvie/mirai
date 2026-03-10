defmodule MiraiWeb.NodesLive do
  use MiraiWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mirai.PubSub, "dashboard:nodes")
    end

    nodes = Mirai.Dashboard.NodeRegistry.list_nodes()
    selected_node = List.first(nodes)

    {:ok, assign(socket,
      nodes: nodes,
      selected_node: selected_node,
      metrics: (if selected_node, do: selected_node.metrics, else: %{})
    )}
  end

  def handle_info({:node_update, updated_node}, socket) do
    nodes = Enum.map(socket.assigns.nodes, fn node ->
      if node.id == updated_node.id, do: updated_node, else: node
    end)

    socket = assign(socket, :nodes, nodes)

    if socket.assigns.selected_node && socket.assigns.selected_node.id == updated_node.id do
      {:noreply, assign(socket, selected_node: updated_node, metrics: updated_node.metrics)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_node", %{"id" => id}, socket) do
    node = Enum.find(socket.assigns.nodes, fn n -> n.id == id end)
    {:noreply, assign(socket, selected_node: node, metrics: node.metrics)}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col lg:flex-row gap-8">
      <!-- Node Selector -->
      <div class="w-full lg:w-80 shrink-0 space-y-4">
        <div>
           <h2 class="text-xl font-bold text-slate-900 tracking-tight">Connected Nodes</h2>
           <p class="text-sm text-slate-500 mt-1">Select a node from the cluster to inspect its vitals.</p>
        </div>
        <div class="space-y-3">
          <%= for node <- @nodes do %>
            <button class={"flex w-full text-left p-4 rounded-xl border transition-all duration-200 #{if @selected_node && @selected_node.id == node.id, do: "bg-white border-blue-500 shadow-md ring-1 ring-blue-500", else: "bg-white/50 border-slate-200 hover:bg-white hover:border-slate-300 hover:shadow-sm"}"} phx-click="select_node" phx-value-id={node.id}>
              <div class="flex-1 min-w-0">
                <div class="flex items-center justify-between mb-1 gap-2">
                  <span class="font-bold text-slate-900 truncate"><%= node.name %></span>
                  <span class={"shrink-0 inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wider #{if node.status == "online", do: "bg-emerald-100 text-emerald-700", else: "bg-red-100 text-red-700"}"}><%= node.status %></span>
                </div>
                <div class="text-xs text-slate-500 font-mono truncate"><%= node.host %></div>
              </div>
            </button>
          <% end %>
        </div>
      </div>

      <!-- Node Metrics -->
      <div class="flex-1 space-y-6">
        <%= if @selected_node do %>
          <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
            <h1 class="text-2xl font-bold text-slate-900 tracking-tight mb-4"><%= @selected_node.name %> Status</h1>

            <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4 mb-8">
              <div class="bg-slate-50 rounded-lg p-4 border border-slate-100">
                <h3 class="text-[11px] font-semibold text-slate-500 uppercase tracking-wider mb-1">CPU Usage</h3>
                <div class="text-3xl font-bold text-slate-900"><%= @metrics.cpu_percent %><span class="text-lg text-slate-400">%</span></div>
              </div>
              <div class="bg-slate-50 rounded-lg p-4 border border-slate-100">
                <h3 class="text-[11px] font-semibold text-slate-500 uppercase tracking-wider mb-1">Memory</h3>
                <div class="text-3xl font-bold text-slate-900"><%= @metrics.memory_mb %><span class="text-sm text-slate-400 ml-1">MB</span></div>
              </div>
              <div class="bg-slate-50 rounded-lg p-4 border border-slate-100">
                <h3 class="text-[11px] font-semibold text-slate-500 uppercase tracking-wider mb-1">Active Agents</h3>
                <div class="text-3xl font-bold text-slate-900"><%= @metrics.active_agents %></div>
              </div>
              <div class="bg-slate-50 rounded-lg p-4 border border-slate-100">
                <h3 class="text-[11px] font-semibold text-slate-500 uppercase tracking-wider mb-1">Sessions</h3>
                <div class="text-3xl font-bold text-slate-900"><%= @metrics.active_sessions %></div>
              </div>
            </div>

            <h2 class="text-base font-semibold text-slate-800 mb-3">Node Details</h2>
            <div class="overflow-x-auto">
              <table class="w-full text-left text-sm whitespace-nowrap">
                <tbody class="divide-y divide-slate-100">
                  <tr>
                    <td class="py-3 pr-4 font-medium text-slate-500 w-32">Node ID</td>
                    <td class="py-3 text-slate-900 font-mono text-xs"><%= @selected_node.id %></td>
                  </tr>
                  <tr>
                    <td class="py-3 pr-4 font-medium text-slate-500">Internal Host</td>
                    <td class="py-3 text-slate-900 font-mono text-xs"><%= @selected_node.host %></td>
                  </tr>
                  <tr>
                    <td class="py-3 pr-4 font-medium text-slate-500">Last Heartbeat</td>
                    <td class="py-3 text-slate-900 font-mono text-xs"><%= @selected_node.last_heartbeat %></td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

        <% else %>
          <div class="text-center py-20 bg-white rounded-xl border border-dashed border-slate-300">
            <svg class="mx-auto h-12 w-12 text-slate-300" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
            <h3 class="mt-4 text-sm font-medium text-slate-900">No node selected</h3>
            <p class="mt-1 text-sm text-slate-500">Select a node from the cluster list to view its metrics.</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
