defmodule AtmosphericHoover.Bluesky.UserTest do
  use AtmosphericHoover.DataCase, async: true

  alias AtmosphericHoover.Bluesky.User

  describe "changeset/2" do
    test "valid with required fields" do
      changeset = User.changeset(%User{}, %{did: "did:plc:abc123"})
      assert changeset.valid?
    end

    test "invalid without did" do
      changeset = User.changeset(%User{}, %{handle: "test.bsky.social"})
      refute changeset.valid?
      assert {:did, {"can't be blank", _}} = hd(changeset.errors)
    end

    test "valid with all fields" do
      attrs = %{
        did: "did:plc:abc123",
        handle: "alice.bsky.social",
        display_name: "Alice",
        description: "Hello world",
        avatar: "https://example.com/avatar.jpg",
        banner: "https://example.com/banner.jpg",
        followers_count: 100,
        follows_count: 50,
        posts_count: 25,
        labels: [%{"val" => "test"}],
        associated: %{"lists" => 1}
      }

      changeset = User.changeset(%User{}, attrs)
      assert changeset.valid?
    end

    test "enforces unique did constraint" do
      {:ok, _user} = %User{} |> User.changeset(%{did: "did:plc:unique"}) |> Repo.insert()

      {:error, changeset} =
        %User{}
        |> User.changeset(%{did: "did:plc:unique"})
        |> Repo.insert()

      assert {:did, {"has already been taken", _}} = hd(changeset.errors)
    end
  end

  describe "from_profile/2" do
    test "converts API response to changeset" do
      profile = %{
        "did" => "did:plc:abc123",
        "handle" => "alice.bsky.social",
        "displayName" => "Alice",
        "description" => "Hello!",
        "avatar" => "https://example.com/avatar.jpg",
        "banner" => "https://example.com/banner.jpg",
        "followersCount" => 100,
        "followsCount" => 50,
        "postsCount" => 25,
        "indexedAt" => "2024-01-01T00:00:00.000Z",
        "createdAt" => "2023-06-01T00:00:00.000Z",
        "labels" => [%{"val" => "test"}],
        "associated" => %{"lists" => 1}
      }

      changeset = User.from_profile(%User{}, profile)
      assert changeset.valid?

      changes = changeset.changes
      assert changes.did == "did:plc:abc123"
      assert changes.handle == "alice.bsky.social"
      assert changes.display_name == "Alice"
      assert changes.followers_count == 100
      assert changes.fetched_at != nil
    end

    test "handles missing optional fields" do
      profile = %{
        "did" => "did:plc:minimal",
        "handle" => "minimal.bsky.social"
      }

      changeset = User.from_profile(%User{}, profile)
      assert changeset.valid?
      assert changeset.changes.did == "did:plc:minimal"
    end

    test "parses datetime fields" do
      profile = %{
        "did" => "did:plc:test",
        "handle" => "test.bsky.social",
        "indexedAt" => "2024-06-15T12:30:00.000Z"
      }

      changeset = User.from_profile(%User{}, profile)
      assert changeset.valid?
      assert %DateTime{} = changeset.changes.indexed_at
    end
  end

  describe "mark_error/3" do
    test "creates changeset with error info" do
      changeset = User.mark_error(%User{}, "did:plc:failed", "not found")
      assert changeset.valid?
      assert changeset.changes.did == "did:plc:failed"
      assert changeset.changes.fetch_error == "not found"
      assert changeset.changes.fetched_at != nil
    end
  end
end
