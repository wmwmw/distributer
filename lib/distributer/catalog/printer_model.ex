defmodule Distributer.Catalog.PrinterModel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "printer_models" do
    field :brand, :string
    field :model, :string
    field :technology, :string, default: "FDM"
    field :bed_x_mm, :integer
    field :bed_y_mm, :integer
    field :bed_z_mm, :integer
    field :nozzle_default_mm, :decimal, default: Decimal.new("0.4")
    field :supported_materials, {:array, :string}, default: []
    field :is_active, :boolean, default: true

    has_many :canonical_profiles, Distributer.Catalog.CanonicalProfile

    timestamps()
  end

  def changeset(model, attrs) do
    model
    |> cast(attrs, [
      :brand, :model, :technology, :bed_x_mm, :bed_y_mm, :bed_z_mm,
      :nozzle_default_mm, :supported_materials, :is_active
    ])
    |> validate_required([:brand, :model, :technology, :bed_x_mm, :bed_y_mm, :bed_z_mm])
    |> validate_inclusion(:technology, ~w(FDM SLA SLS))
    |> unique_constraint([:brand, :model])
  end
end
