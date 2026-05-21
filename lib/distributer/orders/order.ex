defmodule Distributer.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @statuses ~w(quoted paid accepted printing printed shipped delivered released cancelled refunded)

  schema "orders" do
    field :number, :string
    field :status, :string, default: "quoted"

    field :stripe_payment_intent_id, :string
    field :stripe_charge_id, :string
    field :paid_at, :utc_datetime
    field :refunded_at, :utc_datetime

    field :shipping_method, :string, default: "packeta_pickup"
    field :packeta_point_id, :string
    field :packeta_label_id, :string
    field :tracking_number, :string
    field :shipped_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :released_at, :utc_datetime

    field :recipient_name, :string
    field :recipient_email, :string
    field :recipient_phone, :string

    field :total_cents, :integer
    field :currency, :string, default: "CZK"
    field :notes, :string

    belongs_to :quote, Distributer.Orders.Quote
    belongs_to :buyer, Distributer.Accounts.User
    belongs_to :shop, Distributer.Shops.Shop
    has_many :print_jobs, Distributer.Orders.PrintJob

    timestamps()
  end

  def statuses, do: @statuses

  def create_changeset(order, attrs) do
    order
    |> cast(attrs, [
      :number, :quote_id, :buyer_id, :shop_id, :status,
      :shipping_method, :packeta_point_id,
      :recipient_name, :recipient_email, :recipient_phone,
      :total_cents, :currency, :notes
    ])
    |> validate_required([:number, :quote_id, :buyer_id, :shop_id, :total_cents,
                         :recipient_name, :recipient_email])
    |> validate_format(:recipient_email, ~r/@/)
    |> unique_constraint(:number)
  end

  def state_changeset(order, attrs) do
    order
    |> cast(attrs, [
      :status, :stripe_payment_intent_id, :stripe_charge_id, :paid_at, :refunded_at,
      :packeta_label_id, :tracking_number, :shipped_at, :delivered_at, :released_at
    ])
    |> validate_inclusion(:status, @statuses)
  end
end
