defmodule AtmosphericHooverWeb.FirehoseLive do
  @moduledoc """
  LiveView displaying the raw firehose with search/filter capability.
  Shows all posts in real-time with the ability to filter by text content.
  """

  use AtmosphericHooverWeb, :live_view

  @max_posts 100
  @colors [
    "bg-pink-100 border-pink-300",
    "bg-purple-100 border-purple-300",
    "bg-indigo-100 border-indigo-300",
    "bg-blue-100 border-blue-300",
    "bg-cyan-100 border-cyan-300",
    "bg-teal-100 border-teal-300",
    "bg-emerald-100 border-emerald-300",
    "bg-green-100 border-green-300",
    "bg-lime-100 border-lime-300",
    "bg-yellow-100 border-yellow-300",
    "bg-amber-100 border-amber-300",
    "bg-orange-100 border-orange-300",
    "bg-rose-100 border-rose-300"
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AtmosphericHoover.PubSub, "firehose:events")
    end

    {:ok,
     assign(socket,
       page_title: "Firehose",
       posts: [],
       filter: "",
       stats: %{total: 0, matched: 0, rate: 0},
       paused: false,
       last_rate_check: System.monotonic_time(:second),
       rate_count: 0
     ), layout: false}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, filter: filter)}
  end

  def handle_event("toggle_pause", _, socket) do
    {:noreply, assign(socket, paused: not socket.assigns.paused)}
  end

  def handle_event("clear", _, socket) do
    {:noreply, assign(socket, posts: [])}
  end

  @impl true
  def handle_info({:firehose_event, event}, socket) do
    if socket.assigns.paused do
      {:noreply, socket}
    else
      socket = update_rate(socket)
      stats = %{socket.assigns.stats | total: socket.assigns.stats.total + 1}

      if is_post?(event) do
        text = get_text(event)
        filter = socket.assigns.filter

        if matches_filter?(text, filter) do
          post = build_post(event)
          posts = [post | socket.assigns.posts] |> Enum.take(@max_posts)
          stats = %{stats | matched: stats.matched + 1}
          {:noreply, assign(socket, posts: posts, stats: stats)}
        else
          {:noreply, assign(socket, stats: stats)}
        end
      else
        {:noreply, assign(socket, stats: stats)}
      end
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp update_rate(socket) do
    now = System.monotonic_time(:second)

    if now > socket.assigns.last_rate_check do
      rate = socket.assigns.rate_count
      stats = %{socket.assigns.stats | rate: rate}
      assign(socket, stats: stats, last_rate_check: now, rate_count: 1)
    else
      assign(socket, rate_count: socket.assigns.rate_count + 1)
    end
  end

  defp is_post?(event) do
    event.kind == :commit &&
      event.commit &&
      event.commit.collection == "app.bsky.feed.post" &&
      event.commit.operation == :create &&
      event.commit.record
  end

  defp get_text(event) do
    event.commit.record.text || ""
  end

  defp matches_filter?(_text, ""), do: true
  defp matches_filter?(nil, _filter), do: false

  defp matches_filter?(text, filter) do
    String.contains?(String.downcase(text), String.downcase(filter))
  end

  defp build_post(event) do
    %{
      id: "post-#{System.unique_integer([:positive])}",
      text: event.commit.record.text || "",
      did: event.did,
      rkey: event.commit.rkey,
      color: Enum.random(@colors),
      timestamp: DateTime.utc_now()
    }
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp highlight_text(text, ""), do: text

  defp highlight_text(text, filter) do
    case Regex.compile(Regex.escape(filter), "i") do
      {:ok, regex} ->
        Regex.replace(regex, text, fn match ->
          "<mark class=\"bg-yellow-300 dark:bg-yellow-600 rounded px-0.5\">#{match}</mark>"
        end)

      _ ->
        text
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-pink-100 via-purple-100 to-blue-100 dark:from-gray-900 dark:via-purple-900 dark:to-blue-900">
      <nav class="fixed top-0 left-0 right-0 z-50 bg-white/90 dark:bg-gray-800/90 backdrop-blur-sm border-b border-gray-200 dark:border-gray-700">
        <div class="px-4 py-3">
          <div class="flex items-center justify-between mb-3">
            <div class="flex items-center gap-4">
              <h1 class="text-xl font-bold bg-gradient-to-r from-pink-500 to-purple-500 bg-clip-text text-transparent">
                Firehose
              </h1>
              <.link navigate={~p"/grid"} class="btn btn-sm btn-ghost">
                Grid View
              </.link>
            </div>
            <div class="flex items-center gap-4 text-sm text-gray-500 dark:text-gray-400">
              <span><span class="font-mono">{@stats.rate}</span>/sec</span>
              <span><span class="font-mono">{@stats.total}</span> total</span>
              <span><span class="font-mono">{@stats.matched}</span> matched</span>
            </div>
          </div>

          <div class="flex items-center gap-3">
            <form phx-change="filter" class="flex-1">
              <input
                type="text"
                name="filter"
                value={@filter}
                placeholder="Filter posts by text..."
                class="input input-bordered w-full bg-white dark:bg-gray-700 focus:ring-2 focus:ring-purple-400"
                phx-debounce="150"
              />
            </form>
            <button
              phx-click="toggle_pause"
              class={[
                "btn btn-sm",
                if(@paused, do: "btn-success", else: "btn-warning")
              ]}
            >
              {if @paused, do: "Resume", else: "Pause"}
            </button>
            <button phx-click="clear" class="btn btn-sm btn-ghost">
              Clear
            </button>
          </div>
        </div>
      </nav>

      <div class="pt-28 px-4 pb-4">
        <div class="space-y-2 max-w-4xl mx-auto">
          <%= if @posts == [] do %>
            <div class="text-center py-12 text-gray-500 dark:text-gray-400">
              <%= if @filter != "" do %>
                <p class="text-lg">No posts matching "<span class="font-semibold">{@filter}</span>"</p>
                <p class="text-sm mt-2">Waiting for matching posts...</p>
              <% else %>
                <p class="text-lg">Waiting for posts...</p>
                <p class="text-sm mt-2">Posts will appear here in real-time</p>
              <% end %>
            </div>
          <% else %>
            <%= for post <- @posts do %>
              <div
                id={post.id}
                class={[
                  "p-3 rounded-lg border-l-4 shadow-sm",
                  "transform transition-all duration-300",
                  "animate-slide-in",
                  post.color,
                  "dark:bg-opacity-20 dark:border-opacity-50"
                ]}
              >
                <div class="flex items-start justify-between gap-2">
                  <p class="text-gray-800 dark:text-gray-200 text-sm flex-1 whitespace-pre-wrap break-words">
                    {raw(highlight_text(post.text, @filter))}
                  </p>
                  <span class="text-xs text-gray-400 dark:text-gray-500 whitespace-nowrap">
                    {format_time(post.timestamp)}
                  </span>
                </div>
                <div class="mt-1 text-xs text-gray-500 dark:text-gray-400 font-mono truncate">
                  {String.slice(post.did, 0, 32)}...
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>

    <style>
      @keyframes slideIn {
        from {
          opacity: 0;
          transform: translateY(-20px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      .animate-slide-in {
        animation: slideIn 0.3s ease-out;
      }
    </style>
    """
  end
end
