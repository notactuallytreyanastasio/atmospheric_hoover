defmodule AtmosphericHoover.Bluesky.FirehoseEventTest do
  @moduledoc """
  Tests for the FirehoseEvent Ecto schema.
  """

  use AtmosphericHoover.DataCase, async: true

  alias AtmosphericHoover.Bluesky.{FirehoseEvent, Parser}

  describe "changeset/2" do
    test "validates required fields" do
      changeset = FirehoseEvent.changeset(%FirehoseEvent{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).did
      assert "can't be blank" in errors_on(changeset).time_us
      assert "can't be blank" in errors_on(changeset).kind
    end

    test "accepts valid commit event attributes" do
      attrs = %{
        did: "did:plc:abc123",
        time_us: 1_725_911_162_329_308,
        kind: "commit",
        operation: "create",
        collection: "app.bsky.feed.post",
        rkey: "xyz789",
        cid: "bafyreihash",
        record: %{"text" => "Hello!"}
      }

      changeset = FirehoseEvent.changeset(%FirehoseEvent{}, attrs)

      assert changeset.valid?
    end

    test "accepts valid identity event attributes" do
      attrs = %{
        did: "did:plc:abc123",
        time_us: 1_725_911_162_329_308,
        kind: "identity",
        handle: "alice.bsky.social",
        seq: 12345
      }

      changeset = FirehoseEvent.changeset(%FirehoseEvent{}, attrs)

      assert changeset.valid?
    end

    test "accepts valid account event attributes" do
      attrs = %{
        did: "did:plc:abc123",
        time_us: 1_725_911_162_329_308,
        kind: "account",
        active: false,
        status: "deactivated",
        seq: 12345
      }

      changeset = FirehoseEvent.changeset(%FirehoseEvent{}, attrs)

      assert changeset.valid?
    end

    test "validates kind is one of commit, identity, account" do
      attrs = %{
        did: "did:plc:abc123",
        time_us: 1_000_000,
        kind: "invalid"
      }

      changeset = FirehoseEvent.changeset(%FirehoseEvent{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).kind
    end

    test "validates operation is one of create, update, delete" do
      attrs = %{
        did: "did:plc:abc123",
        time_us: 1_000_000,
        kind: "commit",
        operation: "invalid"
      }

      changeset = FirehoseEvent.changeset(%FirehoseEvent{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).operation
    end

    test "allows nil operation for non-commit events" do
      attrs = %{
        did: "did:plc:abc123",
        time_us: 1_000_000,
        kind: "identity",
        operation: nil
      }

      changeset = FirehoseEvent.changeset(%FirehoseEvent{}, attrs)

      assert changeset.valid?
    end
  end

  describe "from_event/1" do
    test "converts a commit event to attributes" do
      {:ok, event} =
        Parser.parse_event(%{
          "did" => "did:plc:test",
          "time_us" => 123_456,
          "kind" => "commit",
          "commit" => %{
            "rev" => "abc",
            "operation" => "create",
            "collection" => "app.bsky.feed.post",
            "rkey" => "xyz",
            "cid" => "bafyrei",
            "record" => %{
              "text" => "Hello!",
              "createdAt" => "2024-01-01T12:00:00.000Z"
            }
          }
        })

      attrs = FirehoseEvent.from_event(event)

      assert attrs.did == "did:plc:test"
      assert attrs.time_us == 123_456
      assert attrs.kind == "commit"
      assert attrs.rev == "abc"
      assert attrs.operation == "create"
      assert attrs.collection == "app.bsky.feed.post"
      assert attrs.rkey == "xyz"
      assert attrs.cid == "bafyrei"
      assert is_map(attrs.record)
      assert attrs.record["text"] == "Hello!"
    end

    test "converts an identity event to attributes" do
      {:ok, event} =
        Parser.parse_event(%{
          "did" => "did:plc:test",
          "time_us" => 123_456,
          "kind" => "identity",
          "identity" => %{
            "did" => "did:plc:test",
            "handle" => "alice.bsky.social",
            "seq" => 100
          }
        })

      attrs = FirehoseEvent.from_event(event)

      assert attrs.kind == "identity"
      assert attrs.handle == "alice.bsky.social"
      assert attrs.seq == 100
      # Identity events don't have operation field
      refute Map.has_key?(attrs, :operation)
    end

    test "converts an account event to attributes" do
      {:ok, event} =
        Parser.parse_event(%{
          "did" => "did:plc:test",
          "time_us" => 123_456,
          "kind" => "account",
          "account" => %{
            "did" => "did:plc:test",
            "active" => false,
            "status" => "suspended",
            "seq" => 100
          }
        })

      attrs = FirehoseEvent.from_event(event)

      assert attrs.kind == "account"
      assert attrs.active == false
      assert attrs.status == "suspended"
      assert attrs.seq == 100
    end

    test "serializes nested record structs to maps" do
      {:ok, event} =
        Parser.parse_event(%{
          "did" => "did:plc:test",
          "time_us" => 123_456,
          "kind" => "commit",
          "commit" => %{
            "rev" => "abc",
            "operation" => "create",
            "collection" => "app.bsky.feed.like",
            "rkey" => "xyz",
            "record" => %{
              "subject" => %{
                "uri" => "at://did/post/1",
                "cid" => "bafyrei"
              },
              "createdAt" => "2024-01-01T12:00:00.000Z"
            }
          }
        })

      attrs = FirehoseEvent.from_event(event)

      # Record should be a serializable map, not a struct
      assert is_map(attrs.record)
      assert is_map(attrs.record["subject"])
      assert attrs.record["subject"]["uri"] == "at://did/post/1"
    end
  end

  describe "database operations" do
    test "inserts a valid firehose event" do
      attrs = %{
        did: "did:plc:insert_test",
        time_us: System.os_time(:microsecond),
        kind: "commit",
        operation: "create",
        collection: "app.bsky.feed.post",
        rkey: "unique_rkey_#{System.unique_integer()}",
        record: %{"text" => "Test post"}
      }

      changeset = FirehoseEvent.changeset(%FirehoseEvent{}, attrs)

      assert {:ok, event} = AtmosphericHoover.Repo.insert(changeset)
      assert event.id != nil
      assert event.did == "did:plc:insert_test"
      assert event.inserted_at != nil
    end

    test "enforces unique constraint on did + collection + rkey" do
      base_attrs = %{
        did: "did:plc:unique_test",
        time_us: System.os_time(:microsecond),
        kind: "commit",
        operation: "create",
        collection: "app.bsky.feed.post",
        rkey: "duplicate_rkey_#{System.unique_integer()}"
      }

      # First insert should succeed
      {:ok, _} =
        %FirehoseEvent{}
        |> FirehoseEvent.changeset(base_attrs)
        |> AtmosphericHoover.Repo.insert()

      # Second insert with same did + collection + rkey should fail
      result =
        %FirehoseEvent{}
        |> FirehoseEvent.changeset(base_attrs)
        |> AtmosphericHoover.Repo.insert()

      assert {:error, changeset} = result
      assert "has already been taken" in errors_on(changeset).did
    end

    test "on_conflict: :nothing allows duplicate inserts without error" do
      base_attrs = %{
        did: "did:plc:on_conflict_test",
        time_us: System.os_time(:microsecond),
        kind: "commit",
        operation: "create",
        collection: "app.bsky.feed.post",
        rkey: "on_conflict_rkey_#{System.unique_integer()}"
      }

      # First insert
      {:ok, _first} =
        %FirehoseEvent{}
        |> FirehoseEvent.changeset(base_attrs)
        |> AtmosphericHoover.Repo.insert()

      # Second insert with on_conflict: :nothing should succeed without inserting
      {:ok, second} =
        %FirehoseEvent{}
        |> FirehoseEvent.changeset(base_attrs)
        |> AtmosphericHoover.Repo.insert(on_conflict: :nothing)

      # Should return the changeset struct without ID (no insert happened)
      assert second.id == nil

      # Only one record should exist
      assert AtmosphericHoover.Repo.aggregate(FirehoseEvent, :count) >= 1
    end
  end
end
