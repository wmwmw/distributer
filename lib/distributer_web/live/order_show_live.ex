defmodule DistributerWeb.OrderShowLive do
  use DistributerWeb, :live_view

  alias Distributer.{Orders, Payments, Shipping, Shops}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    order = Orders.get_order!(id)
    current_user = socket.assigns.current_user

    if order.buyer_id == current_user.id or
         order.shop_id == (Shops.get_shop_for_user(current_user.id) || %{id: nil}).id do
      {:ok, assign(socket, :order, order)}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event("stub-pay", _params, %{assigns: %{order: order}} = socket) do
    {:ok, _} = Payments.stub_mark_paid(order)
    {:noreply, assign(socket, :order, Orders.get_order!(order.id))}
  end

  @impl true
  def handle_event("start-print", _params, %{assigns: %{order: order}} = socket) do
    {:ok, _} = Orders.start_print(order)
    {:noreply, assign(socket, :order, Orders.get_order!(order.id))}
  end

  @impl true
  def handle_event("complete-print", %{"grams" => g}, %{assigns: %{order: order}} = socket) do
    grams = String.to_integer(g)
    {:ok, _} = Orders.complete_print(order, grams)
    {:noreply, assign(socket, :order, Orders.get_order!(order.id))}
  end

  @impl true
  def handle_event("ship", _params, %{assigns: %{order: order}} = socket) do
    case Shipping.create_packet(order) do
      {:ok, %{label_id: lid, tracking: tn}} ->
        {:ok, _} = Orders.mark_shipped(order, %{packeta_label_id: lid, tracking_number: tn})
        {:noreply, assign(socket, :order, Orders.get_order!(order.id))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Packeta failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("mark-delivered", _params, %{assigns: %{order: order}} = socket) do
    {:ok, _} = Orders.mark_delivered(order)
    {:noreply, assign(socket, :order, Orders.get_order!(order.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto py-8 px-4">
      <.header>
        Order <%= @order.number %>
        <:subtitle>Status: <code><%= @order.status %></code></:subtitle>
      </.header>

      <section class="mt-6 border rounded p-4 grid grid-cols-2 gap-4 text-sm">
        <div><dt class="text-gray-500">Total</dt><dd class="font-bold"><%= Distributer.Pricing.format(@order.total_cents, @order.currency) %></dd></div>
        <div><dt class="text-gray-500">Shop</dt><dd><%= @order.shop.name %></dd></div>
        <div><dt class="text-gray-500">Buyer</dt><dd><%= @order.buyer.email %></dd></div>
        <div><dt class="text-gray-500">Ship to</dt><dd><%= @order.recipient_name %></dd></div>
        <div :if={@order.packeta_point_id}>
          <dt class="text-gray-500">Pickup point</dt>
          <dd><%= @order.packeta_point_id %></dd>
        </div>
        <div :if={@order.tracking_number}>
          <dt class="text-gray-500">Tracking</dt>
          <dd><%= @order.tracking_number %></dd>
        </div>
      </section>

      <section class="mt-6 space-y-2">
        <h3 class="font-semibold">Actions</h3>

        <button :if={@order.status == "quoted" and @order.buyer_id == @current_user.id}
          phx-click="stub-pay" class="rounded bg-zinc-900 text-white px-4 py-2 text-sm">
          Pay (stub — real Stripe in prod)
        </button>

        <% seller_shop = Distributer.Shops.get_shop_for_user(@current_user.id) %>
        <% is_seller? = seller_shop && seller_shop.id == @order.shop_id %>

        <button :if={is_seller? and @order.status in ~w(paid accepted)}
          phx-click="start-print" class="rounded bg-blue-600 text-white px-4 py-2 text-sm">
          Mark printing
        </button>

        <form :if={is_seller? and @order.status == "printing"} phx-submit="complete-print" class="flex gap-2">
          <input name="grams" type="number" placeholder="grams used" required class="rounded border-gray-300" />
          <button class="rounded bg-emerald-600 text-white px-4 py-2 text-sm">Mark printed</button>
        </form>

        <button :if={is_seller? and @order.status == "printed"}
          phx-click="ship" class="rounded bg-indigo-600 text-white px-4 py-2 text-sm">
          Generate Packeta label & ship
        </button>

        <button :if={@order.buyer_id == @current_user.id and @order.status == "shipped"}
          phx-click="mark-delivered" class="rounded bg-zinc-900 text-white px-4 py-2 text-sm">
          Confirm delivery
        </button>
      </section>

      <section class="mt-6">
        <h3 class="font-semibold mb-2">Print jobs</h3>
        <ul class="space-y-2 text-sm">
          <li :for={pj <- @order.print_jobs} class="border rounded p-3">
            Status: <%= pj.status %>
            <span :if={pj.started_at} class="ml-2 text-gray-500">started <%= pj.started_at %></span>
            <span :if={pj.finished_at} class="ml-2 text-gray-500">finished <%= pj.finished_at %></span>
            <span :if={pj.grams_used} class="ml-2"><%= pj.grams_used %>g used</span>
          </li>
        </ul>
      </section>
    </div>
    """
  end
end
