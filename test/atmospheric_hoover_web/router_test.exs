defmodule AtmosphericHooverWeb.RouterTest do
  @moduledoc """
  Tests for the application router.
  Verifies all routes are properly configured.
  """

  use AtmosphericHooverWeb.ConnCase, async: true

  describe "browser routes" do
    test "GET / renders analytics page", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Analytics"
    end

    test "GET /grid renders grid page", %{conn: conn} do
      conn = get(conn, ~p"/grid")
      assert html_response(conn, 200) =~ "Grid"
    end

    test "GET /firehose renders firehose page", %{conn: conn} do
      conn = get(conn, ~p"/firehose")
      assert html_response(conn, 200) =~ "Firehose"
    end

    test "GET /conversations renders conversations page", %{conn: conn} do
      conn = get(conn, ~p"/conversations")
      assert html_response(conn, 200) =~ "Conversation"
    end
  end

  describe "404 handling" do
    test "returns 404 for unknown routes", %{conn: conn} do
      conn = get(conn, "/unknown-route")
      assert html_response(conn, 404)
    end
  end
end
