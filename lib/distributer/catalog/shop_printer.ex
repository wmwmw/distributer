defmodule Distributer.Catalog.ShopPrinter do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "shop_printers" do
    field :nickname, :string
    field :hourly_rate_cents, :integer, default: 5000
    field :is_active, :boolean, default: true
    field :last_calibrated_at, :utc_datetime

    belongs_to :shop, Distributer.Shops.Shop
    belongs_to :printer_model, Distributer.Catalog.PrinterModel
    has_many :profile_overrides, Distributer.Catalog.ShopProfileOverride

    timestamps()
  end

  def changeset(shop_printer, attrs) do
    shop_printer
    |> cast(attrs, [
      :shop_id, :printer_model_id, :nickname, :hourly_rate_cents,
      :is_active, :last_calibrated_at
    ])
    |> validate_required([:shop_id, :printer_model_id])
    |> validate_number(:hourly_rate_cents, greater_than_or_equal_to: 0)
  end
end
