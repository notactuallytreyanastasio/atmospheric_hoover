defmodule AtmosphericHoover.Bluesky.ProfilePipeline do
  @moduledoc """
  Broadway pipeline for fetching Bluesky user profiles.

  This pipeline handles DID-to-profile fetching with proper backpressure,
  rate limiting, deduplication via ETS, and batched database writes.

  ## Architecture

  ```
  EventPipeline (emits DIDs)
      ↓ push to producer
  ProfilePipeline (Broadway with internal producer + ETS dedup)
      ↓ rate-limited, parallel HTTP
  Database (bulk upsert)
  ```

  ## Features

  - **ETS Deduplication**: Prevents duplicate fetches within a session
  - **Rate Limiting**: Configurable delay between API calls per processor
  - **Parallel Fetching**: Multiple processors make concurrent HTTP requests
  - **Batched Writes**: Profiles are batched for efficient database upserts
  - **Database Check**: Skips DIDs already in the database

  ## Configuration

      config :atmospheric_hoover, AtmosphericHoover.Bluesky.ProfilePipeline,
        processor_concurrency: 3,
        rate_limit_ms: 100,
        batch_size: 50,
        batch_timeout: 5000

  ## Usage

  Push DIDs from the event pipeline:

      ProfilePipeline.push_did("did:plc:abc123")
      ProfilePipeline.push_dids(["did:plc:abc", "did:plc:xyz"])
  """

  use Broadway

  require Logger

  alias AtmosphericHoover.Bluesky.{ProfileFetcher, User}
  alias AtmosphericHoover.Repo
  alias Broadway.Message

  import Ecto.Query

  @default_processor_concurrency 3
  @default_rate_limit_interval 1_000
  @default_rate_limit_allowed 10
  @default_batch_size 50
  @default_batch_timeout 5_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the profile pipeline.

  ## Options

  - `:name` - Process name (default: `__MODULE__`)
  - `:processor_concurrency` - Number of parallel fetchers (default: 3)
  - `:rate_limit_interval` - Rate limit window in ms (default: 1000)
  - `:rate_limit_allowed` - Requests allowed per interval (default: 10)
  - `:batch_size` - Profiles per batch for DB writes (default: 50)
  - `:batch_timeout` - Max ms to wait for batch (default: 5000)
  """
  def start_link(opts) do
    name = opts[:name] || __MODULE__

    processor_concurrency =
      opts[:processor_concurrency] ||
        config(:processor_concurrency, @default_processor_concurrency)

    rate_limit_interval =
      opts[:rate_limit_interval] || config(:rate_limit_interval, @default_rate_limit_interval)

    rate_limit_allowed =
      opts[:rate_limit_allowed] || config(:rate_limit_allowed, @default_rate_limit_allowed)

    batch_size = opts[:batch_size] || config(:batch_size, @default_batch_size)
    batch_timeout = opts[:batch_timeout] || config(:batch_timeout, @default_batch_timeout)

    Broadway.start_link(__MODULE__,
      name: name,
      producer: [
        module: {__MODULE__.Producer, [name: name]},
        transformer: {__MODULE__, :transform, []},
        concurrency: 1,
        rate_limiting: [
          allowed_messages: rate_limit_allowed,
          interval: rate_limit_interval
        ]
      ],
      processors: [
        default: [concurrency: processor_concurrency]
      ],
      batchers: [
        success: [
          concurrency: 1,
          batch_size: batch_size,
          batch_timeout: batch_timeout
        ],
        error: [
          concurrency: 1,
          batch_size: batch_size,
          batch_timeout: batch_timeout
        ]
      ]
    )
  end

  @doc """
  Pushes a DID for profile fetching.

  The DID will be deduplicated and processed asynchronously.

  ## Examples

      ProfilePipeline.push_did("did:plc:abc123")
  """
  @spec push_did(GenServer.server(), String.t()) :: :ok
  def push_did(pipeline \\ __MODULE__, did) do
    producer = Broadway.producer_names(pipeline) |> List.first()
    GenStage.cast(producer, {:push, did})
  end

  @doc """
  Pushes multiple DIDs for profile fetching.

  ## Examples

      ProfilePipeline.push_dids(["did:plc:abc", "did:plc:xyz"])
  """
  @spec push_dids(GenServer.server(), [String.t()]) :: :ok
  def push_dids(pipeline \\ __MODULE__, dids) do
    producer = Broadway.producer_names(pipeline) |> List.first()
    GenStage.cast(producer, {:push_batch, dids})
  end

  @doc """
  Returns current pipeline statistics.
  """
  @spec get_stats(GenServer.server()) :: map()
  def get_stats(pipeline \\ __MODULE__) do
    producer = Broadway.producer_names(pipeline) |> List.first()
    GenStage.call(producer, :get_stats)
  end

  # ---------------------------------------------------------------------------
  # Broadway Callbacks
  # ---------------------------------------------------------------------------

  @doc false
  def transform(did, _opts) do
    %Message{
      data: did,
      acknowledger: {__MODULE__, :ack_id, nil}
    }
  end

  @impl Broadway
  def handle_message(:default, %Message{data: did} = message, _context) do
    :telemetry.execute(
      [:atmospheric_hoover, :profile_pipeline, :fetch, :start],
      %{system_time: System.system_time()},
      %{did: did}
    )

    # Check if user already exists in DB before fetching
    if user_exists?(did) do
      :telemetry.execute(
        [:atmospheric_hoover, :profile_pipeline, :fetch, :skip],
        %{count: 1},
        %{did: did, reason: :exists_in_db}
      )

      Message.failed(message, :already_exists)
    else
      case ProfileFetcher.fetch_profile(did) do
        {:ok, profile} ->
          :telemetry.execute(
            [:atmospheric_hoover, :profile_pipeline, :fetch, :stop],
            %{duration: 0},
            %{did: did, status: :ok}
          )

          message
          |> Message.put_data({:ok, did, profile})
          |> Message.put_batcher(:success)

        {:error, reason} ->
          :telemetry.execute(
            [:atmospheric_hoover, :profile_pipeline, :fetch, :stop],
            %{duration: 0},
            %{did: did, status: :error, reason: reason}
          )

          message
          |> Message.put_data({:error, did, reason})
          |> Message.put_batcher(:error)
      end
    end
  end

  defp user_exists?(did) do
    Repo.exists?(from(u in User, where: u.did == ^did))
  end

  @impl Broadway
  def handle_batch(:success, messages, _batch_info, _context) do
    profiles =
      messages
      |> Enum.map(fn %{data: {:ok, _did, profile}} -> profile end)

    :telemetry.execute(
      [:atmospheric_hoover, :profile_pipeline, :batch, :success],
      %{count: length(profiles)},
      %{}
    )

    persist_profiles(profiles)
    messages
  end

  def handle_batch(:error, messages, _batch_info, _context) do
    errors =
      messages
      |> Enum.map(fn %{data: {:error, did, reason}} -> {did, reason} end)

    :telemetry.execute(
      [:atmospheric_hoover, :profile_pipeline, :batch, :error],
      %{count: length(errors)},
      %{}
    )

    persist_errors(errors)
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

  defp persist_profiles([]), do: :ok

  defp persist_profiles(profiles) do
    now = DateTime.utc_now()

    entries =
      profiles
      |> Enum.map(fn profile ->
        %{
          did: profile["did"],
          handle: profile["handle"],
          display_name: profile["displayName"],
          description: profile["description"],
          avatar: profile["avatar"],
          banner: profile["banner"],
          followers_count: profile["followersCount"],
          follows_count: profile["followsCount"],
          posts_count: profile["postsCount"],
          indexed_at: parse_datetime(profile["indexedAt"]),
          created_at: parse_datetime(profile["createdAt"]),
          labels: profile["labels"] || [],
          associated: profile["associated"],
          fetched_at: now,
          fetch_error: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    try do
      Repo.insert_all(User, entries,
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: :did
      )

      Logger.debug("Persisted #{length(entries)} profiles")
    rescue
      e ->
        Logger.warning("Failed to persist profiles: #{inspect(e)}")
    end
  end

  defp persist_errors([]), do: :ok

  defp persist_errors(errors) do
    now = DateTime.utc_now()

    entries =
      Enum.map(errors, fn {did, reason} ->
        %{
          did: did,
          fetch_error: to_string(reason),
          fetched_at: now,
          inserted_at: now,
          updated_at: now
        }
      end)

    try do
      Repo.insert_all(User, entries,
        on_conflict: {:replace, [:fetch_error, :fetched_at, :updated_at]},
        conflict_target: :did
      )

      Logger.debug("Recorded #{length(entries)} fetch errors")
    rescue
      e ->
        Logger.warning("Failed to persist errors: #{inspect(e)}")
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> ensure_usec_precision(dt)
      {:error, _} -> nil
    end
  end

  # Ecto's :utc_datetime_usec requires precision of 6
  defp ensure_usec_precision(%DateTime{microsecond: {usec, _precision}} = dt) do
    %{dt | microsecond: {usec, 6}}
  end
end

defmodule AtmosphericHoover.Bluesky.ProfilePipeline.Producer do
  @moduledoc """
  GenStage producer for the ProfilePipeline with ETS-based deduplication.

  Uses ETS for O(1) deduplication lookups within a session. Database existence
  checks are performed in the processor to avoid blocking demand delivery.
  """

  use GenStage

  require Logger

  @max_queue_size 100_000
  @stats_log_interval_ms 30_000

  @impl GenStage
  def init(opts) do
    pipeline_name = opts[:name] || :default
    table_name = :"#{pipeline_name}_seen"
    table = :ets.new(table_name, [:set, :public])

    state = %{
      queue: :queue.new(),
      demand: 0,
      seen_table: table,
      stats: %{
        dids_received: 0,
        dids_skipped_seen: 0,
        dids_queued: 0,
        dids_dropped: 0,
        started_at: DateTime.utc_now()
      }
    }

    Process.send_after(self(), :log_stats, @stats_log_interval_ms)

    {:producer, state}
  end

  @impl GenStage
  def handle_cast({:push, did}, state) do
    state = process_did(state, did)
    dispatch_events(state)
  end

  @impl GenStage
  def handle_cast({:push_batch, dids}, state) do
    state = Enum.reduce(dids, state, &process_did(&2, &1))
    dispatch_events(state)
  end

  @impl GenStage
  def handle_call(:get_stats, _from, state) do
    stats =
      Map.merge(state.stats, %{
        queue_size: :queue.len(state.queue),
        seen_size: :ets.info(state.seen_table, :size)
      })

    {:reply, stats, [], state}
  end

  @impl GenStage
  def handle_demand(incoming_demand, state) do
    dispatch_events(%{state | demand: state.demand + incoming_demand})
  end

  @impl GenStage
  def handle_info(:log_stats, state) do
    stats = state.stats
    queue_size = :queue.len(state.queue)
    seen_size = :ets.info(state.seen_table, :size)

    :telemetry.execute(
      [:atmospheric_hoover, :profile_pipeline, :producer, :stats],
      %{
        dids_received: stats.dids_received,
        dids_queued: stats.dids_queued,
        dids_skipped_seen: stats.dids_skipped_seen,
        dids_dropped: stats.dids_dropped,
        queue_size: queue_size,
        seen_size: seen_size
      },
      %{}
    )

    Logger.info(
      "ProfilePipeline stats: #{stats.dids_received} received, " <>
        "#{stats.dids_queued} queued, #{stats.dids_skipped_seen} skipped (seen), " <>
        "#{queue_size} in queue, #{seen_size} in seen table"
    )

    Process.send_after(self(), :log_stats, @stats_log_interval_ms)
    {:noreply, [], state}
  end

  # ---------------------------------------------------------------------------
  # Private Functions
  # ---------------------------------------------------------------------------

  defp process_did(state, did) do
    stats = %{state.stats | dids_received: state.stats.dids_received + 1}

    cond do
      # Already seen this session (ETS lookup - O(1))
      :ets.member(state.seen_table, did) ->
        :telemetry.execute(
          [:atmospheric_hoover, :profile_pipeline, :producer, :skip],
          %{count: 1},
          %{reason: :seen}
        )

        %{state | stats: %{stats | dids_skipped_seen: stats.dids_skipped_seen + 1}}

      # Queue is full - drop
      :queue.len(state.queue) >= @max_queue_size ->
        :telemetry.execute(
          [:atmospheric_hoover, :profile_pipeline, :producer, :drop],
          %{count: 1},
          %{reason: :queue_full}
        )

        %{state | stats: %{stats | dids_dropped: stats.dids_dropped + 1}}

      # Enqueue for fetching (DB check happens in processor)
      true ->
        :ets.insert(state.seen_table, {did, true})
        queue = :queue.in(did, state.queue)
        %{state | queue: queue, stats: %{stats | dids_queued: stats.dids_queued + 1}}
    end
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
