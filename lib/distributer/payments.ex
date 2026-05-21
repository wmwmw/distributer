defmodule Distributer.Payments do
  @moduledoc """
  Stripe Connect integration. Marketplace charges with destination flow:
  buyer pays full total to platform, platform takes `platform_fee_cents`,
  remainder transferred to seller's connected account.

  Stub mode: when no real Stripe key is set, returns synthetic
  PaymentIntent IDs and the LiveView "place order" button can flip the
  order to `paid` directly. This lets the rest of the pipeline run end
  to end without Stripe credentials.
  """

  require Logger

  alias Distributer.Orders
  alias Distributer.Pricing

  @doc """
  Create a Stripe PaymentIntent for an order. Returns
  `{:ok, %{payment_intent_id: ..., client_secret: ...}}` or `{:error, reason}`.

  In stub mode the `client_secret` is set to a sentinel; the LiveView
  treats this as auto-paid.
  """
  def create_intent(order, shop) do
    case config()[:api_key] do
      "sk_test_placeholder" ->
        {:ok,
         %{
           payment_intent_id: "pi_stub_#{:rand.uniform(99_999_999)}",
           client_secret: "stub"
         }}

      key ->
        do_create_intent(order, shop, key)
    end
  end

  defp do_create_intent(order, shop, key) do
    platform_fee = round(order.total_cents * Pricing.platform_fee_percent() / 100)

    body =
      URI.encode_query(%{
        "amount" => order.total_cents,
        "currency" => String.downcase(order.currency),
        "transfer_data[destination]" => shop.user.stripe_account_id,
        "application_fee_amount" => platform_fee,
        "metadata[order_id]" => order.id,
        "metadata[order_number]" => order.number
      })

    case Req.post("https://api.stripe.com/v1/payment_intents",
           headers: [
             {"authorization", "Bearer #{key}"},
             {"content-type", "application/x-www-form-urlencoded"}
           ],
           body: body
         ) do
      {:ok, %{status: 200, body: %{"id" => id, "client_secret" => secret}}} ->
        {:ok, %{payment_intent_id: id, client_secret: secret}}

      {:ok, %{body: body}} ->
        {:error, body}

      err ->
        {:error, err}
    end
  end

  @doc """
  Handle a verified Stripe webhook event. Real webhook signature
  verification is left to the controller; this just acts on the parsed
  event payload.
  """
  def handle_event(%{"type" => "payment_intent.succeeded", "data" => %{"object" => pi}}) do
    order_id = pi["metadata"]["order_id"]

    if order_id do
      order = Orders.get_order!(order_id)

      Orders.mark_paid(order, %{
        stripe_payment_intent_id: pi["id"],
        stripe_charge_id: pi["latest_charge"]
      })
    else
      :ok
    end
  end

  def handle_event(_), do: :ok

  @doc """
  Mark a stub order as paid in dev without going through Stripe. Use only
  when stub key is configured.
  """
  def stub_mark_paid(order) do
    Orders.mark_paid(order, %{
      stripe_payment_intent_id: "pi_stub_#{order.id}",
      stripe_charge_id: "ch_stub_#{order.id}"
    })
  end

  defp config, do: Application.fetch_env!(:distributer, :stripe)
end
