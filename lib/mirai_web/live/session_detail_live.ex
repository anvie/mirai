defmodule MiraiWeb.SessionDetailLive do
  use MiraiWeb, :live_view

  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mirai.PubSub, "session:#{id}")
    end

    session_data = Mirai.Sessions.get_session(id)

    {:ok, assign(socket, session_id: id, session_data: session_data)}
  end

  def handle_info({:new_message, message}, socket) do
    if socket.assigns.session_data do
      updated_data = %{socket.assigns.session_data | messages: socket.assigns.session_data.messages ++ [message]}
      {:noreply, assign(socket, session_data: updated_data)}
    else
      {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="h-[calc(100vh-8rem)] flex flex-col">
      <!-- Header -->
      <div class="flex items-center justify-between mb-4 shrink-0">
        <div class="flex items-center gap-4">
          <a href="/sessions" class="p-2 text-slate-400 hover:text-slate-600 transition-colors bg-white rounded-lg border border-slate-200 shadow-sm hover:bg-slate-50">
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"/></svg>
          </a>
          <div>
            <h1 class="text-xl font-bold text-slate-900 tracking-tight flex items-center gap-3">
              Session Detail
              <%= if @session_data do %>
                <span class="px-2 py-0.5 bg-emerald-100 text-emerald-800 text-xs rounded-full border border-emerald-200">Active</span>
              <% else %>
                <span class="px-2 py-0.5 bg-slate-100 text-slate-600 text-xs rounded-full border border-slate-200">Archived / Process Dead</span>
              <% end %>
            </h1>
            <p class="text-sm font-mono text-slate-500 mt-0.5"><%= @session_id %></p>
          </div>
        </div>

        <%= if @session_data do %>
          <div class="flex items-center gap-4 text-sm bg-white px-4 py-2 border border-slate-200 shadow-sm rounded-xl">
            <div class="flex items-center gap-2 border-r border-slate-200 pr-4">
              <span class="text-slate-500">Agent:</span>
              <span class="font-semibold text-violet-700 bg-violet-50 px-2 py-0.5 rounded border border-violet-100"><%= @session_data.agent_id %></span>
            </div>
            <%= if @session_data.reply_context do %>
              <div class="flex items-center gap-2">
                <span class="text-slate-500">Channel:</span>
                <span class="font-medium text-slate-700 capitalize"><%= @session_data.reply_context.channel %></span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Chat History Area -->
      <div class="flex-1 bg-white border border-slate-200 shadow-sm rounded-2xl overflow-hidden flex flex-col">
        <%= if is_nil(@session_data) do %>
          <div class="flex-1 flex flex-col items-center justify-center p-8 text-center bg-slate-50/50">
            <svg class="w-12 h-12 text-slate-300 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
            <h3 class="text-lg font-semibold text-slate-900">Session not found</h3>
            <p class="text-slate-500 max-w-sm mt-2">The requested session could not be found in active memory. It may have expired or the worker crashed.</p>
          </div>
        <% else %>
          <!-- Messages -->
          <div class="flex-1 overflow-y-auto p-6 space-y-6" id="chat-container" phx-hook="ScrollToBottom">
            <%= if Enum.empty?(@session_data.messages) do %>
              <div class="h-full flex items-center justify-center text-sm text-slate-400">
                Waiting for first message...
              </div>
            <% else %>
              <%= for msg <- @session_data.messages do %>
                <div class={"flex #{if msg.role == "user", do: "justify-end", else: "justify-start"}"}>
                  <div class={"flex flex-col max-w-[80%] #{if msg.role == "user", do: "items-end", else: "items-start"}"}>
                    <span class="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-1 px-1">
                      <%= if msg.role == "user", do: "User", else: "Agent (#{@session_data.agent_id})" %>
                    </span>
                    <div class={"px-5 py-3.5 rounded-2xl whitespace-pre-wrap leading-relaxed shadow-sm
                      #{if msg.role == "user",
                          do: "bg-blue-600 text-white rounded-tr-sm",
                          else: "bg-slate-50 border border-slate-200 text-slate-800 rounded-tl-sm"}"}>
                      <%= msg.content %>
                    </div>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
