defmodule DistributerWeb.StripeWebhookController do
  use DistributerWeb, :controller

  require Logger

  alias Distributer.Payments
  alias DistributerWeb.CacheBodyReader

  def create(conn, _params) do
    payload = CacheBodyReader.raw_body(conn)
    signature = get_req_header(conn, "stripe-signature") |> List.first()

    case Payments.construct_event(payload, signature) do
      {:ok, event} ->
        Payments.handle_event(event)
        send_resp(conn, 200, "ok")

      {:error, reason} ->
        Logger.warning("Rejected Stripe webhook: #{inspect(reason)}")
        send_resp(conn, 400, "invalid signature")
    end
  end
end
