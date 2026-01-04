defmodule AtmosphericHoover.Bluesky.Telemetry do
  @moduledoc """
  Telemetry handlers for the Bluesky pipeline subsystem.

  This module attaches handlers to telemetry events emitted by:
  - Firehose (WebSocket client)
  - EventPipeline (Broadway event processing)
  - ProfilePipeline (Broadway profile fetching)

  ## Events

  ### Firehose Events
  - `[:atmospheric_hoover, :firehose, :message, :received]` - Message received from WebSocket
  - `[:atmospheric_hoover, :firehose, :message, :pushed]` - Message pushed to pipeline
  - `[:atmospheric_hoover, :firehose, :message, :skipped]` - Message skipped (sampling)
  - `[:atmospheric_hoover, :firehose, :stats]` - Periodic stats

  ### EventPipeline Events
  - `[:atmospheric_hoover, :event_pipeline, :parse, :success]` - Event parsed successfully
  - `[:atmospheric_hoover, :event_pipeline, :parse, :error]` - Event parse failed
  - `[:atmospheric_hoover, :event_pipeline, :batch, :process]` - Batch processed
  - `[:atmospheric_hoover, :event_pipeline, :emit_dids]` - DIDs emitted to ProfilePipeline

  ### ProfilePipeline Events
  - `[:atmospheric_hoover, :profile_pipeline, :fetch, :start]` - Profile fetch started
  - `[:atmospheric_hoover, :profile_pipeline, :fetch, :stop]` - Profile fetch completed
  - `[:atmospheric_hoover, :profile_pipeline, :fetch, :skip]` - Profile fetch skipped
  - `[:atmospheric_hoover, :profile_pipeline, :batch, :success]` - Profiles persisted
  - `[:atmospheric_hoover, :profile_pipeline, :batch, :error]` - Errors persisted
  - `[:atmospheric_hoover, :profile_pipeline, :producer, :stats]` - Producer stats
  - `[:atmospheric_hoover, :profile_pipeline, :producer, :skip]` - DID skipped in producer
  - `[:atmospheric_hoover, :profile_pipeline, :producer, :drop]` - DID dropped (queue full)

  ## Usage

  Attach handlers in your application startup:

      def start(_type, _args) do
        AtmosphericHoover.Bluesky.Telemetry.attach()
        # ...
      end

  ## Custom Handlers

  You can attach your own handlers to these events:

      :telemetry.attach(
        "my-handler",
        [:atmospheric_hoover, :firehose, :stats],
        &MyModule.handle_firehose_stats/4,
        nil
      )
  """

  require Logger

  @doc """
  Attaches default telemetry handlers for logging and metrics.
  """
  def attach do
    events = [
      # Firehose events
      [:atmospheric_hoover, :firehose, :stats],

      # EventPipeline events
      [:atmospheric_hoover, :event_pipeline, :batch, :process],

      # ProfilePipeline events
      [:atmospheric_hoover, :profile_pipeline, :batch, :success],
      [:atmospheric_hoover, :profile_pipeline, :batch, :error],
      [:atmospheric_hoover, :profile_pipeline, :producer, :stats]
    ]

    :telemetry.attach_many(
      "atmospheric-hoover-default-handlers",
      events,
      &__MODULE__.handle_event/4,
      nil
    )

    # Attach Broadway telemetry handlers
    attach_broadway_handlers()
  end

  @doc """
  Detaches the default telemetry handlers.
  """
  def detach do
    :telemetry.detach("atmospheric-hoover-default-handlers")
    :telemetry.detach("atmospheric-hoover-broadway-handlers")
  end

  @doc false
  def handle_event([:atmospheric_hoover, :firehose, :stats], measurements, _metadata, _config) do
    Logger.debug(
      "Telemetry: firehose stats - " <>
        "received=#{measurements.messages_received}, " <>
        "pushed=#{measurements.events_pushed}, " <>
        "rate=#{Float.round(measurements.effective_rate * 100, 1)}%"
    )
  end

  def handle_event(
        [:atmospheric_hoover, :event_pipeline, :batch, :process],
        measurements,
        _metadata,
        _config
      ) do
    Logger.debug(
      "Telemetry: event batch processed - " <>
        "success=#{measurements.successful_count}, " <>
        "failed=#{measurements.failed_count}"
    )
  end

  def handle_event(
        [:atmospheric_hoover, :profile_pipeline, :batch, :success],
        measurements,
        _metadata,
        _config
      ) do
    Logger.debug("Telemetry: profiles persisted - count=#{measurements.count}")
  end

  def handle_event(
        [:atmospheric_hoover, :profile_pipeline, :batch, :error],
        measurements,
        _metadata,
        _config
      ) do
    Logger.debug("Telemetry: profile errors persisted - count=#{measurements.count}")
  end

  def handle_event(
        [:atmospheric_hoover, :profile_pipeline, :producer, :stats],
        measurements,
        _metadata,
        _config
      ) do
    Logger.debug(
      "Telemetry: profile producer stats - " <>
        "received=#{measurements.dids_received}, " <>
        "queued=#{measurements.dids_queued}, " <>
        "queue_size=#{measurements.queue_size}"
    )
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end

  # Attach handlers for Broadway's built-in telemetry
  defp attach_broadway_handlers do
    broadway_events = [
      [:broadway, :processor, :start],
      [:broadway, :processor, :stop],
      [:broadway, :processor, :message, :start],
      [:broadway, :processor, :message, :stop],
      [:broadway, :processor, :message, :exception],
      [:broadway, :batcher, :start],
      [:broadway, :batcher, :stop],
      [:broadway, :batch_processor, :start],
      [:broadway, :batch_processor, :stop]
    ]

    :telemetry.attach_many(
      "atmospheric-hoover-broadway-handlers",
      broadway_events,
      &__MODULE__.handle_broadway_event/4,
      nil
    )
  end

  @doc false
  def handle_broadway_event([:broadway, :processor, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    if duration_ms > 1000 do
      Logger.warning(
        "Broadway processor slow: #{duration_ms}ms for #{inspect(metadata.name)}"
      )
    end
  end

  def handle_broadway_event(
        [:broadway, :processor, :message, :exception],
        _measurements,
        metadata,
        _config
      ) do
    Logger.error(
      "Broadway message exception: #{inspect(metadata.kind)} - #{inspect(metadata.reason)}"
    )
  end

  def handle_broadway_event([:broadway, :batch_processor, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    batch_size = length(metadata.messages)

    if duration_ms > 5000 do
      Logger.warning(
        "Broadway batch slow: #{duration_ms}ms for #{batch_size} messages in #{inspect(metadata.name)}"
      )
    end
  end

  def handle_broadway_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end
