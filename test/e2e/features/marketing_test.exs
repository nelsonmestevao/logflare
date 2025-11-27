defmodule E2E.Features.MarketingTest do
  use PhoenixTest.Playwright.Case,
    async: true,
    headless: true,
    slow_mo: :timer.seconds(2)

  import Phoenix.VerifiedRoutes

  @router LogflareWeb.Router
  @endpoint LogflareWeb.Endpoint

  setup do
    # pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Logflare.Repo, shared: false)
    # on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    start_supervised!(Logflare.SystemMetricsSup)
    :ok
  end

  test "goes to visit page", %{conn: conn} do
    conn
    |> visit(~p"/pricing")
    |> screenshot("error.png", full_page: true)
  end
end
