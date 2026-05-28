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

  # Reject events whose timestamp is more than this many seconds away from now
  # (replay protection), matching Stripe's recommended default tolerance.
  @signature_tolerance_seconds 300

  @doc """
  Create a Stripe PaymentIntent for an order. Returns
  `{:ok, %{payment_intent_id: ..., client_secret: ...}}` or `{:error, reason}`.

  In stub mode the `client_secret` is set to a sentinel; the LiveView
  treats this as auto-paid.
  """
  def create_intent(order, shop) do
    if stub_mode?() do
      {:ok,
       %{
         payment_intent_id: "pi_stub_#{:rand.uniform(99_999_999)}",
         client_secret: "stub"
       }}
    else
      do_create_intent(order, shop, config()[:api_key])
    end
  end

  defp do_create_intent(order, shop, key) do
    # Use the platform fee that was quoted to the buyer rather than
    # recomputing from the order total (which already includes the fee).
    # This keeps the Stripe `application_fee_amount` reconciled with the
    # `platform_fee_cents` in the pricing breakdown the buyer agreed to.
    quote = Orders.get_quote!(order.quote_id)
    platform_fee = quote.platform_fee_cents

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
  Verify a raw Stripe webhook payload against the `Stripe-Signature` header
  and return the parsed event.

  Returns `{:ok, event_map}` when the HMAC-SHA256 signature is valid and the
  timestamp is within tolerance, otherwise `{:error, reason}`. In stub mode
  (no real webhook secret configured) verification is skipped and the payload
  is parsed directly — this keeps local development working without Stripe
  credentials, but a real secret MUST be set in production.
  """
  def construct_event(payload, signature_header) when is_binary(payload) do
    secret = config()[:webhook_secret]

    if webhook_stub_mode?() do
      Logger.warning("Stripe webhook signature verification skipped (stub mode)")
      decode_event(payload)
    else
      with :ok <- verify_signature(payload, signature_header, secret) do
        decode_event(payload)
      end
    end
  end

  def construct_event(_payload, _signature_header), do: {:error, :missing_payload}

  defp decode_event(payload) do
    case Jason.decode(payload) do
      {:ok, event} -> {:ok, event}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp verify_signature(_payload, nil, _secret), do: {:error, :missing_signature}

  defp verify_signature(payload, signature_header, secret) when is_binary(signature_header) do
    with {:ok, timestamp, signatures} <- parse_signature_header(signature_header),
         :ok <- check_timestamp(timestamp) do
      expected =
        :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{payload}")
        |> Base.encode16(case: :lower)

      # Constant-time comparison (via Plug.Crypto) to avoid timing leaks.
      if Enum.any?(signatures, &Plug.Crypto.secure_compare(&1, expected)) do
        :ok
      else
        {:error, :signature_mismatch}
      end
    end
  end

  defp parse_signature_header(header) do
    parts =
      header
      |> String.split(",")
      |> Enum.map(fn pair ->
        case String.split(pair, "=", parts: 2) do
          [k, v] -> {String.trim(k), v}
          _ -> {nil, nil}
        end
      end)

    timestamp = Enum.find_value(parts, fn {k, v} -> k == "t" && v end)
    signatures = for {"v1", v} <- parts, do: v

    cond do
      is_nil(timestamp) -> {:error, :malformed_signature}
      signatures == [] -> {:error, :malformed_signature}
      true -> {:ok, timestamp, signatures}
    end
  end

  defp check_timestamp(timestamp) do
    case Integer.parse(timestamp) do
      {ts, _} ->
        if abs(System.system_time(:second) - ts) <= @signature_tolerance_seconds do
          :ok
        else
          {:error, :timestamp_out_of_tolerance}
        end

      :error ->
        {:error, :malformed_signature}
    end
  end

  @doc """
  Act on a parsed (and already verified) Stripe webhook event.
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

  @doc """
  True when no real Stripe API key is configured, so charges are simulated.
  """
  def stub_mode? do
    config()[:api_key] in [nil, "", "sk_test_placeholder"]
  end

  @doc """
  True when no real Stripe webhook secret is configured, so signature
  verification is skipped. MUST be false in production.
  """
  def webhook_stub_mode? do
    config()[:webhook_secret] in [nil, "", "whsec_placeholder"]
  end

  defp config, do: Application.fetch_env!(:distributer, :stripe)
end
