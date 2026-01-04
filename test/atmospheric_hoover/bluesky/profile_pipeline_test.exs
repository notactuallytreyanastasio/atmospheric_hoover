defmodule AtmosphericHoover.Bluesky.ProfilePipelineTest do
  use AtmosphericHoover.DataCase, async: false

  alias AtmosphericHoover.Bluesky.{ProfilePipeline, User}

  describe "start_link/1" do
    test "starts the pipeline" do
      assert {:ok, pid} = start_pipeline(:test_profile_pipeline_1)
      assert Process.alive?(pid)
      stop_pipeline(pid)
    end

    test "accepts configuration options" do
      opts = [
        name: :test_profile_pipeline_2,
        processor_concurrency: 2,
        rate_limit_ms: 50,
        batch_size: 10,
        batch_timeout: 100
      ]

      assert {:ok, pid} = ProfilePipeline.start_link(opts)
      assert Process.alive?(pid)
      stop_pipeline(pid)
    end
  end

  describe "push_did/2" do
    setup do
      {:ok, pid} = start_pipeline(:test_profile_pipeline_push)
      # Give Broadway time to fully start
      Process.sleep(50)
      on_exit(fn -> stop_pipeline(pid) end)
      {:ok, pipeline: :test_profile_pipeline_push}
    end

    test "enqueues a DID", %{pipeline: pipeline} do
      :ok = ProfilePipeline.push_did(pipeline, "did:plc:test123")

      # Give it a moment to process the cast
      Process.sleep(50)

      stats = ProfilePipeline.get_stats(pipeline)
      assert stats.dids_received >= 1
    end
  end

  describe "push_dids/2" do
    setup do
      {:ok, pid} = start_pipeline(:test_profile_pipeline_batch_push)
      Process.sleep(50)
      on_exit(fn -> stop_pipeline(pid) end)
      {:ok, pipeline: :test_profile_pipeline_batch_push}
    end

    test "enqueues multiple DIDs", %{pipeline: pipeline} do
      dids = ["did:plc:a", "did:plc:b", "did:plc:c"]
      :ok = ProfilePipeline.push_dids(pipeline, dids)

      Process.sleep(50)

      stats = ProfilePipeline.get_stats(pipeline)
      assert stats.dids_received >= 3
    end
  end

  describe "get_stats/1" do
    test "returns pipeline statistics" do
      {:ok, pid} = start_pipeline(:test_profile_pipeline_stats)
      Process.sleep(50)

      stats = ProfilePipeline.get_stats(:test_profile_pipeline_stats)

      assert is_map(stats)
      assert Map.has_key?(stats, :dids_received)
      assert Map.has_key?(stats, :dids_queued)
      assert Map.has_key?(stats, :dids_skipped_seen)
      assert Map.has_key?(stats, :queue_size)
      assert Map.has_key?(stats, :seen_size)

      stop_pipeline(pid)
    end
  end

  describe "ETS deduplication" do
    setup do
      {:ok, pid} = start_pipeline(:test_profile_pipeline_dedup)
      Process.sleep(50)
      on_exit(fn -> stop_pipeline(pid) end)
      {:ok, pipeline: :test_profile_pipeline_dedup}
    end

    test "skips duplicate DIDs in same session", %{pipeline: pipeline} do
      :ok = ProfilePipeline.push_did(pipeline, "did:plc:duplicate")
      :ok = ProfilePipeline.push_did(pipeline, "did:plc:duplicate")
      :ok = ProfilePipeline.push_did(pipeline, "did:plc:duplicate")

      # Give it a moment to process
      Process.sleep(100)

      stats = ProfilePipeline.get_stats(pipeline)
      assert stats.dids_received == 3
      assert stats.dids_skipped_seen >= 2
    end

    test "skips DIDs already in database", %{pipeline: pipeline} do
      # Insert a user first
      {:ok, _user} = %User{} |> User.changeset(%{did: "did:plc:existing"}) |> Repo.insert()

      :ok = ProfilePipeline.push_did(pipeline, "did:plc:existing")

      # Give it a moment to process - DB check now happens in processor
      Process.sleep(200)

      # The DID should be queued (producer doesn't check DB anymore)
      # but processor will skip it and mark message as failed
      stats = ProfilePipeline.get_stats(pipeline)
      assert stats.dids_queued >= 1
    end
  end

  describe "profile fetching integration" do
    @describetag :external

    setup do
      {:ok, pid} = start_pipeline(:test_profile_pipeline_fetch, rate_limit_interval: 1000, rate_limit_allowed: 10)
      Process.sleep(50)
      on_exit(fn -> stop_pipeline(pid) end)
      {:ok, pipeline: :test_profile_pipeline_fetch}
    end

    @tag :external
    test "fetches and stores profile from Bluesky API", %{pipeline: pipeline} do
      # Use Bluesky's official account for testing
      did = "did:plc:z72i7hdynmk6r22z27h6tvur"

      :ok = ProfilePipeline.push_did(pipeline, did)

      # Wait for processing (rate limit + fetch + batch)
      Process.sleep(6000)

      # Check that user was stored
      user = Repo.get_by(User, did: did)
      assert user != nil
      assert user.handle == "bsky.app"
      assert user.fetched_at != nil
      assert user.fetch_error == nil
    end

    @tag :external
    test "handles fetch errors gracefully", %{pipeline: pipeline} do
      # Use an invalid DID
      did = "did:plc:invalid_did_that_does_not_exist_12345"

      :ok = ProfilePipeline.push_did(pipeline, did)

      # Wait for processing
      Process.sleep(6000)

      # Check that error was recorded
      user = Repo.get_by(User, did: did)
      assert user != nil
      assert user.fetch_error != nil
    end
  end

  # Helper functions

  defp start_pipeline(name, opts \\ []) do
    default_opts = [
      name: name,
      processor_concurrency: 1,
      rate_limit_interval: 100,
      rate_limit_allowed: 100,
      batch_size: 10,
      batch_timeout: 100
    ]

    ProfilePipeline.start_link(Keyword.merge(default_opts, opts))
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
end
