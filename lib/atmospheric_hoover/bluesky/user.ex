defmodule AtmosphericHoover.Bluesky.User do
  @moduledoc """
  Ecto schema for Bluesky user profiles.

  This schema stores user profile data fetched from the Bluesky API.
  Users are uniquely identified by their DID (Decentralized Identifier).

  ## Fields

  ### Identity
  * `did` - The DID (Decentralized Identifier) of the user (unique)
  * `handle` - User handle (e.g., "alice.bsky.social")
  * `display_name` - Display name shown on profile

  ### Profile Content
  * `description` - User bio/description
  * `avatar` - URL to avatar image
  * `banner` - URL to banner image

  ### Stats
  * `followers_count` - Number of followers
  * `follows_count` - Number of accounts followed
  * `posts_count` - Number of posts

  ### Metadata
  * `indexed_at` - When Bluesky indexed this profile
  * `created_at` - Account creation time
  * `labels` - Content labels/warnings
  * `associated` - Associated lists and other data

  ### Fetch Status
  * `fetched_at` - When we last fetched this profile
  * `fetch_error` - Error message if fetch failed

  ## Examples

      iex> alias AtmosphericHoover.Bluesky.User
      iex> changeset = User.changeset(%User{}, %{
      ...>   did: "did:plc:abc123",
      ...>   handle: "alice.bsky.social",
      ...>   display_name: "Alice"
      ...> })
      iex> changeset.valid?
      true
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          did: String.t() | nil,
          handle: String.t() | nil,
          display_name: String.t() | nil,
          description: String.t() | nil,
          avatar: String.t() | nil,
          banner: String.t() | nil,
          followers_count: integer() | nil,
          follows_count: integer() | nil,
          posts_count: integer() | nil,
          indexed_at: DateTime.t() | nil,
          created_at: DateTime.t() | nil,
          labels: [map()] | nil,
          associated: map() | nil,
          fetched_at: DateTime.t() | nil,
          fetch_error: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "users" do
    field :did, :string
    field :handle, :string
    field :display_name, :string

    field :description, :string
    field :avatar, :string
    field :banner, :string

    field :followers_count, :integer
    field :follows_count, :integer
    field :posts_count, :integer

    field :indexed_at, :utc_datetime_usec
    field :created_at, :utc_datetime_usec

    field :labels, {:array, :map}, default: []
    field :associated, :map

    field :fetched_at, :utc_datetime_usec
    field :fetch_error, :string

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(did)a
  @optional_fields ~w(handle display_name description avatar banner
                      followers_count follows_count posts_count
                      indexed_at created_at labels associated
                      fetched_at fetch_error)a

  @doc """
  Creates a changeset for a user profile.

  ## Parameters

  * `user` - The User struct
  * `attrs` - Map of attributes

  ## Examples

      iex> User.changeset(%User{}, %{did: "did:plc:test"})
      #Ecto.Changeset<...>
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:did)
  end

  @doc """
  Creates a changeset from a Bluesky API profile response.

  ## Parameters

  * `user` - The User struct
  * `profile` - Map from the Bluesky getProfile API response

  ## Examples

      iex> profile = %{
      ...>   "did" => "did:plc:test",
      ...>   "handle" => "test.bsky.social",
      ...>   "displayName" => "Test User",
      ...>   "followersCount" => 100
      ...> }
      iex> User.from_profile(%User{}, profile)
      #Ecto.Changeset<...>
  """
  @spec from_profile(t(), map()) :: Ecto.Changeset.t()
  def from_profile(user, profile) do
    attrs = %{
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
      fetched_at: DateTime.utc_now()
    }

    changeset(user, attrs)
  end

  @doc """
  Creates a changeset marking a fetch error.

  ## Parameters

  * `user` - The User struct
  * `did` - The DID that failed to fetch
  * `error` - Error message

  ## Examples

      iex> User.mark_error(%User{}, "did:plc:test", "not found")
      #Ecto.Changeset<...>
  """
  @spec mark_error(t(), String.t(), String.t()) :: Ecto.Changeset.t()
  def mark_error(user, did, error) do
    changeset(user, %{
      did: did,
      fetch_error: error,
      fetched_at: DateTime.utc_now()
    })
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
