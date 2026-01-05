defmodule AtmosphericHoover.Bluesky.EventPipeline do
  @moduledoc """
  Broadway pipeline for processing Bluesky firehose events.

  This pipeline handles events from the Jetstream firehose with proper
  backpressure, batching, and parallel processing.

  ## Architecture

  ```
  Firehose (WebSocket)
      ↓ push to producer
  EventPipeline (Broadway with internal producer)
      ↓ batched
  Database (bulk insert) + PubSub (broadcast)
  ```

  ## Features

  - **Backpressure**: Demand-driven flow prevents overwhelming the system
  - **Batching**: Events are batched for efficient database writes
  - **Parallel processing**: Multiple processors handle events concurrently
  - **Telemetry**: Built-in metrics via Broadway telemetry

  ## Configuration

      config :atmospheric_hoover, AtmosphericHoover.Bluesky.EventPipeline,
        processor_concurrency: 5,
        batch_size: 100,
        batch_timeout: 1000

  ## Usage

  Push events from the firehose:

      EventPipeline.push_event(raw_json)

  Or push parsed events:

      EventPipeline.push_parsed_event(parsed_event)
  """

  use Broadway

  require Logger

  alias AtmosphericHoover.Bluesky.{FirehoseEvent, Parser}
  alias AtmosphericHoover.{Clickhouse, Repo}
  alias Broadway.Message

  @default_processor_concurrency 5
  @default_batch_size 100
  @default_batch_timeout 1_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the event pipeline.

  ## Options

  - `:name` - Process name (default: `__MODULE__`)
  - `:processor_concurrency` - Number of parallel processors (default: 5)
  - `:batch_size` - Events per batch for DB writes (default: 100)
  - `:batch_timeout` - Max ms to wait for batch (default: 1000)
  - `:persist` - Whether to persist to database (default: true)
  - `:broadcast` - Whether to broadcast via PubSub (default: true)
  """
  def start_link(opts) do
    name = opts[:name] || __MODULE__

    processor_concurrency =
      opts[:processor_concurrency] ||
        config(:processor_concurrency, @default_processor_concurrency)

    batch_size = opts[:batch_size] || config(:batch_size, @default_batch_size)
    batch_timeout = opts[:batch_timeout] || config(:batch_timeout, @default_batch_timeout)

    persist = Keyword.get(opts, :persist, true)
    broadcast = Keyword.get(opts, :broadcast, true)

    Broadway.start_link(__MODULE__,
      name: name,
      producer: [
        module: {__MODULE__.Producer, []},
        transformer: {__MODULE__, :transform, []},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: processor_concurrency]
      ],
      batchers: [
        default: [
          concurrency: 2,
          batch_size: batch_size,
          batch_timeout: batch_timeout
        ]
      ],
      context: %{
        persist: persist,
        broadcast: broadcast
      }
    )
  end

  @doc """
  Pushes a raw JSON event to the pipeline.

  The event will be parsed and processed asynchronously with backpressure.

  ## Examples

      EventPipeline.push_event(~s({"did":"did:plc:test",...}))
  """
  @spec push_event(GenServer.server(), binary()) :: :ok
  def push_event(pipeline \\ __MODULE__, raw_json) do
    producer = Broadway.producer_names(pipeline) |> List.first()
    GenStage.cast(producer, {:push, {:raw, raw_json}})
  end

  @doc """
  Pushes a pre-parsed event to the pipeline.

  Use this when you've already parsed the event (e.g., for testing).

  ## Examples

      {:ok, event} = Parser.parse_event(json)
      EventPipeline.push_parsed_event(event)
  """
  @spec push_parsed_event(GenServer.server(), term()) :: :ok
  def push_parsed_event(pipeline \\ __MODULE__, parsed_event) do
    producer = Broadway.producer_names(pipeline) |> List.first()
    GenStage.cast(producer, {:push, {:parsed, parsed_event}})
  end

  @doc """
  Returns the current queue depth.
  """
  @spec queue_depth(GenServer.server()) :: non_neg_integer()
  def queue_depth(pipeline \\ __MODULE__) do
    producer = Broadway.producer_names(pipeline) |> List.first()
    GenStage.call(producer, :queue_depth)
  end

  # ---------------------------------------------------------------------------
  # Broadway Callbacks
  # ---------------------------------------------------------------------------

  @doc false
  def transform({:raw, raw_json}, _opts) do
    %Message{
      data: {:raw, raw_json},
      acknowledger: {__MODULE__, :ack_id, nil}
    }
  end

  def transform({:parsed, event}, _opts) do
    %Message{
      data: {:parsed, event},
      acknowledger: {__MODULE__, :ack_id, nil}
    }
  end

  @impl Broadway
  def handle_message(:default, %Message{data: {:raw, raw_json}} = message, _context) do
    start_time = System.monotonic_time()

    case Parser.parse_event(raw_json) do
      {:ok, event} ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:atmospheric_hoover, :event_pipeline, :parse, :success],
          %{duration: duration},
          %{collection: event.commit && event.commit.collection}
        )

        Message.put_data(message, event)

      {:error, reason} ->
        :telemetry.execute(
          [:atmospheric_hoover, :event_pipeline, :parse, :error],
          %{count: 1},
          %{reason: reason}
        )

        Message.failed(message, {:parse_error, reason})
    end
  end

  def handle_message(:default, %Message{data: {:parsed, event}} = message, _context) do
    Message.put_data(message, event)
  end

  @impl Broadway
  def handle_batch(:default, messages, _batch_info, context) do
    # Separate successful and failed messages
    {successful, failed} =
      Enum.split_with(messages, fn msg ->
        msg.status == :ok
      end)

    events = Enum.map(successful, & &1.data)

    :telemetry.execute(
      [:atmospheric_hoover, :event_pipeline, :batch, :process],
      %{
        successful_count: length(successful),
        failed_count: length(failed),
        total_count: length(messages)
      },
      %{}
    )

    # Persist to database if enabled
    if context.persist do
      persist_batch(events)
    end

    # Broadcast via PubSub if enabled
    if context.broadcast do
      broadcast_batch(events)
    end

    # Store in ClickHouse for analytics
    store_in_clickhouse(events)

    # Emit DIDs for profile fetching
    emit_dids(events)

    # Return all messages (Broadway handles failed ones)
    messages
  end

  @doc false
  def ack(:ack_id, _successful, _failed) do
    :ok
  end

  # ---------------------------------------------------------------------------
  # Private Functions
  # ---------------------------------------------------------------------------

  defp config(key, default) do
    Application.get_env(:atmospheric_hoover, __MODULE__, [])
    |> Keyword.get(key, default)
  end

  defp persist_batch([]), do: :ok

  defp persist_batch(events) do
    now = DateTime.utc_now()

    entries =
      events
      |> Enum.map(&FirehoseEvent.from_event/1)
      |> Enum.map(fn attrs ->
        attrs
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    try do
      Repo.insert_all(FirehoseEvent, entries, on_conflict: :nothing)
    rescue
      e ->
        Logger.warning("Failed to persist event batch: #{inspect(e)}")
    end
  end

  defp broadcast_batch([]), do: :ok

  defp broadcast_batch(events) do
    Enum.each(events, fn event ->
      Phoenix.PubSub.broadcast(
        AtmosphericHoover.PubSub,
        "firehose:events",
        {:firehose_event, event}
      )
    end)
  end

  defp store_in_clickhouse([]), do: :ok

  defp store_in_clickhouse(events) do
    # Only store posts (not other event types) - batch insert directly
    posts =
      events
      |> Enum.filter(&is_post?/1)
      |> Enum.map(&event_to_clickhouse_post/1)

    if posts != [] do
      Clickhouse.insert_posts(posts)
    end
  end

  defp is_post?(event) do
    event.kind == :commit &&
      event.commit &&
      event.commit.collection == "app.bsky.feed.post" &&
      event.commit.operation == :create &&
      event.commit.record &&
      event.commit.record.text
  end

  defp event_to_clickhouse_post(event) do
    record = event.commit.record

    %{
      did: event.did,
      handle: "",
      display_name: "",
      text: record.text || "",
      langs: record.langs || [],
      hashtags: extract_hashtags(record.facets),
      cid: event.commit.cid || "",
      uri: "at://#{event.did}/app.bsky.feed.post/#{event.commit.rkey}",
      reply_parent: get_reply_parent(record),
      reply_root: get_reply_root(record),
      has_images: has_images?(record),
      has_video: has_video?(record),
      has_external_link: has_external_link?(record),
      created_at: record.created_at
    }
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

  defp get_reply_parent(%{reply: %{parent: %{uri: uri}}}), do: uri
  defp get_reply_parent(_), do: ""

  defp get_reply_root(%{reply: %{root: %{uri: uri}}}), do: uri
  defp get_reply_root(_), do: ""

  defp has_images?(%{embed: %{type: :images}}), do: true
  defp has_images?(%{embed: %{type: :record_with_media, media: %{type: :images}}}), do: true
  defp has_images?(_), do: false

  defp has_video?(%{embed: %{type: :video}}), do: true
  defp has_video?(_), do: false

  defp has_external_link?(%{embed: %{type: :external}}), do: true
  defp has_external_link?(_), do: false

  defp emit_dids(events) do
    dids = Enum.map(events, & &1.did) |> Enum.uniq()

    :telemetry.execute(
      [:atmospheric_hoover, :event_pipeline, :emit_dids],
      %{count: length(dids)},
      %{}
    )

    # Push to profile pipeline if it's running
    try do
      AtmosphericHoover.Bluesky.ProfilePipeline.push_dids(dids)
    rescue
      e ->
        Logger.warning("Failed to push DIDs to ProfilePipeline: #{inspect(e)}")

        :telemetry.execute(
          [:atmospheric_hoover, :event_pipeline, :emit_dids, :error],
          %{count: length(dids)},
          %{reason: :exception}
        )
    catch
      :exit, reason ->
        Logger.warning("ProfilePipeline not available: #{inspect(reason)}")

        :telemetry.execute(
          [:atmospheric_hoover, :event_pipeline, :emit_dids, :error],
          %{count: length(dids)},
          %{reason: :not_running}
        )
    end
  end
end

defmodule AtmosphericHoover.Bluesky.EventPipeline.Producer do
  @moduledoc """
  GenStage producer for the EventPipeline.

  Buffers incoming events and emits them based on downstream demand.
  Provides backpressure when the pipeline is overwhelmed.
  """

  use GenStage

  @max_queue_size 50_000

  @impl GenStage
  def init(_opts) do
    {:producer, %{queue: :queue.new(), demand: 0, dropped: 0}}
  end

  @impl GenStage
  def handle_cast({:push, event}, state) do
    queue_len = :queue.len(state.queue)

    if queue_len >= @max_queue_size do
      # Drop oldest events when queue is full (shed load)
      {{:value, _dropped}, queue} = :queue.out(state.queue)
      queue = :queue.in(event, queue)
      {:noreply, [], %{state | queue: queue, dropped: state.dropped + 1}}
    else
      queue = :queue.in(event, state.queue)
      dispatch_events(%{state | queue: queue})
    end
  end

  @impl GenStage
  def handle_call(:queue_depth, _from, state) do
    {:reply, :queue.len(state.queue), [], state}
  end

  @impl GenStage
  def handle_demand(incoming_demand, state) do
    dispatch_events(%{state | demand: state.demand + incoming_demand})
  end

  defp dispatch_events(%{demand: 0} = state) do
    {:noreply, [], state}
  end

  defp dispatch_events(%{demand: demand, queue: queue} = state) do
    {events, remaining_queue, remaining_demand} = take_events(queue, demand, [])

    {:noreply, events, %{state | queue: remaining_queue, demand: remaining_demand}}
  end

  defp take_events(queue, 0, acc) do
    {Enum.reverse(acc), queue, 0}
  end

  defp take_events(queue, demand, acc) do
    case :queue.out(queue) do
      {{:value, event}, remaining} ->
        take_events(remaining, demand - 1, [event | acc])

      {:empty, queue} ->
        {Enum.reverse(acc), queue, demand}
    end
  end
end
