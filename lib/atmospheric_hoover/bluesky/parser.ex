defmodule AtmosphericHoover.Bluesky.Parser do
  @moduledoc """
  Functional core for parsing Bluesky Jetstream firehose events.

  This module provides pure functions for transforming raw JSON data from
  the Bluesky Jetstream WebSocket into typed Elixir structs. All functions
  are designed to be composable, testable, and side-effect free.

  ## Architecture

  The parser follows a functional core pattern:

  1. **Input**: Raw JSON binary or decoded map from WebSocket
  2. **Processing**: Pure transformation functions
  3. **Output**: Typed structs from `AtmosphericHoover.Bluesky.Types`

  ## Usage

      iex> json = ~s({"did":"did:plc:abc","time_us":123,"kind":"commit","commit":{"rev":"xyz","operation":"create","collection":"app.bsky.feed.post","rkey":"abc"}})
      iex> {:ok, event} = AtmosphericHoover.Bluesky.Parser.parse_event(json)
      iex> event.kind
      :commit

  ## Parsing Pipeline

  The module exposes a main entry point `parse_event/1` and individual
  record parsers for testing and composition:

  * `parse_event/1` - Parse a complete firehose event
  * `parse_commit/1` - Parse a commit object
  * `parse_post/1` - Parse a post record
  * `parse_like/1` - Parse a like record
  * `parse_repost/1` - Parse a repost record
  * `parse_follow/1` - Parse a follow record
  """

  alias AtmosphericHoover.Bluesky.Types.{
    Account,
    ByteSlice,
    Commit,
    Embed,
    Event,
    ExternalEmbed,
    Facet,
    FacetFeature,
    Follow,
    Identity,
    ImageEmbed,
    Like,
    Post,
    ReplyRef,
    Repost,
    StrongRef
  }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Parses a raw JSON event from the Jetstream firehose.

  Accepts either a JSON binary string or an already-decoded map.

  ## Parameters

  * `input` - JSON string or decoded map

  ## Returns

  * `{:ok, Event.t()}` - Successfully parsed event
  * `{:error, reason}` - Parse failure with reason

  ## Examples

      iex> json = ~s({"did":"did:plc:test","time_us":1000000,"kind":"commit","commit":{"rev":"abc","operation":"create","collection":"app.bsky.feed.post","rkey":"xyz"}})
      iex> {:ok, event} = AtmosphericHoover.Bluesky.Parser.parse_event(json)
      iex> event.did
      "did:plc:test"
      iex> event.kind
      :commit

      iex> AtmosphericHoover.Bluesky.Parser.parse_event("not json")
      {:error, {:json_decode_error, %Jason.DecodeError{position: 0, token: nil, data: "not json"}}}
  """
  @spec parse_event(binary() | map()) :: {:ok, Event.t()} | {:error, term()}
  def parse_event(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, data} -> parse_event(data)
      {:error, error} -> {:error, {:json_decode_error, error}}
    end
  end

  def parse_event(data) when is_map(data) do
    with {:ok, kind} <- parse_kind(data["kind"]),
         {:ok, time_us} <- parse_time_us(data["time_us"]),
         {:ok, did} <- parse_did(data["did"]) do
      event = %Event{
        did: did,
        time_us: time_us,
        kind: kind,
        commit: parse_commit_if_present(data["commit"], kind),
        identity: parse_identity_if_present(data["identity"], kind),
        account: parse_account_if_present(data["account"], kind)
      }

      {:ok, event}
    end
  end

  @doc """
  Parses a commit object from a firehose event.

  ## Parameters

  * `data` - Map containing commit fields

  ## Returns

  * `{:ok, Commit.t()}` - Successfully parsed commit
  * `{:error, reason}` - Parse failure

  ## Examples

      iex> data = %{"rev" => "abc", "operation" => "create", "collection" => "app.bsky.feed.post", "rkey" => "xyz", "cid" => "bafyrei"}
      iex> {:ok, commit} = AtmosphericHoover.Bluesky.Parser.parse_commit(data)
      iex> commit.operation
      :create
      iex> commit.collection
      "app.bsky.feed.post"
  """
  @spec parse_commit(map()) :: {:ok, Commit.t()} | {:error, term()}
  def parse_commit(data) when is_map(data) do
    with {:ok, operation} <- parse_operation(data["operation"]) do
      collection = data["collection"]
      record = parse_record(data["record"], collection)

      commit = %Commit{
        rev: data["rev"],
        operation: operation,
        collection: collection,
        rkey: data["rkey"],
        cid: data["cid"],
        record: record
      }

      {:ok, commit}
    end
  end

  def parse_commit(nil), do: {:ok, nil}

  @doc """
  Parses a post record from the firehose.

  ## Parameters

  * `data` - Map containing post fields

  ## Returns

  * `Post.t()` - Parsed post struct

  ## Examples

      iex> data = %{"text" => "Hello!", "createdAt" => "2024-01-01T12:00:00.000Z"}
      iex> post = AtmosphericHoover.Bluesky.Parser.parse_post(data)
      iex> post.text
      "Hello!"

      iex> data = %{"text" => "Reply!", "createdAt" => "2024-01-01T12:00:00.000Z", "reply" => %{"parent" => %{"uri" => "at://did/post/1", "cid" => "cid1"}, "root" => %{"uri" => "at://did/post/0", "cid" => "cid0"}}}
      iex> post = AtmosphericHoover.Bluesky.Parser.parse_post(data)
      iex> post.reply.parent.uri
      "at://did/post/1"
  """
  @spec parse_post(map() | nil) :: Post.t() | nil
  def parse_post(nil), do: nil

  def parse_post(data) when is_map(data) do
    %Post{
      text: data["text"] || "",
      created_at: parse_datetime(data["createdAt"]),
      embed: parse_embed(data["embed"]),
      facets: parse_facets(data["facets"]),
      reply: parse_reply_ref(data["reply"]),
      langs: data["langs"],
      labels: data["labels"],
      tags: data["tags"]
    }
  end

  @doc """
  Parses a like record from the firehose.

  ## Parameters

  * `data` - Map containing like fields

  ## Returns

  * `Like.t()` - Parsed like struct

  ## Examples

      iex> data = %{"subject" => %{"uri" => "at://did/post/1", "cid" => "bafyrei"}, "createdAt" => "2024-01-01T12:00:00.000Z"}
      iex> like = AtmosphericHoover.Bluesky.Parser.parse_like(data)
      iex> like.subject.uri
      "at://did/post/1"
  """
  @spec parse_like(map() | nil) :: Like.t() | nil
  def parse_like(nil), do: nil

  def parse_like(data) when is_map(data) do
    %Like{
      subject: parse_strong_ref(data["subject"]),
      created_at: parse_datetime(data["createdAt"])
    }
  end

  @doc """
  Parses a repost record from the firehose.

  ## Parameters

  * `data` - Map containing repost fields

  ## Returns

  * `Repost.t()` - Parsed repost struct

  ## Examples

      iex> data = %{"subject" => %{"uri" => "at://did/post/1", "cid" => "bafyrei"}, "createdAt" => "2024-01-01T12:00:00.000Z"}
      iex> repost = AtmosphericHoover.Bluesky.Parser.parse_repost(data)
      iex> repost.subject.cid
      "bafyrei"
  """
  @spec parse_repost(map() | nil) :: Repost.t() | nil
  def parse_repost(nil), do: nil

  def parse_repost(data) when is_map(data) do
    %Repost{
      subject: parse_strong_ref(data["subject"]),
      created_at: parse_datetime(data["createdAt"])
    }
  end

  @doc """
  Parses a follow record from the firehose.

  ## Parameters

  * `data` - Map containing follow fields

  ## Returns

  * `Follow.t()` - Parsed follow struct

  ## Examples

      iex> data = %{"subject" => "did:plc:targetuser", "createdAt" => "2024-01-01T12:00:00.000Z"}
      iex> follow = AtmosphericHoover.Bluesky.Parser.parse_follow(data)
      iex> follow.subject
      "did:plc:targetuser"
  """
  @spec parse_follow(map() | nil) :: Follow.t() | nil
  def parse_follow(nil), do: nil

  def parse_follow(data) when is_map(data) do
    %Follow{
      subject: data["subject"],
      created_at: parse_datetime(data["createdAt"])
    }
  end

  @doc """
  Parses an identity event from the firehose.

  ## Examples

      iex> data = %{"did" => "did:plc:abc", "handle" => "alice.bsky.social", "seq" => 123}
      iex> identity = AtmosphericHoover.Bluesky.Parser.parse_identity(data)
      iex> identity.handle
      "alice.bsky.social"
  """
  @spec parse_identity(map() | nil) :: Identity.t() | nil
  def parse_identity(nil), do: nil

  def parse_identity(data) when is_map(data) do
    %Identity{
      did: data["did"],
      handle: data["handle"],
      seq: data["seq"]
    }
  end

  @doc """
  Parses an account event from the firehose.

  ## Examples

      iex> data = %{"did" => "did:plc:abc", "active" => true, "status" => "active", "seq" => 123}
      iex> account = AtmosphericHoover.Bluesky.Parser.parse_account(data)
      iex> account.active
      true
  """
  @spec parse_account(map() | nil) :: Account.t() | nil
  def parse_account(nil), do: nil

  def parse_account(data) when is_map(data) do
    %Account{
      did: data["did"],
      active: data["active"],
      status: data["status"],
      seq: data["seq"]
    }
  end

  @doc """
  Parses a strong reference (URI + CID).

  ## Examples

      iex> data = %{"uri" => "at://did/coll/rkey", "cid" => "bafyrei"}
      iex> ref = AtmosphericHoover.Bluesky.Parser.parse_strong_ref(data)
      iex> ref.uri
      "at://did/coll/rkey"
  """
  @spec parse_strong_ref(map() | nil) :: StrongRef.t() | nil
  def parse_strong_ref(nil), do: nil

  def parse_strong_ref(data) when is_map(data) do
    %StrongRef{
      uri: data["uri"],
      cid: data["cid"]
    }
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp parse_kind("commit"), do: {:ok, :commit}
  defp parse_kind("identity"), do: {:ok, :identity}
  defp parse_kind("account"), do: {:ok, :account}
  defp parse_kind(other), do: {:error, {:invalid_kind, other}}

  defp parse_operation("create"), do: {:ok, :create}
  defp parse_operation("update"), do: {:ok, :update}
  defp parse_operation("delete"), do: {:ok, :delete}
  defp parse_operation(other), do: {:error, {:invalid_operation, other}}

  defp parse_time_us(time_us) when is_integer(time_us), do: {:ok, time_us}
  defp parse_time_us(nil), do: {:error, :missing_time_us}
  defp parse_time_us(other), do: {:error, {:invalid_time_us, other}}

  defp parse_did(did) when is_binary(did), do: {:ok, did}
  defp parse_did(nil), do: {:error, :missing_did}
  defp parse_did(other), do: {:error, {:invalid_did, other}}

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> nil
    end
  end

  defp parse_commit_if_present(data, :commit), do: parse_commit_unsafe(data)
  defp parse_commit_if_present(_, _), do: nil

  defp parse_commit_unsafe(nil), do: nil

  defp parse_commit_unsafe(data) do
    case parse_commit(data) do
      {:ok, commit} -> commit
      {:error, _} -> nil
    end
  end

  defp parse_identity_if_present(data, :identity), do: parse_identity(data)
  defp parse_identity_if_present(_, _), do: nil

  defp parse_account_if_present(data, :account), do: parse_account(data)
  defp parse_account_if_present(_, _), do: nil

  defp parse_record(nil, _collection), do: nil
  defp parse_record(data, "app.bsky.feed.post"), do: parse_post(data)
  defp parse_record(data, "app.bsky.feed.like"), do: parse_like(data)
  defp parse_record(data, "app.bsky.feed.repost"), do: parse_repost(data)
  defp parse_record(data, "app.bsky.graph.follow"), do: parse_follow(data)
  defp parse_record(data, _collection), do: data

  defp parse_reply_ref(nil), do: nil

  defp parse_reply_ref(data) when is_map(data) do
    %ReplyRef{
      parent: parse_strong_ref(data["parent"]),
      root: parse_strong_ref(data["root"])
    }
  end

  defp parse_embed(nil), do: nil

  defp parse_embed(%{"$type" => "app.bsky.embed.images"} = data) do
    %Embed{
      type: :images,
      images: parse_images(data["images"])
    }
  end

  defp parse_embed(%{"$type" => "app.bsky.embed.external"} = data) do
    %Embed{
      type: :external,
      external: parse_external(data["external"])
    }
  end

  defp parse_embed(%{"$type" => "app.bsky.embed.record"} = data) do
    %Embed{
      type: :record,
      record: parse_strong_ref(data["record"])
    }
  end

  defp parse_embed(%{"$type" => "app.bsky.embed.recordWithMedia"} = data) do
    %Embed{
      type: :record_with_media,
      record: parse_strong_ref(get_in(data, ["record", "record"])),
      images: parse_images(get_in(data, ["media", "images"]))
    }
  end

  defp parse_embed(%{"$type" => "app.bsky.embed.video"} = data) do
    %Embed{
      type: :video,
      video: data["video"]
    }
  end

  defp parse_embed(_), do: nil

  defp parse_images(nil), do: nil

  defp parse_images(images) when is_list(images) do
    Enum.map(images, fn img ->
      %ImageEmbed{
        alt: img["alt"],
        image: img["image"],
        aspect_ratio: img["aspectRatio"]
      }
    end)
  end

  defp parse_external(nil), do: nil

  defp parse_external(data) when is_map(data) do
    %ExternalEmbed{
      uri: data["uri"],
      title: data["title"],
      description: data["description"],
      thumb: data["thumb"]
    }
  end

  defp parse_facets(nil), do: nil

  defp parse_facets(facets) when is_list(facets) do
    Enum.map(facets, &parse_facet/1)
  end

  defp parse_facet(data) when is_map(data) do
    %Facet{
      index: parse_byte_slice(data["index"]),
      features: parse_features(data["features"])
    }
  end

  defp parse_byte_slice(nil), do: nil

  defp parse_byte_slice(data) when is_map(data) do
    %ByteSlice{
      byte_start: data["byteStart"],
      byte_end: data["byteEnd"]
    }
  end

  defp parse_features(nil), do: []

  defp parse_features(features) when is_list(features) do
    Enum.map(features, &parse_feature/1)
  end

  defp parse_feature(%{"$type" => "app.bsky.richtext.facet#mention"} = data) do
    %FacetFeature{type: :mention, did: data["did"]}
  end

  defp parse_feature(%{"$type" => "app.bsky.richtext.facet#link"} = data) do
    %FacetFeature{type: :link, uri: data["uri"]}
  end

  defp parse_feature(%{"$type" => "app.bsky.richtext.facet#tag"} = data) do
    %FacetFeature{type: :tag, tag: data["tag"]}
  end

  defp parse_feature(_), do: %FacetFeature{}
end
