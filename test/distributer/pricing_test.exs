defmodule Distributer.PricingTest do
  use ExUnit.Case, async: true

  alias Distributer.Pricing
  alias Distributer.Shops.Shop
  alias Distributer.Catalog.ShopPrinter
  alias Distributer.Inventory.MaterialSpool

  # In-memory structs — pricing is pure and needs no DB.
  defp shop(opts \\ []) do
    %Shop{
      handling_fee_cents: Keyword.get(opts, :handling_fee_cents, 0),
      markup_percent: Keyword.get(opts, :markup_percent, Decimal.new("15.0")),
      default_currency: Keyword.get(opts, :currency, "CZK")
    }
  end

  defp printer(rate \\ 6000), do: %ShopPrinter{hourly_rate_cents: rate}
  defp spool(price \\ 150), do: %MaterialSpool{sell_price_per_gram_cents: price}

  defp params(overrides) do
    Map.merge(
      %{
        grams: 20.0,
        minutes: 120,
        quantity: 1,
        shop: shop(),
        shop_printer: printer(),
        spool: spool(),
        shipping_cents: 8900
      },
      Map.new(overrides)
    )
  end

  test "computes the full breakdown in minor units" do
    b = Pricing.quote_price(params([]))

    assert b.material_cost_cents == 3000
    assert b.machine_cost_cents == 12_000
    assert b.handling_fee_cents == 0
    # (3000 + 12000 + 0) * 15% = 2250
    assert b.markup_cents == 2250
    assert b.shipping_cents == 8900
    # seller_subtotal = 15000 + 2250 + 8900 = 26150; 3% => 784.5 -> 785
    assert b.platform_fee_cents == 785
    assert b.total_cents == 26_935
    assert b.currency == "CZK"
  end

  test "the platform fee reconciles: subtotal + fee == total" do
    b = Pricing.quote_price(params([]))
    seller_subtotal = b.total_cents - b.platform_fee_cents

    assert b.platform_fee_cents == round(seller_subtotal * Pricing.platform_fee_percent() / 100)
    assert b.total_cents == seller_subtotal + b.platform_fee_cents
  end

  test "scales grams and minutes by quantity" do
    one = Pricing.quote_price(params(quantity: 1))
    two = Pricing.quote_price(params(quantity: 2))

    assert two.material_cost_cents == one.material_cost_cents * 2
    assert two.machine_cost_cents == one.machine_cost_cents * 2
  end

  test "handling fee feeds the markup base" do
    b = Pricing.quote_price(params(shop: shop(handling_fee_cents: 1000)))

    assert b.handling_fee_cents == 1000
    # (3000 + 12000 + 1000) * 15% = 2400
    assert b.markup_cents == 2400
  end

  test "nil grams and minutes are treated as zero" do
    b = Pricing.quote_price(params(grams: nil, minutes: nil, shipping_cents: 0))

    assert b.material_cost_cents == 0
    assert b.machine_cost_cents == 0
  end

  describe "format/2" do
    test "renders minor units with two fractional digits" do
      assert Pricing.format(26_935, "CZK") == "269,35 CZK"
      assert Pricing.format(5, "CZK") == "0,05 CZK"
      assert Pricing.format(100, "CZK") == "1,00 CZK"
    end
  end
end
