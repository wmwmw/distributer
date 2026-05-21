defmodule Distributer.Repo.Migrations.CreateUploads do
  use Ecto.Migration

  def change do
    create table(:uploads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # NULL allowed for anonymous uploads pre-signup; will be claimed on register
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :original_filename, :string, null: false
      # stl | 3mf
      add :format, :string, null: false
      add :storage_key, :string, null: false
      add :size_bytes, :integer, null: false
      add :sha256, :string, null: false
      # Bounding box (mm)
      add :bbox_x_mm, :decimal, precision: 10, scale: 3
      add :bbox_y_mm, :decimal, precision: 10, scale: 3
      add :bbox_z_mm, :decimal, precision: 10, scale: 3
      # Volume in mm^3
      add :volume_mm3, :decimal, precision: 14, scale: 3
      # Pending | analyzed | failed
      add :analysis_status, :string, null: false, default: "pending"
      add :analysis_error, :text
      # Free-form description of what the buyer wants (used by AI recommender)
      add :intent_text, :text

      timestamps(type: :utc_datetime)
    end

    create index(:uploads, [:user_id])
    create unique_index(:uploads, [:sha256])
    create index(:uploads, [:analysis_status])
  end
end
