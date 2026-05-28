defmodule DistributerWeb.SellerDashboardLive do
  use DistributerWeb, :live_view

  alias Distributer.{Shops, Catalog, Inventory, Orders}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    shop = Shops.get_shop_for_user(user.id)

    if shop do
      Phoenix.PubSub.subscribe(Distributer.PubSub, "shop:#{shop.id}:orders")

      {:ok,
       socket
       |> assign(:shop, shop)
       |> assign(:printers, Catalog.list_shop_printers(shop.id))
       |> assign(:spools, Inventory.list_spools(shop.id))
       |> assign(:orders, Orders.list_orders_for_shop(shop.id))}
    else
      {:ok, redirect(socket, to: ~p"/sellers/onboarding")}
    end
  end

  @impl true
  def handle_event("toggle-active", _params, %{assigns: %{shop: shop}} = socket) do
    {:ok, updated} =
      if shop.is_active, do: Shops.deactivate_shop(shop), else: Shops.activate_shop(shop)

    {:noreply,
     socket
     |> assign(:shop, updated)
     |> put_flash(:info, if(updated.is_active, do: "Shop is now live.", else: "Shop deactivated."))}
  end

  @impl true
  def handle_event("accept-order", %{"id" => id}, socket) do
    shop = socket.assigns.shop
    order = Orders.get_order!(id)

    case Orders.accept_order(order, shop.id) do
      {:ok, _} ->
        {:noreply, assign(socket, :orders, Orders.list_orders_for_shop(shop.id))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not accept order: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:order_paid, _id}, socket) do
    {:noreply, assign(socket, :orders, Orders.list_orders_for_shop(socket.assigns.shop.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4 space-y-8">
      <header class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold"><%= @shop.name %></h1>
          <p class="text-sm text-gray-600">/<%= @shop.slug %> · markup <%= @shop.markup_percent %>%</p>
        </div>
        <div class="flex items-center gap-3">
          <span class={"text-xs px-2 py-1 rounded #{if @shop.is_active, do: "bg-emerald-100 text-emerald-800", else: "bg-gray-100 text-gray-600"}"}>
            <%= if @shop.is_active, do: "Live", else: "Inactive" %>
          </span>
          <button phx-click="toggle-active" class="rounded border px-3 py-1 text-sm">
            <%= if @shop.is_active, do: "Deactivate", else: "Activate" %>
          </button>
          <.link navigate={~p"/sellers/shop/edit"} class="rounded border px-3 py-1 text-sm">Edit shop</.link>
        </div>
      </header>

      <section>
        <div class="flex items-center justify-between mb-3">
          <h2 class="font-semibold">Printers</h2>
          <.link navigate={~p"/sellers/printers/new"} class="text-sm underline">Add printer</.link>
        </div>
        <div :if={@printers == []} class="text-gray-500 text-sm italic">
          Add a printer to activate your shop.
        </div>
        <ul class="space-y-2">
          <li :for={p <- @printers} class="border rounded p-3 flex items-center justify-between">
            <div>
              <span class="font-medium"><%= p.printer_model.brand %> <%= p.printer_model.model %></span>
              <span :if={p.nickname} class="text-gray-500 ml-2">(<%= p.nickname %>)</span>
              <div class="text-xs text-gray-500">
                <%= Distributer.Pricing.format(p.hourly_rate_cents, @shop.default_currency) %>/h
              </div>
            </div>
            <span class={"text-xs px-2 py-1 rounded #{if p.is_active, do: "bg-emerald-100 text-emerald-800", else: "bg-gray-100"}"}>
              <%= if p.is_active, do: "active", else: "off" %>
            </span>
          </li>
        </ul>
      </section>

      <section>
        <div class="flex items-center justify-between mb-3">
          <h2 class="font-semibold">Material spools</h2>
          <.link navigate={~p"/sellers/spools/new"} class="text-sm underline">Add spool</.link>
        </div>
        <div :if={@spools == []} class="text-gray-500 text-sm italic">
          Add at least one spool to start receiving orders.
        </div>
        <ul class="space-y-2">
          <li :for={s <- @spools} class="border rounded p-3 flex items-center justify-between">
            <div>
              <span class="font-medium"><%= s.material.type %> <%= s.material.brand %> <%= s.material.name %></span>
              <span class="text-gray-500 ml-2">(<%= s.color_name %>)</span>
              <div class="text-xs text-gray-500">
                <%= s.grams_remaining %>g / <%= s.grams_total %>g remaining · <%= s.sell_price_per_gram_cents %> haléře/g
              </div>
            </div>
          </li>
        </ul>
      </section>

      <section>
        <h2 class="font-semibold mb-3">Orders</h2>
        <div :if={@orders == []} class="text-gray-500 text-sm italic">No orders yet.</div>
        <table :if={@orders != []} class="w-full text-sm">
          <thead class="text-left text-gray-500 border-b">
            <tr><th class="py-2">Number</th><th>Status</th><th>Total</th><th>Buyer</th><th></th></tr>
          </thead>
          <tbody>
            <tr :for={o <- @orders} class="border-b">
              <td class="py-2"><%= o.number %></td>
              <td><%= o.status %></td>
              <td><%= Distributer.Pricing.format(o.total_cents, o.currency) %></td>
              <td><%= o.buyer.email %></td>
              <td>
                <button :if={o.status == "paid"} phx-click="accept-order" phx-value-id={o.id} class="text-blue-600 underline">
                  Accept
                </button>
                <.link navigate={~p"/orders/#{o.id}"} class="text-blue-600 underline ml-2">View</.link>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
    """
  end
end
