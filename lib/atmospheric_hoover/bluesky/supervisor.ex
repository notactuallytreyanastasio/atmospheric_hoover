defmodule AtmosphericHoover.Bluesky.Supervisor do
  @moduledoc """
  Supervisor for the Bluesky firehose subsystem.

  This supervisor manages the firehose WebSocket connection and ensures
  it's restarted if it crashes. Uses a `:rest_for_one` strategy to allow
  for future dependent workers.

  ## Architecture

  ```
  AtmosphericHoover.Bluesky.Supervisor
  └── AtmosphericHoover.Bluesky.Firehose (WebSocket client)
  ```

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

  * `AtmosphericHoover.Bluesky.Firehose` - The WebSocket client that connects
    to the Bluesky Jetstream and processes incoming events.
  """

  use Supervisor

  require Logger

  @doc """
  Starts the Bluesky supervisor.

  ## Options

  * `:name` - Process name (default: `__MODULE__`)
  * `:firehose_opts` - Options passed to the Firehose worker

  ## Examples

      {:ok, pid} = Supervisor.start_link([])

      # With custom firehose options
      {:ok, pid} = Supervisor.start_link(firehose_opts: [persist: false])
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = opts[:name] || __MODULE__
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl Supervisor
  def init(opts) do
    if enabled?() do
      Logger.info("Starting Bluesky Supervisor")

      firehose_opts = opts[:firehose_opts] || []

      children = [
        {AtmosphericHoover.Bluesky.Firehose, firehose_opts}
      ]

      Supervisor.init(children, strategy: :rest_for_one)
    else
      Logger.info("Bluesky Supervisor disabled, not starting firehose")
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
