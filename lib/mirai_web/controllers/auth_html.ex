defmodule MiraiWeb.AuthHTML do
  use MiraiWeb, :html

  def login(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>Login - Mirai Dashboard</title>
        <script src="https://cdn.tailwindcss.com"></script>
        <style>
          @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
          body { font-family: 'Inter', sans-serif; }
        </style>
      </head>
      <body class="bg-slate-50 text-slate-900 h-screen flex items-center justify-center p-4 selection:bg-blue-200">
        <div class="w-full max-w-sm bg-white rounded-2xl shadow-xl border border-slate-100 p-8">
          <div class="text-center mb-8">
            <h1 class="text-3xl font-bold text-slate-900 tracking-tight flex items-center justify-center gap-2">
              <span class="text-3xl">🤖</span> Mirai
            </h1>
            <p class="text-sm text-slate-500 mt-2">Sign in to control your agent network</p>
          </div>

          <%= if Phoenix.Flash.get(@flash, :error) do %>
            <div class="mb-6 p-4 rounded-lg bg-red-50 text-red-700 text-sm border border-red-100 flex items-start gap-3">
              <svg class="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
              <span><%= Phoenix.Flash.get(@flash, :error) %></span>
            </div>
          <% end %>

          <%= if Phoenix.Flash.get(@flash, :info) do %>
            <div class="mb-6 p-4 rounded-lg bg-emerald-50 text-emerald-700 text-sm border border-emerald-100 flex items-start gap-3">
              <svg class="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
              <span><%= Phoenix.Flash.get(@flash, :info) %></span>
            </div>
          <% end %>

          <form action="/login" method="post" class="space-y-6">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />

            <div class="space-y-2">
              <label for="username" class="block text-sm font-medium text-slate-700">Username</label>
              <input type="text" id="username" name="user[username]" required autofocus
                class="w-full px-4 py-3 rounded-lg border border-slate-200 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 transition-all"
                placeholder="root" />
            </div>

            <div class="space-y-2">
              <label for="password" class="block text-sm font-medium text-slate-700">Password</label>
              <input type="password" id="password" name="user[password]" required
                class="w-full px-4 py-3 rounded-lg border border-slate-200 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 transition-all"
                placeholder="••••••••" />
            </div>

            <button type="submit" class="w-full py-3 px-4 bg-slate-900 hover:bg-slate-800 text-white font-medium rounded-lg transition-colors focus:ring-4 focus:ring-slate-900/20">
              Access Interlink
            </button>
          </form>
        </div>
      </body>
    </html>
    """
  end
end
