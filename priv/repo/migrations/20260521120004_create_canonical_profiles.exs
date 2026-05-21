defmodule Distributer.Repo.Migrations.CreateCanonicalProfiles do
  use Ecto.Migration

  def change do
    create table(:canonical_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :printer_model_id, references(:printer_models, type: :binary_id, on_delete: :delete_all), null: false
      # Material category this profile is tuned for (e.g. "PLA", "PETG")
      add :material_type, :string, null: false
      # Quality tier: draft | standard | strong | detail
      add :quality_tier, :string, null: false, default: "standard"
      # Layer height in mm (denormalized for fast lookup)
      add :layer_height_mm, :decimal, precision: 4, scale: 3, null: false
      # Full PrusaSlicer config_bundle as JSON. The actual slicer profile lives here.
      add :slicer_config, :map, null: false, default: %{}
      add :description, :text
      add :is_default, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:canonical_profiles, [:printer_model_id, :material_type, :quality_tier])
    create unique_index(:canonical_profiles, [:printer_model_id, :material_type, :quality_tier],
             name: :canonical_profiles_unique_combo)
  end
end
