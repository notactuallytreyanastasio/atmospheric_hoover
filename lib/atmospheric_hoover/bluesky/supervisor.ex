defmodule AtmosphericHoover.Bluesky.Supervisor do
  @moduledoc """
  Supervisor for the Bluesky firehose subsystem.

  This supervisor manages the Broadway pipelines and WebSocket connection,
  ensuring proper startup order and restart behavior.

  ## Architecture

  ```
  AtmosphericHoover.Bluesky.Supervisor
  ├── EventPipeline (Broadway - event processing)
  ├── ProfilePipeline (Broadway - profile fetching)
  └── Firehose (WebSocket client)
  ```

  The startup order ensures:
  1. Broadway pipelines start first (to receive events)
  2. Firehose starts last (and immediately begins pushing events)

  ## Configuration

  The supervisor can be enabled/disabled via config:

      config :atmospheric_hoover, AtmosphericHoover.Bluesky.Supervisor,
        enabled: true

  Set `enabled: false` to prevent the firehose from connecting on startup.
  This is useful for development or testing environments.

  ## Usage

  Add to your application supervision tree:

      # In lib/atmospheric_hoover/application.ex
      def start(_type, _args) do
        children = [
          # ... other children
          AtmosphericHoover.Bluesky.Supervisor
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end

  Or start manually:

      {:ok, pid} = AtmosphericHoover.Bluesky.Supervisor.start_link([])

  ## Child Processes

  * `EventPipeline` - Broadway pipeline for parsing, persisting, and broadcasting events
  * `ProfilePipeline` - Broadway pipeline for fetching user profiles with ETS dedup
  * `Firehose` - WebSocket client that pushes events to the pipelines
  """

  use Supervisor

  require Logger

  alias AtmosphericHoover.Bluesky.{EventPipeline, ProfilePipeline, Firehose}

  @doc """
  Starts the Bluesky supervisor.

  ## Options

  * `:name` - Process name (default: `__MODULE__`)
  * `:firehose_opts` - Options passed to the Firehose worker
  * `:event_pipeline_opts` - Options passed to EventPipeline
  * `:profile_pipeline_opts` - Options passed to ProfilePipeline

  ## Examples

      {:ok, pid} = Supervisor.start_link([])

      # With custom options
      {:ok, pid} = Supervisor.start_link(
        firehose_opts: [sample_rate: 0.5],
        event_pipeline_opts: [processor_concurrency: 10]
      )
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = opts[:name] || __MODULE__
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl Supervisor
  def init(opts) do
    if enabled?() do
      Logger.info("Starting Bluesky Supervisor with Broadway pipelines")

      firehose_opts = opts[:firehose_opts] || []
      event_pipeline_opts = opts[:event_pipeline_opts] || []
      profile_pipeline_opts = opts[:profile_pipeline_opts] || []

      children = [
        # Task supervisor for async operations
        {Task.Supervisor, name: AtmosphericHoover.Bluesky.TaskSupervisor},

        # Start Broadway pipelines first
        {EventPipeline, event_pipeline_opts},
        {ProfilePipeline, profile_pipeline_opts},

        # Start firehose last (it will push to EventPipeline)
        {Firehose, firehose_opts}
      ]

      # Use rest_for_one so if a pipeline crashes, firehose restarts too
      Supervisor.init(children, strategy: :rest_for_one)
    else
      Logger.info("Bluesky Supervisor disabled, not starting pipelines")
      :ignore
    end
  end

  @doc """
  Checks if the supervisor is enabled.

  Returns `true` if the supervisor should start its children.

  ## Examples

      iex> AtmosphericHoover.Bluesky.Supervisor.enabled?()
      true
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:atmospheric_hoover, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end
end
