defmodule Distributer.Orders do
  @moduledoc """
  Quotes, orders, and print jobs.

  Lifecycle:
    1. Buyer creates a quote (Orders.create_quote) → Oban enqueues
       SliceQuoteWorker → slicer runs → quote moves to `sliced` with
       grams/minutes/price filled in.
    2. Buyer picks a sliced quote and places order
       (Orders.place_order) → order in `quoted` status with Stripe
       PaymentIntent pending.
    3. Stripe webhook confirms payment → Orders.mark_paid → seller
       notified, print_job created, gcode unlocked.
    4. Seller accepts/prints/ships → state transitions, spool consumed.
    5. Delivered (via Packeta webhook or manual confirm) →
       escrow releases T+72h or on buyer confirm.
  """

  import Ecto.Query, warn: false
  alias Distributer.Repo
  alias Distributer.Orders.{Quote, Order, PrintJob}
  alias Distributer.{Catalog, Inventory, Pricing, Shops, Slicing}

  # ----- Quotes -----

  def get_quote!(id) do
    Repo.get!(Quote, id)
    |> Repo.preload([
      :upload,
      :canonical_profile,
      shop_printer: [:printer_model, :shop],
      material_spool: [:material]
    ])
  end

  @doc """
  Initiate a quote. The slicer hasn't run yet — the row is inserted with
  status `pending` and a SliceQuoteWorker is enqueued. The LiveView
  subscribes to PubSub and re-renders when the slicer completes.
  """
  def create_quote(attrs) do
    with {:ok, quote} <- %Quote{} |> Quote.changeset(attrs) |> Repo.insert() do
      %{quote_id: quote.id}
      |> Distributer.Orders.SliceQuoteWorker.new()
      |> Oban.insert()

      {:ok, quote}
    end
  end

  def update_quote_with_slice_result(%Quote{} = quote, slice_result, shipping_cents \\ 0) do
    shop_printer = Catalog.get_shop_printer!(quote.shop_printer_id)
    spool = Inventory.get_spool!(quote.material_spool_id)
    shop = Shops.get_shop!(shop_printer.shop_id)

    breakdown =
      Pricing.quote_price(%{
        grams: slice_result.grams,
        minutes: slice_result.print_minutes,
        quantity: quote.quantity,
        shop: shop,
        shop_printer: shop_printer,
        spool: spool,
        shipping_cents: shipping_cents
      })

    quote
    |> Quote.changeset(
      Map.merge(breakdown, %{
        estimated_grams: slice_result.grams && Decimal.from_float(slice_result.grams),
        estimated_print_minutes: slice_result.print_minutes,
        slicer_log: String.slice(slice_result.log || "", 0, 10_000),
        gcode_storage_key: slice_result.gcode_storage_key,
        status: "sliced",
        expires_at: DateTime.utc_now() |> DateTime.add(60 * 60 * 24, :second)
      })
    )
    |> Repo.update()
  end

  def mark_quote_failed(%Quote{} = quote, reason) do
    quote
    |> Quote.changeset(%{status: "failed", error: inspect(reason)})
    |> Repo.update()
  end

  # ----- Orders -----

  def get_order!(id) do
    Repo.get!(Order, id)
    |> Repo.preload([:shop, :buyer, :print_jobs, quote: [:material_spool, :shop_printer]])
  end

  def list_orders_for_buyer(buyer_id) do
    Repo.all(
      from o in Order,
        where: o.buyer_id == ^buyer_id,
        order_by: [desc: o.inserted_at],
        preload: [:shop]
    )
  end

  def list_orders_for_shop(shop_id) do
    Repo.all(
      from o in Order,
        where: o.shop_id == ^shop_id,
        order_by: [desc: o.inserted_at],
        preload: [:buyer, quote: [:material_spool, :shop_printer]]
    )
  end

  @doc """
  Create an order from a sliced quote.
  """
  def place_order(%Quote{status: "sliced"} = quote, buyer, params) do
    shop_printer = Catalog.get_shop_printer!(quote.shop_printer_id)
    shop_id = shop_printer.shop_id

    attrs = %{
      number: generate_order_number(),
      quote_id: quote.id,
      buyer_id: buyer.id,
      shop_id: shop_id,
      total_cents: quote.total_cents,
      currency: quote.currency,
      shipping_method: params["shipping_method"] || "packeta_pickup",
      packeta_point_id: params["packeta_point_id"],
      recipient_name: params["recipient_name"],
      recipient_email: params["recipient_email"] || buyer.email,
      recipient_phone: params["recipient_phone"],
      notes: params["notes"]
    }

    Repo.transaction(fn ->
      order =
        case %Order{} |> Order.create_changeset(attrs) |> Repo.insert() do
          {:ok, order} -> order
          {:error, changeset} -> Repo.rollback(changeset)
        end

      quote
      |> Quote.changeset(%{status: "converted"})
      |> Repo.update!()

      order
    end)
  end

  def place_order(_quote, _buyer, _params), do: {:error, :quote_not_sliced}

  @doc """
  Mark an order paid, from a confirmed Stripe payment or the dev stub.

  Idempotent and single-shot: a replayed/duplicate webhook for an order that
  is already paid returns `{:ok, order}` without creating a second print job,
  and only one print job is ever created per order. Only transitions from
  `quoted`; any other source status returns `{:error, :invalid_state}`.
  """
  def mark_paid(%Order{status: "paid"} = order, _attrs), do: {:ok, order}

  def mark_paid(%Order{status: "quoted"} = order, %{
        stripe_payment_intent_id: pi,
        stripe_charge_id: charge
      }) do
    Repo.transaction(fn ->
      updated =
        order
        |> Order.state_changeset(%{
          status: "paid",
          stripe_payment_intent_id: pi,
          stripe_charge_id: charge,
          paid_at: DateTime.utc_now()
        })
        |> Repo.update!()

      # One print job per order — guard against duplicate webhook deliveries.
      unless Repo.exists?(from j in PrintJob, where: j.order_id == ^order.id) do
        quote = get_quote!(order.quote_id)

        %PrintJob{}
        |> PrintJob.changeset(%{
          order_id: order.id,
          shop_printer_id: quote.shop_printer_id,
          material_spool_id: quote.material_spool_id,
          gcode_storage_key: quote.gcode_storage_key,
          status: "queued"
        })
        |> Repo.insert!()
      end

      Phoenix.PubSub.broadcast(
        Distributer.PubSub,
        "shop:#{order.shop_id}:orders",
        {:order_paid, updated.id}
      )

      updated
    end)
  end

  def mark_paid(%Order{}, _attrs), do: {:error, :invalid_state}

  @doc "Seller accepts a paid order. `shop_id` is the acting seller's shop."
  def accept_order(%Order{} = order, shop_id) do
    with :ok <- authorize_shop(order, shop_id),
         :ok <- require_status(order, "paid") do
      order
      |> Order.state_changeset(%{status: "accepted"})
      |> Repo.update()
    end
  end

  @doc "Seller marks an accepted/paid order as printing. `shop_id` is the acting seller's shop."
  def start_print(%Order{} = order, shop_id) do
    with :ok <- authorize_shop(order, shop_id),
         :ok <- require_status(order, ~w(accepted paid)) do
      Repo.transaction(fn ->
        updated =
          order
          |> Order.state_changeset(%{status: "printing"})
          |> Repo.update!()

        job =
          Repo.one!(
            from j in PrintJob,
              where: j.order_id == ^order.id,
              order_by: [desc: j.inserted_at],
              limit: 1
          )

        job
        |> PrintJob.changeset(%{status: "printing", started_at: DateTime.utc_now()})
        |> Repo.update!()

        updated
      end)
    end
  end

  @doc """
  Seller marks a printing order complete, recording grams of filament used.
  Atomically decrements the spool; if stock is insufficient the whole
  transaction is rolled back and `{:error, :insufficient_stock}` is returned.
  """
  def complete_print(%Order{} = order, shop_id, grams_used) do
    with :ok <- authorize_shop(order, shop_id),
         :ok <- require_status(order, "printing") do
      Repo.transaction(fn ->
        job =
          Repo.one!(
            from j in PrintJob,
              where: j.order_id == ^order.id,
              order_by: [desc: j.inserted_at],
              limit: 1
          )

        job
        |> PrintJob.changeset(%{
          status: "succeeded",
          finished_at: DateTime.utc_now(),
          grams_used: Decimal.new("#{grams_used}")
        })
        |> Repo.update!()

        spool = Inventory.get_spool!(job.material_spool_id)

        # Roll the whole completion back (incl. the job update above) if the
        # spool can't cover the filament used, so we never oversell stock.
        case Inventory.consume(spool, grams_used, job.id, "auto-decrement on print completion") do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end

        order
        |> Order.state_changeset(%{status: "printed"})
        |> Repo.update!()
      end)
    end
  end

  @doc "Seller marks a printed order shipped. `shop_id` is the acting seller's shop."
  def mark_shipped(%Order{} = order, shop_id, %{packeta_label_id: label, tracking_number: tracking}) do
    with :ok <- authorize_shop(order, shop_id),
         :ok <- require_status(order, "printed") do
      order
      |> Order.state_changeset(%{
        status: "shipped",
        packeta_label_id: label,
        tracking_number: tracking,
        shipped_at: DateTime.utc_now()
      })
      |> Repo.update()
    end
  end

  @doc "Buyer confirms delivery of a shipped order. `buyer_id` is the acting user."
  def mark_delivered(%Order{} = order, buyer_id) do
    with :ok <- authorize_buyer(order, buyer_id),
         :ok <- require_status(order, "shipped") do
      order
      |> Order.state_changeset(%{status: "delivered", delivered_at: DateTime.utc_now()})
      |> Repo.update()
    end
  end

  def release_escrow(%Order{status: "delivered"} = order) do
    order
    |> Order.state_changeset(%{status: "released", released_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def release_escrow(_), do: {:error, :not_delivered}

  # ----- helpers -----

  defp authorize_shop(%Order{shop_id: shop_id}, shop_id), do: :ok
  defp authorize_shop(%Order{}, _shop_id), do: {:error, :unauthorized}

  defp authorize_buyer(%Order{buyer_id: buyer_id}, buyer_id), do: :ok
  defp authorize_buyer(%Order{}, _buyer_id), do: {:error, :unauthorized}

  defp require_status(%Order{status: status}, expected) when is_binary(expected) do
    if status == expected, do: :ok, else: {:error, :invalid_state}
  end

  defp require_status(%Order{status: status}, expected) when is_list(expected) do
    if status in expected, do: :ok, else: {:error, :invalid_state}
  end

  defp generate_order_number do
    year = Date.utc_today().year
    # 10 hex chars of CSPRNG entropy; collisions are negligible and the
    # `unique_constraint(:number)` is the backstop if one ever occurs.
    suffix = :crypto.strong_rand_bytes(5) |> Base.encode16() |> binary_part(0, 10)
    "DST-#{year}-#{suffix}"
  end
end
