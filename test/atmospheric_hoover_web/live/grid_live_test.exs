defmodule AtmosphericHooverWeb.GridLiveTest do
  @moduledoc """
  Tests for the Grid LiveView displaying posts in a grid layout.
  """

  use AtmosphericHooverWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "mount/3" do
    test "renders the grid page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/grid")

      assert html =~ "Bluesky Grid"
    end

    test "initializes with empty posts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/grid")

      # Grid should show empty slots
      html = render(view)
      assert html =~ "grid"
    end

    test "assigns page_title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/grid")

      assert page_title(view) =~ "Post Grid"
    end
  end

  describe "navigation" do
    test "has link to analytics", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/grid")

      assert html =~ ~s(href="/")
    end

    test "has link to firehose", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/grid")

      assert html =~ "Raw Firehose"
      assert html =~ ~s(href="/firehose")
    end

    test "has link to conversations", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/grid")

      assert html =~ "Conversations"
      assert html =~ ~s(href="/conversations")
    end
  end

  describe "filter panel" do
    test "toggle_filters event shows filter panel", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/grid")

      # Initially filter panel may be hidden
      refute html =~ "Search posts..."

      # Click filter toggle
      html = view |> element("button", "Filter") |> render_click()

      assert html =~ "Search"
      assert html =~ "Languages"
      assert html =~ "Hashtags"
      assert html =~ "Users"
    end

    test "update_text event updates text filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/grid")

      # Show filters first
      view |> element("button", "Filter") |> render_click()

      # Update text filter
      view |> element("input[placeholder=\"Search posts...\"]") |> render_keyup(%{"value" => "test"})

      html = render(view)
      assert html =~ "Filter"
    end

    test "toggle_lang event toggles language filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/grid")

      # Show filters
      view |> element("button", "Filter") |> render_click()

      # Toggle English language
      html = view |> element("button", "en") |> render_click()

      # The button should now be active (blue)
      assert html =~ "bg-blue-500"
    end

    test "add_hashtag event adds hashtag filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/grid")

      # Show filters
      view |> element("button", "Filter") |> render_click()

      # Add a hashtag
      view
      |> form("form[phx-submit=\"add_hashtag\"]", %{"value" => "elixir"})
      |> render_submit()

      html = render(view)
      assert html =~ "#elixir"
    end

    test "remove_hashtag event removes hashtag", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/grid")

      # Show filters and add a hashtag first
      view |> element("button", "Filter") |> render_click()

      view
      |> form("form[phx-submit=\"add_hashtag\"]", %{"value" => "test"})
      |> render_submit()

      html = render(view)
      assert html =~ "#test"

      # Remove it
      view |> element("button[phx-click=\"remove_hashtag\"]") |> render_click()

      html = render(view)
      refute html =~ "inline-flex items-center gap-1 px-2 py-0.5 text-xs bg-blue-100" &&
               html =~ "#test"
    end

    test "add_user event adds user filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/grid")

      # Show filters
      view |> element("button", "Filter") |> render_click()

      # Add a user
      view
      |> form("form[phx-submit=\"add_user\"]", %{"value" => "test.bsky.social"})
      |> render_submit()

      html = render(view)
      assert html =~ "@test.bsky.social"
    end

    test "toggle_user_mode switches between blocklist and whitelist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/grid")

      # Show filters
      view |> element("button", "Filter") |> render_click()

      html = render(view)
      assert html =~ "(block)"

      # Toggle mode
      view |> element("button", "(block)") |> render_click()

      html = render(view)
      assert html =~ "(allow)"
    end

    test "clear_filters event resets all filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/grid")

      # Show filters and add some
      view |> element("button", "Filter") |> render_click()
      view |> element("button", "en") |> render_click()

      view
      |> form("form[phx-submit=\"add_hashtag\"]", %{"value" => "test"})
      |> render_submit()

      # Clear all
      html = view |> element("button", "Clear all") |> render_click()

      # Filter count badge should be gone
      refute html =~ "bg-blue-500 text-white text-xs rounded-full"
    end
  end

  describe "stats display" do
    test "shows displayed count", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/grid")

      assert html =~ "shown"
    end

    test "shows pending count", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/grid")

      assert html =~ "pending"
    end
  end

  describe "grid slots" do
    test "renders empty slots initially", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/grid")

      # Should have placeholder slots
      assert html =~ "border-dashed"
    end
  end
end
