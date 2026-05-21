defmodule Distributer.Orders.PrintJob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "print_jobs" do
    field :gcode_storage_key, :string
    field :status, :string, default: "queued"
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :grams_used, :decimal
    field :failure_reason, :string
    field :photo_url, :string

    belongs_to :order, Distributer.Orders.Order
    belongs_to :shop_printer, Distributer.Catalog.ShopPrinter
    belongs_to :material_spool, Distributer.Inventory.MaterialSpool

    timestamps()
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :order_id, :shop_printer_id, :material_spool_id, :gcode_storage_key,
      :status, :started_at, :finished_at, :grams_used, :failure_reason, :photo_url
    ])
    |> validate_required([:order_id, :shop_printer_id, :material_spool_id, :gcode_storage_key])
    |> validate_inclusion(:status, ~w(queued downloaded printing succeeded failed aborted))
  end
end
