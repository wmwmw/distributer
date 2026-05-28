defmodule DistributerWeb.OrderShowLive do
  use DistributerWeb, :live_view

  alias Distributer.{Orders, Payments, Shipping, Shops}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    order = Orders.get_order!(id)
    current_user = socket.assigns.current_user
    seller_shop = Shops.get_shop_for_user(current_user.id)

    is_buyer? = order.buyer_id == current_user.id
    is_seller? = seller_shop && seller_shop.id == order.shop_id

    if is_buyer? or is_seller? do
      {:ok,
       socket
       |> assign(:order, order)
       |> assign(:seller_shop, seller_shop)
       |> assign(:is_buyer?, is_buyer?)
       |> assign(:is_seller?, !!is_seller?)}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event("stub-pay", _params, %{assigns: %{order: order, is_buyer?: true}} = socket) do
    {:ok, _} = Payments.stub_mark_paid(order)
    {:noreply, reload_order(socket)}
  end

  @impl true
  def handle_event("start-print", _params, %{assigns: %{is_seller?: true}} = socket) do
    %{order: order, seller_shop: shop} = socket.assigns
    handle_result(Orders.start_print(order, shop.id), socket)
  end

  @impl true
  def handle_event(
        "complete-print",
        %{"grams" => g},
        %{assigns: %{is_seller?: true}} = socket
      ) do
    %{order: order, seller_shop: shop} = socket.assigns

    case parse_grams(g) do
      {:ok, grams} -> handle_result(Orders.complete_print(order, shop.id, grams), socket)
      :error -> {:noreply, put_flash(socket, :error, "Enter a valid number of grams.")}
    end
  end

  @impl true
  def handle_event("ship", _params, %{assigns: %{is_seller?: true}} = socket) do
    %{order: order, seller_shop: shop} = socket.assigns

    case Shipping.create_packet(order) do
      {:ok, %{label_id: lid, tracking: tn}} ->
        handle_result(
          Orders.mark_shipped(order, shop.id, %{packeta_label_id: lid, tracking_number: tn}),
          socket
        )

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Packeta failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("mark-delivered", _params, %{assigns: %{is_buyer?: true}} = socket) do
    %{order: order, current_user: user} = socket.assigns
    handle_result(Orders.mark_delivered(order, user.id), socket)
  end

  # Any action that doesn't match an authorized clause above is rejected.
  @impl true
  def handle_event(_event, _params, socket) do
    {:noreply, put_flash(socket, :error, "You are not allowed to do that.")}
  end

  defp handle_result({:ok, _}, socket), do: {:noreply, reload_order(socket)}

  defp handle_result({:error, reason}, socket) do
    {:noreply, put_flash(socket, :error, "Action failed: #{inspect(reason)}")}
  end

  defp reload_order(socket) do
    assign(socket, :order, Orders.get_order!(socket.assigns.order.id))
  end

  defp parse_grams(value) do
    case Integer.parse(String.trim(value)) do
      {grams, ""} when grams >= 0 -> {:ok, grams}
      _ -> :error
    end
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

        <button :if={@is_buyer? and @order.status == "quoted"}
          phx-click="stub-pay" class="rounded bg-zinc-900 text-white px-4 py-2 text-sm">
          Pay (stub — real Stripe in prod)
        </button>

        <button :if={@is_seller? and @order.status in ~w(paid accepted)}
          phx-click="start-print" class="rounded bg-blue-600 text-white px-4 py-2 text-sm">
          Mark printing
        </button>

        <form :if={@is_seller? and @order.status == "printing"} phx-submit="complete-print" class="flex gap-2">
          <input name="grams" type="number" placeholder="grams used" required class="rounded border-gray-300" />
          <button class="rounded bg-emerald-600 text-white px-4 py-2 text-sm">Mark printed</button>
        </form>

        <button :if={@is_seller? and @order.status == "printed"}
          phx-click="ship" class="rounded bg-indigo-600 text-white px-4 py-2 text-sm">
          Generate Packeta label & ship
        </button>

        <button :if={@is_buyer? and @order.status == "shipped"}
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
