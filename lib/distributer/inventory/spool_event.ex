defmodule Distributer.Inventory.SpoolEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime, updated_at: false]

  schema "spool_events" do
    field :kind, :string
    field :grams_delta, :decimal
    field :grams_remaining_after, :integer
    field :notes, :string

    belongs_to :material_spool, Distributer.Inventory.MaterialSpool
    belongs_to :print_job, Distributer.Orders.PrintJob

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:material_spool_id, :print_job_id, :kind, :grams_delta, :grams_remaining_after, :notes])
    |> validate_required([:material_spool_id, :kind, :grams_delta, :grams_remaining_after])
    |> validate_inclusion(:kind, ~w(consume restock correction discard))
  end
end
