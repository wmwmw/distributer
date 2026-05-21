defmodule Distributer.Repo.Migrations.CreateQuotes do
  use Ecto.Migration

  def change do
    create table(:quotes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :upload_id, references(:uploads, type: :binary_id, on_delete: :delete_all), null: false
      add :shop_printer_id, references(:shop_printers, type: :binary_id, on_delete: :restrict), null: false
      add :material_spool_id, references(:material_spools, type: :binary_id, on_delete: :restrict), null: false
      add :canonical_profile_id, references(:canonical_profiles, type: :binary_id, on_delete: :restrict), null: false
      # Buyer-chosen overrides on top of canonical
      add :infill_percent, :integer, null: false, default: 20
      add :walls, :integer, null: false, default: 3
      add :supports, :boolean, null: false, default: false
      add :quantity, :integer, null: false, default: 1
      # Slicer outputs
      add :estimated_grams, :decimal, precision: 10, scale: 3
      add :estimated_print_minutes, :integer
      add :slicer_log, :text
      # Pricing breakdown (minor units / haléře)
      add :material_cost_cents, :integer
      add :machine_cost_cents, :integer
      add :handling_fee_cents, :integer
      add :markup_cents, :integer
      add :platform_fee_cents, :integer
      add :shipping_cents, :integer
      add :total_cents, :integer
      add :currency, :string, null: false, default: "CZK"
      # pending | sliced | failed | converted (to order)
      add :status, :string, null: false, default: "pending"
      add :error, :text
      # Cached gcode storage key (re-used if order is placed)
      add :gcode_storage_key, :string
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:quotes, [:upload_id])
    create index(:quotes, [:shop_printer_id])
    create index(:quotes, [:material_spool_id])
    create index(:quotes, [:status])
  end
end
