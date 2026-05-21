defmodule Distributer.Orders.Quote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "quotes" do
    field :infill_percent, :integer, default: 20
    field :walls, :integer, default: 3
    field :supports, :boolean, default: false
    field :quantity, :integer, default: 1

    field :estimated_grams, :decimal
    field :estimated_print_minutes, :integer
    field :slicer_log, :string

    field :material_cost_cents, :integer
    field :machine_cost_cents, :integer
    field :handling_fee_cents, :integer
    field :markup_cents, :integer
    field :platform_fee_cents, :integer
    field :shipping_cents, :integer
    field :total_cents, :integer
    field :currency, :string, default: "CZK"

    field :status, :string, default: "pending"
    field :error, :string
    field :gcode_storage_key, :string
    field :expires_at, :utc_datetime

    belongs_to :upload, Distributer.Slicing.Upload
    belongs_to :shop_printer, Distributer.Catalog.ShopPrinter
    belongs_to :material_spool, Distributer.Inventory.MaterialSpool
    belongs_to :canonical_profile, Distributer.Catalog.CanonicalProfile

    timestamps()
  end

  def changeset(quote, attrs) do
    quote
    |> cast(attrs, [
      :upload_id, :shop_printer_id, :material_spool_id, :canonical_profile_id,
      :infill_percent, :walls, :supports, :quantity,
      :estimated_grams, :estimated_print_minutes, :slicer_log,
      :material_cost_cents, :machine_cost_cents, :handling_fee_cents,
      :markup_cents, :platform_fee_cents, :shipping_cents, :total_cents,
      :currency, :status, :error, :gcode_storage_key, :expires_at
    ])
    |> validate_required([:upload_id, :shop_printer_id, :material_spool_id, :canonical_profile_id])
    |> validate_number(:infill_percent, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:walls, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:quantity, greater_than_or_equal_to: 1, less_than_or_equal_to: 100)
    |> validate_inclusion(:status, ~w(pending sliced failed converted))
  end
end
