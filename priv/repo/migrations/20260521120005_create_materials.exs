defmodule Distributer.Repo.Migrations.CreateMaterials do
  use Ecto.Migration

  def change do
    create table(:materials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Category, e.g. PLA / PETG / ASA / ABS / TPU
      add :type, :string, null: false
      add :brand, :string, null: false
      add :name, :string, null: false
      # Filament diameter in mm (1.75 typical)
      add :diameter_mm, :decimal, precision: 4, scale: 2, default: "1.75"
      # Density in g/cm^3 (PLA ~1.24)
      add :density, :decimal, precision: 5, scale: 3, null: false
      # Recommended nozzle temp range
      add :nozzle_temp_min, :integer
      add :nozzle_temp_max, :integer
      add :bed_temp_min, :integer
      add :bed_temp_max, :integer
      # Properties used by the recommender: ["uv_resistant", "flexible", "food_safe", ...]
      add :properties, {:array, :string}, default: []
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:materials, [:brand, :name])
    create index(:materials, [:type])
  end
end
