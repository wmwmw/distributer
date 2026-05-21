defmodule Distributer.AI.Recommendation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime, updated_at: false]

  schema "ai_recommendations" do
    field :kind, :string
    field :model, :string
    field :prompt, :string
    field :response_json, :map, default: %{}
    field :latency_ms, :integer
    field :input_tokens, :integer
    field :output_tokens, :integer

    belongs_to :upload, Distributer.Slicing.Upload

    timestamps()
  end

  def changeset(rec, attrs) do
    rec
    |> cast(attrs, [:upload_id, :kind, :model, :prompt, :response_json,
                    :latency_ms, :input_tokens, :output_tokens])
    |> validate_required([:upload_id, :kind, :model, :prompt])
    |> validate_inclusion(:kind, ~w(material intent geometry))
  end
end
