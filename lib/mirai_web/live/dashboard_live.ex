defmodule MiraiWeb.DashboardLive do
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
    # Update the nodes list
    nodes = Enum.map(socket.assigns.nodes, fn node ->
      if node.id == updated_node.id, do: updated_node, else: node
    end)

    socket = assign(socket, :nodes, nodes)

    # Update metrics if we are looking at the updated node
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
    <div class="dashboard">
      <aside class="sidebar">
        <h2>Cluster Nodes</h2>
        <ul class="node-list">
          <%= for node <- @nodes do %>
            <li class={"node-item #{if @selected_node && @selected_node.id == node.id, do: "active"}"} phx-click="select_node" phx-value-id={node.id}>
              <span class={"status-badge #{node.status}"}><%= node.status %></span><br/>
              <b><%= node.name %></b><br/>
              <small><%= node.host %></small>
            </li>
          <% end %>
        </ul>
      </aside>

      <main class="content">
        <%= if @selected_node do %>
          <h1><%= @selected_node.name %> Status</h1>
          <p>Last heartbeat: <%= @selected_node.last_heartbeat %></p>

          <div class="metrics-grid">
            <div class="metric-card">
              <h3>CPU Usage</h3>
              <div class="value"><%= @metrics.cpu_percent %>%</div>
            </div>
            <div class="metric-card">
              <h3>Memory Usage</h3>
              <div class="value"><%= @metrics.memory_mb %> MB</div>
            </div>
            <div class="metric-card">
              <h3>Active Agents</h3>
              <div class="value"><%= @metrics.active_agents %></div>
            </div>
            <div class="metric-card">
              <h3>Active Sessions</h3>
              <div class="value"><%= @metrics.active_sessions %></div>
            </div>
          </div>

          <h2>Node Information</h2>
          <table>
            <thead>
              <tr>
                <th>Property</th>
                <th>Value</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>ID</td>
                <td><%= @selected_node.id %></td>
              </tr>
              <tr>
                <td>Host</td>
                <td><%= @selected_node.host %></td>
              </tr>
            </tbody>
          </table>

        <% else %>
          <h1>Welcome to Mirai Dashboard</h1>
          <p>Select a node from the sidebar to view metrics.</p>
        <% end %>
      </main>
    </div>
    """
  end
end
