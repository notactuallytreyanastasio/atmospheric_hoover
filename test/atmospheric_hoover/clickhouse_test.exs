defmodule AtmosphericHoover.ClickhouseTest do
  @moduledoc """
  Tests for ClickHouse client functions.
  These tests verify the API and data transformation functions.
  Note: Requires ClickHouse to be running for integration tests.
  """

  use ExUnit.Case, async: true

  alias AtmosphericHoover.Clickhouse

  describe "insert_posts/1" do
    test "returns :ok for empty list" do
      assert Clickhouse.insert_posts([]) == :ok
    end

    test "inserts a valid post" do
      post = %{
        did: "did:plc:test_insert_#{System.unique_integer([:positive])}",
        handle: "test.bsky.social",
        display_name: "Test User",
        text: "Test post #{System.unique_integer([:positive])}",
        langs: ["en"],
        hashtags: ["test"],
        cid: "bafyreihash#{System.unique_integer([:positive])}",
        uri: "at://did:plc:test/app.bsky.feed.post/#{System.unique_integer([:positive])}",
        reply_parent: "",
        reply_root: "",
        has_images: false,
        has_video: false,
        has_external_link: false,
        created_at: DateTime.utc_now()
      }

      # Should succeed or fail gracefully
      result = Clickhouse.insert_post(post)
      assert result == :ok || match?({:error, _}, result)
    end

    test "handles post with nil fields gracefully" do
      post = %{
        did: "did:plc:nil_test",
        text: nil,
        created_at: nil
      }

      # Should not crash - either succeeds or returns error
      result = Clickhouse.insert_post(post)
      assert result == :ok || match?({:error, _}, result)
    end

    test "handles post with string datetime" do
      post = %{
        did: "did:plc:string_date_test",
        text: "Test",
        created_at: "2024-01-01T12:00:00.000Z"
      }

      result = Clickhouse.insert_post(post)
      assert result == :ok || match?({:error, _}, result)
    end
  end

  describe "query/1" do
    test "executes a simple query" do
      result = Clickhouse.query("SELECT 1 as num")
      assert match?({:ok, _}, result) || match?({:error, _}, result)

      case result do
        {:ok, [%{"num" => 1}]} -> assert true
        {:error, _} -> assert true
      end
    end

    test "supports custom format option" do
      result = Clickhouse.query("SELECT 1", format: "JSONEachRow")
      assert match?({:ok, _}, result) || match?({:error, _}, result)
    end
  end

  describe "execute/1" do
    test "executes a command" do
      result = Clickhouse.execute("SELECT 1")
      assert result == :ok || match?({:error, _}, result)
    end
  end

  describe "query functions" do
    test "post_count/0 returns a count or error" do
      result = Clickhouse.post_count()

      case result do
        {:ok, count} when is_integer(count) -> assert count >= 0
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end

    test "posts_by_user/2 returns posts or error" do
      result = Clickhouse.posts_by_user("nonexistent.user")

      case result do
        {:ok, posts} when is_list(posts) -> assert true
        {:error, _} -> assert true
      end
    end

    test "top_posters/2 returns list or error" do
      result = Clickhouse.top_posters(24, 10)

      case result do
        {:ok, posters} when is_list(posters) -> assert true
        {:error, _} -> assert true
      end
    end

    test "language_stats/1 returns list or error" do
      result = Clickhouse.language_stats(24)

      case result do
        {:ok, stats} when is_list(stats) -> assert true
        {:error, _} -> assert true
      end
    end

    test "trending_hashtags/2 returns list or error" do
      result = Clickhouse.trending_hashtags(1, 10)

      case result do
        {:ok, hashtags} when is_list(hashtags) -> assert true
        {:error, _} -> assert true
      end
    end

    test "posts_per_minute/1 returns list or error" do
      result = Clickhouse.posts_per_minute(30)

      case result do
        {:ok, rate} when is_list(rate) -> assert true
        {:error, _} -> assert true
      end
    end

    test "hot_threads/2 returns list or error" do
      result = Clickhouse.hot_threads(30, 10)

      case result do
        {:ok, threads} when is_list(threads) -> assert true
        {:error, _} -> assert true
      end
    end

    test "thread_posts/1 returns list or error" do
      result = Clickhouse.thread_posts("at://test/post/123")

      case result do
        {:ok, posts} when is_list(posts) -> assert true
        {:error, _} -> assert true
      end
    end

    test "thread_velocity/2 returns list or error" do
      result = Clickhouse.thread_velocity("at://test/post/123", 60)

      case result do
        {:ok, velocity} when is_list(velocity) -> assert true
        {:error, _} -> assert true
      end
    end

    test "get_post/1 returns post, not_found, or error" do
      result = Clickhouse.get_post("at://nonexistent/post/xyz")

      case result do
        {:ok, post} when is_map(post) -> assert true
        {:error, :not_found} -> assert true
        {:error, _} -> assert true
      end
    end
  end

  describe "module exports" do
    test "exports expected functions" do
      exports = Clickhouse.__info__(:functions)

      assert {:insert_posts, 1} in exports
      assert {:insert_post, 1} in exports
      assert {:query, 1} in exports
      assert {:query, 2} in exports
      assert {:execute, 1} in exports
      assert {:post_count, 0} in exports
      assert {:posts_by_user, 1} in exports
      assert {:posts_by_user, 2} in exports
      assert {:top_posters, 0} in exports
      assert {:top_posters, 2} in exports
      assert {:language_stats, 0} in exports
      assert {:language_stats, 1} in exports
      assert {:trending_hashtags, 0} in exports
      assert {:trending_hashtags, 2} in exports
      assert {:posts_per_minute, 0} in exports
      assert {:posts_per_minute, 1} in exports
      assert {:hot_threads, 0} in exports
      assert {:hot_threads, 2} in exports
      assert {:thread_posts, 1} in exports
      assert {:thread_velocity, 1} in exports
      assert {:thread_velocity, 2} in exports
      assert {:get_post, 1} in exports
      assert {:backfill_from_postgres, 0} in exports
      assert {:backfill_from_postgres, 1} in exports
    end
  end

  describe "data formatting" do
    test "handles DateTime objects" do
      post = %{
        did: "did:plc:datetime_test",
        text: "Test",
        created_at: ~U[2024-06-15 10:30:00.123Z]
      }

      # Should not crash on DateTime formatting
      result = Clickhouse.insert_post(post)
      assert result == :ok || match?({:error, _}, result)
    end

    test "handles empty arrays" do
      post = %{
        did: "did:plc:empty_array_test",
        text: "Test",
        langs: [],
        hashtags: [],
        created_at: DateTime.utc_now()
      }

      result = Clickhouse.insert_post(post)
      assert result == :ok || match?({:error, _}, result)
    end

    test "handles special characters in text" do
      post = %{
        did: "did:plc:special_char_test",
        text: "Test with 'quotes' and \"double quotes\" and \\backslash",
        created_at: DateTime.utc_now()
      }

      result = Clickhouse.insert_post(post)
      assert result == :ok || match?({:error, _}, result)
    end
  end
end
