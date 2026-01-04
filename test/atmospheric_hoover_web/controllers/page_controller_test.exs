defmodule AtmosphericHooverWeb.PageControllerTest do
  use AtmosphericHooverWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Atmospheric Hoover"
  end
end
