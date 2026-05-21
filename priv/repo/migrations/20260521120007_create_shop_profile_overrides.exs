defmodule Distributer.Repo.Migrations.CreateShopProfileOverrides do
  use Ecto.Migration

  def change do
    create table(:shop_profile_overrides, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :shop_printer_id, references(:shop_printers, type: :binary_id, on_delete: :delete_all), null: false
      add :canonical_profile_id, references(:canonical_profiles, type: :binary_id, on_delete: :restrict), null: false
      # Partial slicer config that overrides specific keys in the canonical profile
      add :overrides_json, :map, null: false, default: %{}
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shop_profile_overrides, [:shop_printer_id, :canonical_profile_id],
             name: :shop_overrides_unique_pair)
  end
end
