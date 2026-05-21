defmodule DistributerWeb.HomeLive do
  use DistributerWeb, :live_view

  alias Distributer.Shops

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, shops: Shops.list_active_shops())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto py-12 px-4">
      <header class="mb-12 text-center">
        <h1 class="text-4xl font-bold tracking-tight">
          Distributer
        </h1>
        <p class="mt-3 text-lg text-gray-600">
          Community-driven 3D printing marketplace. Upload a model, pick a shop, get it printed and shipped.
        </p>
        <div class="mt-6 flex justify-center gap-3">
          <.link navigate={~p"/upload"} class="rounded bg-zinc-900 text-white px-5 py-2 text-sm font-semibold hover:bg-zinc-700">
            Upload a model
          </.link>
          <.link navigate={~p"/sellers/onboarding"} class="rounded border px-5 py-2 text-sm font-semibold hover:bg-zinc-50">
            Open a shop
          </.link>
        </div>
      </header>

      <section>
        <h2 class="text-xl font-semibold mb-4">Active shops</h2>
        <div :if={@shops == []} class="text-gray-500 italic">
          No shops are active yet. Be the first — <.link navigate={~p"/sellers/onboarding"} class="underline">open a shop</.link>.
        </div>
        <ul class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <li :for={shop <- @shops} class="border rounded p-4 hover:shadow-sm">
            <.link navigate={~p"/shops/#{shop.slug}"} class="block">
              <h3 class="font-semibold"><%= shop.name %></h3>
              <p class="text-sm text-gray-600 mt-1"><%= shop.tagline || "—" %></p>
              <p class="text-xs text-gray-400 mt-2"><%= shop.country %></p>
            </.link>
          </li>
        </ul>
      </section>
    </div>
    """
  end
end
