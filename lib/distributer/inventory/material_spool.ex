defmodule Distributer.Inventory.MaterialSpool do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "material_spools" do
    field :color_name, :string
    field :color_hex, :string
    field :batch_code, :string
    field :grams_total, :integer
    field :grams_remaining, :integer
    field :purchase_price_cents, :integer
    field :sell_price_per_gram_cents, :integer
    field :is_active, :boolean, default: true
    field :photo_url, :string

    belongs_to :shop, Distributer.Shops.Shop
    belongs_to :material, Distributer.Inventory.Material
    has_many :events, Distributer.Inventory.SpoolEvent

    timestamps()
  end

  def changeset(spool, attrs) do
    spool
    |> cast(attrs, [
      :shop_id, :material_id, :color_name, :color_hex, :batch_code,
      :grams_total, :grams_remaining, :purchase_price_cents,
      :sell_price_per_gram_cents, :is_active, :photo_url
    ])
    |> validate_required([:shop_id, :material_id, :color_name, :grams_total, :grams_remaining, :sell_price_per_gram_cents])
    |> validate_number(:grams_total, greater_than: 0)
    |> validate_number(:grams_remaining, greater_than_or_equal_to: 0)
    |> validate_number(:sell_price_per_gram_cents, greater_than_or_equal_to: 0)
    |> validate_format(:color_hex, ~r/^#?[0-9a-fA-F]{6}$/, message: "must be a 6-digit hex color")
  end
end
