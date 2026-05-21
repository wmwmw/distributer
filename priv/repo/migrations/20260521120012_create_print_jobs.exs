defmodule Distributer.Repo.Migrations.CreatePrintJobs do
  use Ecto.Migration

  def change do
    create table(:print_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false
      add :shop_printer_id, references(:shop_printers, type: :binary_id, on_delete: :restrict), null: false
      add :material_spool_id, references(:material_spools, type: :binary_id, on_delete: :restrict), null: false
      add :gcode_storage_key, :string, null: false
      # queued | downloaded | printing | succeeded | failed | aborted
      add :status, :string, null: false, default: "queued"
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      # Actual grams consumed (seller can correct)
      add :grams_used, :decimal, precision: 10, scale: 3
      add :failure_reason, :text
      # Photo proof of print (URL)
      add :photo_url, :string

      timestamps(type: :utc_datetime)
    end

    create index(:print_jobs, [:order_id])
    create index(:print_jobs, [:status])
  end
end
