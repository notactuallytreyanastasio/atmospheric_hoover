defmodule AtmosphericHooverWeb.PageControllerTest do
  use AtmosphericHooverWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    # Root route now renders AnalyticsLive
    assert html_response(conn, 200) =~ "Analytics"
  end
end
