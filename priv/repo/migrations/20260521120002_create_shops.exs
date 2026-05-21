defmodule Distributer.Repo.Migrations.CreateShops do
  use Ecto.Migration

  def change do
    create table(:shops, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :slug, :string, null: false
      add :name, :string, null: false
      add :tagline, :string
      add :description, :text
      add :logo_url, :string
      add :country, :string, null: false, default: "CZ"
      add :default_currency, :string, null: false, default: "CZK"
      add :is_active, :boolean, null: false, default: false
      # Seller-defined markup applied to material+machine cost (percent)
      add :markup_percent, :decimal, precision: 6, scale: 2, default: "15.0"
      # Per-print fixed handling fee in minor units (haléře)
      add :handling_fee_cents, :integer, default: 0
      # Free-form policies/terms (markdown)
      add :policies, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shops, [:slug])
    create index(:shops, [:user_id])
    create index(:shops, [:is_active])
  end
end
