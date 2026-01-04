defmodule AtmosphericHoover.Bluesky.ParserTest do
  @moduledoc """
  Tests for the Bluesky firehose event parser.

  These tests verify the functional core of the parser module,
  ensuring all event types and record formats are correctly parsed.
  """

  use ExUnit.Case, async: true

  alias AtmosphericHoover.Bluesky.Parser

  alias AtmosphericHoover.Bluesky.Types.{
    Event,
    Commit,
    Post,
    Like,
    Repost,
    Follow,
    Identity,
    Account,
    StrongRef,
    ReplyRef,
    Facet,
    FacetFeature,
    ByteSlice,
    Embed,
    ExternalEmbed
  }

  doctest AtmosphericHoover.Bluesky.Parser

  describe "parse_event/1" do
    test "parses a complete post create event from JSON" do
      json = """
      {
        "did": "did:plc:abc123",
        "time_us": 1725911162329308,
        "kind": "commit",
        "commit": {
          "rev": "3l3qo2vutsw2b",
          "operation": "create",
          "collection": "app.bsky.feed.post",
          "rkey": "3l3qo2vuowo2b",
          "cid": "bafyreihash123",
          "record": {
            "text": "Hello Bluesky!",
            "createdAt": "2024-01-01T12:00:00.000Z",
            "langs": ["en"]
          }
        }
      }
      """

      assert {:ok, %Event{} = event} = Parser.parse_event(json)
      assert event.did == "did:plc:abc123"
      assert event.time_us == 1_725_911_162_329_308
      assert event.kind == :commit

      assert %Commit{} = commit = event.commit
      assert commit.rev == "3l3qo2vutsw2b"
      assert commit.operation == :create
      assert commit.collection == "app.bsky.feed.post"
      assert commit.rkey == "3l3qo2vuowo2b"
      assert commit.cid == "bafyreihash123"

      assert %Post{} = post = commit.record
      assert post.text == "Hello Bluesky!"
      assert post.langs == ["en"]
      assert %DateTime{} = post.created_at
    end

    test "parses a like event" do
      data = %{
        "did" => "did:plc:user123",
        "time_us" => 1_000_000,
        "kind" => "commit",
        "commit" => %{
          "rev" => "abc",
          "operation" => "create",
          "collection" => "app.bsky.feed.like",
          "rkey" => "xyz",
          "cid" => "bafyrei",
          "record" => %{
            "subject" => %{
              "uri" => "at://did:plc:author/app.bsky.feed.post/123",
              "cid" => "bafypostcid"
            },
            "createdAt" => "2024-01-01T12:00:00.000Z"
          }
        }
      }

      assert {:ok, %Event{} = event} = Parser.parse_event(data)
      assert %Like{} = like = event.commit.record
      assert %StrongRef{} = like.subject
      assert like.subject.uri == "at://did:plc:author/app.bsky.feed.post/123"
      assert like.subject.cid == "bafypostcid"
    end

    test "parses a repost event" do
      data = %{
        "did" => "did:plc:user123",
        "time_us" => 1_000_000,
        "kind" => "commit",
        "commit" => %{
          "rev" => "abc",
          "operation" => "create",
          "collection" => "app.bsky.feed.repost",
          "rkey" => "xyz",
          "record" => %{
            "subject" => %{
              "uri" => "at://did:plc:author/app.bsky.feed.post/123",
              "cid" => "bafypostcid"
            },
            "createdAt" => "2024-01-01T12:00:00.000Z"
          }
        }
      }

      assert {:ok, %Event{} = event} = Parser.parse_event(data)
      assert %Repost{} = repost = event.commit.record
      assert repost.subject.uri == "at://did:plc:author/app.bsky.feed.post/123"
    end

    test "parses a follow event" do
      data = %{
        "did" => "did:plc:follower",
        "time_us" => 1_000_000,
        "kind" => "commit",
        "commit" => %{
          "rev" => "abc",
          "operation" => "create",
          "collection" => "app.bsky.graph.follow",
          "rkey" => "xyz",
          "record" => %{
            "subject" => "did:plc:followee",
            "createdAt" => "2024-01-01T12:00:00.000Z"
          }
        }
      }

      assert {:ok, %Event{} = event} = Parser.parse_event(data)
      assert %Follow{} = follow = event.commit.record
      assert follow.subject == "did:plc:followee"
    end

    test "parses a delete operation" do
      data = %{
        "did" => "did:plc:user123",
        "time_us" => 1_000_000,
        "kind" => "commit",
        "commit" => %{
          "rev" => "abc",
          "operation" => "delete",
          "collection" => "app.bsky.feed.post",
          "rkey" => "deletedpost"
        }
      }

      assert {:ok, %Event{} = event} = Parser.parse_event(data)
      assert event.commit.operation == :delete
      assert event.commit.record == nil
    end

    test "parses an identity event" do
      data = %{
        "did" => "did:plc:user123",
        "time_us" => 1_000_000,
        "kind" => "identity",
        "identity" => %{
          "did" => "did:plc:user123",
          "handle" => "alice.bsky.social",
          "seq" => 12345
        }
      }

      assert {:ok, %Event{} = event} = Parser.parse_event(data)
      assert event.kind == :identity
      assert event.commit == nil
      assert %Identity{} = identity = event.identity
      assert identity.handle == "alice.bsky.social"
      assert identity.seq == 12345
    end

    test "parses an account event" do
      data = %{
        "did" => "did:plc:user123",
        "time_us" => 1_000_000,
        "kind" => "account",
        "account" => %{
          "did" => "did:plc:user123",
          "active" => false,
          "status" => "deactivated",
          "seq" => 12345
        }
      }

      assert {:ok, %Event{} = event} = Parser.parse_event(data)
      assert event.kind == :account
      assert %Account{} = account = event.account
      assert account.active == false
      assert account.status == "deactivated"
    end

    test "returns error for invalid JSON" do
      assert {:error, {:json_decode_error, _}} = Parser.parse_event("not json")
    end

    test "returns error for missing required fields" do
      assert {:error, :missing_did} = Parser.parse_event(%{"time_us" => 123, "kind" => "commit"})

      assert {:error, :missing_time_us} =
               Parser.parse_event(%{"did" => "did:plc:x", "kind" => "commit"})

      assert {:error, {:invalid_kind, nil}} =
               Parser.parse_event(%{"did" => "did:plc:x", "time_us" => 123})
    end
  end

  describe "parse_post/1" do
    test "parses a simple post" do
      data = %{
        "text" => "Hello world!",
        "createdAt" => "2024-01-01T12:00:00.000Z"
      }

      post = Parser.parse_post(data)
      assert %Post{} = post
      assert post.text == "Hello world!"
      assert %DateTime{} = post.created_at
    end

    test "parses a post with reply reference" do
      data = %{
        "text" => "This is a reply",
        "createdAt" => "2024-01-01T12:00:00.000Z",
        "reply" => %{
          "parent" => %{
            "uri" => "at://did:plc:parent/app.bsky.feed.post/123",
            "cid" => "bafyparent"
          },
          "root" => %{
            "uri" => "at://did:plc:root/app.bsky.feed.post/000",
            "cid" => "bafyroot"
          }
        }
      }

      post = Parser.parse_post(data)
      assert %ReplyRef{} = post.reply
      assert %StrongRef{} = post.reply.parent
      assert post.reply.parent.uri == "at://did:plc:parent/app.bsky.feed.post/123"
      assert post.reply.root.uri == "at://did:plc:root/app.bsky.feed.post/000"
    end

    test "parses a post with facets (mentions, links, tags)" do
      data = %{
        "text" => "@alice check out https://example.com #bluesky",
        "createdAt" => "2024-01-01T12:00:00.000Z",
        "facets" => [
          %{
            "index" => %{"byteStart" => 0, "byteEnd" => 6},
            "features" => [
              %{"$type" => "app.bsky.richtext.facet#mention", "did" => "did:plc:alice"}
            ]
          },
          %{
            "index" => %{"byteStart" => 17, "byteEnd" => 36},
            "features" => [
              %{"$type" => "app.bsky.richtext.facet#link", "uri" => "https://example.com"}
            ]
          },
          %{
            "index" => %{"byteStart" => 37, "byteEnd" => 45},
            "features" => [
              %{"$type" => "app.bsky.richtext.facet#tag", "tag" => "bluesky"}
            ]
          }
        ]
      }

      post = Parser.parse_post(data)
      assert length(post.facets) == 3

      [mention_facet, link_facet, tag_facet] = post.facets

      assert %Facet{} = mention_facet
      assert %ByteSlice{byte_start: 0, byte_end: 6} = mention_facet.index
      assert [%FacetFeature{type: :mention, did: "did:plc:alice"}] = mention_facet.features

      assert %FacetFeature{type: :link, uri: "https://example.com"} = hd(link_facet.features)
      assert %FacetFeature{type: :tag, tag: "bluesky"} = hd(tag_facet.features)
    end

    test "parses a post with external embed (link card)" do
      data = %{
        "text" => "Check this out",
        "createdAt" => "2024-01-01T12:00:00.000Z",
        "embed" => %{
          "$type" => "app.bsky.embed.external",
          "external" => %{
            "uri" => "https://example.com/article",
            "title" => "Example Article",
            "description" => "An interesting article"
          }
        }
      }

      post = Parser.parse_post(data)
      assert %Embed{type: :external} = post.embed
      assert %ExternalEmbed{} = post.embed.external
      assert post.embed.external.uri == "https://example.com/article"
      assert post.embed.external.title == "Example Article"
    end

    test "parses a post with image embed" do
      data = %{
        "text" => "Photo post",
        "createdAt" => "2024-01-01T12:00:00.000Z",
        "embed" => %{
          "$type" => "app.bsky.embed.images",
          "images" => [
            %{"alt" => "A photo", "image" => %{"ref" => "blob123"}}
          ]
        }
      }

      post = Parser.parse_post(data)
      assert %Embed{type: :images} = post.embed
      assert [image] = post.embed.images
      assert image.alt == "A photo"
    end

    test "parses a post with quote embed" do
      data = %{
        "text" => "Quoting this",
        "createdAt" => "2024-01-01T12:00:00.000Z",
        "embed" => %{
          "$type" => "app.bsky.embed.record",
          "record" => %{
            "uri" => "at://did:plc:author/app.bsky.feed.post/quoted",
            "cid" => "bafyquoted"
          }
        }
      }

      post = Parser.parse_post(data)
      assert %Embed{type: :record} = post.embed
      assert %StrongRef{} = post.embed.record
      assert post.embed.record.uri == "at://did:plc:author/app.bsky.feed.post/quoted"
    end

    test "parses a post with languages and tags" do
      data = %{
        "text" => "Multi-language post",
        "createdAt" => "2024-01-01T12:00:00.000Z",
        "langs" => ["en", "es"],
        "tags" => ["tech", "elixir"]
      }

      post = Parser.parse_post(data)
      assert post.langs == ["en", "es"]
      assert post.tags == ["tech", "elixir"]
    end

    test "returns nil for nil input" do
      assert Parser.parse_post(nil) == nil
    end
  end

  describe "parse_commit/1" do
    test "parses a create commit" do
      data = %{
        "rev" => "abc123",
        "operation" => "create",
        "collection" => "app.bsky.feed.post",
        "rkey" => "xyz789",
        "cid" => "bafyrei"
      }

      assert {:ok, %Commit{} = commit} = Parser.parse_commit(data)
      assert commit.operation == :create
      assert commit.collection == "app.bsky.feed.post"
    end

    test "parses an update commit" do
      data = %{
        "rev" => "abc123",
        "operation" => "update",
        "collection" => "app.bsky.feed.post",
        "rkey" => "xyz789"
      }

      assert {:ok, %Commit{} = commit} = Parser.parse_commit(data)
      assert commit.operation == :update
    end

    test "parses a delete commit" do
      data = %{
        "rev" => "abc123",
        "operation" => "delete",
        "collection" => "app.bsky.feed.post",
        "rkey" => "xyz789"
      }

      assert {:ok, %Commit{} = commit} = Parser.parse_commit(data)
      assert commit.operation == :delete
    end

    test "returns error for invalid operation" do
      data = %{
        "rev" => "abc123",
        "operation" => "invalid",
        "collection" => "app.bsky.feed.post",
        "rkey" => "xyz789"
      }

      assert {:error, {:invalid_operation, "invalid"}} = Parser.parse_commit(data)
    end
  end

  describe "parse_strong_ref/1" do
    test "parses a strong reference" do
      data = %{
        "uri" => "at://did:plc:abc/collection/rkey",
        "cid" => "bafyreihash"
      }

      ref = Parser.parse_strong_ref(data)
      assert %StrongRef{} = ref
      assert ref.uri == "at://did:plc:abc/collection/rkey"
      assert ref.cid == "bafyreihash"
    end

    test "returns nil for nil input" do
      assert Parser.parse_strong_ref(nil) == nil
    end
  end

  describe "parse_like/1" do
    test "parses a like record" do
      data = %{
        "subject" => %{
          "uri" => "at://did:plc:author/app.bsky.feed.post/123",
          "cid" => "bafypostcid"
        },
        "createdAt" => "2024-06-15T10:30:00.000Z"
      }

      like = Parser.parse_like(data)
      assert %Like{} = like
      assert like.subject.uri == "at://did:plc:author/app.bsky.feed.post/123"
      assert %DateTime{} = like.created_at
    end
  end

  describe "parse_follow/1" do
    test "parses a follow record" do
      data = %{
        "subject" => "did:plc:targetuser",
        "createdAt" => "2024-06-15T10:30:00.000Z"
      }

      follow = Parser.parse_follow(data)
      assert %Follow{} = follow
      assert follow.subject == "did:plc:targetuser"
    end
  end

  describe "parse_identity/1" do
    test "parses an identity record" do
      data = %{
        "did" => "did:plc:user",
        "handle" => "user.bsky.social",
        "seq" => 100
      }

      identity = Parser.parse_identity(data)
      assert %Identity{} = identity
      assert identity.did == "did:plc:user"
      assert identity.handle == "user.bsky.social"
      assert identity.seq == 100
    end
  end

  describe "parse_account/1" do
    test "parses an account record" do
      data = %{
        "did" => "did:plc:user",
        "active" => true,
        "status" => "active",
        "seq" => 100
      }

      account = Parser.parse_account(data)
      assert %Account{} = account
      assert account.active == true
      assert account.status == "active"
    end
  end
end
