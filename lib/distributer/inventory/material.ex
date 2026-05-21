defmodule Distributer.Inventory.Material do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "materials" do
    field :type, :string
    field :brand, :string
    field :name, :string
    field :diameter_mm, :decimal, default: Decimal.new("1.75")
    field :density, :decimal
    field :nozzle_temp_min, :integer
    field :nozzle_temp_max, :integer
    field :bed_temp_min, :integer
    field :bed_temp_max, :integer
    field :properties, {:array, :string}, default: []
    field :description, :string

    timestamps()
  end

  def changeset(material, attrs) do
    material
    |> cast(attrs, [
      :type, :brand, :name, :diameter_mm, :density,
      :nozzle_temp_min, :nozzle_temp_max, :bed_temp_min, :bed_temp_max,
      :properties, :description
    ])
    |> validate_required([:type, :brand, :name, :density])
    |> validate_inclusion(:type, ~w(PLA PETG ASA ABS TPU PC PA Nylon PVA HIPS))
    |> unique_constraint([:brand, :name])
  end
end
