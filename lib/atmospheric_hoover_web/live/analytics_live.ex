defmodule AtmosphericHooverWeb.AnalyticsLive do
  @moduledoc """
  LiveView dashboard for Bluesky analytics powered by ClickHouse.
  Auto-refreshes every 5 seconds.
  """

  use AtmosphericHooverWeb, :live_view

  alias AtmosphericHoover.Clickhouse

  @refresh_interval_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      schedule_refresh()
      # Subscribe to firehose events for real-time counting
      Phoenix.PubSub.subscribe(AtmosphericHoover.PubSub, "firehose:events")
      schedule_rate_calc()
      schedule_minute_tick()
      schedule_chart_push()
    end

    # Initialize 30 minutes of zeros for the live chart
    now = System.system_time(:second)
    current_minute = div(now, 60)

    {:ok,
     socket
     |> assign(
       page_title: "Analytics",
       loading: true,
       live_post_count: 0,
       live_posts_per_sec: 0,
       last_rate_calc: System.monotonic_time(:millisecond),
       # Live chart data: map of minute_timestamp -> count
       live_minute_counts: %{},
       current_minute: current_minute,
       current_minute_count: 0
     )
     |> load_data()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    socket = load_data(socket)

    # Push updates to D3 hooks instead of re-rendering
    socket =
      socket
      |> push_event("update-posts-rate", %{points: socket.assigns.posts_rate})
      |> push_event("update-languages", %{languages: socket.assigns.languages})
      |> push_event("update-hashtags", %{hashtags: socket.assigns.hashtags})
      |> push_event("update-media", %{stats: get_media_stats_map(socket.assigns.media_stats)})
      |> push_event("update-hourly", %{hours: socket.assigns.hourly_stats})

    {:noreply, socket}
  end

  # Handle firehose events for live counting (only count posts)
  @impl true
  def handle_info({:firehose_event, event}, socket) do
    if event.kind == :commit &&
         event.commit &&
         event.commit.collection == "app.bsky.feed.post" &&
         event.commit.operation == :create do
      {:noreply,
       socket
       |> update(:live_post_count, &(&1 + 1))
       |> update(:current_minute_count, &(&1 + 1))}
    else
      {:noreply, socket}
    end
  end

  # Calculate posts per second every second
  @impl true
  def handle_info(:calc_rate, socket) do
    schedule_rate_calc()
    now = System.monotonic_time(:millisecond)
    elapsed = now - socket.assigns.last_rate_calc
    count = socket.assigns.live_post_count

    # Calculate rate (posts per second)
    rate = if elapsed > 0, do: round(count * 1000 / elapsed), else: 0

    {:noreply,
     assign(socket,
       live_posts_per_sec: rate,
       live_post_count: 0,
       last_rate_calc: now
     )}
  end

  # Tick every minute to roll the counts
  @impl true
  def handle_info(:minute_tick, socket) do
    schedule_minute_tick()

    now = System.system_time(:second)
    new_minute = div(now, 60)
    old_minute = socket.assigns.current_minute

    if new_minute > old_minute do
      # Save the count for the completed minute
      updated_counts =
        socket.assigns.live_minute_counts
        |> Map.put(old_minute, socket.assigns.current_minute_count)
        # Keep only last 30 minutes
        |> Enum.filter(fn {min, _} -> min > new_minute - 30 end)
        |> Map.new()

      {:noreply,
       assign(socket,
         live_minute_counts: updated_counts,
         current_minute: new_minute,
         current_minute_count: 0
       )}
    else
      {:noreply, socket}
    end
  end

  # Push chart updates to the frontend every 2 seconds
  @impl true
  def handle_info(:push_chart, socket) do
    schedule_chart_push()

    live_data = build_live_chart_data(socket)

    {:noreply, push_event(socket, "update-live-rate", %{points: live_data})}
  end

  defp build_live_chart_data(socket) do
    now = System.system_time(:second)
    current_minute = div(now, 60)
    counts = socket.assigns.live_minute_counts

    # Build 30 data points, one per minute
    Enum.map(29..0//-1, fn offset ->
      minute = current_minute - offset
      count = if offset == 0 do
        # Current minute - show live count
        socket.assigns.current_minute_count
      else
        Map.get(counts, minute, 0)
      end
      %{"minute" => minute, "count" => count}
    end)
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
  end

  defp schedule_rate_calc do
    Process.send_after(self(), :calc_rate, 1_000)
  end

  defp schedule_minute_tick do
    Process.send_after(self(), :minute_tick, 1_000)
  end

  defp schedule_chart_push do
    Process.send_after(self(), :push_chart, 2_000)
  end

  defp load_data(socket) do
    # Load all analytics data
    {:ok, total_posts} = Clickhouse.post_count()
    {:ok, languages} = Clickhouse.language_stats(24)
    {:ok, hashtags} = Clickhouse.trending_hashtags(1, 20)
    {:ok, posts_rate} = Clickhouse.posts_per_minute(30)
    {:ok, media_stats} = get_media_stats()
    {:ok, hourly_stats} = get_hourly_stats()

    assign(socket,
      loading: false,
      total_posts: total_posts,
      languages: languages,
      hashtags: hashtags,
      posts_rate: posts_rate,
      media_stats: media_stats,
      hourly_stats: hourly_stats,
      last_updated: DateTime.utc_now()
    )
  end

  defp get_media_stats do
    Clickhouse.query("""
    SELECT
      sum(has_images) as images,
      sum(has_video) as videos,
      sum(has_external_link) as links,
      count() as total,
      round(sum(has_images) * 100.0 / count(), 1) as images_pct,
      round(sum(has_video) * 100.0 / count(), 1) as videos_pct,
      round(sum(has_external_link) * 100.0 / count(), 1) as links_pct
    FROM posts
    WHERE created_at >= now() - INTERVAL 24 HOUR
    """)
  end

  defp get_hourly_stats do
    Clickhouse.query("""
    SELECT
      toStartOfHour(created_at) as hour,
      count() as posts,
      uniq(did) as unique_users
    FROM posts
    WHERE created_at >= now() - INTERVAL 24 HOUR
    GROUP BY hour
    ORDER BY hour
    """)
  end

  # Helper to format large numbers
  defp format_number(n) when is_integer(n) and n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_number(n) when is_integer(n) and n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(n) when is_binary(n), do: n
  defp format_number(n), do: inspect(n)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950">
      <!-- Header -->
      <nav class="bg-gray-900/95 backdrop-blur-sm border-b border-gray-800 sticky top-0 z-10">
        <div class="px-6 py-4 flex items-center justify-between max-w-7xl mx-auto">
          <div class="flex items-center gap-6">
            <h1 class="text-2xl font-bold bg-gradient-to-r from-blue-400 to-cyan-400 bg-clip-text text-transparent">
              Bluesky Analytics
            </h1>
            <div class="flex gap-4">
              <.link navigate={~p"/grid"} class="text-sm text-gray-400 hover:text-white transition-colors">
                Grid View
              </.link>
              <.link navigate={~p"/conversations"} class="text-sm text-gray-400 hover:text-white transition-colors">
                Conversations
              </.link>
              <.link navigate={~p"/firehose"} class="text-sm text-gray-400 hover:text-white transition-colors">
                Raw Firehose
              </.link>
            </div>
          </div>
          <div class="flex items-center gap-4">
            <span class="relative flex h-2.5 w-2.5">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-green-500"></span>
            </span>
            <span :if={@last_updated} class="text-sm text-gray-500">
              {Calendar.strftime(@last_updated, "%H:%M:%S UTC")}
            </span>
          </div>
        </div>
      </nav>

      <div :if={@loading} class="flex items-center justify-center h-96">
        <div class="flex flex-col items-center gap-4">
          <div class="w-12 h-12 border-4 border-blue-500 border-t-transparent rounded-full animate-spin"></div>
          <div class="text-gray-400">Loading analytics...</div>
        </div>
      </div>

      <div :if={!@loading} class="p-6 space-y-8 max-w-7xl mx-auto">
        <!-- Top Stats Cards -->
        <div class="grid grid-cols-2 lg:grid-cols-5 gap-4">
          <.stat_card title="Total Posts" value={format_number(@total_posts)} subtitle="all time" color="blue" icon="database" />
          <.stat_card
            title="Live Rate"
            value={"#{@live_posts_per_sec}/s"}
            subtitle="firehose intake"
            color="green"
            icon="activity"
            live={true}
          />
          <.stat_card
            title="Posts/min"
            value={get_current_rate(@posts_rate)}
            subtitle="avg (ClickHouse)"
            color="cyan"
            icon="chart"
          />
          <.stat_card
            title="Languages"
            value={length(@languages)}
            subtitle="active (24h)"
            color="purple"
            icon="globe"
          />
          <.stat_card
            title="Hashtags"
            value={length(@hashtags)}
            subtitle="trending (1h)"
            color="orange"
            icon="hash"
          />
        </div>

        <!-- Live Firehose Chart - Full Width -->
        <div class="bg-gray-900 rounded-2xl border border-green-500/30 p-6 shadow-xl relative overflow-hidden">
          <div class="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-green-500 via-emerald-400 to-green-500 animate-pulse" />
          <div class="flex items-center justify-between mb-4">
            <div class="flex items-center gap-3">
              <h3 class="text-lg font-semibold text-white">Live Firehose Posts per Minute</h3>
              <span class="relative flex h-2.5 w-2.5">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
                <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-green-500"></span>
              </span>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-2xl font-bold text-green-400">{@live_posts_per_sec}/s</span>
              <span class="text-xs text-gray-500 bg-gray-800 px-2 py-1 rounded">Live from Broadway</span>
            </div>
          </div>
          <div
            id="live-rate-chart"
            phx-hook="LiveRateChart"
            phx-update="ignore"
            class="w-full"
          />
        </div>

        <!-- Secondary Charts Row -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <!-- ClickHouse Historical Rate -->
          <div class="bg-gray-900 rounded-2xl border border-gray-800 p-6 shadow-xl">
            <div class="flex items-center justify-between mb-6">
              <h3 class="text-lg font-semibold text-white">Posts per Minute (ClickHouse)</h3>
              <span class="text-xs text-gray-500 bg-gray-800 px-2 py-1 rounded">Historical</span>
            </div>
            <div
              id="posts-rate-chart"
              phx-hook="PostsRateChart"
              phx-update="ignore"
              data-points={Jason.encode!(@posts_rate)}
              class="w-full"
            />
          </div>

          <!-- Language Distribution with D3 -->
          <div class="bg-gray-900 rounded-2xl border border-gray-800 p-6 shadow-xl">
            <div class="flex items-center justify-between mb-6">
              <h3 class="text-lg font-semibold text-white">Top Languages</h3>
              <span class="text-xs text-gray-500 bg-gray-800 px-2 py-1 rounded">Last 24h</span>
            </div>
            <div
              id="language-chart"
              phx-hook="LanguageChart"
              phx-update="ignore"
              data-languages={Jason.encode!(@languages)}
              class="w-full"
            />
          </div>
        </div>

        <!-- Bottom Row -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Trending Hashtags with D3 -->
          <div class="bg-gray-900 rounded-2xl border border-gray-800 p-6 shadow-xl">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-lg font-semibold text-white">Trending Hashtags</h3>
              <span class="text-xs text-gray-500 bg-gray-800 px-2 py-1 rounded">Last hour</span>
            </div>
            <div
              id="hashtags-chart"
              phx-hook="HashtagsChart"
              phx-update="ignore"
              data-hashtags={Jason.encode!(@hashtags)}
              class="max-h-72 overflow-y-auto"
            />
          </div>

          <!-- Media Types Donut Chart -->
          <div class="bg-gray-900 rounded-2xl border border-gray-800 p-6 shadow-xl">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-lg font-semibold text-white">Media Types</h3>
              <span class="text-xs text-gray-500 bg-gray-800 px-2 py-1 rounded">Last 24h</span>
            </div>
            <div
              id="media-chart"
              phx-hook="MediaChart"
              phx-update="ignore"
              data-stats={Jason.encode!(get_media_stats_map(@media_stats))}
              class="flex justify-center"
            />
          </div>

          <!-- Hourly Activity Chart -->
          <div class="bg-gray-900 rounded-2xl border border-gray-800 p-6 shadow-xl">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-lg font-semibold text-white">Hourly Activity</h3>
              <span class="text-xs text-gray-500 bg-gray-800 px-2 py-1 rounded">Last 24h</span>
            </div>
            <div
              id="hourly-chart"
              phx-hook="HourlyChart"
              phx-update="ignore"
              data-hours={Jason.encode!(@hourly_stats)}
              class="w-full"
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp get_media_stats_map([]), do: %{}
  defp get_media_stats_map([stats | _]), do: stats
  defp get_media_stats_map(_), do: %{}

  # Components

  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :subtitle, :string, required: true
  attr :color, :string, default: "blue"
  attr :icon, :string, default: nil
  attr :live, :boolean, default: false

  defp stat_card(assigns) do
    color_classes = %{
      "blue" => %{gradient: "from-blue-400 to-blue-600", bg: "bg-blue-500/10", border: "border-blue-500/20", icon: "text-blue-400"},
      "green" => %{gradient: "from-green-400 to-emerald-500", bg: "bg-green-500/10", border: "border-green-500/20", icon: "text-green-400"},
      "cyan" => %{gradient: "from-cyan-400 to-teal-500", bg: "bg-cyan-500/10", border: "border-cyan-500/20", icon: "text-cyan-400"},
      "purple" => %{gradient: "from-purple-400 to-pink-500", bg: "bg-purple-500/10", border: "border-purple-500/20", icon: "text-purple-400"},
      "orange" => %{gradient: "from-orange-400 to-amber-500", bg: "bg-orange-500/10", border: "border-orange-500/20", icon: "text-orange-400"}
    }

    colors = Map.get(color_classes, assigns.color, color_classes["blue"])
    assigns = assign(assigns, colors: colors)

    ~H"""
    <div class={"#{@colors.bg} #{@colors.border} border rounded-2xl p-5 backdrop-blur-sm relative overflow-hidden"}>
      <div :if={@live} class="absolute top-2 right-2">
        <span class="relative flex h-2 w-2">
          <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
          <span class="relative inline-flex rounded-full h-2 w-2 bg-green-500"></span>
        </span>
      </div>
      <div class="flex items-center justify-between mb-3">
        <span class="text-sm text-gray-400 font-medium">{@title}</span>
        <.stat_icon :if={@icon} name={@icon} class={@colors.icon} />
      </div>
      <div class={"text-4xl font-bold bg-gradient-to-r #{@colors.gradient} bg-clip-text text-transparent"}>
        {@value}
      </div>
      <div class="text-xs text-gray-500 mt-1">{@subtitle}</div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :class, :string, default: ""

  defp stat_icon(%{name: "database"} = assigns) do
    ~H"""
    <svg class={"w-5 h-5 #{@class}"} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <ellipse cx="12" cy="5" rx="9" ry="3" />
      <path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3" />
      <path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5" />
    </svg>
    """
  end

  defp stat_icon(%{name: "activity"} = assigns) do
    ~H"""
    <svg class={"w-5 h-5 #{@class}"} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <polyline points="22 12 18 12 15 21 9 3 6 12 2 12" />
    </svg>
    """
  end

  defp stat_icon(%{name: "globe"} = assigns) do
    ~H"""
    <svg class={"w-5 h-5 #{@class}"} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="10" />
      <line x1="2" y1="12" x2="22" y2="12" />
      <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" />
    </svg>
    """
  end

  defp stat_icon(%{name: "hash"} = assigns) do
    ~H"""
    <svg class={"w-5 h-5 #{@class}"} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <line x1="4" y1="9" x2="20" y2="9" />
      <line x1="4" y1="15" x2="20" y2="15" />
      <line x1="10" y1="3" x2="8" y2="21" />
      <line x1="16" y1="3" x2="14" y2="21" />
    </svg>
    """
  end

  defp stat_icon(%{name: "chart"} = assigns) do
    ~H"""
    <svg class={"w-5 h-5 #{@class}"} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path d="M3 3v18h18" />
      <path d="M18 17V9" />
      <path d="M13 17V5" />
      <path d="M8 17v-3" />
    </svg>
    """
  end

  defp stat_icon(assigns), do: ~H""

  defp get_current_rate(posts_rate) do
    case Enum.take(posts_rate, -1) do
      [last] -> Map.get(last, "count", 0) |> to_string()
      _ -> "0"
    end
  end
end
