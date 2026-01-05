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
      # Check expired posts less frequently to reduce DOM updates
      :timer.send_interval(500, :check_expired)
      :timer.send_interval(@pending_check_interval_ms, :check_pending)
      # Update stats display periodically instead of on every event
      :timer.send_interval(1000, :update_stats_display)
    end

    {:ok,
     assign(socket,
       page_title: "Post Grid",
       posts: %{},
       pending_posts: [],
       stats: %{received: 0, displayed: 0, pending: 0},
       stats_display: %{received: 0, displayed: 0, pending: 0},
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
          # Profile exists - check filters and display if passes
          if passes_filters?(event, user, socket.assigns.filters) do
            socket = add_post_to_grid(socket, event, user)
            {:noreply, assign(socket, stats: %{stats | displayed: stats.displayed + 1})}
          else
            {:noreply, assign(socket, stats: stats)}
          end

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

    # Add ready posts to the grid (if they pass filters)
    socket =
      Enum.reduce(ready, socket, fn %{event: event}, acc ->
        case get_user_profile(event.did) do
          %User{} = user ->
            if passes_filters?(event, user, acc.assigns.filters) do
              acc = add_post_to_grid(acc, event, user)
              stats = acc.assigns.stats
              assign(acc, stats: %{stats | displayed: stats.displayed + 1})
            else
              acc
            end

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

  def handle_info(:update_stats_display, socket) do
    {:noreply, assign(socket, stats_display: socket.assigns.stats)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_filters", _, socket) do
    {:noreply, assign(socket, show_filters: !socket.assigns.show_filters)}
  end

  def handle_event("update_text", %{"value" => value}, socket) do
    filters = %{socket.assigns.filters | text: value}
    {:noreply, assign(socket, filters: filters)}
  end

  def handle_event("toggle_lang", %{"lang" => lang}, socket) do
    filters = socket.assigns.filters
    langs = if lang in filters.langs do
      List.delete(filters.langs, lang)
    else
      [lang | filters.langs]
    end
    {:noreply, assign(socket, filters: %{filters | langs: langs})}
  end

  def handle_event("add_hashtag", %{"value" => value}, socket) do
    tag = value |> String.trim() |> String.trim_leading("#")
    if tag != "" do
      filters = socket.assigns.filters
      hashtags = if tag in filters.hashtags, do: filters.hashtags, else: [tag | filters.hashtags]
      {:noreply, assign(socket, filters: %{filters | hashtags: hashtags})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_hashtag", %{"tag" => tag}, socket) do
    filters = socket.assigns.filters
    hashtags = List.delete(filters.hashtags, tag)
    {:noreply, assign(socket, filters: %{filters | hashtags: hashtags})}
  end

  def handle_event("add_user", %{"value" => value}, socket) do
    handle = value |> String.trim() |> String.trim_leading("@")
    if handle != "" do
      filters = socket.assigns.filters
      users = if handle in filters.users, do: filters.users, else: [handle | filters.users]
      {:noreply, assign(socket, filters: %{filters | users: users})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_user", %{"handle" => handle}, socket) do
    filters = socket.assigns.filters
    users = List.delete(filters.users, handle)
    {:noreply, assign(socket, filters: %{filters | users: users})}
  end

  def handle_event("toggle_user_mode", _, socket) do
    filters = socket.assigns.filters
    new_mode = if filters.user_mode == :blocklist, do: :whitelist, else: :blocklist
    {:noreply, assign(socket, filters: %{filters | user_mode: new_mode})}
  end

  def handle_event("clear_filters", _, socket) do
    {:noreply, assign(socket, filters: %{
      text: "",
      langs: [],
      hashtags: [],
      users: [],
      user_mode: :blocklist
    })}
  end

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
      langs: event.commit.record.langs || [],
      hashtags: extract_hashtags(event.commit.record.facets),
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

  # Function components for reusable UI elements

  attr :lang, :string, required: true
  attr :active, :boolean, default: false
  defp lang_button(assigns) do
    ~H"""
    <button
      phx-click="toggle_lang"
      phx-value-lang={@lang}
      class={[
        "px-2 py-1 text-xs rounded border transition-colors",
        if(@active,
          do: "bg-blue-500 text-white border-blue-500",
          else: "bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400 border-gray-300 dark:border-gray-600 hover:bg-gray-200 dark:hover:bg-gray-700"
        )
      ]}
    >
      {@lang}
    </button>
    """
  end

  attr :tag, :string, required: true
  defp hashtag_chip(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 px-2 py-0.5 text-xs bg-blue-100 dark:bg-blue-900/50 text-blue-700 dark:text-blue-300 rounded-full">
      #{@tag}
      <button phx-click="remove_hashtag" phx-value-tag={@tag} class="hover:text-blue-900 dark:hover:text-blue-100">&times;</button>
    </span>
    """
  end

  attr :handle, :string, required: true
  attr :mode, :atom, required: true
  defp user_chip(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full",
      if(@mode == :blocklist,
        do: "bg-red-100 dark:bg-red-900/50 text-red-700 dark:text-red-300",
        else: "bg-green-100 dark:bg-green-900/50 text-green-700 dark:text-green-300"
      )
    ]}>
      @{@handle}
      <button phx-click="remove_user" phx-value-handle={@handle} class="hover:opacity-70">&times;</button>
    </span>
    """
  end

  attr :post, :map, required: true
  defp post_card(assigns) do
    ~H"""
    <div
      id={@post.id}
      class={[
        "absolute inset-0 bg-white dark:bg-gray-900 rounded-xl shadow-md border border-gray-200 dark:border-gray-800 overflow-hidden",
        if(@post.exiting, do: @post.exit_direction, else: @post.direction)
      ]}
    >
      <div class="p-3 h-full flex flex-col">
        <div class="flex items-start gap-2.5 mb-2">
          <.avatar post={@post} />
          <div class="flex-1 min-w-0">
            <span class="font-semibold text-gray-900 dark:text-gray-100 text-sm truncate block">
              {@post.display_name}
            </span>
            <span class="text-gray-500 dark:text-gray-400 text-xs truncate block">
              @{@post.handle}
            </span>
          </div>
        </div>
        <p class="text-gray-800 dark:text-gray-200 text-sm leading-snug flex-1 overflow-hidden line-clamp-4">
          {@post.text}
        </p>
      </div>
    </div>
    """
  end

  attr :post, :map, required: true
  defp avatar(assigns) do
    ~H"""
    <img
      :if={@post.avatar}
      src={@post.avatar}
      alt=""
      class="w-10 h-10 rounded-full flex-shrink-0 bg-gray-200 dark:bg-gray-700 object-cover"
    />
    <div
      :if={!@post.avatar}
      class="w-10 h-10 rounded-full flex-shrink-0 bg-gradient-to-br from-blue-400 to-purple-500 flex items-center justify-center"
    >
      <span class="text-white text-sm font-bold">
        {String.first(@post.display_name || @post.handle || "?") |> String.upcase()}
      </span>
    </div>
    """
  end

  defp filter_icon(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
    </svg>
    """
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
            <.link navigate={~p"/conversations"} class="text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
              Conversations
            </.link>
            <.link navigate={~p"/firehose"} class="text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
              Raw Firehose →
            </.link>
          </div>
          <div class="text-sm text-gray-500 dark:text-gray-400 flex items-center gap-4">
            <button
              phx-click="toggle_filters"
              class={[
                "px-3 py-1 rounded-lg border transition-colors flex items-center gap-1.5",
                if(@show_filters or active_filter_count(@filters) > 0,
                  do: "bg-blue-50 dark:bg-blue-900/30 border-blue-300 dark:border-blue-700 text-blue-600 dark:text-blue-400",
                  else: "border-gray-300 dark:border-gray-600 hover:bg-gray-100 dark:hover:bg-gray-800"
                )
              ]}
            >
              <.filter_icon />
              Filter
              <span
                :if={active_filter_count(@filters) > 0}
                class="bg-blue-500 text-white text-xs rounded-full px-1.5 py-0.5 min-w-[1.25rem] text-center"
              >
                {active_filter_count(@filters)}
              </span>
            </button>
            <span><span class="font-mono">{@stats_display.displayed}</span> shown</span>
            <span><span class="font-mono">{@stats_display.pending}</span> pending</span>
          </div>
        </div>
      </nav>

      <!-- Filter Panel -->
      <div
        :if={@show_filters}
        class="flex-shrink-0 bg-white dark:bg-gray-900 border-b border-gray-200 dark:border-gray-800 px-4 py-3"
      >
        <div class="flex flex-wrap gap-4 items-start">
          <!-- Text Search -->
          <div class="flex-1 min-w-[200px]">
            <label class="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Search</label>
            <input
              type="text"
              value={@filters.text}
              phx-keyup="update_text"
              phx-debounce="300"
              placeholder="Search posts..."
              class="w-full px-3 py-1.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          <!-- Language Filter -->
          <div>
            <label class="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Languages</label>
            <div class="flex flex-wrap gap-1">
              <.lang_button :for={lang <- @languages} lang={lang} active={lang in @filters.langs} />
            </div>
          </div>

          <!-- Hashtag Filter -->
          <div class="min-w-[180px]">
            <label class="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">Hashtags</label>
            <form phx-submit="add_hashtag" class="flex gap-1">
              <input
                type="text"
                name="value"
                placeholder="#tag"
                class="flex-1 px-2 py-1 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
              <button type="submit" class="px-2 py-1 text-sm bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-700">+</button>
            </form>
            <div :if={@filters.hashtags != []} class="flex flex-wrap gap-1 mt-1">
              <.hashtag_chip :for={tag <- @filters.hashtags} tag={tag} />
            </div>
          </div>

          <!-- User Filter -->
          <div class="min-w-[180px]">
            <label class="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">
              Users
              <button phx-click="toggle_user_mode" class="ml-1 text-blue-500 hover:text-blue-600">
                ({if @filters.user_mode == :blocklist, do: "block", else: "allow"})
              </button>
            </label>
            <form phx-submit="add_user" class="flex gap-1">
              <input
                type="text"
                name="value"
                placeholder="@handle"
                class="flex-1 px-2 py-1 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
              <button type="submit" class="px-2 py-1 text-sm bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-700">+</button>
            </form>
            <div :if={@filters.users != []} class="flex flex-wrap gap-1 mt-1">
              <.user_chip :for={handle <- @filters.users} handle={handle} mode={@filters.user_mode} />
            </div>
          </div>

          <!-- Clear Button -->
          <div :if={active_filter_count(@filters) > 0} class="flex items-end">
            <button
              phx-click="clear_filters"
              class="px-3 py-1.5 text-sm text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/30 rounded-lg transition-colors"
            >
              Clear all
            </button>
          </div>
        </div>
      </div>

      <div class="flex-1 overflow-auto p-2 sm:p-4">
        <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-4 gap-3">
          <div :for={slot <- 0..(@grid_size - 1)} class="relative min-h-[180px]">
            <.post_card :if={@posts[slot]} post={@posts[slot]} />
            <div
              :if={!@posts[slot]}
              class="absolute inset-0 bg-gray-100/50 dark:bg-gray-900/30 rounded-xl border border-dashed border-gray-200 dark:border-gray-800"
            />
          </div>
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
