defmodule AtmosphericHoover.Bluesky.TypesTest do
  @moduledoc """
  Tests for the Bluesky type definitions.
  Verifies struct creation and doctests.
  """

  use ExUnit.Case, async: true

  alias AtmosphericHoover.Bluesky.Types.{
    StrongRef,
    ReplyRef,
    ByteSlice,
    FacetFeature,
    Facet,
    ImageEmbed,
    ExternalEmbed,
    Embed,
    Post,
    Like,
    Repost,
    Follow,
    Commit,
    Identity,
    Account,
    Event
  }

  doctest AtmosphericHoover.Bluesky.Types

  describe "StrongRef" do
    test "creates struct with uri and cid" do
      ref = %StrongRef{uri: "at://did:plc:abc/col/123", cid: "bafyhash"}
      assert ref.uri == "at://did:plc:abc/col/123"
      assert ref.cid == "bafyhash"
    end

    test "defaults to nil values" do
      ref = %StrongRef{}
      assert ref.uri == nil
      assert ref.cid == nil
    end
  end

  describe "ReplyRef" do
    test "creates struct with parent and root references" do
      parent = %StrongRef{uri: "at://parent", cid: "parentcid"}
      root = %StrongRef{uri: "at://root", cid: "rootcid"}
      reply = %ReplyRef{parent: parent, root: root}

      assert reply.parent.uri == "at://parent"
      assert reply.root.uri == "at://root"
    end
  end

  describe "ByteSlice" do
    test "creates struct with byte range" do
      slice = %ByteSlice{byte_start: 0, byte_end: 10}
      assert slice.byte_start == 0
      assert slice.byte_end == 10
    end
  end

  describe "FacetFeature" do
    test "creates mention feature" do
      feature = %FacetFeature{type: :mention, did: "did:plc:abc"}
      assert feature.type == :mention
      assert feature.did == "did:plc:abc"
    end

    test "creates link feature" do
      feature = %FacetFeature{type: :link, uri: "https://example.com"}
      assert feature.type == :link
      assert feature.uri == "https://example.com"
    end

    test "creates tag feature" do
      feature = %FacetFeature{type: :tag, tag: "elixir"}
      assert feature.type == :tag
      assert feature.tag == "elixir"
    end
  end

  describe "Facet" do
    test "creates struct with index and features" do
      index = %ByteSlice{byte_start: 0, byte_end: 5}
      feature = %FacetFeature{type: :mention, did: "did:plc:test"}
      facet = %Facet{index: index, features: [feature]}

      assert facet.index.byte_start == 0
      assert length(facet.features) == 1
      assert hd(facet.features).type == :mention
    end
  end

  describe "ImageEmbed" do
    test "creates struct with alt text" do
      image = %ImageEmbed{alt: "A photo", image: %{}, aspect_ratio: %{width: 16, height: 9}}
      assert image.alt == "A photo"
    end
  end

  describe "ExternalEmbed" do
    test "creates struct with link card data" do
      embed = %ExternalEmbed{
        uri: "https://example.com",
        title: "Example",
        description: "A description"
      }

      assert embed.uri == "https://example.com"
      assert embed.title == "Example"
    end
  end

  describe "Embed" do
    test "creates images embed" do
      image = %ImageEmbed{alt: "test"}
      embed = %Embed{type: :images, images: [image]}

      assert embed.type == :images
      assert length(embed.images) == 1
    end

    test "creates external embed" do
      external = %ExternalEmbed{uri: "https://test.com", title: "Test", description: ""}
      embed = %Embed{type: :external, external: external}

      assert embed.type == :external
      assert embed.external.uri == "https://test.com"
    end

    test "creates record embed (quote post)" do
      ref = %StrongRef{uri: "at://quote", cid: "quotecid"}
      embed = %Embed{type: :record, record: ref}

      assert embed.type == :record
      assert embed.record.uri == "at://quote"
    end
  end

  describe "Post" do
    test "creates struct with text and created_at" do
      post = %Post{text: "Hello!", created_at: ~U[2024-01-01 12:00:00Z]}
      assert post.text == "Hello!"
      assert post.created_at == ~U[2024-01-01 12:00:00Z]
    end

    test "creates post with reply reference" do
      parent = %StrongRef{uri: "at://parent", cid: "pcid"}
      root = %StrongRef{uri: "at://root", cid: "rcid"}
      reply = %ReplyRef{parent: parent, root: root}

      post = %Post{text: "A reply", created_at: ~U[2024-01-01 12:00:00Z], reply: reply}

      assert post.reply.parent.uri == "at://parent"
      assert post.reply.root.uri == "at://root"
    end

    test "creates post with facets" do
      facet = %Facet{
        index: %ByteSlice{byte_start: 0, byte_end: 5},
        features: [%FacetFeature{type: :tag, tag: "test"}]
      }

      post = %Post{text: "#test", created_at: ~U[2024-01-01 12:00:00Z], facets: [facet]}

      assert length(post.facets) == 1
    end

    test "creates post with languages" do
      post = %Post{text: "Hello", created_at: ~U[2024-01-01 12:00:00Z], langs: ["en", "es"]}
      assert post.langs == ["en", "es"]
    end
  end

  describe "Like" do
    test "creates struct with subject reference" do
      subject = %StrongRef{uri: "at://liked/post", cid: "likecid"}
      like = %Like{subject: subject, created_at: ~U[2024-01-01 12:00:00Z]}

      assert like.subject.uri == "at://liked/post"
    end
  end

  describe "Repost" do
    test "creates struct with subject reference" do
      subject = %StrongRef{uri: "at://reposted/post", cid: "repostcid"}
      repost = %Repost{subject: subject, created_at: ~U[2024-01-01 12:00:00Z]}

      assert repost.subject.uri == "at://reposted/post"
    end
  end

  describe "Follow" do
    test "creates struct with subject DID" do
      follow = %Follow{subject: "did:plc:followed", created_at: ~U[2024-01-01 12:00:00Z]}
      assert follow.subject == "did:plc:followed"
    end
  end

  describe "Commit" do
    test "creates struct for create operation" do
      commit = %Commit{
        rev: "rev123",
        operation: :create,
        collection: "app.bsky.feed.post",
        rkey: "rkey123",
        cid: "cid123"
      }

      assert commit.operation == :create
      assert commit.collection == "app.bsky.feed.post"
    end

    test "creates struct for delete operation" do
      commit = %Commit{
        rev: "rev123",
        operation: :delete,
        collection: "app.bsky.feed.post",
        rkey: "rkey123"
      }

      assert commit.operation == :delete
      assert commit.record == nil
    end
  end

  describe "Identity" do
    test "creates struct with did and handle" do
      identity = %Identity{did: "did:plc:test", handle: "test.bsky.social", seq: 100}

      assert identity.did == "did:plc:test"
      assert identity.handle == "test.bsky.social"
      assert identity.seq == 100
    end
  end

  describe "Account" do
    test "creates struct with status" do
      account = %Account{did: "did:plc:test", active: true, status: "active", seq: 100}

      assert account.active == true
      assert account.status == "active"
    end

    test "creates struct for deactivated account" do
      account = %Account{did: "did:plc:test", active: false, status: "deactivated"}

      assert account.active == false
      assert account.status == "deactivated"
    end
  end

  describe "Event" do
    test "creates commit event" do
      commit = %Commit{rev: "rev", operation: :create, collection: "col", rkey: "rkey"}

      event = %Event{
        did: "did:plc:user",
        time_us: 1_725_911_162_329_308,
        kind: :commit,
        commit: commit
      }

      assert event.kind == :commit
      assert event.commit.operation == :create
      assert event.identity == nil
      assert event.account == nil
    end

    test "creates identity event" do
      identity = %Identity{did: "did:plc:user", handle: "user.bsky.social"}

      event = %Event{
        did: "did:plc:user",
        time_us: 1_725_911_162_329_308,
        kind: :identity,
        identity: identity
      }

      assert event.kind == :identity
      assert event.identity.handle == "user.bsky.social"
      assert event.commit == nil
    end

    test "creates account event" do
      account = %Account{did: "did:plc:user", active: false, status: "takendown"}

      event = %Event{
        did: "did:plc:user",
        time_us: 1_725_911_162_329_308,
        kind: :account,
        account: account
      }

      assert event.kind == :account
      assert event.account.active == false
    end
  end
end
