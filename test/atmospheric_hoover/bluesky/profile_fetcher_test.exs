defmodule AtmosphericHoover.Bluesky.ProfileFetcherTest do
  use ExUnit.Case, async: true

  alias AtmosphericHoover.Bluesky.ProfileFetcher

  # Note: These tests make real HTTP calls to the Bluesky API
  # They are tagged :external so they can be skipped in CI
  @moduletag :external

  describe "fetch_profile/2" do
    @tag :external
    test "fetches a known public profile by DID" do
      # Bluesky's official account
      result = ProfileFetcher.fetch_profile("did:plc:z72i7hdynmk6r22z27h6tvur")

      assert {:ok, profile} = result
      assert profile["did"] == "did:plc:z72i7hdynmk6r22z27h6tvur"
      assert profile["handle"] == "bsky.app"
      assert is_binary(profile["displayName"])
    end

    @tag :external
    test "fetches a profile by handle" do
      result = ProfileFetcher.fetch_profile("bsky.app")

      assert {:ok, profile} = result
      assert profile["handle"] == "bsky.app"
      assert is_binary(profile["did"])
    end

    @tag :external
    test "returns error for invalid actor" do
      result = ProfileFetcher.fetch_profile("not-a-real-did-or-handle-12345")

      assert {:error, _reason} = result
    end

    test "respects timeout option" do
      # Very short timeout should fail
      result = ProfileFetcher.fetch_profile("bsky.app", timeout: 1)

      assert {:error, _reason} = result
    end
  end

  describe "fetch_profiles/2" do
    @tag :external
    test "fetches multiple profiles" do
      actors = ["bsky.app", "did:plc:z72i7hdynmk6r22z27h6tvur"]

      results = ProfileFetcher.fetch_profiles(actors, delay_ms: 50)

      assert length(results) == 2

      Enum.each(results, fn {actor, result} ->
        assert actor in actors
        assert {:ok, _profile} = result
      end)
    end
  end
end
