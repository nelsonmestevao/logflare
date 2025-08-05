defmodule LogflareWeb.BillingControllerTest do
  use LogflareWeb.ConnCase, async: false

  alias Logflare.Billing.Stripe
  alias Logflare.Source
  alias Logflare.TestUtils

  setup do
    insert(:plan, name: "Free")
    insert(:plan, name: "Metered", stripe_id: "price_metered_test")
    insert(:plan, name: "Standard", stripe_id: "price_standard_test")
    :ok
  end

  describe "create/2 - POST /billing" do
    test "creates billing account successfully", %{conn: conn} do
      user = insert(:user_without_billing_account)
      stripe_customer_id = TestUtils.random_string()

      Stripe.Customer
      |> expect(:create, 1, fn ^user -> {:ok, %{id: stripe_customer_id}} end)

      conn
      |> login_user(user)
      |> visit(~p"/account/edit")
      |> assert_has("h1", text: "Account Settings")
      |> click_button("Create billing account")
      |> assert_path(~p"/billing/edit")
      |> assert_has("#flash-info", text: "Success! Billing account created!")

      # Verify billing account was created
      user_reloaded = Logflare.Repo.reload!(user) |> Logflare.Repo.preload(:billing_account)
      assert user_reloaded.billing_account.stripe_customer == stripe_customer_id
    end

    test "handles Stripe customer creation failure", %{conn: conn} do
      user = insert(:user_without_billing_account)

      Stripe.Customer
      |> expect(:create, 1, fn ^user -> {:error, "Stripe error"} end)
      |> expect(:delete, 1, fn _customer_id -> {:ok, %{}} end)

      conn
      |> login_user(user)
      |> visit(~p"/account/edit")
      |> click_button("Create billing account")
      |> assert_path(~p"/account/edit")
      |> assert_has("#flash-error", text: "Something went wrong")
    end

    test "not authenticated user is redirected to login", %{conn: conn} do
      conn
      |> visit(~p"/billing")
      |> assert_path(~p"/auth/login")
    end
  end

  describe "edit/2 - GET /billing/edit" do
    test "redirects to create billing account if user has no billing account", %{conn: conn} do
      user = insert(:user_without_billing_account)

      conn
      |> login_user(user)
      |> visit(~p"/billing/edit")
      |> assert_path(~p"/account/edit#billing-account")
      |> assert_has("#flash-error", text: "create a billing account")
    end

    test "renders edit page for user with billing account", %{conn: conn} do
      user = insert(:user_with_billing_account)

      conn
      |> login_user(user)
      |> visit(~p"/billing/edit")
      |> assert_has("h1", text: "Billing Account")
      |> assert_has("p", text: "Free plan")
    end

    test "not authenticated user is redirected to login", %{conn: conn} do
      conn
      |> visit(~p"/billing/edit")
      |> assert_path(~p"/auth/login")
    end
  end

  describe "delete/2 - DELETE /billing" do
    test "deletes billing account successfully", %{conn: conn} do
      user = insert(:user_with_billing_account)
      billing_account = user.billing_account

      Logflare.Billing
      |> expect(:delete_billing_account, 1, fn ^user -> {:ok, %{}} end)

      Stripe.Customer
      |> expect(:delete, 1, fn stripe_customer_id ->
        assert stripe_customer_id == billing_account.stripe_customer
        {:ok, %{}}
      end)

      conn
      |> login_user(user)
      |> visit(~p"/billing/edit")
      |> click_button("Delete billing account")
      |> assert_path(~p"/")
      |> assert_has("#flash-info", text: "Billing account deleted!")
    end

    test "handles billing account deletion failure", %{conn: conn} do
      user = insert(:user_with_billing_account)

      Logflare.Billing
      |> expect(:delete_billing_account, 1, fn ^user -> {:error, "Database error"} end)

      conn
      |> login_user(user)
      |> visit(~p"/billing/edit")
      |> click_button("Delete billing account")
      |> assert_path(~p"/billing/edit")
      |> assert_has("#flash-error", text: "Something went wrong")
    end

    test "handles Stripe customer deletion failure", %{conn: conn} do
      user = insert(:user_with_billing_account)
      billing_account = user.billing_account

      Logflare.Billing
      |> expect(:delete_billing_account, 1, fn ^user -> {:ok, %{}} end)

      Stripe.Customer
      |> expect(:delete, 1, fn stripe_customer_id ->
        assert stripe_customer_id == billing_account.stripe_customer
        {:error, "Stripe error"}
      end)

      conn
      |> login_user(user)
      |> visit(~p"/billing/edit")
      |> click_button("Delete billing account")
      |> assert_path(~p"/")
      |> assert_has("#flash-error", text: "Something went wrong")
    end

    test "not authenticated user is redirected to login", %{conn: conn} do
      conn
      |> visit(~p"/billing")
      |> assert_path(~p"/auth/login")
    end
  end

  describe "confirm_subscription/2 - GET /billing/subscription/confirm" do
    test "creates billing account and confirms subscription for user without billing account", %{
      conn: conn
    } do
      user = insert(:user_without_billing_account)
      insert(:plan, stripe_id: "price_test123")
      stripe_customer_id = TestUtils.random_string()
      session_id = "cs_test_" <> TestUtils.random_string()

      Stripe.Customer
      |> expect(:create, 1, fn ^user -> {:ok, %{id: stripe_customer_id}} end)

      Stripe.Session
      |> expect(:create, 1, fn _params -> {:ok, %{id: session_id}} end)

      conn
      |> login_user(user)
      |> visit(~p"/billing/subscription/confirm?stripe_id=price_test123")
      |> assert_has("h1", text: "Confirm")
      |> assert_has("button", text: "Confirm subscription")
    end

    test "confirms payment mode subscription", %{conn: conn} do
      user = insert(:user_with_no_subscription)
      insert(:plan, stripe_id: "price_test123")
      session_id = "cs_test_" <> TestUtils.random_string()

      Stripe.Session
      |> expect(:create, 1, fn params ->
        assert params[:mode] == "payment"
        {:ok, %{id: session_id}}
      end)

      conn
      |> login_user(user)
      |> visit(~p"/billing/subscription/confirm?stripe_id=price_test123&mode=payment")
      |> assert_has("h1", text: "Confirm")
      |> assert_has("button", text: "Confirm subscription")
    end

    test "confirms metered subscription", %{conn: conn} do
      user = insert(:user_with_no_subscription)
      insert(:plan, stripe_id: "price_test123")
      session_id = "cs_test_" <> TestUtils.random_string()

      Stripe.Session
      |> expect(:create, 1, fn _params -> {:ok, %{id: session_id}} end)

      conn
      |> login_user(user)
      |> visit(~p"/billing/subscription/confirm?stripe_id=price_test123&type=metered")
      |> assert_has("h1", text: "Confirm")
      |> assert_has("button", text: "Confirm subscription")
    end

    test "confirms standard subscription", %{conn: conn} do
      user = insert(:user_with_no_subscription)
      insert(:plan, stripe_id: "price_test123")
      session_id = "cs_test_" <> TestUtils.random_string()

      Stripe.Session
      |> expect(:create, 1, fn _params -> {:ok, %{id: session_id}} end)

      conn
      |> login_user(user)
      |> visit(~p"/billing/subscription/confirm?stripe_id=price_test123")
      |> assert_has("h1", text: "Confirm")
      |> assert_has("button", text: "Confirm subscription")
    end

    test "rejects if user already has subscription", %{conn: conn} do
      user = insert(:user_with_subscription)
      insert(:plan, stripe_id: "price_test123")

      conn
      |> login_user(user)
      |> visit(~p"/billing/subscription/confirm?stripe_id=price_test123")
      |> assert_path(~p"/billing/edit")
      |> assert_has("#flash-error", text: "Please delete your current subscription first!")
    end

    test "handles Stripe session creation failure", %{conn: conn} do
      user = insert(:user_with_no_subscription)
      insert(:plan, stripe_id: "price_test123")

      Stripe.Session
      |> expect(:create, 1, fn _params -> {:error, "Stripe error"} end)

      conn
      |> login_user(user)
      |> visit(~p"/billing/subscription/confirm?stripe_id=price_test123")
      |> assert_path(~p"/billing/edit")
      |> assert_has("#flash-error", text: "Something went wrong")
    end

    test "not authenticated user is redirected to login", %{conn: conn} do
      conn
      |> visit(~p"/billing/subscription/confirm?stripe_id=price_test123")
      |> assert_path(~p"/auth/login")
    end
  end

  describe "change_subscription/2 - GET /billing/subscription/change" do
    test "changes from standard to metered subscription", %{conn: conn} do
      user = insert(:user_with_standard_subscription)
      plan = insert(:plan, name: "Metered", stripe_id: "price_metered")

      Stripe.Subscription
      |> expect(:update, 1, fn _subscription_id, _params -> {:ok, %{}} end)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/subscription/change?plan=#{plan.id}&type=metered")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Success! Plan successfully changed!"
    end

    test "changes from metered to metered subscription", %{conn: conn} do
      user = insert(:user_with_metered_subscription)
      plan = insert(:plan, name: "Metered Premium", stripe_id: "price_metered_premium")

      Stripe.Subscription
      |> expect(:update, 1, fn _subscription_id, _params -> {:ok, %{}} end)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/subscription/change?plan=#{plan.id}&type=metered")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Success! Plan successfully changed!"
    end

    test "changes from standard to standard subscription", %{conn: conn} do
      user = insert(:user_with_standard_subscription)
      plan = insert(:plan, name: "Standard Premium", stripe_id: "price_standard_premium")

      Stripe.Subscription
      |> expect(:update, 1, fn _subscription_id, _params -> {:ok, %{}} end)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/subscription/change?plan=#{plan.id}&type=standard")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Success! Plan successfully changed!"
    end

    test "changes from metered to standard subscription", %{conn: conn} do
      user = insert(:user_with_metered_subscription)
      plan = insert(:plan, name: "Standard", stripe_id: "price_standard")

      Stripe.Subscription
      |> expect(:update, 1, fn _subscription_id, _params -> {:ok, %{}} end)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/subscription/change?plan=#{plan.id}&type=standard")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Success! Plan successfully changed!"
    end

    test "rejects if user has no subscription", %{conn: conn} do
      user = insert(:user_with_no_subscription)
      plan = insert(:plan, name: "Standard", stripe_id: "price_standard")

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/subscription/change?plan=#{plan.id}&type=standard")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "You need a subscription to change first!"
    end

    test "handles Stripe subscription change failure", %{conn: conn} do
      user = insert(:user_with_standard_subscription)
      plan = insert(:plan, name: "Metered", stripe_id: "price_metered")

      Stripe.Subscription
      |> expect(:update, 1, fn _subscription_id, _params -> {:error, "Stripe error"} end)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/subscription/change?plan=#{plan.id}&type=metered")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Something went wrong. Try that again! If this continues please contact support."
    end

    test "not authenticated user is redirected to login", %{conn: conn} do
      plan = insert(:plan, name: "Standard", stripe_id: "price_standard")

      conn =
        conn
        |> get(~p"/billing/subscription/change?plan=#{plan.id}&type=standard")

      assert redirected_to(conn, 302) == ~p"/auth/login"
    end
  end

  describe "portal/2 - GET /billing/subscription/manage" do
    test "redirects to Stripe billing portal", %{conn: conn} do
      user = insert(:user_with_billing_account)
      portal_url = "https://billing.stripe.com/session/test_123"

      Stripe.BillingPortal.Session
      |> expect(:create, 1, fn _params -> {:ok, %{url: portal_url}} end)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/subscription/manage")

      assert redirected_to(conn, 302) == portal_url
    end

    test "handles Stripe portal creation failure", %{conn: conn} do
      user = insert(:user_with_billing_account)

      Stripe.BillingPortal.Session
      |> expect(:create, 1, fn _params -> {:error, "Stripe error"} end)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/subscription/manage")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Something went wrong. Try that again! If this continues please contact support."
    end

    test "not authenticated user is redirected to login", %{conn: conn} do
      conn =
        conn
        |> get(~p"/billing/subscription/manage")

      assert redirected_to(conn, 302) == ~p"/auth/login"
    end
  end

  describe "update_payment_details/2 - GET /billing/subscription/confirm/change" do
    test "creates session for updating payment details", %{conn: conn} do
      user = insert(:user_with_subscription)
      session_id = "cs_setup_" <> TestUtils.random_string()

      Stripe.Session
      |> expect(:create, 1, fn params ->
        assert params[:mode] == "setup"
        {:ok, %{id: session_id}}
      end)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/subscription/confirm/change")

      assert html_response(conn, 200) =~ "confirm"
      assert get_session(conn, :stripe_session)
    end

    test "rejects if user has no subscription", %{conn: conn} do
      user = insert(:user_with_no_subscription)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/subscription/confirm/change")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Please subscribe first!"
    end

    test "handles Stripe session creation failure", %{conn: conn} do
      user = insert(:user_with_subscription)

      Stripe.Session
      |> expect(:create, 1, fn _params -> {:error, "Stripe error"} end)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/subscription/confirm/change")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Something went wrong. Try that again! If this continues please contact support."
    end

    test "not authenticated user is redirected to login", %{conn: conn} do
      conn =
        conn
        |> get(~p"/billing/subscription/confirm/change")

      assert redirected_to(conn, 302) == ~p"/auth/login"
    end
  end

  describe "unsubscribe/2 - DELETE /billing/subscription" do
    test "deletes subscription successfully", %{conn: conn} do
      user = insert(:user_with_subscription)
      billing_account = user.billing_account
      subscription_id = "sub_test123"

      Source.Supervisor
      |> expect(:reset_all_user_sources, 1, fn ^user -> :ok end)

      Stripe.Subscription
      |> expect(:delete, 1, fn ^subscription_id -> {:ok, %{}} end)

      Logflare.Billing
      |> expect(:sync_subscriptions, 1, fn ^billing_account -> {:ok, billing_account} end)

      conn =
        conn
        |> login_user(user)
        |> delete(~p"/billing/subscription?id=#{subscription_id}")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Success! Subscription deleted!"
    end

    test "handles subscription not found", %{conn: conn} do
      user = insert(:user_with_subscription)
      subscription_id = "sub_nonexistent"

      conn =
        conn
        |> login_user(user)
        |> delete(~p"/billing/subscription?id=#{subscription_id}")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Subscription not found."
    end

    test "handles Stripe deletion failure", %{conn: conn} do
      user = insert(:user_with_subscription)
      billing_account = user.billing_account
      subscription_id = hd(billing_account.stripe_subscriptions["data"])["id"]

      Stripe.Subscription
      |> expect(:delete, 1, fn ^subscription_id -> {:error, "Stripe error"} end)

      conn =
        conn
        |> login_user(user)
        |> delete(~p"/billing/subscription?id=#{subscription_id}")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Something went wrong. Try that again! If this continues please contact support."
    end

    test "not authenticated user is redirected to login", %{conn: conn} do
      subscription_id = "sub_test123"

      conn =
        conn
        |> delete(~p"/billing/subscription?id=#{subscription_id}")

      assert redirected_to(conn, 302) == ~p"/auth/login"
    end
  end

  describe "update_credit_card_success/2 - GET /billing/subscription/updated-payment-method" do
    test "updates payment method successfully", %{conn: conn} do
      user = insert(:user_with_billing_account)
      billing_account = user.billing_account
      session_id = "cs_test_" <> TestUtils.random_string()
      setup_intent_id = "seti_test_" <> TestUtils.random_string()
      payment_method_id = "pm_test_" <> TestUtils.random_string()

      stripe_session = %{id: session_id, setup_intent: setup_intent_id}

      Stripe.Session
      |> expect(:retrieve, 1, fn ^session_id -> {:ok, stripe_session} end)

      Stripe.SetupIntent
      |> expect(:retrieve, 1, fn ^setup_intent_id -> 
        {:ok, %{payment_method: payment_method_id}} 
      end)

      Stripe.Customer
      |> expect(:update, 1, fn customer_id, params ->
        assert customer_id == billing_account.stripe_customer
        assert params[:invoice_settings][:default_payment_method] == payment_method_id
        {:ok, %{}}
      end)

      Logflare.Billing
      |> expect(:update_billing_account, 1, fn ^billing_account, params ->
        assert params[:latest_successful_stripe_session] == stripe_session
        {:ok, billing_account}
      end)

      conn =
        conn
        |> login_user(user)
        |> put_session(:stripe_session, stripe_session)
        |> get(~p"/billing/subscription/updated-payment-method")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Success! Payment method updated!"
    end

    test "handles Stripe session retrieval failure", %{conn: conn} do
      user = insert(:user_with_billing_account)
      session_id = "cs_test_" <> TestUtils.random_string()
      stripe_session = %{id: session_id}

      Stripe.Session
      |> expect(:retrieve, 1, fn ^session_id -> {:error, "Stripe error"} end)

      conn =
        conn
        |> login_user(user)
        |> put_session(:stripe_session, stripe_session)
        |> get(~p"/billing/subscription/updated-payment-method")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Something went wrong. Try that again! If this continues please contact support."
    end

    test "not authenticated user is redirected to login", %{conn: conn} do
      conn =
        conn
        |> get(~p"/billing/subscription/updated-payment-method")

      assert redirected_to(conn, 302) == ~p"/auth/login"
    end
  end

  describe "success/2 - GET /billing/subscription/subscribed" do
    test "processes successful subscription creation", %{conn: conn} do
      user = insert(:user_with_billing_account)
      billing_account = user.billing_account
      session_id = "cs_test_" <> TestUtils.random_string()
      stripe_session = %{id: session_id}

      Source.Supervisor
      |> expect(:reset_all_user_sources, 1, fn ^user -> :ok end)

      Stripe.Session
      |> expect(:retrieve, 1, fn ^session_id -> {:ok, stripe_session} end)

      Logflare.Billing
      |> expect(:update_billing_account, 1, fn ^billing_account, params ->
        assert params[:latest_successful_stripe_session] == stripe_session
        {:ok, billing_account}
      end)

      conn =
        conn
        |> login_user(user)
        |> put_session(:stripe_session, stripe_session)
        |> get(~p"/billing/subscription/subscribed")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Success! Subscription created!"
    end

    test "handles Stripe session retrieval failure", %{conn: conn} do
      user = insert(:user_with_billing_account)
      session_id = "cs_test_" <> TestUtils.random_string()
      stripe_session = %{id: session_id}

      Stripe.Session
      |> expect(:retrieve, 1, fn ^session_id -> {:error, "Stripe error"} end)

      conn =
        conn
        |> login_user(user)
        |> put_session(:stripe_session, stripe_session)
        |> get(~p"/billing/subscription/subscribed")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Something went wrong. Try that again! If this continues please contact support."
    end

    test "not authenticated user is redirected to login", %{conn: conn} do
      conn =
        conn
        |> get(~p"/billing/subscription/subscribed")

      assert redirected_to(conn, 302) == ~p"/auth/login"
    end
  end

  describe "sync/2 - GET /billing/sync" do
    test "syncs billing account successfully", %{conn: conn} do
      user = insert(:user_with_billing_account)
      billing_account = user.billing_account

      Logflare.Billing
      |> expect(:sync_billing_account, 1, fn ^billing_account -> {:ok, billing_account} end)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/sync")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Success! Billing account synced!"
    end

    test "handles sync failure", %{conn: conn} do
      user = insert(:user_with_billing_account)
      billing_account = user.billing_account

      Logflare.Billing
      |> expect(:sync_billing_account, 1, fn ^billing_account -> {:error, "Sync error"} end)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/sync")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Something went wrong. Try that again! If this continues please contact support."
    end

    test "not authenticated user is redirected to login", %{conn: conn} do
      conn =
        conn
        |> get(~p"/billing/sync")

      assert redirected_to(conn, 302) == ~p"/auth/login"
    end
  end

  describe "abandoned/2 - GET /billing/subscription/abandoned" do
    test "handles abandoned checkout", %{conn: conn} do
      user = insert(:user_with_billing_account)

      conn =
        conn
        |> login_user(user)
        |> get(~p"/billing/subscription/abandoned")

      assert redirected_to(conn, 302) == ~p"/billing/edit"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Abandoned!"
    end

    test "not authenticated user is redirected to login", %{conn: conn} do
      conn =
        conn
        |> get(~p"/billing/subscription/abandoned")

      assert redirected_to(conn, 302) == ~p"/auth/login"
    end
  end
end
