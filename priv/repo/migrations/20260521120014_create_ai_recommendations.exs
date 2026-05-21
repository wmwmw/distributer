defmodule Distributer.Repo.Migrations.CreateAiRecommendations do
  use Ecto.Migration

  def change do
    create table(:ai_recommendations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :upload_id, references(:uploads, type: :binary_id, on_delete: :delete_all), null: false
      # material | intent | geometry
      add :kind, :string, null: false
      add :model, :string, null: false
      add :prompt, :text, null: false
      add :response_json, :map, null: false, default: %{}
      add :latency_ms, :integer
      add :input_tokens, :integer
      add :output_tokens, :integer

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ai_recommendations, [:upload_id])
    create index(:ai_recommendations, [:kind])
  end
end
