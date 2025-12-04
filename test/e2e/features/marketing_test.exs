defmodule E2E.Features.MarketingTest do
  use PhoenixTest.Playwright.Case,
    async: false,
    headless: false,
    slow_mo: :timer.seconds(2)

  import Logflare.Factory

  import Phoenix.VerifiedRoutes

  @router LogflareWeb.Router
  @endpoint LogflareWeb.Endpoint

  setup do
    start_supervised!(Logflare.SystemMetricsSup)
    :ok
  end

  test "goes to visit page", %{conn: conn} do
    insert(:plan, price: 123, period: "month", name: "Metered")
    insert(:plan, price: 123, period: "month", name: "Metered BYOB")

    conn
    |> visit("http://localhost:4001/pricing")
    |> screenshot("error.png", full_page: true)
  end
end
