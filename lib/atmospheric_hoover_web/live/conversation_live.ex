defmodule AtmosphericHooverWeb.ConversationLive do
  @moduledoc """
  LiveView for exploring conversation threads on Bluesky.
  Shows hot threads and visualizes reply trees.
  """

  use AtmosphericHooverWeb, :live_view

  alias AtmosphericHoover.Clickhouse

  @refresh_interval_ms 10_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      schedule_refresh()
      Phoenix.PubSub.subscribe(AtmosphericHoover.PubSub, "firehose:events")
    end

    {:ok,
     socket
     |> assign(
       page_title: "Conversations",
       loading: true,
       hot_threads: [],
       selected_thread: nil,
       selected_uri: nil,
       thread_posts: [],
       thread_velocity: [],
       thread_loading: false,
       new_reply_count: 0
     )
     |> load_hot_threads()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, load_hot_threads(socket)}
  end

  # Track new replies to selected thread
  @impl true
  def handle_info({:firehose_event, event}, socket) do
    selected = socket.assigns.selected_thread

    if selected && is_map(selected) && Map.has_key?(selected, "reply_root") do
      root_uri = selected["reply_root"]

      if event.kind == :commit &&
           event.commit &&
           event.commit.collection == "app.bsky.feed.post" &&
           event.commit.operation == :create &&
           event.commit.record do
        # Check if this is a reply to the selected thread
        # Access struct fields directly instead of using get_in (structs don't implement Access)
        reply_root =
          case event.commit.record do
            %{reply: %{root: %{uri: uri}}} -> uri
            _ -> nil
          end

        if reply_root && reply_root == root_uri do
          {:noreply, update(socket, :new_reply_count, &(&1 + 1))}
        else
          {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_thread", %{"uri" => uri}, socket) do
    # Store the thread data with the URI for robustness
    thread = find_thread(socket.assigns.hot_threads, uri) || %{"reply_root" => uri}

    {:noreply,
     socket
     |> assign(selected_thread: thread, selected_uri: uri, new_reply_count: 0, thread_loading: true)
     |> start_async(:load_thread, fn -> load_thread_data(uri) end)}
  end

  @impl true
  def handle_event("refresh_thread", _, socket) do
    if socket.assigns.selected_thread do
      uri = socket.assigns.selected_thread["reply_root"]

      {:noreply,
       socket
       |> assign(new_reply_count: 0, thread_loading: true)
       |> start_async(:load_thread, fn -> load_thread_data(uri) end)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_thread", _, socket) do
    {:noreply, assign(socket, selected_thread: nil, thread_posts: [], thread_velocity: [])}
  end

  @impl true
  def handle_async(:load_thread, {:ok, {posts, velocity}}, socket) do
    {:noreply,
     socket
     |> assign(thread_posts: posts, thread_velocity: velocity, thread_loading: false)
     |> push_event("render-thread-tree", %{posts: build_tree_data(posts)})
     |> push_event("update-thread-velocity", %{points: velocity})}
  end

  def handle_async(:load_thread, {:exit, _reason}, socket) do
    {:noreply, assign(socket, thread_posts: [], thread_velocity: [], thread_loading: false)}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
  end

  defp load_hot_threads(socket) do
    case Clickhouse.hot_threads(30, 25) do
      {:ok, threads} ->
        assign(socket, loading: false, hot_threads: threads)

      {:error, _} ->
        assign(socket, loading: false, hot_threads: [])
    end
  end

  defp load_thread_data(uri) do
    # Load posts and velocity - this runs in the async task
    posts =
      case Clickhouse.thread_posts(uri) do
        {:ok, p} -> p
        _ -> []
      end

    velocity =
      case Clickhouse.thread_velocity(uri, 60) do
        {:ok, v} -> v
        _ -> []
      end

    {posts, velocity}
  end

  defp find_thread(threads, uri) do
    Enum.find(threads, fn t -> t["reply_root"] == uri end)
  end

  defp build_tree_data([]), do: nil

  defp build_tree_data(posts) do
    # Build a tree structure from posts
    # Find the root (post with no reply_parent or reply_parent == uri)
    posts_by_uri = Map.new(posts, fn p -> {p["uri"], p} end)

    # Find root post
    root =
      Enum.find(posts, fn p ->
        p["reply_parent"] == "" || p["reply_parent"] == p["uri"]
      end)

    if root do
      build_node(root, posts, posts_by_uri)
    else
      # If no explicit root, use the first post as root
      case posts do
        [first | _] -> build_node(first, posts, posts_by_uri)
        _ -> nil
      end
    end
  end

  defp build_node(post, all_posts, posts_by_uri) do
    # Find children (posts that have this post as reply_parent)
    children =
      all_posts
      |> Enum.filter(fn p -> p["reply_parent"] == post["uri"] && p["uri"] != post["uri"] end)
      |> Enum.map(fn child -> build_node(child, all_posts, posts_by_uri) end)

    %{
      uri: post["uri"],
      did: post["did"],
      text: String.slice(post["text"] || "", 0, 100),
      created_at: post["created_at"],
      has_images: post["has_images"],
      has_video: post["has_video"],
      children: children
    }
  end

  defp format_time_ago(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, dt, _} -> format_time_ago(dt)
      _ -> datetime_str
    end
  end

  defp format_time_ago(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp format_time_ago(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <nav class="bg-white/90 backdrop-blur-sm border-b border-gray-200 sticky top-0 z-10">
        <div class="px-6 py-4 flex items-center justify-between max-w-7xl mx-auto">
          <div class="flex items-center gap-6">
            <h1 class="text-2xl font-bold text-blue-500">
              Conversation Explorer
            </h1>
            <div class="flex gap-4">
              <.link navigate={~p"/"} class="text-sm text-gray-500 hover:text-gray-700 transition-colors">
                Analytics
              </.link>
              <.link navigate={~p"/grid"} class="text-sm text-gray-500 hover:text-gray-700 transition-colors">
                Grid View
              </.link>
              <.link navigate={~p"/firehose"} class="text-sm text-gray-500 hover:text-gray-700 transition-colors">
                Raw Firehose
              </.link>
            </div>
          </div>
          <div class="flex items-center gap-4">
            <span class="relative flex h-2.5 w-2.5">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-green-500"></span>
            </span>
            <span class="text-sm text-gray-500">Live</span>
          </div>
        </div>
      </nav>

      <div :if={@loading} class="flex items-center justify-center h-96">
        <div class="flex flex-col items-center gap-4">
          <div class="w-12 h-12 border-4 border-blue-500 border-t-transparent rounded-full animate-spin"></div>
          <div class="text-gray-500">Loading hot threads...</div>
        </div>
      </div>

      <div :if={!@loading} class="flex h-[calc(100vh-73px)]">
        <!-- Left Panel: Hot Threads List -->
        <div class="w-96 border-r border-gray-200 overflow-y-auto bg-white">
          <div class="p-4 border-b border-gray-200 bg-gray-50 sticky top-0">
            <h2 class="text-lg font-semibold text-gray-900 flex items-center gap-2">
              <svg class="w-5 h-5 text-orange-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.879 16.121A3 3 0 1012.015 11L11 14H9c0 .768.293 1.536.879 2.121z" />
              </svg>
              Hot Threads
              <span class="text-xs text-gray-400 font-normal">(last 30 min)</span>
            </h2>
          </div>

          <div class="divide-y divide-gray-100">
            <%= for thread <- @hot_threads do %>
              <button
                phx-click="select_thread"
                phx-value-uri={thread["reply_root"]}
                class={"w-full text-left p-4 hover:bg-gray-50 transition-colors #{if @selected_thread && @selected_thread["reply_root"] == thread["reply_root"], do: "bg-blue-50 border-l-4 border-blue-500", else: ""}"}
              >
                <div class="flex items-center justify-between mb-2">
                  <span class="text-2xl font-bold text-orange-500">
                    {thread["reply_count"]}
                  </span>
                  <span class="text-xs text-gray-500 bg-gray-100 px-2 py-0.5 rounded-full">
                    {thread["unique_repliers"]} users
                  </span>
                </div>
                <div class="text-xs text-gray-500 truncate font-mono mb-1">
                  {thread["reply_root"]}
                </div>
                <div class="flex items-center gap-2 text-xs text-gray-400">
                  <span>Started {format_time_ago(thread["first_reply"])}</span>
                  <span class="text-gray-300">•</span>
                  <span>Latest {format_time_ago(thread["last_reply"])}</span>
                </div>
              </button>
            <% end %>
          </div>

          <%= if @hot_threads == [] do %>
            <div class="p-8 text-center text-gray-400">
              <svg class="w-12 h-12 mx-auto mb-4 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
              </svg>
              <p>No hot threads found</p>
              <p class="text-sm mt-1">Check back soon!</p>
            </div>
          <% end %>
        </div>

        <!-- Right Panel: Thread Details -->
        <div class="flex-1 overflow-y-auto bg-gradient-to-br from-gray-50 to-slate-100">
          <%= if @selected_thread do %>
            <div class="p-6">
              <!-- Thread Header -->
              <div class="bg-white rounded-xl border border-gray-200 shadow-sm p-6 mb-6">
                <div class="flex items-center justify-between mb-4">
                  <h3 class="text-xl font-bold text-gray-900">Thread Details</h3>
                  <div class="flex items-center gap-3">
                    <%= if @new_reply_count > 0 do %>
                      <button
                        phx-click="refresh_thread"
                        class="flex items-center gap-2 px-3 py-1.5 bg-orange-100 text-orange-600 rounded-lg hover:bg-orange-200 transition-colors"
                      >
                        <span class="relative flex h-2 w-2">
                          <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-orange-400 opacity-75"></span>
                          <span class="relative inline-flex rounded-full h-2 w-2 bg-orange-500"></span>
                        </span>
                        {"+#{@new_reply_count} new"} - Click to refresh
                      </button>
                    <% end %>
                    <button
                      phx-click="close_thread"
                      class="text-gray-400 hover:text-gray-600 transition-colors"
                    >
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  </div>
                </div>

                <div class="grid grid-cols-4 gap-4 text-center">
                  <div class="bg-orange-50 rounded-lg p-4 border border-orange-100">
                    <div class="text-3xl font-bold text-orange-500">{@selected_thread["reply_count"] || length(@thread_posts)}</div>
                    <div class="text-xs text-gray-500 mt-1">Replies</div>
                  </div>
                  <div class="bg-blue-50 rounded-lg p-4 border border-blue-100">
                    <div class="text-3xl font-bold text-blue-500">{@selected_thread["unique_repliers"] || "?"}</div>
                    <div class="text-xs text-gray-500 mt-1">Participants</div>
                  </div>
                  <div class="bg-green-50 rounded-lg p-4 border border-green-100">
                    <div class="text-xl font-bold text-green-500">{length(@thread_posts)}</div>
                    <div class="text-xs text-gray-500 mt-1">Posts Loaded</div>
                  </div>
                  <div class="bg-purple-50 rounded-lg p-4 border border-purple-100">
                    <div class="text-xl font-bold text-purple-500">
                      {if @thread_velocity != [], do: Enum.sum(Enum.map(@thread_velocity, &(Map.get(&1, "replies", 0)))), else: 0}
                    </div>
                    <div class="text-xs text-gray-500 mt-1">Last Hour</div>
                  </div>
                </div>
              </div>

              <!-- Thread Velocity Chart -->
              <div class="bg-white rounded-xl border border-gray-200 shadow-sm p-6 mb-6">
                <div class="flex items-center justify-between mb-4">
                  <h4 class="text-lg font-semibold text-gray-900">Reply Velocity</h4>
                  <span class="text-xs text-gray-400">Replies per minute (last hour)</span>
                </div>
                <div
                  id="thread-velocity-chart"
                  phx-hook="ThreadVelocityChart"
                  phx-update="ignore"
                  data-points={Jason.encode!(@thread_velocity)}
                  class="w-full h-32"
                />
              </div>

              <!-- Thread Tree Visualization -->
              <div class="bg-white rounded-xl border border-gray-200 shadow-sm p-6">
                <div class="flex items-center justify-between mb-4">
                  <h4 class="text-lg font-semibold text-gray-900">Reply Tree</h4>
                  <span class="text-xs text-gray-400">Visual structure of the conversation</span>
                </div>
                <div
                  id="thread-tree"
                  phx-hook="ThreadTreeChart"
                  phx-update="ignore"
                  data-posts={Jason.encode!(build_tree_data(@thread_posts))}
                  class="w-full overflow-x-auto"
                  style="min-height: 400px;"
                />
              </div>
            </div>
          <% else %>
            <div class="flex items-center justify-center h-full">
              <div class="text-center text-gray-400">
                <svg class="w-16 h-16 mx-auto mb-4 opacity-30" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
                </svg>
                <p class="text-lg text-gray-500">Select a thread to explore</p>
                <p class="text-sm mt-1">Click on a hot thread from the left panel</p>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
