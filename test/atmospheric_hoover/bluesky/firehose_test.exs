defmodule AtmosphericHoover.Bluesky.FirehoseTest do
  @moduledoc """
  Tests for the Bluesky Firehose WebSocket client.

  These tests focus on the pure/testable parts of the Firehose module
  without actually connecting to the real WebSocket endpoint.
  """

  use ExUnit.Case, async: true

  alias AtmosphericHoover.Bluesky.Firehose

  describe "build_url/2" do
    test "builds URL without collections" do
      url = Firehose.build_url("wss://example.com/subscribe", [])
      assert url == "wss://example.com/subscribe"
    end

    test "builds URL with single collection" do
      url = Firehose.build_url("wss://example.com/subscribe", ["app.bsky.feed.post"])
      assert url == "wss://example.com/subscribe?wantedCollections=app.bsky.feed.post"
    end

    test "builds URL with multiple collections" do
      url =
        Firehose.build_url("wss://example.com/subscribe", [
          "app.bsky.feed.post",
          "app.bsky.feed.like"
        ])

      assert url =~ "wss://example.com/subscribe?"
      assert url =~ "wantedCollections=app.bsky.feed.post"
      assert url =~ "wantedCollections=app.bsky.feed.like"
    end

    test "properly encodes collection names" do
      url = Firehose.build_url("wss://example.com/subscribe", ["app.bsky.graph.follow"])

      # The dot should be preserved in the query string
      assert url =~ "app.bsky.graph.follow"
    end
  end
end
