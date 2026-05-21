defmodule Distributer.Repo.Migrations.CreateMaterialSpools do
  use Ecto.Migration

  def change do
    create table(:material_spools, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :shop_id, references(:shops, type: :binary_id, on_delete: :delete_all), null: false
      add :material_id, references(:materials, type: :binary_id, on_delete: :restrict), null: false
      add :color_name, :string, null: false
      # Hex code for UI rendering
      add :color_hex, :string
      add :batch_code, :string
      add :grams_total, :integer, null: false
      add :grams_remaining, :integer, null: false
      # Price seller paid (used to derive cost basis); minor units
      add :purchase_price_cents, :integer
      # Price per gram charged to buyers (minor units, per gram), seller-set
      add :sell_price_per_gram_cents, :integer, null: false
      add :is_active, :boolean, default: true
      # Optional photo URL (seller verification)
      add :photo_url, :string

      timestamps(type: :utc_datetime)
    end

    create index(:material_spools, [:shop_id])
    create index(:material_spools, [:material_id])
    create index(:material_spools, [:is_active])
  end
end
