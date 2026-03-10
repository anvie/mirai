defmodule MiraiWeb.SessionsLive do
  use MiraiWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Refresh every 3 seconds to keep session list reasonably updated
      :timer.send_interval(3000, self(), :tick)
    end

    {:ok, assign(socket, sessions: Mirai.Sessions.list_active_sessions())}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, sessions: Mirai.Sessions.list_active_sessions())}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-6xl space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold text-slate-900 tracking-tight">Active Sessions</h1>
          <p class="text-sm text-slate-500 mt-1">Live overview of connected chat channels routing to your agents.</p>
        </div>
        <div class="flex items-center gap-2 px-3 py-1.5 bg-white border border-slate-200 rounded-full text-xs font-semibold text-slate-600 shadow-sm">
          <span class="flex h-2 w-2 relative">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75"></span>
            <span class="relative inline-flex rounded-full h-2 w-2 bg-blue-500"></span>
          </span>
          Live Sync
        </div>
      </div>

      <div class="bg-white border border-slate-200 shadow-sm rounded-xl overflow-hidden">
        <%= if Enum.empty?(@sessions) do %>
          <div class="p-12 text-center flex flex-col items-center">
            <div class="h-16 w-16 bg-slate-50 border border-slate-100 rounded-2xl flex items-center justify-center mb-4">
              <svg class="w-8 h-8 text-slate-300" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"/></svg>
            </div>
            <h3 class="text-base font-semibold text-slate-900">No active sessions</h3>
            <p class="text-sm text-slate-500 mt-1 max-w-sm">There are currently no active conversations being managed by your agents.</p>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="w-full text-left border-collapse whitespace-nowrap">
              <thead class="bg-slate-50/80 border-b border-slate-200 text-xs font-semibold text-slate-500 uppercase tracking-wider">
                <tr>
                  <th class="px-6 py-4">Session ID</th>
                  <th class="px-6 py-4">Handling Agent</th>
                  <th class="px-6 py-4">Channel Origin</th>
                  <th class="px-6 py-4 text-center">Messages</th>
                  <th class="px-6 py-4 text-right">Action</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100 text-sm">
                <%= for session <- @sessions do %>
                  <tr class="hover:bg-slate-50/50 transition-colors group">
                    <td class="px-6 py-4">
                      <div class="flex items-center gap-3">
                        <div class="w-8 h-8 rounded-full bg-blue-50 text-blue-600 flex items-center justify-center shrink-0 border border-blue-100">
                          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 8h2a2 2 0 012 2v6a2 2 0 01-2 2h-2v4l-4-4H9a1.994 1.994 0 01-1.414-.586m0 0L11 14h4a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2v4l.586-.586z"/></svg>
                        </div>
                        <div class="flex flex-col">
                          <span class="font-mono font-medium text-slate-900 text-xs"><%= session.session_key %></span>
                        </div>
                      </div>
                    </td>
                    <td class="px-6 py-4">
                      <span class="inline-flex items-center px-2.5 py-0.5 rounded-md text-xs font-semibold bg-violet-100 text-violet-800 border border-violet-200">
                        <%= session.agent_id %>
                      </span>
                    </td>
                    <td class="px-6 py-4">
                      <%= if session.reply_context do %>
                        <div class="flex items-center gap-1.5">
                          <span class="w-1.5 h-1.5 rounded-full bg-slate-400"></span>
                          <span class="text-slate-600 font-medium capitalize"><%= session.reply_context.channel %></span>
                        </div>
                      <% else %>
                        <span class="text-slate-400 italic">Unknown</span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 text-center">
                      <span class="inline-flex items-center justify-center min-w-[2rem] px-1.5 py-0.5 rounded-full bg-slate-100 text-slate-600 font-bold text-xs">
                        <%= length(session.messages) %>
                      </span>
                    </td>
                    <td class="px-6 py-4 text-right">
                      <a href={"/sessions/#{session.session_key}"} class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white border border-slate-200 text-slate-700 text-xs font-semibold rounded-lg hover:bg-slate-50 hover:text-blue-600 hover:border-blue-200 transition-all opacity-0 group-hover:opacity-100">
                        View Chat
                        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/></svg>
                      </a>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
