defmodule Distributer.Fixtures do
  @moduledoc """
  Test fixtures for the domain. Each helper inserts the minimum valid row and
  accepts an attrs map/keyword to override fields. IDs are made unique per call
  so fixtures can be combined freely within a test.
  """

  alias Distributer.{Accounts, Catalog, Inventory, Orders, Repo, Shops}
  alias Distributer.Orders.Quote
  alias Distributer.Slicing.Upload

  def uniq, do: System.unique_integer([:positive])

  def user_fixture(attrs \\ %{}) do
    n = uniq()

    {:ok, user} =
      attrs
      |> Map.new()
      |> Map.put_new(:email, "user#{n}@example.com")
      |> Map.put_new(:password, "supersecret123")
      |> Accounts.register_user()

    user
  end

  def seller_fixture(attrs \\ %{}) do
    {:ok, user} = user_fixture(attrs) |> Accounts.promote_to_seller()
    user
  end

  def shop_fixture(user \\ nil, attrs \\ %{}) do
    user = user || seller_fixture()
    n = uniq()

    {:ok, shop} =
      attrs
      |> Map.new()
      |> Map.put_new(:user_id, user.id)
      |> Map.put_new(:slug, "shop-#{n}")
      |> Map.put_new(:name, "Shop #{n}")
      |> Map.put_new(:is_active, true)
      |> Map.put_new(:default_currency, "CZK")
      |> Map.put_new(:markup_percent, Decimal.new("15.0"))
      |> Map.put_new(:handling_fee_cents, 0)
      |> Shops.create_shop()

    shop
  end

  def printer_model_fixture(attrs \\ %{}) do
    n = uniq()

    {:ok, pm} =
      attrs
      |> Map.new()
      |> Map.put_new(:brand, "Prusa")
      |> Map.put_new(:model, "MK4-#{n}")
      |> Map.put_new(:technology, "FDM")
      |> Map.put_new(:bed_x_mm, 250)
      |> Map.put_new(:bed_y_mm, 210)
      |> Map.put_new(:bed_z_mm, 220)
      |> Map.put_new(:supported_materials, ["PLA", "PETG"])
      |> Map.put_new(:is_active, true)
      |> Catalog.create_printer_model()

    pm
  end

  def canonical_profile_fixture(printer_model \\ nil, attrs \\ %{}) do
    printer_model = printer_model || printer_model_fixture()

    {:ok, cp} =
      attrs
      |> Map.new()
      |> Map.put_new(:printer_model_id, printer_model.id)
      |> Map.put_new(:material_type, "PLA")
      |> Map.put_new(:quality_tier, "standard")
      |> Map.put_new(:layer_height_mm, Decimal.new("0.2"))
      |> Map.put_new(:slicer_config, %{"layer_height" => "0.2"})
      |> Catalog.create_canonical_profile()

    cp
  end

  def material_fixture(attrs \\ %{}) do
    n = uniq()

    {:ok, m} =
      attrs
      |> Map.new()
      |> Map.put_new(:type, "PLA")
      |> Map.put_new(:brand, "Prusament")
      |> Map.put_new(:name, "PLA #{n}")
      |> Map.put_new(:density, Decimal.new("1.24"))
      |> Map.put_new(:diameter_mm, Decimal.new("1.75"))
      |> Map.put_new(:properties, ["rigid"])
      |> Inventory.create_material()

    m
  end

  def spool_fixture(shop, material \\ nil, attrs \\ %{}) do
    material = material || material_fixture()

    {:ok, spool} =
      attrs
      |> stringify()
      |> Map.put_new("shop_id", shop.id)
      |> Map.put_new("material_id", material.id)
      |> Map.put_new("color_name", "Black")
      |> Map.put_new("color_hex", "#1a1a1a")
      |> Map.put_new("grams_total", 1000)
      |> Map.put_new("grams_remaining", 1000)
      |> Map.put_new("sell_price_per_gram_cents", 150)
      |> Map.put_new("is_active", true)
      |> Inventory.create_spool()

    Inventory.get_spool!(spool.id)
  end

  def shop_printer_fixture(shop, printer_model \\ nil, attrs \\ %{}) do
    printer_model = printer_model || printer_model_fixture()

    {:ok, sp} =
      attrs
      |> stringify()
      |> Map.put_new("shop_id", shop.id)
      |> Map.put_new("printer_model_id", printer_model.id)
      |> Map.put_new("hourly_rate_cents", 6000)
      |> Map.put_new("is_active", true)
      |> Catalog.create_shop_printer()

    Catalog.get_shop_printer!(sp.id)
  end

  def upload_fixture(user \\ nil, attrs \\ %{}) do
    n = uniq()

    {:ok, upload} =
      %Upload{}
      |> Upload.changeset(
        attrs
        |> stringify()
        |> Map.put_new("user_id", user && user.id)
        |> Map.put_new("original_filename", "model#{n}.stl")
        |> Map.put_new("format", "stl")
        |> Map.put_new("storage_key", "uploads/test-#{n}.stl")
        |> Map.put_new("size_bytes", 1024)
        |> Map.put_new("sha256", :crypto.hash(:sha256, "file-#{n}") |> Base.encode16(case: :lower))
        |> Map.put_new("analysis_status", "analyzed")
      )
      |> Repo.insert()

    upload
  end

  @doc """
  Build a full sliced quote plus its supporting rows. Returns a map with
  `:quote, :shop, :shop_printer, :spool, :material, :canonical, :upload`.
  Override any of those by passing them in `opts`.
  """
  def sliced_quote_fixture(opts \\ %{}) do
    opts = Map.new(opts)
    shop = opts[:shop] || shop_fixture()
    printer_model = opts[:printer_model] || printer_model_fixture()
    shop_printer = opts[:shop_printer] || shop_printer_fixture(shop, printer_model)
    material = opts[:material] || material_fixture()
    spool = opts[:spool] || spool_fixture(shop, material)
    canonical = opts[:canonical] || canonical_profile_fixture(printer_model)
    upload = opts[:upload] || upload_fixture(opts[:buyer])

    quote_attrs =
      Map.merge(
        %{
          upload_id: upload.id,
          shop_printer_id: shop_printer.id,
          material_spool_id: spool.id,
          canonical_profile_id: canonical.id,
          quantity: 1,
          status: "sliced",
          estimated_grams: Decimal.new("20.0"),
          estimated_print_minutes: 120,
          material_cost_cents: 3000,
          machine_cost_cents: 12_000,
          handling_fee_cents: 0,
          markup_cents: 2250,
          shipping_cents: 8900,
          platform_fee_cents: 786,
          total_cents: 26_936,
          currency: "CZK",
          gcode_storage_key: "gcode/test-#{uniq()}.gcode"
        },
        Map.get(opts, :quote_attrs, %{})
      )

    {:ok, quote} = %Quote{} |> Quote.changeset(quote_attrs) |> Repo.insert()

    %{
      quote: quote,
      shop: shop,
      shop_printer: shop_printer,
      spool: spool,
      material: material,
      canonical: canonical,
      upload: upload
    }
  end

  @doc """
  Place a real order (status `quoted`) and return
  `{order, ctx}` where `ctx` is the `sliced_quote_fixture/1` map plus `:buyer`.
  """
  def order_fixture(opts \\ %{}) do
    opts = Map.new(opts)
    buyer = opts[:buyer] || user_fixture()
    ctx = sliced_quote_fixture(Map.put(opts, :buyer, buyer))

    {:ok, order} =
      Orders.place_order(ctx.quote, buyer, %{
        "recipient_name" => "Test Buyer",
        "recipient_email" => buyer.email,
        "packeta_point_id" => "STUB-1"
      })

    {order, Map.put(ctx, :buyer, buyer)}
  end

  defp stringify(attrs) do
    attrs
    |> Map.new()
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end
end
