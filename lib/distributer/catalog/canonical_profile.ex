defmodule Distributer.Catalog.CanonicalProfile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "canonical_profiles" do
    field :material_type, :string
    field :quality_tier, :string, default: "standard"
    field :layer_height_mm, :decimal
    field :slicer_config, :map, default: %{}
    field :description, :string
    field :is_default, :boolean, default: false

    belongs_to :printer_model, Distributer.Catalog.PrinterModel

    timestamps()
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :printer_model_id, :material_type, :quality_tier, :layer_height_mm,
      :slicer_config, :description, :is_default
    ])
    |> validate_required([:printer_model_id, :material_type, :quality_tier, :layer_height_mm, :slicer_config])
    |> validate_inclusion(:quality_tier, ~w(draft standard strong detail))
    |> unique_constraint([:printer_model_id, :material_type, :quality_tier],
        name: :canonical_profiles_unique_combo)
  end
end
