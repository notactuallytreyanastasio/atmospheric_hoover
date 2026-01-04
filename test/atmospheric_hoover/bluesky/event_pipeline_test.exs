defmodule AtmosphericHoover.Bluesky.EventPipelineTest do
  use AtmosphericHoover.DataCase, async: false

  alias AtmosphericHoover.Bluesky.{EventPipeline, FirehoseEvent}

  @valid_post_event %{
    "did" => "did:plc:test123",
    "time_us" => 1_725_911_162_329_308,
    "kind" => "commit",
    "commit" => %{
      "rev" => "abc123",
      "operation" => "create",
      "collection" => "app.bsky.feed.post",
      "rkey" => "xyz789",
      "cid" => "bafyrei",
      "record" => %{
        "text" => "Hello Broadway!",
        "createdAt" => "2024-01-01T12:00:00.000Z"
      }
    }
  }

  @valid_like_event %{
    "did" => "did:plc:liker",
    "time_us" => 1_725_911_162_329_309,
    "kind" => "commit",
    "commit" => %{
      "rev" => "def456",
      "operation" => "create",
      "collection" => "app.bsky.feed.like",
      "rkey" => "like123",
      "cid" => "bafyrei2",
      "record" => %{
        "subject" => %{
          "uri" => "at://did:plc:author/app.bsky.feed.post/abc",
          "cid" => "bafyrei"
        },
        "createdAt" => "2024-01-01T12:00:00.000Z"
      }
    }
  }

  describe "start_link/1" do
    test "starts the pipeline" do
      assert {:ok, pid} = start_pipeline(:test_event_pipeline_1)
      assert Process.alive?(pid)
      stop_pipeline(pid)
    end

    test "accepts configuration options" do
      opts = [
        name: :test_event_pipeline_2,
        processor_concurrency: 2,
        batch_size: 10,
        batch_timeout: 100,
        persist: false,
        broadcast: false
      ]

      assert {:ok, pid} = EventPipeline.start_link(opts)
      assert Process.alive?(pid)
      stop_pipeline(pid)
    end
  end

  describe "push_event/2" do
    setup do
      {:ok, pid} = start_pipeline(:test_event_pipeline_push)
      on_exit(fn -> stop_pipeline(pid) end)
      {:ok, pipeline: :test_event_pipeline_push}
    end

    test "pushes and processes a valid event", %{pipeline: pipeline} do
      json = Jason.encode!(@valid_post_event)
      :ok = EventPipeline.push_event(pipeline, json)

      # Wait for processing - Broadway needs time to batch and persist
      Process.sleep(300)

      # Check that event was persisted
      event = Repo.get_by(FirehoseEvent, did: "did:plc:test123", rkey: "xyz789")
      assert event != nil
      assert event.kind == "commit"
      assert event.operation == "create"
      assert event.collection == "app.bsky.feed.post"
    end

    test "handles multiple events", %{pipeline: pipeline} do
      :ok = EventPipeline.push_event(pipeline, Jason.encode!(@valid_post_event))
      :ok = EventPipeline.push_event(pipeline, Jason.encode!(@valid_like_event))

      # Wait for processing
      Process.sleep(300)

      # Check both events were persisted
      post_event = Repo.get_by(FirehoseEvent, did: "did:plc:test123")
      like_event = Repo.get_by(FirehoseEvent, did: "did:plc:liker")

      assert post_event != nil
      assert like_event != nil
      assert post_event.collection == "app.bsky.feed.post"
      assert like_event.collection == "app.bsky.feed.like"
    end

    test "handles invalid JSON gracefully", %{pipeline: pipeline} do
      :ok = EventPipeline.push_event(pipeline, "not valid json")

      # Should not crash
      Process.sleep(150)

      # Pipeline should still be alive
      assert Process.alive?(Process.whereis(pipeline))
    end
  end

  describe "push_parsed_event/2" do
    setup do
      {:ok, pid} = start_pipeline(:test_event_pipeline_parsed)
      on_exit(fn -> stop_pipeline(pid) end)
      {:ok, pipeline: :test_event_pipeline_parsed}
    end

    test "pushes a pre-parsed event", %{pipeline: pipeline} do
      {:ok, event} = AtmosphericHoover.Bluesky.Parser.parse_event(@valid_post_event)

      :ok = EventPipeline.push_parsed_event(pipeline, event)

      # Wait for processing
      Process.sleep(300)

      # Check that event was persisted
      db_event = Repo.get_by(FirehoseEvent, did: "did:plc:test123")
      assert db_event != nil
    end
  end

  describe "queue_depth/1" do
    test "returns current queue depth" do
      {:ok, pid} = start_pipeline(:test_event_pipeline_queue)

      # Give Broadway time to fully start
      Process.sleep(50)

      depth = EventPipeline.queue_depth(:test_event_pipeline_queue)
      assert is_integer(depth)
      assert depth >= 0

      stop_pipeline(pid)
    end
  end

  describe "batching behavior" do
    test "batches multiple events for database insert" do
      {:ok, pid} = start_pipeline(:test_event_pipeline_batch, batch_size: 5, batch_timeout: 500)

      # Push 5 events to trigger a batch
      for i <- 1..5 do
        json = build_event_json("did:plc:batch#{i}", "rkey#{i}")
        EventPipeline.push_event(:test_event_pipeline_batch, json)
      end

      # Wait for batch processing
      Process.sleep(700)

      # All events should be persisted
      count = Repo.aggregate(FirehoseEvent, :count)
      assert count >= 5

      stop_pipeline(pid)
    end
  end

  # Helper functions

  defp start_pipeline(name, opts \\ []) do
    default_opts = [
      name: name,
      processor_concurrency: 1,
      batch_size: 10,
      batch_timeout: 100,
      persist: true,
      broadcast: false
    ]

    EventPipeline.start_link(Keyword.merge(default_opts, opts))
  end

  defp stop_pipeline(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        Broadway.stop(pid, :normal, 5000)
      catch
        :exit, _ -> :ok
      end
    end
  end

  defp stop_pipeline(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> stop_pipeline(pid)
    end
  end

  defp build_event_json(did, rkey) do
    %{
      "did" => did,
      "time_us" => System.system_time(:microsecond),
      "kind" => "commit",
      "commit" => %{
        "rev" => "rev#{rkey}",
        "operation" => "create",
        "collection" => "app.bsky.feed.post",
        "rkey" => rkey,
        "cid" => "cid#{rkey}",
        "record" => %{
          "text" => "Test post",
          "createdAt" => "2024-01-01T12:00:00.000Z"
        }
      }
    }
    |> Jason.encode!()
  end
end
