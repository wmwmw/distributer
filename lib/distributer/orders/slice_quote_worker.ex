defmodule Distributer.Orders.SliceQuoteWorker do
  @moduledoc """
  Background slicing for a pending quote. Loads upload + resolved profile,
  runs PrusaSlicer, persists results, broadcasts to the LiveView.
  """
  use Oban.Worker, queue: :slicing, max_attempts: 2

  alias Distributer.{Catalog, Inventory, Orders, Shipping, Slicing}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"quote_id" => id}}) do
    quote = Orders.get_quote!(id)
    shop_printer = quote.shop_printer
    canonical = quote.canonical_profile
    spool = quote.material_spool

    config = Catalog.effective_slicer_config(shop_printer, canonical)

    intent = %{
      infill_percent: quote.infill_percent,
      walls: quote.walls,
      supports: quote.supports
    }

    material = Inventory.get_material!(spool.material_id)
    density = Decimal.to_float(material.density)
    diameter = Decimal.to_float(material.diameter_mm)

    case Slicing.slice_for_quote(quote.upload, %{
           slicer_config: config,
           intent_params: intent,
           material_density: density,
           filament_diameter_mm: diameter
         }) do
      {:ok, result} ->
        shipping = Shipping.estimate_cents(shop_printer.shop_id, quote.quantity)
        {:ok, updated} = Orders.update_quote_with_slice_result(quote, result, shipping)

        Phoenix.PubSub.broadcast(
          Distributer.PubSub,
          "quote:#{updated.id}",
          {:quote_sliced, updated.id}
        )

        :ok

      {:error, reason, _log} ->
        Orders.mark_quote_failed(quote, reason)
        {:error, reason}
    end
  end
end
