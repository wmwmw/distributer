defmodule Distributer.Shops.Shop do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "shops" do
    field :slug, :string
    field :name, :string
    field :tagline, :string
    field :description, :string
    field :logo_url, :string
    field :country, :string, default: "CZ"
    field :default_currency, :string, default: "CZK"
    field :is_active, :boolean, default: false
    field :markup_percent, :decimal, default: Decimal.new("15.0")
    field :handling_fee_cents, :integer, default: 0
    field :policies, :string

    belongs_to :user, Distributer.Accounts.User
    has_many :shop_printers, Distributer.Catalog.ShopPrinter
    has_many :material_spools, Distributer.Inventory.MaterialSpool

    timestamps()
  end

  def changeset(shop, attrs) do
    shop
    |> cast(attrs, [
      :user_id,
      :slug,
      :name,
      :tagline,
      :description,
      :logo_url,
      :country,
      :default_currency,
      :is_active,
      :markup_percent,
      :handling_fee_cents,
      :policies
    ])
    |> validate_required([:user_id, :slug, :name])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "may only contain lowercase letters, numbers, and dashes")
    |> validate_length(:slug, min: 3, max: 60)
    |> validate_number(:markup_percent, greater_than_or_equal_to: 0, less_than: 1000)
    |> validate_number(:handling_fee_cents, greater_than_or_equal_to: 0)
    |> unique_constraint(:slug)
    |> unique_constraint(:user_id, name: :shops_user_id_index)
  end
end
