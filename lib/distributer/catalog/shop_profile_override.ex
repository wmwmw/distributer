defmodule Distributer.Catalog.ShopProfileOverride do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "shop_profile_overrides" do
    field :overrides_json, :map, default: %{}
    field :notes, :string

    belongs_to :shop_printer, Distributer.Catalog.ShopPrinter
    belongs_to :canonical_profile, Distributer.Catalog.CanonicalProfile

    timestamps()
  end

  def changeset(override, attrs) do
    override
    |> cast(attrs, [:shop_printer_id, :canonical_profile_id, :overrides_json, :notes])
    |> validate_required([:shop_printer_id, :canonical_profile_id])
    |> unique_constraint([:shop_printer_id, :canonical_profile_id],
        name: :shop_overrides_unique_pair)
  end
end
