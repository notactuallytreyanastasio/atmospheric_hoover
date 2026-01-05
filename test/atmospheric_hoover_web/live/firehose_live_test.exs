defmodule AtmosphericHooverWeb.FirehoseLiveTest do
  @moduledoc """
  Tests for the Firehose LiveView displaying raw firehose events.
  """

  use AtmosphericHooverWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AtmosphericHoover.Bluesky.Types.{Event, Commit, Post}

  describe "mount/3" do
    test "renders the firehose page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/firehose")

      assert html =~ "Firehose"
    end

    test "assigns page_title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/firehose")

      assert page_title(view) =~ "Firehose"
    end

    test "starts with empty posts", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/firehose")

      assert html =~ "Waiting for posts..."
    end
  end

  describe "navigation" do
    test "has link to grid view", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/firehose")

      assert html =~ "Grid View"
      assert html =~ ~s(href="/grid")
    end
  end

  describe "stats" do
    test "shows rate per second", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/firehose")

      assert html =~ "/sec"
    end

    test "shows total count", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/firehose")

      assert html =~ "total"
    end

    test "shows matched count", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/firehose")

      assert html =~ "matched"
    end
  end

  describe "filter event" do
    test "updates filter text", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/firehose")

      # Change the filter
      view
      |> form("form[phx-change=\"filter\"]", %{"filter" => "elixir"})
      |> render_change()

      html = render(view)
      # The filter input should have the value
      assert html =~ ~s(value="elixir")
    end

    test "shows no posts message when filter has no matches", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/firehose")

      view
      |> form("form[phx-change=\"filter\"]", %{"filter" => "xyz123nonexistent"})
      |> render_change()

      html = render(view)
      assert html =~ "No posts matching"
      assert html =~ "xyz123nonexistent"
    end
  end

  describe "toggle_pause event" do
    test "pauses the firehose", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/firehose")

      # Initially showing "Pause" button
      html = render(view)
      assert html =~ "Pause"

      # Click pause
      html = view |> element("button", "Pause") |> render_click()

      assert html =~ "Resume"
    end

    test "resumes the firehose", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/firehose")

      # Pause first
      view |> element("button", "Pause") |> render_click()

      # Resume
      html = view |> element("button", "Resume") |> render_click()

      assert html =~ "Pause"
    end
  end

  describe "clear event" do
    test "clears posts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/firehose")

      # Click clear
      view |> element("button", "Clear") |> render_click()

      html = render(view)
      assert html =~ "Waiting for posts..."
    end
  end

  describe "firehose event handling" do
    test "displays matching posts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/firehose")

      # Create a mock event
      post = %Post{
        text: "Hello from the test!",
        created_at: DateTime.utc_now()
      }

      commit = %Commit{
        rev: "rev123",
        operation: :create,
        collection: "app.bsky.feed.post",
        rkey: "rkey123",
        cid: "cid123",
        record: post
      }

      event = %Event{
        did: "did:plc:testuser123",
        time_us: 1_725_911_162_329_308,
        kind: :commit,
        commit: commit
      }

      send(view.pid, {:firehose_event, event})

      # Allow time for async update
      :timer.sleep(50)

      html = render(view)
      assert html =~ "Hello from the test!"
    end

    test "ignores non-post events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/firehose")

      # Create a like event (not a post)
      commit = %Commit{
        rev: "rev123",
        operation: :create,
        collection: "app.bsky.feed.like",
        rkey: "rkey123"
      }

      event = %Event{
        did: "did:plc:testuser",
        time_us: 1_725_911_162_329_308,
        kind: :commit,
        commit: commit
      }

      send(view.pid, {:firehose_event, event})

      html = render(view)
      # Should still show waiting message
      assert html =~ "Waiting for posts..."
    end

    test "does not add posts when paused", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/firehose")

      # Pause
      view |> element("button", "Pause") |> render_click()

      # Send an event
      post = %Post{text: "Should not appear", created_at: DateTime.utc_now()}

      commit = %Commit{
        rev: "rev123",
        operation: :create,
        collection: "app.bsky.feed.post",
        rkey: "rkey123",
        record: post
      }

      event = %Event{
        did: "did:plc:testuser",
        time_us: 1_725_911_162_329_308,
        kind: :commit,
        commit: commit
      }

      send(view.pid, {:firehose_event, event})

      html = render(view)
      refute html =~ "Should not appear"
    end

    test "filters posts by text", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/firehose")

      # Set filter
      view
      |> form("form[phx-change=\"filter\"]", %{"filter" => "elixir"})
      |> render_change()

      # Send a non-matching post
      post1 = %Post{text: "Hello world", created_at: DateTime.utc_now()}

      commit1 = %Commit{
        rev: "rev123",
        operation: :create,
        collection: "app.bsky.feed.post",
        rkey: "rkey123",
        record: post1
      }

      event1 = %Event{
        did: "did:plc:testuser",
        time_us: 1_725_911_162_329_308,
        kind: :commit,
        commit: commit1
      }

      send(view.pid, {:firehose_event, event1})

      html = render(view)
      refute html =~ "Hello world"

      # Send a matching post
      post2 = %Post{text: "I love elixir programming!", created_at: DateTime.utc_now()}

      commit2 = %Commit{
        rev: "rev124",
        operation: :create,
        collection: "app.bsky.feed.post",
        rkey: "rkey124",
        record: post2
      }

      event2 = %Event{
        did: "did:plc:testuser2",
        time_us: 1_725_911_162_329_309,
        kind: :commit,
        commit: commit2
      }

      send(view.pid, {:firehose_event, event2})

      # Allow time for async update
      :timer.sleep(50)

      html = render(view)
      assert html =~ "elixir"
    end
  end

  describe "highlight_text" do
    test "highlights matched text in posts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/firehose")

      # Set filter
      view
      |> form("form[phx-change=\"filter\"]", %{"filter" => "test"})
      |> render_change()

      # Send a matching post
      post = %Post{text: "This is a test post", created_at: DateTime.utc_now()}

      commit = %Commit{
        rev: "rev123",
        operation: :create,
        collection: "app.bsky.feed.post",
        rkey: "rkey123",
        record: post
      }

      event = %Event{
        did: "did:plc:testuser",
        time_us: 1_725_911_162_329_308,
        kind: :commit,
        commit: commit
      }

      send(view.pid, {:firehose_event, event})

      # Allow time for async update
      :timer.sleep(50)

      html = render(view)
      # Should contain the highlight mark
      assert html =~ "<mark"
      assert html =~ "test"
    end
  end
end
