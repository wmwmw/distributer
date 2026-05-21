defmodule Distributer.Pricing do
  @moduledoc """
  Deterministic price computation. All money is in minor units (haléře = CZK × 100).

  Buyer total =
      material_cost       (grams × spool.sell_price_per_gram_cents)
    + machine_cost        (minutes × shop_printer.hourly_rate_cents / 60)
    + handling_fee_cents  (per-shop, per-print fixed)
    + markup              (shop.markup_percent of subtotal-so-far)
    + shipping_cents
    + platform_fee        (configured percent of the above subtotal)

  Stripe Connect splits the resulting charge: platform_fee → platform,
  remainder → seller's connected account.
  """

  alias Distributer.Catalog.ShopPrinter
  alias Distributer.Inventory.MaterialSpool
  alias Distributer.Shops.Shop

  @type breakdown :: %{
          material_cost_cents: integer(),
          machine_cost_cents: integer(),
          handling_fee_cents: integer(),
          markup_cents: integer(),
          shipping_cents: integer(),
          platform_fee_cents: integer(),
          total_cents: integer(),
          currency: String.t()
        }

  @doc """
  Compute the full price breakdown.
  """
  @spec quote_price(%{
          grams: float() | nil,
          minutes: integer() | nil,
          quantity: pos_integer(),
          shop: Shop.t(),
          shop_printer: ShopPrinter.t(),
          spool: MaterialSpool.t(),
          shipping_cents: integer()
        }) :: breakdown()
  def quote_price(params) do
    %{
      grams: grams,
      minutes: minutes,
      quantity: qty,
      shop: shop,
      shop_printer: printer,
      spool: spool,
      shipping_cents: shipping
    } = params

    grams = (grams || 0.0) * qty
    minutes = (minutes || 0) * qty

    material = round(grams * spool.sell_price_per_gram_cents)
    machine = round(minutes * printer.hourly_rate_cents / 60)
    handling = shop.handling_fee_cents || 0

    pre_markup = material + machine + handling
    markup_percent = Decimal.to_float(shop.markup_percent || Decimal.new("0"))
    markup = round(pre_markup * markup_percent / 100)

    seller_subtotal = pre_markup + markup + shipping
    platform_percent = platform_fee_percent()
    platform = round(seller_subtotal * platform_percent / 100)

    total = seller_subtotal + platform

    %{
      material_cost_cents: material,
      machine_cost_cents: machine,
      handling_fee_cents: handling,
      markup_cents: markup,
      shipping_cents: shipping,
      platform_fee_cents: platform,
      total_cents: total,
      currency: shop.default_currency
    }
  end

  def platform_fee_percent do
    Application.get_env(:distributer, :stripe)[:platform_fee_percent] || 3
  end

  @doc "Format minor units as a human display string with currency."
  def format(cents, currency) when is_integer(cents) do
    whole = div(cents, 100)
    frac = rem(cents, 100) |> abs() |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{whole},#{frac} #{currency}"
  end
end
