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
      metrics: (if selected_node, do: selected_node.metrics, else: %{}),
      authenticated_nodes: %{},
      show_auth_form: false
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

  def handle_event("connect_node", %{"node_name" => node_name}, socket) do
    if node_name == "" do
      {:noreply, socket}
    else
      node_atom = String.to_atom(node_name)
      if Node.connect(node_atom) do
        {:noreply, put_flash(socket, :info, "Successfully connected to #{node_name}. It will soon appear in the list.")}
      else
        {:noreply, put_flash(socket, :error, "Failed to connect to #{node_name}. Please ensure the node is running and the cookie matches.")}
      end
    end
  end

  def handle_event("select_node", %{"id" => id}, socket) do
    node = Enum.find(socket.assigns.nodes, fn n -> n.id == id end)
    {:noreply, assign(socket, selected_node: node, metrics: node.metrics, show_auth_form: false)}
  end

  def handle_event("toggle_auth_form", _, socket) do
    {:noreply, assign(socket, show_auth_form: !Map.get(socket.assigns, :show_auth_form, false))}
  end

  def handle_event("authenticate_node", %{"password" => password}, socket) do
    node = socket.assigns.selected_node

    if node do
      target_node = String.to_atom(node.id)

      # Handle local vs remote checks
      valid_password =
        if node.id == "local_mirai_1" do
          Application.get_env(:mirai, :node_password) == password
        else
          try do
            case :rpc.call(target_node, Application, :get_env, [:mirai, :node_password], 5000) do
              {:badrpc, _reason} -> false
              remote_pass -> remote_pass == password
            end
          catch
            _, _ -> false
          end
        end

      if valid_password do
        auth_nodes = Map.put(socket.assigns.authenticated_nodes, node.id, true)
        {:noreply,
         socket
         |> assign(authenticated_nodes: auth_nodes, show_auth_form: false)
         |> put_flash(:info, "Successfully authenticated with #{node.name}")}
      else
        {:noreply, put_flash(socket, :error, "Invalid password for #{node.name}")}
      end
    else
      {:noreply, socket}
    end
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

        <form phx-submit="connect_node" class="flex items-center gap-2">
          <input type="text" name="node_name" placeholder="node@hostname" required class="flex-1 rounded-lg border-slate-300 shadow-sm text-sm focus:border-blue-500 focus:ring-blue-500 py-2 h-[38px]" />
          <button type="submit" class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-2 rounded-lg text-sm font-medium transition-colors h-[38px] flex items-center shrink-0">
            <svg class="w-4 h-4 mr-1.5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
            Connect
          </button>
        </form>

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
          <% is_authenticated = Map.get(@authenticated_nodes, @selected_node.id, false) %>
          <div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
            <div class="flex items-center justify-between mb-4">
              <h1 class="text-2xl font-bold text-slate-900 tracking-tight"><%= @selected_node.name %> Status</h1>
              <%= if not is_authenticated do %>
                <button phx-click="toggle_auth_form" class="bg-violet-600 hover:bg-violet-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors flex items-center shadow-sm">
                  <svg class="w-4 h-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/></svg>
                  Access Node
                </button>
              <% else %>
                <span class="inline-flex items-center gap-1.5 px-3 py-1 rounded-md bg-emerald-50 text-emerald-700 font-medium text-sm">
                  <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z"/></svg>
                  Authenticated
                </span>
              <% end %>
            </div>

            <%= if Map.get(assigns, :show_auth_form, false) and not is_authenticated do %>
              <div class="mb-8 p-4 bg-slate-50 border border-slate-200 rounded-lg">
                <form phx-submit="authenticate_node" class="flex gap-3 items-end">
                  <div class="flex-1 max-w-sm">
                    <label class="block text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1.5">Node Password</label>
                    <input type="password" name="password" required autofocus class="w-full rounded-lg border-slate-300 shadow-sm text-sm focus:border-violet-500 focus:ring-violet-500" placeholder="Enter node password..." />
                  </div>
                  <button type="submit" class="bg-slate-900 hover:bg-slate-800 text-white px-4 py-2 mt-[22px] h-[38px] rounded-lg text-sm font-medium transition-colors">
                    Unlock
                  </button>
                </form>
              </div>
            <% end %>

            <%= if is_authenticated do %>
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
            <% else %>
               <div class="mb-8 p-5 bg-slate-50 rounded-lg border border-slate-100 flex items-center gap-4">
                  <div class="w-10 h-10 rounded-full bg-slate-200 flex items-center justify-center shrink-0">
                    <svg class="w-5 h-5 text-slate-500" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/></svg>
                  </div>
                  <div>
                    <h3 class="text-sm font-semibold text-slate-900">Metrics are locked</h3>
                    <p class="text-sm text-slate-500 mt-0.5">Please unlock this node to view its full vitals and configuration.</p>
                  </div>
               </div>
            <% end %>

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
