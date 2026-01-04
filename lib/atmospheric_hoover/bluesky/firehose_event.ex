defmodule AtmosphericHoover.Bluesky.FirehoseEvent do
  @moduledoc """
  Ecto schema for persisting Bluesky firehose events to PostgreSQL.

  This schema stores all event types from the Jetstream firehose:
  commits (creates, updates, deletes), identity updates, and account changes.

  ## Fields

  ### Event Metadata
  * `did` - The DID (Decentralized Identifier) of the user
  * `time_us` - Timestamp in microseconds from the firehose
  * `kind` - Event kind: "commit", "identity", or "account"

  ### Commit Fields (for kind="commit")
  * `rev` - Repository revision string
  * `operation` - "create", "update", or "delete"
  * `collection` - Record collection (e.g., "app.bsky.feed.post")
  * `rkey` - Record key within the collection
  * `cid` - Content identifier (hash)
  * `record` - The full record data as JSONB

  ### Identity/Account Fields
  * `handle` - User handle (for identity events)
  * `active` - Account active status (for account events)
  * `status` - Account status string (for account events)
  * `seq` - Sequence number

  ## Examples

      iex> alias AtmosphericHoover.Bluesky.FirehoseEvent
      iex> changeset = FirehoseEvent.changeset(%FirehoseEvent{}, %{
      ...>   did: "did:plc:abc123",
      ...>   time_us: 1725911162329308,
      ...>   kind: "commit",
      ...>   operation: "create",
      ...>   collection: "app.bsky.feed.post",
      ...>   rkey: "xyz789",
      ...>   record: %{"text" => "Hello!"}
      ...> })
      iex> changeset.valid?
      true
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AtmosphericHoover.Bluesky.Types.Event

  @type t :: %__MODULE__{
          id: integer() | nil,
          did: String.t() | nil,
          time_us: integer() | nil,
          kind: String.t() | nil,
          rev: String.t() | nil,
          operation: String.t() | nil,
          collection: String.t() | nil,
          rkey: String.t() | nil,
          cid: String.t() | nil,
          record: map() | nil,
          handle: String.t() | nil,
          active: boolean() | nil,
          status: String.t() | nil,
          seq: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "firehose_events" do
    field :did, :string
    field :time_us, :integer
    field :kind, :string

    # Commit fields
    field :rev, :string
    field :operation, :string
    field :collection, :string
    field :rkey, :string
    field :cid, :string
    field :record, :map

    # Identity/Account fields
    field :handle, :string
    field :active, :boolean
    field :status, :string
    field :seq, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(did time_us kind)a
  @optional_fields ~w(rev operation collection rkey cid record handle active status seq)a

  @doc """
  Creates a changeset for a firehose event.

  ## Parameters

  * `event` - The FirehoseEvent struct
  * `attrs` - Map of attributes

  ## Examples

      iex> FirehoseEvent.changeset(%FirehoseEvent{}, %{did: "did:plc:test", time_us: 123, kind: "commit"})
      #Ecto.Changeset<...>
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:kind, ~w(commit identity account))
    |> validate_inclusion(:operation, ~w(create update delete), allow_nil: true)
    |> unique_constraint([:did, :collection, :rkey], name: :firehose_events_unique_record)
  end

  @doc """
  Converts a parsed Event struct to attributes for database insertion.

  This function transforms the typed structs from `AtmosphericHoover.Bluesky.Types`
  into a flat map suitable for the database schema.

  ## Parameters

  * `event` - A parsed `Event.t()` struct

  ## Returns

  * Map of attributes ready for `changeset/2`

  ## Examples

      iex> alias AtmosphericHoover.Bluesky.{Parser, FirehoseEvent}
      iex> {:ok, event} = Parser.parse_event(%{
      ...>   "did" => "did:plc:test",
      ...>   "time_us" => 123456,
      ...>   "kind" => "commit",
      ...>   "commit" => %{
      ...>     "rev" => "abc",
      ...>     "operation" => "create",
      ...>     "collection" => "app.bsky.feed.post",
      ...>     "rkey" => "xyz",
      ...>     "cid" => "bafyrei"
      ...>   }
      ...> })
      iex> attrs = FirehoseEvent.from_event(event)
      iex> attrs.collection
      "app.bsky.feed.post"
  """
  @spec from_event(Event.t()) :: map()
  def from_event(%Event{} = event) do
    base = %{
      did: event.did,
      time_us: event.time_us,
      kind: Atom.to_string(event.kind)
    }

    base
    |> maybe_add_commit(event.commit)
    |> maybe_add_identity(event.identity)
    |> maybe_add_account(event.account)
  end

  defp maybe_add_commit(attrs, nil), do: attrs

  defp maybe_add_commit(attrs, commit) do
    Map.merge(attrs, %{
      rev: commit.rev,
      operation: commit.operation && Atom.to_string(commit.operation),
      collection: commit.collection,
      rkey: commit.rkey,
      cid: commit.cid,
      record: serialize_record(commit.record)
    })
  end

  defp maybe_add_identity(attrs, nil), do: attrs

  defp maybe_add_identity(attrs, identity) do
    Map.merge(attrs, %{
      handle: identity.handle,
      seq: identity.seq
    })
  end

  defp maybe_add_account(attrs, nil), do: attrs

  defp maybe_add_account(attrs, account) do
    Map.merge(attrs, %{
      active: account.active,
      status: account.status,
      seq: account.seq
    })
  end

  # Serialize typed record structs back to maps for JSONB storage
  defp serialize_record(nil), do: nil
  defp serialize_record(record) when is_map(record), do: deep_serialize(record)

  # DateTime must be matched BEFORE generic struct to avoid Map.from_struct
  # converting it to a map with tuple fields that Jason can't encode
  defp deep_serialize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp deep_serialize(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), deep_serialize(v)} end)
    |> Map.new()
  end

  defp deep_serialize(list) when is_list(list) do
    Enum.map(list, &deep_serialize/1)
  end

  defp deep_serialize(value), do: value
end
