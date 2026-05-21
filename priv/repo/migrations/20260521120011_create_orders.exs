defmodule Distributer.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Human-readable order number (e.g. DST-2026-00042)
      add :number, :string, null: false
      add :quote_id, references(:quotes, type: :binary_id, on_delete: :restrict), null: false
      add :buyer_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :shop_id, references(:shops, type: :binary_id, on_delete: :restrict), null: false

      # State machine:
      # quoted -> paid -> accepted -> printing -> printed -> shipped -> delivered -> released
      #                                          -> cancelled -> refunded
      add :status, :string, null: false, default: "quoted"

      # Payment
      add :stripe_payment_intent_id, :string
      add :stripe_charge_id, :string
      add :paid_at, :utc_datetime
      add :refunded_at, :utc_datetime

      # Shipping
      add :shipping_method, :string, null: false, default: "packeta_pickup"
      add :packeta_point_id, :string
      add :packeta_label_id, :string
      add :tracking_number, :string
      add :shipped_at, :utc_datetime
      add :delivered_at, :utc_datetime
      add :released_at, :utc_datetime

      # Recipient info
      add :recipient_name, :string, null: false
      add :recipient_email, :string, null: false
      add :recipient_phone, :string

      # Snapshot of totals at time of order (in case quote changes)
      add :total_cents, :integer, null: false
      add :currency, :string, null: false, default: "CZK"

      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:orders, [:number])
    create index(:orders, [:buyer_id])
    create index(:orders, [:shop_id])
    create index(:orders, [:status])
    create index(:orders, [:stripe_payment_intent_id])
  end
end
