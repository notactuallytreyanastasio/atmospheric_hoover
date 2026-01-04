defmodule AtmosphericHooverWeb.GridLive do
  @moduledoc """
  LiveView displaying a grid of posts that slide in from different directions.
  Posts are sampled from the firehose and displayed once their profile is populated.
  """

  use AtmosphericHooverWeb, :live_view

  alias AtmosphericHoover.Bluesky.User
  alias AtmosphericHoover.Repo

  import Ecto.Query

  @grid_size 24
  @post_lifetime_ms 8_000
  @sample_rate 0.35
  # How often to check if pending posts have profiles ready
  @pending_check_interval_ms 200
  # Max time to wait for a profile before dropping the post
  @max_pending_wait_ms 10_000

  @directions ["slide-from-left", "slide-from-right", "slide-from-top", "slide-from-bottom"]
  @languages ["en", "ja", "pt", "es", "de", "fr", "ko", "zh", "it", "nl", "ru", "ar"]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AtmosphericHoover.PubSub, "firehose:events")
      :timer.send_interval(100, :check_expired)
      :timer.send_interval(@pending_check_interval_ms, :check_pending)
    end

    {:ok,
     assign(socket,
       page_title: "Post Grid",
       posts: %{},
       pending_posts: [],
       stats: %{received: 0, displayed: 0, pending: 0},
       grid_size: @grid_size,
       filters: %{
         text: "",
         langs: [],
         hashtags: [],
         users: [],
         user_mode: :blocklist
       },
       show_filters: false,
       languages: @languages
     ), layout: false}
  end

  @impl true
  def handle_info({:firehose_event, event}, socket) do
    stats = %{socket.assigns.stats | received: socket.assigns.stats.received + 1}

    if should_sample?() and is_post?(event) do
      # Check if we already have the profile
      case get_user_profile(event.did) do
        %User{} = user ->
          # Profile exists - display immediately
          socket = add_post_to_grid(socket, event, user)
          {:noreply, assign(socket, stats: %{stats | displayed: stats.displayed + 1})}

        nil ->
          # No profile yet - add to pending queue, ProfilePipeline will fetch it
          pending_post = %{
            event: event,
            queued_at: System.monotonic_time(:millisecond)
          }

          pending = [pending_post | socket.assigns.pending_posts] |> Enum.take(100)
          {:noreply, assign(socket, pending_posts: pending, stats: %{stats | pending: length(pending)})}
      end
    else
      {:noreply, assign(socket, stats: stats)}
    end
  end

  def handle_info(:check_pending, socket) do
    now = System.monotonic_time(:millisecond)
    pending = socket.assigns.pending_posts

    # Separate into ready (profile exists) and still waiting
    {ready, still_waiting} =
      Enum.split_with(pending, fn %{event: event} ->
        get_user_profile(event.did) != nil
      end)

    # Filter out posts that have been waiting too long
    still_waiting =
      Enum.filter(still_waiting, fn %{queued_at: queued_at} ->
        now - queued_at < @max_pending_wait_ms
      end)

    # Add ready posts to the grid
    socket =
      Enum.reduce(ready, socket, fn %{event: event}, acc ->
        case get_user_profile(event.did) do
          %User{} = user ->
            acc = add_post_to_grid(acc, event, user)
            stats = acc.assigns.stats
            assign(acc, stats: %{stats | displayed: stats.displayed + 1})

          nil ->
            acc
        end
      end)

    stats = %{socket.assigns.stats | pending: length(still_waiting)}
    {:noreply, assign(socket, pending_posts: still_waiting, stats: stats)}
  end

  def handle_info(:check_expired, socket) do
    now = System.monotonic_time(:millisecond)
    posts = socket.assigns.posts

    expired_keys =
      posts
      |> Enum.filter(fn {_k, post} -> now - post.added_at > @post_lifetime_ms end)
      |> Enum.map(fn {k, _} -> k end)

    posts =
      Enum.reduce(expired_keys, posts, fn key, acc ->
        Map.update!(acc, key, fn post -> %{post | exiting: true} end)
      end)

    # Remove posts that have been exiting for a bit
    posts =
      posts
      |> Enum.reject(fn {_k, post} ->
        post.exiting && now - post.added_at > @post_lifetime_ms + 500
      end)
      |> Map.new()

    {:noreply, assign(socket, posts: posts)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp should_sample?, do: :rand.uniform() < @sample_rate

  defp is_post?(event) do
    event.kind == :commit &&
      event.commit &&
      event.commit.collection == "app.bsky.feed.post" &&
      event.commit.operation == :create &&
      event.commit.record &&
      event.commit.record.text &&
      String.length(event.commit.record.text) > 0
  end

  defp add_post_to_grid(socket, event, user) do
    posts = socket.assigns.posts
    grid_slots = 0..(@grid_size - 1) |> Enum.to_list()
    occupied = posts |> Map.keys() |> MapSet.new()
    available = Enum.filter(grid_slots, &(not MapSet.member?(occupied, &1)))

    if available != [] do
      slot = Enum.random(available)
      post = build_post(event, user, slot)
      assign(socket, posts: Map.put(posts, slot, post))
    else
      # Replace oldest post
      {oldest_slot, _} =
        posts
        |> Enum.min_by(fn {_, p} -> p.added_at end)

      post = build_post(event, user, oldest_slot)
      posts = Map.put(posts, oldest_slot, %{posts[oldest_slot] | exiting: true})
      assign(socket, posts: Map.put(posts, oldest_slot, post))
    end
  end

  defp build_post(event, user, slot) do
    %{
      id: "post-#{System.unique_integer([:positive])}",
      text: truncate_text(event.commit.record.text, 200),
      did: event.did,
      handle: user.handle,
      display_name: user.display_name || user.handle,
      avatar: user.avatar,
      direction: Enum.random(@directions),
      exit_direction: Enum.random(@directions) |> String.replace("from", "to"),
      added_at: System.monotonic_time(:millisecond),
      slot: slot,
      exiting: false
    }
  end

  defp get_user_profile(did) do
    Repo.one(from(u in User, where: u.did == ^did, limit: 1))
  end

  defp truncate_text(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "..."
    else
      text
    end
  end

  defp extract_hashtags(nil), do: []

  defp extract_hashtags(facets) when is_list(facets) do
    facets
    |> Enum.flat_map(fn facet ->
      case facet do
        %{features: features} when is_list(features) -> features
        _ -> []
      end
    end)
    |> Enum.filter(fn f ->
      case f do
        %{type: :tag} -> true
        _ -> false
      end
    end)
    |> Enum.map(fn f -> Map.get(f, :tag) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
  end

  defp extract_hashtags(_), do: []

  defp passes_filters?(event, user, filters) do
    text = event.commit.record.text || ""
    langs = event.commit.record.langs || []
    hashtags = extract_hashtags(event.commit.record.facets)
    handle = user.handle || ""

    passes_text_filter?(text, filters.text) &&
      passes_lang_filter?(langs, filters.langs) &&
      passes_hashtag_filter?(hashtags, filters.hashtags) &&
      passes_user_filter?(handle, filters.users, filters.user_mode)
  end

  defp passes_text_filter?(_text, ""), do: true
  defp passes_text_filter?(text, search) do
    String.contains?(String.downcase(text), String.downcase(search))
  end

  defp passes_lang_filter?(_langs, []), do: true
  defp passes_lang_filter?(langs, filter_langs) do
    Enum.any?(langs || [], fn lang -> lang in filter_langs end)
  end

  defp passes_hashtag_filter?(_hashtags, []), do: true
  defp passes_hashtag_filter?(hashtags, filter_tags) do
    filter_tags_lower = Enum.map(filter_tags, &String.downcase/1)
    Enum.any?(hashtags, fn tag -> tag in filter_tags_lower end)
  end

  defp passes_user_filter?(_handle, [], _mode), do: true
  defp passes_user_filter?(handle, users, :whitelist) do
    String.downcase(handle) in Enum.map(users, &String.downcase/1)
  end
  defp passes_user_filter?(handle, users, :blocklist) do
    String.downcase(handle) not in Enum.map(users, &String.downcase/1)
  end

  defp active_filter_count(filters) do
    count = 0
    count = if filters.text != "", do: count + 1, else: count
    count = count + length(filters.langs)
    count = count + length(filters.hashtags)
    count = count + length(filters.users)
    count
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col bg-gray-50 dark:bg-gray-950">
      <nav class="flex-shrink-0 bg-white/90 dark:bg-gray-900/90 backdrop-blur-sm border-b border-gray-200 dark:border-gray-800">
        <div class="px-4 py-3 flex items-center justify-between">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/"} class="text-xl font-bold text-blue-500 hover:text-blue-600">
              Bluesky Grid
            </.link>
            <.link navigate={~p"/firehose"} class="text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
              Raw Firehose →
            </.link>
          </div>
          <div class="text-sm text-gray-500 dark:text-gray-400 flex gap-4">
            <span><span class="font-mono">{@stats.displayed}</span> shown</span>
            <span><span class="font-mono">{@stats.pending}</span> pending</span>
          </div>
        </div>
      </nav>

      <div class="flex-1 overflow-auto p-2 sm:p-4">
        <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-4 gap-3">
          <%= for slot <- 0..(@grid_size - 1) do %>
            <div class="relative min-h-[180px]">
              <%= if post = @posts[slot] do %>
                <div
                  id={post.id}
                  class={[
                    "absolute inset-0 bg-white dark:bg-gray-900 rounded-xl shadow-md border border-gray-200 dark:border-gray-800 overflow-hidden",
                    if(post.exiting, do: post.exit_direction, else: post.direction)
                  ]}
                >
                  <div class="p-3 h-full flex flex-col">
                    <!-- Header with avatar and user info -->
                    <div class="flex items-start gap-2.5 mb-2">
                      <%= if post.avatar do %>
                        <img
                          src={post.avatar}
                          alt=""
                          class="w-10 h-10 rounded-full flex-shrink-0 bg-gray-200 dark:bg-gray-700 object-cover"
                        />
                      <% else %>
                        <div class="w-10 h-10 rounded-full flex-shrink-0 bg-gradient-to-br from-blue-400 to-purple-500 flex items-center justify-center">
                          <span class="text-white text-sm font-bold">
                            {String.first(post.display_name || post.handle || "?") |> String.upcase()}
                          </span>
                        </div>
                      <% end %>
                      <div class="flex-1 min-w-0">
                        <span class="font-semibold text-gray-900 dark:text-gray-100 text-sm truncate block">
                          {post.display_name}
                        </span>
                        <span class="text-gray-500 dark:text-gray-400 text-xs truncate block">
                          @{post.handle}
                        </span>
                      </div>
                    </div>

                    <!-- Post text -->
                    <p class="text-gray-800 dark:text-gray-200 text-sm leading-snug flex-1 overflow-hidden line-clamp-4">
                      {post.text}
                    </p>
                  </div>
                </div>
              <% else %>
                <div class="absolute inset-0 bg-gray-100/50 dark:bg-gray-900/30 rounded-xl border border-dashed border-gray-200 dark:border-gray-800"></div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <style>
      @keyframes slideFromLeft {
        from { transform: translateX(-100%); opacity: 0; }
        to { transform: translateX(0); opacity: 1; }
      }
      @keyframes slideFromRight {
        from { transform: translateX(100%); opacity: 0; }
        to { transform: translateX(0); opacity: 1; }
      }
      @keyframes slideFromTop {
        from { transform: translateY(-100%); opacity: 0; }
        to { transform: translateY(0); opacity: 1; }
      }
      @keyframes slideFromBottom {
        from { transform: translateY(100%); opacity: 0; }
        to { transform: translateY(0); opacity: 1; }
      }
      @keyframes slideToLeft {
        from { transform: translateX(0); opacity: 1; }
        to { transform: translateX(-100%); opacity: 0; }
      }
      @keyframes slideToRight {
        from { transform: translateX(0); opacity: 1; }
        to { transform: translateX(100%); opacity: 0; }
      }
      @keyframes slideToTop {
        from { transform: translateY(0); opacity: 1; }
        to { transform: translateY(-100%); opacity: 0; }
      }
      @keyframes slideToBottom {
        from { transform: translateY(0); opacity: 1; }
        to { transform: translateY(100%); opacity: 0; }
      }
      .slide-from-left { animation: slideFromLeft 0.4s ease-out forwards; }
      .slide-from-right { animation: slideFromRight 0.4s ease-out forwards; }
      .slide-from-top { animation: slideFromTop 0.4s ease-out forwards; }
      .slide-from-bottom { animation: slideFromBottom 0.4s ease-out forwards; }
      .slide-to-left { animation: slideToLeft 0.4s ease-in forwards; }
      .slide-to-right { animation: slideToRight 0.4s ease-in forwards; }
      .slide-to-top { animation: slideToTop 0.4s ease-in forwards; }
      .slide-to-bottom { animation: slideToBottom 0.4s ease-in forwards; }
    </style>
    """
  end
end
