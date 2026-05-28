defmodule Distributer.OrdersTest do
  use Distributer.DataCase, async: true

  import Distributer.Fixtures

  alias Distributer.{Inventory, Orders}
  alias Distributer.Orders.{PrintJob, Quote}

  defp pay_attrs(n \\ 1),
    do: %{stripe_payment_intent_id: "pi_#{n}", stripe_charge_id: "ch_#{n}"}

  defp jobs_count(order_id),
    do: Repo.aggregate(from(j in PrintJob, where: j.order_id == ^order_id), :count)

  describe "place_order/3" do
    test "creates a quoted order from a sliced quote and converts the quote" do
      {order, ctx} = order_fixture()

      assert order.status == "quoted"
      assert order.total_cents == ctx.quote.total_cents
      assert order.shop_id == ctx.shop.id
      assert Repo.get!(Quote, ctx.quote.id).status == "converted"
    end

    test "refuses a quote that hasn't been sliced" do
      ctx = sliced_quote_fixture()
      pending = %{ctx.quote | status: "pending"}
      buyer = user_fixture()

      assert {:error, :quote_not_sliced} =
               Orders.place_order(pending, buyer, %{
                 "recipient_name" => "X",
                 "recipient_email" => buyer.email
               })
    end
  end

  describe "mark_paid/2 idempotency and state" do
    test "transitions quoted -> paid and creates exactly one print job" do
      {order, _ctx} = order_fixture()

      assert {:ok, paid} = Orders.mark_paid(order, pay_attrs())
      assert paid.status == "paid"
      assert paid.paid_at
      assert jobs_count(order.id) == 1
    end

    test "is idempotent — a replayed webhook makes no second job" do
      {order, _ctx} = order_fixture()
      {:ok, paid} = Orders.mark_paid(order, pay_attrs(1))

      assert {:ok, again} = Orders.mark_paid(paid, pay_attrs(2))
      assert again.status == "paid"
      assert jobs_count(order.id) == 1
    end

    test "rejects payment from a non-quoted state" do
      {order, ctx} = order_fixture()
      {:ok, paid} = Orders.mark_paid(order, pay_attrs())
      {:ok, accepted} = Orders.accept_order(paid, ctx.shop.id)

      assert {:error, :invalid_state} = Orders.mark_paid(accepted, pay_attrs())
    end
  end

  describe "seller transitions require ownership and the right source state" do
    setup do
      {order, ctx} = order_fixture()
      {:ok, paid} = Orders.mark_paid(order, %{stripe_payment_intent_id: "pi", stripe_charge_id: "ch"})
      %{order: paid, ctx: ctx}
    end

    test "accept_order: wrong shop is unauthorized", %{order: order} do
      assert {:error, :unauthorized} = Orders.accept_order(order, Ecto.UUID.generate())
    end

    test "accept_order: only from paid", %{order: order, ctx: ctx} do
      {:ok, accepted} = Orders.accept_order(order, ctx.shop.id)
      assert {:error, :invalid_state} = Orders.accept_order(accepted, ctx.shop.id)
    end

    test "start_print: wrong shop is unauthorized", %{order: order} do
      assert {:error, :unauthorized} = Orders.start_print(order, Ecto.UUID.generate())
    end

    test "complete_print: rejects non-printing orders", %{order: order, ctx: ctx} do
      assert {:error, :invalid_state} = Orders.complete_print(order, ctx.shop.id, 10)
    end

    test "mark_shipped: rejects non-printed orders", %{order: order, ctx: ctx} do
      assert {:error, :invalid_state} =
               Orders.mark_shipped(order, ctx.shop.id, %{
                 packeta_label_id: "L",
                 tracking_number: "T"
               })
    end
  end

  describe "full happy-path lifecycle" do
    test "quoted -> ... -> released, decrementing the spool exactly once" do
      {order, ctx} = order_fixture()
      shop_id = ctx.shop.id
      buyer_id = ctx.buyer.id

      {:ok, paid} = Orders.mark_paid(order, pay_attrs())
      {:ok, accepted} = Orders.accept_order(paid, shop_id)
      assert accepted.status == "accepted"

      {:ok, printing} = Orders.start_print(accepted, shop_id)
      assert printing.status == "printing"

      {:ok, printed} = Orders.complete_print(printing, shop_id, 20)
      assert printed.status == "printed"
      assert Inventory.get_spool!(ctx.spool.id).grams_remaining == 980

      {:ok, shipped} =
        Orders.mark_shipped(printed, shop_id, %{packeta_label_id: "L1", tracking_number: "T1"})

      assert shipped.status == "shipped"
      assert shipped.tracking_number == "T1"

      {:ok, delivered} = Orders.mark_delivered(shipped, buyer_id)
      assert delivered.status == "delivered"

      {:ok, released} = Orders.release_escrow(delivered)
      assert released.status == "released"
    end

    test "mark_delivered rejects a non-buyer" do
      {order, ctx} = order_fixture()
      {:ok, paid} = Orders.mark_paid(order, pay_attrs())
      {:ok, accepted} = Orders.accept_order(paid, ctx.shop.id)
      {:ok, printing} = Orders.start_print(accepted, ctx.shop.id)
      {:ok, printed} = Orders.complete_print(printing, ctx.shop.id, 20)

      {:ok, shipped} =
        Orders.mark_shipped(printed, ctx.shop.id, %{packeta_label_id: "L", tracking_number: "T"})

      assert {:error, :unauthorized} = Orders.mark_delivered(shipped, Ecto.UUID.generate())
    end
  end

  describe "complete_print stock safety" do
    test "rolls the whole completion back when the spool can't cover it" do
      shop = shop_fixture()
      spool = spool_fixture(shop, nil, %{"grams_total" => 10, "grams_remaining" => 10})
      {order, ctx} = order_fixture(shop: shop, spool: spool)

      {:ok, paid} = Orders.mark_paid(order, pay_attrs())
      {:ok, accepted} = Orders.accept_order(paid, ctx.shop.id)
      {:ok, printing} = Orders.start_print(accepted, ctx.shop.id)

      assert {:error, :insufficient_stock} = Orders.complete_print(printing, ctx.shop.id, 50)

      # Order stays printing and the spool is untouched.
      assert Orders.get_order!(order.id).status == "printing"
      assert Inventory.get_spool!(spool.id).grams_remaining == 10
    end
  end

  describe "release_escrow/1" do
    test "only releases delivered orders" do
      {order, _ctx} = order_fixture()
      assert {:error, :not_delivered} = Orders.release_escrow(order)
    end
  end
end
