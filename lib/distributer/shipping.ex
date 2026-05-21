defmodule Distributer.Shipping do
  @moduledoc """
  Shipping integration. Phase 1: Packeta (Zásilkovna) for CZ.

  This module wraps the Packeta REST API for creating shipments and
  fetching pickup-point info. In dev / when no API key is configured,
  all calls return stubbed responses so the rest of the flow can be
  exercised without external dependencies.

  Docs: https://docs.packetery.com/03-creating-packets/
  """

  require Logger

  @doc """
  Estimate shipping cost in minor units (haléře). Phase 1: flat rate per
  shop, based on pickup-point delivery. Will be replaced with live rates
  in phase 2.
  """
  def estimate_cents(_shop_id, quantity) when is_integer(quantity) and quantity > 0 do
    # 89 CZK base + 0 CZK extra per item, since Packeta charges by package, not item.
    8900
  end

  @doc """
  Create a Packeta shipment label for an order.

  Returns `{:ok, %{label_id: ..., tracking: ..., label_url: ...}}` or
  `{:error, reason}`.
  """
  def create_packet(order) do
    case config()[:api_password] do
      pwd when pwd in [nil, "packeta_placeholder"] ->
        Logger.info("Packeta stub: returning fake label for order #{order.number}")

        {:ok,
         %{
           label_id: "STUB-#{order.number}",
           tracking: "Z#{:rand.uniform(99_999_999)}",
           label_url: "https://example.com/labels/STUB-#{order.number}.pdf"
         }}

      _pwd ->
        do_create_packet(order)
    end
  end

  defp do_create_packet(order) do
    body = %{
      apiPassword: config()[:api_password],
      packetAttributes: %{
        number: order.number,
        name: order.recipient_name,
        email: order.recipient_email,
        phone: order.recipient_phone,
        addressId: order.packeta_point_id,
        cod: 0,
        value: order.total_cents / 100,
        weight: 0.5,
        eshop: config()[:sender_label]
      }
    }

    case Req.post("https://www.zasilkovna.cz/api/rest/", json: body) do
      {:ok, %{status: 200, body: %{"status" => "ok", "result" => result}}} ->
        {:ok,
         %{
           label_id: result["id"],
           tracking: result["barcode"],
           label_url: result["barcodeText"]
         }}

      {:ok, %{body: %{"status" => "fault", "fault" => msg}}} ->
        {:error, msg}

      err ->
        {:error, err}
    end
  end

  @doc """
  Fetch metadata for a Packeta pickup point by its id, e.g. for display
  on the order confirmation page. Stub in dev.
  """
  def lookup_pickup_point(point_id) do
    case config()[:api_password] do
      pwd when pwd in [nil, "packeta_placeholder"] ->
        {:ok,
         %{
           id: point_id,
           name: "Z-BOX Praha (stub)",
           street: "Vinohradská 1",
           city: "Praha 3",
           zip: "130 00",
           country: "CZ"
         }}

      _ ->
        # Live API call would go here
        {:error, :not_implemented}
    end
  end

  defp config, do: Application.fetch_env!(:distributer, :packeta)
end
