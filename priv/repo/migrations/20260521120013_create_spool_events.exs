defmodule Distributer.Repo.Migrations.CreateSpoolEvents do
  use Ecto.Migration

  def change do
    create table(:spool_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :material_spool_id, references(:material_spools, type: :binary_id, on_delete: :delete_all), null: false
      add :print_job_id, references(:print_jobs, type: :binary_id, on_delete: :nilify_all)
      # consume | restock | correction | discard
      add :kind, :string, null: false
      add :grams_delta, :decimal, precision: 10, scale: 3, null: false
      add :grams_remaining_after, :integer, null: false
      add :notes, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:spool_events, [:material_spool_id])
    create index(:spool_events, [:print_job_id])
  end
end
