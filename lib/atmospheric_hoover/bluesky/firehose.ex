defmodule AtmosphericHoover.Bluesky.Firehose do
  @moduledoc """
  WebSocket client for consuming the Bluesky Jetstream firehose.

  This GenServer uses WebSockex to maintain a persistent connection to the
  Bluesky Jetstream WebSocket endpoint and processes incoming events.

  ## Architecture

  The Firehose follows a functional core/imperative shell pattern:

  1. **WebSockex callbacks** handle connection lifecycle
  2. **Parser module** transforms raw JSON to typed structs
  3. **Database persistence** stores events via Ecto
  4. **PubSub broadcasting** notifies LiveViews of new events

  ## Configuration

  Configure the firehose in your config:

      config :atmospheric_hoover, AtmosphericHoover.Bluesky.Firehose,
        url: "wss://jetstream2.us-east.bsky.network/subscribe",
        collections: ["app.bsky.feed.post", "app.bsky.feed.like"],
        sample_rate: 0.1  # Process 10% of events

  ## Sampling

  The firehose can process millions of events per hour. Use `sample_rate` to
  control the percentage of events processed:

  * `1.0` - Process 100% of events (full firehose)
  * `0.1` - Process 10% of events (default for dev)
  * `0.01` - Process 1% of events

  Events are sampled randomly using `:rand.uniform/0`.

  ## Collections

  By default, subscribes to all collections. Limit with `wantedCollections`:

  * `app.bsky.feed.post` - Posts
  * `app.bsky.feed.like` - Likes
  * `app.bsky.feed.repost` - Reposts
  * `app.bsky.graph.follow` - Follows

  ## Usage

  The Firehose is typically started via its Supervisor:

      # In your application.ex
      children = [
        AtmosphericHoover.Bluesky.Supervisor
      ]

  Or start manually for testing:

      {:ok, pid} = AtmosphericHoover.Bluesky.Firehose.start_link([])

  ## Events

  New events are broadcast on the PubSub topic `"firehose:events"`:

      Phoenix.PubSub.subscribe(AtmosphericHoover.PubSub, "firehose:events")

      # Receive events
      def handle_info({:firehose_event, event}, socket) do
        # Handle the event
      end

  ## Statistics

  Use `get_stats/1` to see throughput metrics:

      Firehose.get_stats()
      # => %{
      #   messages_received: 10000,
      #   events_processed: 1000,
      #   sample_rate: 0.1,
      #   messages_per_second: 450.5,
      #   ...
      # }
  """

  use WebSockex

  require Logger

  alias AtmosphericHoover.Bluesky.{FirehoseEvent, Parser}
  alias AtmosphericHoover.Repo

  @default_url "wss://jetstream2.us-east.bsky.network/subscribe"
  @default_collections [
    "app.bsky.feed.post",
    "app.bsky.feed.like",
    "app.bsky.feed.repost",
    "app.bsky.graph.follow"
  ]
  @default_sample_rate 0.1
  @stats_log_interval_ms 30_000

  @typedoc "Firehose state"
  @type state :: %{
          url: String.t(),
          collections: [String.t()],
          sample_rate: float(),
          messages_received: non_neg_integer(),
          events_processed: non_neg_integer(),
          events_skipped: non_neg_integer(),
          started_at: DateTime.t(),
          last_event_at: DateTime.t() | nil,
          persist: boolean(),
          broadcast: boolean()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the firehose WebSocket connection.

  ## Options

  * `:url` - WebSocket URL (default: Jetstream US East)
  * `:collections` - List of collections to subscribe to
  * `:sample_rate` - Float 0.0-1.0, percentage of events to process (default: 0.1)
  * `:persist` - Whether to persist events to database (default: true)
  * `:broadcast` - Whether to broadcast events via PubSub (default: true)
  * `:name` - Process name (default: `__MODULE__`)

  ## Examples

      # Start with defaults (10% sampling)
      {:ok, pid} = Firehose.start_link([])

      # Start with custom collections and 50% sampling
      {:ok, pid} = Firehose.start_link(collections: ["app.bsky.feed.post"], sample_rate: 0.5)

      # Start without persistence (useful for testing)
      {:ok, pid} = Firehose.start_link(persist: false)

      # Full firehose (100% of events)
      {:ok, pid} = Firehose.start_link(sample_rate: 1.0)
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    url = opts[:url] || config(:url, @default_url)
    collections = opts[:collections] || config(:collections, @default_collections)
    sample_rate = opts[:sample_rate] || config(:sample_rate, @default_sample_rate)
    persist = Keyword.get(opts, :persist, true)
    broadcast = Keyword.get(opts, :broadcast, true)
    name = opts[:name] || __MODULE__

    full_url = build_url(url, collections)

    state = %{
      url: url,
      collections: collections,
      sample_rate: sample_rate,
      messages_received: 0,
      events_processed: 0,
      events_skipped: 0,
      started_at: DateTime.utc_now(),
      last_event_at: nil,
      persist: persist,
      broadcast: broadcast
    }

    Logger.info("Starting Bluesky firehose connection to #{url}")
    Logger.info("Subscribing to collections: #{inspect(collections)}")
    Logger.info("Sample rate: #{Float.round(sample_rate * 100, 1)}% of events will be processed")

    WebSockex.start_link(full_url, __MODULE__, state, name: name)
  end

  @doc """
  Returns the current statistics of the firehose connection.

  ## Returns

  A map containing:
  * `:messages_received` - Total messages received from WebSocket
  * `:events_processed` - Events that passed sampling and were processed
  * `:events_skipped` - Events skipped due to sampling
  * `:sample_rate` - Current sample rate (0.0-1.0)
  * `:effective_rate` - Actual processing rate (processed/received)
  * `:messages_per_second` - Average throughput since start
  * `:uptime_seconds` - Seconds since connection started
  * `:last_event_at` - Timestamp of last processed event
  * `:collections` - Subscribed collections

  ## Examples

      iex> Firehose.get_stats()
      %{
        messages_received: 10000,
        events_processed: 1000,
        events_skipped: 9000,
        sample_rate: 0.1,
        effective_rate: 0.1,
        messages_per_second: 450.5,
        uptime_seconds: 22,
        ...
      }
  """
  @spec get_stats(GenServer.server()) :: map()
  def get_stats(server \\ __MODULE__) do
    WebSockex.cast(server, {:get_stats, self()})

    receive do
      {:stats, stats} -> stats
    after
      5000 -> %{error: :timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # WebSockex Callbacks
  # ---------------------------------------------------------------------------

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.info("Connected to Bluesky firehose")
    # Schedule periodic stats logging
    Process.send_after(self(), :log_stats, @stats_log_interval_ms)
    {:ok, state}
  end

  @impl WebSockex
  def handle_disconnect(disconnect_map, state) do
    reason = disconnect_map[:reason]
    Logger.warning("Disconnected from Bluesky firehose: #{inspect(reason)}")

    # Attempt to reconnect after a delay
    Process.sleep(5_000)
    {:reconnect, state}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    state = %{state | messages_received: state.messages_received + 1}

    # Apply sampling - only process if random value is below sample rate
    if should_sample?(state.sample_rate) do
      state = process_message(msg, state)
      {:ok, state}
    else
      {:ok, %{state | events_skipped: state.events_skipped + 1}}
    end
  end

  @impl WebSockex
  def handle_frame({:binary, _msg}, state) do
    # Jetstream uses JSON, but handle binary just in case
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast({:get_stats, from}, state) do
    stats = build_stats(state)
    send(from, {:stats, stats})
    {:ok, state}
  end

  @impl WebSockex
  def handle_info(:log_stats, state) do
    stats = build_stats(state)

    Logger.info(
      "Firehose stats: #{stats.messages_received} received, " <>
        "#{stats.events_processed} processed (#{Float.round(stats.effective_rate * 100, 1)}%), " <>
        "#{Float.round(stats.messages_per_second, 1)} msg/sec"
    )

    # Schedule next stats log
    Process.send_after(self(), :log_stats, @stats_log_interval_ms)
    {:ok, state}
  end

  @impl WebSockex
  def handle_info(msg, state) do
    Logger.debug("Firehose received unexpected message: #{inspect(msg)}")
    {:ok, state}
  end

  @impl WebSockex
  def terminate(reason, state) do
    stats = build_stats(state)

    Logger.info(
      "Firehose terminating: #{inspect(reason)}, " <>
        "processed #{stats.events_processed}/#{stats.messages_received} events " <>
        "(#{Float.round(stats.effective_rate * 100, 1)}%)"
    )

    :ok
  end

  # ---------------------------------------------------------------------------
  # Private Functions
  # ---------------------------------------------------------------------------

  defp config(key, default) do
    Application.get_env(:atmospheric_hoover, __MODULE__, [])
    |> Keyword.get(key, default)
  end

  @doc false
  @spec build_url(String.t(), [String.t()]) :: String.t()
  def build_url(base_url, collections) when collections == [] do
    base_url
  end

  def build_url(base_url, collections) do
    query =
      collections
      |> Enum.map(&{"wantedCollections", &1})
      |> URI.encode_query()

    "#{base_url}?#{query}"
  end

  # Determine if we should process this event based on sample rate
  @spec should_sample?(float()) :: boolean()
  defp should_sample?(rate) when rate >= 1.0, do: true
  defp should_sample?(rate) when rate <= 0.0, do: false
  defp should_sample?(rate), do: :rand.uniform() < rate

  # Build stats map from current state
  @spec build_stats(state()) :: map()
  defp build_stats(state) do
    now = DateTime.utc_now()
    uptime_seconds = DateTime.diff(now, state.started_at, :second)

    messages_per_second =
      if uptime_seconds > 0 do
        state.messages_received / uptime_seconds
      else
        0.0
      end

    effective_rate =
      if state.messages_received > 0 do
        state.events_processed / state.messages_received
      else
        0.0
      end

    %{
      messages_received: state.messages_received,
      events_processed: state.events_processed,
      events_skipped: state.events_skipped,
      sample_rate: state.sample_rate,
      effective_rate: effective_rate,
      messages_per_second: messages_per_second,
      uptime_seconds: uptime_seconds,
      started_at: state.started_at,
      last_event_at: state.last_event_at,
      collections: state.collections
    }
  end

  defp process_message(msg, state) do
    case Parser.parse_event(msg) do
      {:ok, event} ->
        handle_event(event, state)

      {:error, reason} ->
        Logger.warning("Failed to parse firehose event: #{inspect(reason)}")
        state
    end
  end

  defp handle_event(event, state) do
    # Persist to database if enabled
    if state.persist do
      persist_event(event)
    end

    # Broadcast via PubSub if enabled
    if state.broadcast do
      broadcast_event(event)
    end

    # Update stats
    %{
      state
      | events_processed: state.events_processed + 1,
        last_event_at: DateTime.utc_now()
    }
  end

  defp persist_event(event) do
    attrs = FirehoseEvent.from_event(event)

    %FirehoseEvent{}
    |> FirehoseEvent.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
    |> case do
      {:ok, _} -> :ok
      {:error, changeset} -> Logger.debug("Failed to persist event: #{inspect(changeset.errors)}")
    end
  end

  defp broadcast_event(event) do
    Phoenix.PubSub.broadcast(
      AtmosphericHoover.PubSub,
      "firehose:events",
      {:firehose_event, event}
    )
  end
end
