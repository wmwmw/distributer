defmodule Distributer.Repo.Migrations.CreateShopPrinters do
  use Ecto.Migration

  def change do
    create table(:shop_printers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :shop_id, references(:shops, type: :binary_id, on_delete: :delete_all), null: false
      add :printer_model_id, references(:printer_models, type: :binary_id, on_delete: :restrict), null: false
      # Seller's nickname for this printer (e.g. "MK4 - Garage")
      add :nickname, :string
      # Machine time cost, per hour, in minor units (haléře = CZK * 100)
      add :hourly_rate_cents, :integer, null: false, default: 5000
      # Currently usable?
      add :is_active, :boolean, default: true
      # Last successful test print at
      add :last_calibrated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:shop_printers, [:shop_id])
    create index(:shop_printers, [:printer_model_id])
    create index(:shop_printers, [:is_active])
  end
end
