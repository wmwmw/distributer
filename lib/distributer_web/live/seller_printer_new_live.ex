defmodule DistributerWeb.SellerPrinterNewLive do
  use DistributerWeb, :live_view

  alias Distributer.{Shops, Catalog}

  @impl true
  def mount(_params, _session, socket) do
    shop = Shops.get_shop_for_user(socket.assigns.current_user.id)
    {:ok,
     socket
     |> assign(:shop, shop)
     |> assign(:printer_models, Catalog.list_printer_models())}
  end

  @impl true
  def handle_event("save", params, socket) do
    attrs = %{
      "shop_id" => socket.assigns.shop.id,
      "printer_model_id" => params["printer_model_id"],
      "nickname" => params["nickname"],
      "hourly_rate_cents" => String.to_integer(params["hourly_rate_cents"] || "5000"),
      "is_active" => true
    }

    case Catalog.create_shop_printer(attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Printer added.")
         |> redirect(to: ~p"/sellers")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add printer.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto py-8 px-4">
      <.header>Add a printer</.header>

      <form phx-submit="save" class="mt-6 space-y-4">
        <div>
          <label class="block text-sm font-medium">Printer model</label>
          <select name="printer_model_id" required class="mt-1 w-full rounded border-gray-300">
            <option :for={pm <- @printer_models} value={pm.id}>
              <%= pm.brand %> <%= pm.model %> (<%= pm.bed_x_mm %>×<%= pm.bed_y_mm %>×<%= pm.bed_z_mm %>)
            </option>
          </select>
        </div>
        <div>
          <label class="block text-sm font-medium">Nickname (optional)</label>
          <input name="nickname" placeholder="e.g. 'Garage MK4'" class="mt-1 w-full rounded border-gray-300" />
        </div>
        <div>
          <label class="block text-sm font-medium">Hourly rate (haléře)</label>
          <input type="number" name="hourly_rate_cents" value="5000" min="0" required class="mt-1 w-full rounded border-gray-300" />
          <p class="text-xs text-gray-500 mt-1">5000 haléře = 50 CZK/hour</p>
        </div>
        <button class="w-full rounded bg-zinc-900 text-white px-4 py-2 font-semibold">Add printer</button>
      </form>
    </div>
    """
  end
end
