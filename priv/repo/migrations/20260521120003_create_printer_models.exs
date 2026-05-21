defmodule Distributer.Repo.Migrations.CreatePrinterModels do
  use Ecto.Migration

  def change do
    create table(:printer_models, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :brand, :string, null: false
      add :model, :string, null: false
      # FDM, SLA, SLS, etc. - phase 1 only FDM
      add :technology, :string, null: false, default: "FDM"
      add :bed_x_mm, :integer, null: false
      add :bed_y_mm, :integer, null: false
      add :bed_z_mm, :integer, null: false
      add :nozzle_default_mm, :decimal, precision: 4, scale: 2, default: "0.4"
      # Supported material types e.g. ["PLA", "PETG", "ASA", "ABS"]
      add :supported_materials, {:array, :string}, default: []
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:printer_models, [:brand, :model])
  end
end
