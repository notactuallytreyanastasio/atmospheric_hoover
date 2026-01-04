defmodule AtmosphericHooverWeb.ErrorJSONTest do
  use AtmosphericHooverWeb.ConnCase, async: true

  test "renders 404" do
    assert AtmosphericHooverWeb.ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Not Found"}
           }
  end

  test "renders 500" do
    assert AtmosphericHooverWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
