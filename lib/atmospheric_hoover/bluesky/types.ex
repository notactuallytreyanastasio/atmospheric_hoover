defmodule AtmosphericHoover.Bluesky.Types do
  @moduledoc """
  Type definitions for Bluesky AT Protocol firehose events.

  This module defines typed structs for all record types received from the
  Bluesky Jetstream firehose. The types mirror the AT Protocol lexicon schemas.

  ## Event Kinds

  The firehose emits three kinds of events:

  * `:commit` - A repository commit (create, update, or delete of a record)
  * `:identity` - A DID identity change
  * `:account` - An account status change (active, deactivated, takendown)

  ## Collections

  Supported record collections:

  * `app.bsky.feed.post` - Posts/skeets
  * `app.bsky.feed.like` - Likes on posts
  * `app.bsky.feed.repost` - Reposts/shares
  * `app.bsky.graph.follow` - Follow relationships

  ## Examples

      iex> alias AtmosphericHoover.Bluesky.Types
      iex> %Types.Post{text: "Hello!", created_at: ~U[2024-01-01 00:00:00Z]}
      %AtmosphericHoover.Bluesky.Types.Post{text: "Hello!", created_at: ~U[2024-01-01 00:00:00Z], embed: nil, facets: nil, reply: nil, langs: nil, labels: nil, tags: nil}
  """

  @typedoc "Bluesky DID (Decentralized Identifier)"
  @type did :: String.t()

  @typedoc "AT Protocol URI (at://did/collection/rkey)"
  @type at_uri :: String.t()

  @typedoc "Content Identifier (CID) - immutable hash"
  @type cid :: String.t()

  @typedoc "Record key within a collection"
  @type rkey :: String.t()

  @typedoc "Collection name (e.g., app.bsky.feed.post)"
  @type collection :: String.t()

  @typedoc "Commit operation type"
  @type operation :: :create | :update | :delete

  @typedoc "Event kind from the firehose"
  @type event_kind :: :commit | :identity | :account

  # -----------------------------------------------------------------------------
  # Reference Types
  # -----------------------------------------------------------------------------

  defmodule StrongRef do
    @moduledoc """
    A strong reference to another record, containing both URI and CID.

    Used for referencing posts in likes, reposts, and reply chains.
    The CID ensures immutability - if the record changes, the CID changes.

    ## Examples

        iex> %AtmosphericHoover.Bluesky.Types.StrongRef{
        ...>   uri: "at://did:plc:abc123/app.bsky.feed.post/xyz",
        ...>   cid: "bafyreihash..."
        ...> }
        %AtmosphericHoover.Bluesky.Types.StrongRef{uri: "at://did:plc:abc123/app.bsky.feed.post/xyz", cid: "bafyreihash..."}
    """
    @type t :: %__MODULE__{
            uri: String.t(),
            cid: String.t()
          }

    defstruct [:uri, :cid]
  end

  defmodule ReplyRef do
    @moduledoc """
    Reply reference containing parent and root post references.

    In a reply chain A -> B -> C:
    * For C replying to B: parent is B, root is A
    * For B replying to A: parent is A, root is A (same)

    ## Examples

        iex> parent = %AtmosphericHoover.Bluesky.Types.StrongRef{uri: "at://did:plc:abc/app.bsky.feed.post/parent", cid: "bafyparent"}
        iex> root = %AtmosphericHoover.Bluesky.Types.StrongRef{uri: "at://did:plc:abc/app.bsky.feed.post/root", cid: "bafyroot"}
        iex> %AtmosphericHoover.Bluesky.Types.ReplyRef{parent: parent, root: root}
        %AtmosphericHoover.Bluesky.Types.ReplyRef{parent: %AtmosphericHoover.Bluesky.Types.StrongRef{uri: "at://did:plc:abc/app.bsky.feed.post/parent", cid: "bafyparent"}, root: %AtmosphericHoover.Bluesky.Types.StrongRef{uri: "at://did:plc:abc/app.bsky.feed.post/root", cid: "bafyroot"}}
    """
    @type t :: %__MODULE__{
            parent: StrongRef.t(),
            root: StrongRef.t()
          }

    defstruct [:parent, :root]
  end

  # -----------------------------------------------------------------------------
  # Facets (Rich Text)
  # -----------------------------------------------------------------------------

  defmodule ByteSlice do
    @moduledoc """
    Byte range for a facet feature within text.

    Note: These are byte indices, not character indices.
    UTF-8 characters may span multiple bytes.
    """
    @type t :: %__MODULE__{
            byte_start: non_neg_integer(),
            byte_end: non_neg_integer()
          }

    defstruct [:byte_start, :byte_end]
  end

  defmodule FacetFeature do
    @moduledoc """
    A rich text feature within a facet.

    Feature types:
    * `:mention` - User mention with DID
    * `:link` - External URL
    * `:tag` - Hashtag
    """
    @type feature_type :: :mention | :link | :tag

    @type t :: %__MODULE__{
            type: feature_type(),
            uri: String.t() | nil,
            did: String.t() | nil,
            tag: String.t() | nil
          }

    defstruct [:type, :uri, :did, :tag]
  end

  defmodule Facet do
    @moduledoc """
    A facet annotates a byte range of post text with rich features.

    Used for mentions, links, and hashtags within post text.

    ## Examples

        iex> feature = %AtmosphericHoover.Bluesky.Types.FacetFeature{type: :mention, did: "did:plc:abc123"}
        iex> index = %AtmosphericHoover.Bluesky.Types.ByteSlice{byte_start: 0, byte_end: 10}
        iex> %AtmosphericHoover.Bluesky.Types.Facet{index: index, features: [feature]}
        %AtmosphericHoover.Bluesky.Types.Facet{index: %AtmosphericHoover.Bluesky.Types.ByteSlice{byte_start: 0, byte_end: 10}, features: [%AtmosphericHoover.Bluesky.Types.FacetFeature{type: :mention, did: "did:plc:abc123", uri: nil, tag: nil}]}
    """
    @type t :: %__MODULE__{
            index: ByteSlice.t(),
            features: [FacetFeature.t()]
          }

    defstruct [:index, :features]
  end

  # -----------------------------------------------------------------------------
  # Embeds
  # -----------------------------------------------------------------------------

  defmodule ImageEmbed do
    @moduledoc """
    An image embedded in a post.
    """
    @type t :: %__MODULE__{
            alt: String.t() | nil,
            image: map() | nil,
            aspect_ratio: map() | nil
          }

    defstruct [:alt, :image, :aspect_ratio]
  end

  defmodule ExternalEmbed do
    @moduledoc """
    An external link embed (link card preview).
    """
    @type t :: %__MODULE__{
            uri: String.t(),
            title: String.t(),
            description: String.t(),
            thumb: map() | nil
          }

    defstruct [:uri, :title, :description, :thumb]
  end

  defmodule Embed do
    @moduledoc """
    Embedded media in a post.

    Embed types:
    * `:images` - One or more images
    * `:external` - External link card
    * `:record` - Quote post
    * `:record_with_media` - Quote post with media
    * `:video` - Video content
    """
    @type embed_type :: :images | :external | :record | :record_with_media | :video

    @type t :: %__MODULE__{
            type: embed_type(),
            images: [ImageEmbed.t()] | nil,
            external: ExternalEmbed.t() | nil,
            record: StrongRef.t() | nil,
            video: map() | nil
          }

    defstruct [:type, :images, :external, :record, :video]
  end

  # -----------------------------------------------------------------------------
  # Record Types
  # -----------------------------------------------------------------------------

  defmodule Post do
    @moduledoc """
    A Bluesky post (skeet) record.

    ## Required Fields

    * `text` - The post content (may be empty if embeds present)
    * `created_at` - Client-declared timestamp

    ## Optional Fields

    * `embed` - Embedded media (images, links, videos, quote posts)
    * `facets` - Rich text formatting (mentions, links, hashtags)
    * `reply` - Reply chain references
    * `langs` - Language codes (max 3)
    * `labels` - Self-applied content labels
    * `tags` - Post tags (max 8)

    ## Examples

        iex> %AtmosphericHoover.Bluesky.Types.Post{
        ...>   text: "Hello Bluesky!",
        ...>   created_at: ~U[2024-01-01 12:00:00Z],
        ...>   langs: ["en"]
        ...> }
        %AtmosphericHoover.Bluesky.Types.Post{text: "Hello Bluesky!", created_at: ~U[2024-01-01 12:00:00Z], langs: ["en"], embed: nil, facets: nil, reply: nil, labels: nil, tags: nil}
    """
    alias AtmosphericHoover.Bluesky.Types.{Embed, Facet, ReplyRef}

    @type t :: %__MODULE__{
            text: String.t(),
            created_at: DateTime.t(),
            embed: Embed.t() | nil,
            facets: [Facet.t()] | nil,
            reply: ReplyRef.t() | nil,
            langs: [String.t()] | nil,
            labels: map() | nil,
            tags: [String.t()] | nil
          }

    defstruct [:text, :created_at, :embed, :facets, :reply, :langs, :labels, :tags]
  end

  defmodule Like do
    @moduledoc """
    A like record on a post.

    ## Fields

    * `subject` - Reference to the liked post (URI and CID)
    * `created_at` - When the like was created

    ## Examples

        iex> subject = %AtmosphericHoover.Bluesky.Types.StrongRef{
        ...>   uri: "at://did:plc:abc/app.bsky.feed.post/123",
        ...>   cid: "bafyrei..."
        ...> }
        iex> %AtmosphericHoover.Bluesky.Types.Like{
        ...>   subject: subject,
        ...>   created_at: ~U[2024-01-01 12:00:00Z]
        ...> }
        %AtmosphericHoover.Bluesky.Types.Like{subject: %AtmosphericHoover.Bluesky.Types.StrongRef{uri: "at://did:plc:abc/app.bsky.feed.post/123", cid: "bafyrei..."}, created_at: ~U[2024-01-01 12:00:00Z]}
    """
    alias AtmosphericHoover.Bluesky.Types.StrongRef

    @type t :: %__MODULE__{
            subject: StrongRef.t(),
            created_at: DateTime.t()
          }

    defstruct [:subject, :created_at]
  end

  defmodule Repost do
    @moduledoc """
    A repost/share record.

    ## Fields

    * `subject` - Reference to the reposted post (URI and CID)
    * `created_at` - When the repost was created

    ## Examples

        iex> subject = %AtmosphericHoover.Bluesky.Types.StrongRef{
        ...>   uri: "at://did:plc:abc/app.bsky.feed.post/123",
        ...>   cid: "bafyrei..."
        ...> }
        iex> %AtmosphericHoover.Bluesky.Types.Repost{
        ...>   subject: subject,
        ...>   created_at: ~U[2024-01-01 12:00:00Z]
        ...> }
        %AtmosphericHoover.Bluesky.Types.Repost{subject: %AtmosphericHoover.Bluesky.Types.StrongRef{uri: "at://did:plc:abc/app.bsky.feed.post/123", cid: "bafyrei..."}, created_at: ~U[2024-01-01 12:00:00Z]}
    """
    alias AtmosphericHoover.Bluesky.Types.StrongRef

    @type t :: %__MODULE__{
            subject: StrongRef.t(),
            created_at: DateTime.t()
          }

    defstruct [:subject, :created_at]
  end

  defmodule Follow do
    @moduledoc """
    A follow relationship record.

    ## Fields

    * `subject` - DID of the user being followed
    * `created_at` - When the follow was created

    ## Examples

        iex> %AtmosphericHoover.Bluesky.Types.Follow{
        ...>   subject: "did:plc:targetuser123",
        ...>   created_at: ~U[2024-01-01 12:00:00Z]
        ...> }
        %AtmosphericHoover.Bluesky.Types.Follow{subject: "did:plc:targetuser123", created_at: ~U[2024-01-01 12:00:00Z]}
    """
    @type t :: %__MODULE__{
            subject: String.t(),
            created_at: DateTime.t()
          }

    defstruct [:subject, :created_at]
  end

  # -----------------------------------------------------------------------------
  # Event Types
  # -----------------------------------------------------------------------------

  defmodule Commit do
    @moduledoc """
    A commit event from the firehose.

    Represents a create, update, or delete operation on a record.

    ## Fields

    * `rev` - Repository revision string
    * `operation` - `:create`, `:update`, or `:delete`
    * `collection` - Record collection (e.g., "app.bsky.feed.post")
    * `rkey` - Record key within the collection
    * `record` - The record data (nil for deletes)
    * `cid` - Content identifier for the record

    ## Examples

        iex> %AtmosphericHoover.Bluesky.Types.Commit{
        ...>   rev: "3l3qo2vutsw2b",
        ...>   operation: :create,
        ...>   collection: "app.bsky.feed.post",
        ...>   rkey: "3l3qo2vuowo2b",
        ...>   record: %{text: "Hello!"},
        ...>   cid: "bafyrei..."
        ...> }
        %AtmosphericHoover.Bluesky.Types.Commit{rev: "3l3qo2vutsw2b", operation: :create, collection: "app.bsky.feed.post", rkey: "3l3qo2vuowo2b", record: %{text: "Hello!"}, cid: "bafyrei..."}
    """
    @type t :: %__MODULE__{
            rev: String.t(),
            operation: AtmosphericHoover.Bluesky.Types.operation(),
            collection: String.t(),
            rkey: String.t(),
            record: map() | Post.t() | Like.t() | Repost.t() | Follow.t() | nil,
            cid: String.t() | nil
          }

    defstruct [:rev, :operation, :collection, :rkey, :record, :cid]
  end

  defmodule Identity do
    @moduledoc """
    An identity update event.

    Indicates a DID document or handle change that should trigger cache invalidation.

    ## Fields

    * `did` - The DID whose identity changed
    * `handle` - The new handle (if changed)
    * `seq` - Sequence number
    """
    @type t :: %__MODULE__{
            did: String.t(),
            handle: String.t() | nil,
            seq: integer() | nil
          }

    defstruct [:did, :handle, :seq]
  end

  defmodule Account do
    @moduledoc """
    An account status change event.

    Indicates account state changes like activation, deactivation, or takedown.

    ## Fields

    * `did` - The DID of the account
    * `active` - Whether the account is active
    * `status` - Status string (e.g., "active", "deactivated", "takendown")
    * `seq` - Sequence number
    """
    @type t :: %__MODULE__{
            did: String.t(),
            active: boolean(),
            status: String.t() | nil,
            seq: integer() | nil
          }

    defstruct [:did, :active, :status, :seq]
  end

  defmodule Event do
    @moduledoc """
    A complete firehose event.

    This is the top-level structure received from the Jetstream WebSocket.

    ## Fields

    * `did` - DID of the user who generated the event
    * `time_us` - Timestamp in microseconds
    * `kind` - Event kind (`:commit`, `:identity`, `:account`)
    * `commit` - Commit data (for commit events)
    * `identity` - Identity data (for identity events)
    * `account` - Account data (for account events)

    ## Examples

        iex> commit = %AtmosphericHoover.Bluesky.Types.Commit{
        ...>   rev: "abc123",
        ...>   operation: :create,
        ...>   collection: "app.bsky.feed.post",
        ...>   rkey: "xyz789",
        ...>   record: nil,
        ...>   cid: nil
        ...> }
        iex> %AtmosphericHoover.Bluesky.Types.Event{
        ...>   did: "did:plc:abc123",
        ...>   time_us: 1725911162329308,
        ...>   kind: :commit,
        ...>   commit: commit
        ...> }
        %AtmosphericHoover.Bluesky.Types.Event{did: "did:plc:abc123", time_us: 1725911162329308, kind: :commit, commit: %AtmosphericHoover.Bluesky.Types.Commit{rev: "abc123", operation: :create, collection: "app.bsky.feed.post", rkey: "xyz789", record: nil, cid: nil}, identity: nil, account: nil}
    """
    @type t :: %__MODULE__{
            did: String.t(),
            time_us: integer(),
            kind: AtmosphericHoover.Bluesky.Types.event_kind(),
            commit: Commit.t() | nil,
            identity: Identity.t() | nil,
            account: Account.t() | nil
          }

    defstruct [:did, :time_us, :kind, :commit, :identity, :account]
  end
end
