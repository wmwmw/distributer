defmodule DistributerWeb.StripeWebhookController do
  use DistributerWeb, :controller

  alias Distributer.Payments

  def create(conn, params) do
    # In production: verify the Stripe signature header against the webhook
    # secret before handling. Phase 1 accepts unsigned events for local testing.
    Payments.handle_event(params)
    send_resp(conn, 200, "ok")
  end
end
