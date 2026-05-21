defmodule DistributerWeb.ShopShowLive do
  use DistributerWeb, :live_view

  alias Distributer.{Shops, Catalog, Inventory}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Shops.get_shop_by_slug(slug) do
      nil ->
        {:ok, redirect(socket, to: ~p"/")}

      shop ->
        {:ok,
         socket
         |> assign(:shop, shop)
         |> assign(:printers, Catalog.list_shop_printers(shop.id))
         |> assign(:spools, Inventory.list_active_spools_for_shop(shop.id))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-8 px-4">
      <header>
        <h1 class="text-3xl font-bold"><%= @shop.name %></h1>
        <p class="mt-2 text-gray-600"><%= @shop.tagline %></p>
        <p :if={@shop.description} class="mt-4 text-sm whitespace-pre-line"><%= @shop.description %></p>
      </header>

      <section class="mt-8">
        <h2 class="font-semibold mb-3">Printers</h2>
        <ul class="grid grid-cols-2 gap-3">
          <li :for={p <- @printers} class="border rounded p-3 text-sm">
            <span class="font-medium"><%= p.printer_model.brand %> <%= p.printer_model.model %></span>
            <div class="text-xs text-gray-500">
              Bed: <%= p.printer_model.bed_x_mm %>×<%= p.printer_model.bed_y_mm %>×<%= p.printer_model.bed_z_mm %> mm
            </div>
            <div class="text-xs text-gray-500">
              <%= Distributer.Pricing.format(p.hourly_rate_cents, @shop.default_currency) %>/h
            </div>
          </li>
        </ul>
      </section>

      <section class="mt-8">
        <h2 class="font-semibold mb-3">Materials in stock</h2>
        <ul class="grid grid-cols-1 md:grid-cols-2 gap-3">
          <li :for={s <- @spools} class="border rounded p-3 text-sm">
            <div class="flex items-center gap-2">
              <div :if={s.color_hex} class="w-4 h-4 rounded-full border" style={"background-color: #{s.color_hex}"}></div>
              <span class="font-medium"><%= s.material.type %> <%= s.material.brand %> <%= s.material.name %></span>
            </div>
            <div class="text-xs text-gray-500 mt-1">
              <%= s.color_name %> · <%= s.grams_remaining %>g remaining ·
              <%= s.sell_price_per_gram_cents %> haléře/g
            </div>
          </li>
        </ul>
      </section>

      <div class="mt-8">
        <.link navigate={~p"/upload"} class="rounded bg-zinc-900 text-white px-5 py-2 text-sm font-semibold">
          Print something here
        </.link>
      </div>
    </div>
    """
  end
end
