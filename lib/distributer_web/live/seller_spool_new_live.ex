defmodule DistributerWeb.SellerSpoolNewLive do
  use DistributerWeb, :live_view

  alias Distributer.{Shops, Inventory}

  @impl true
  def mount(_params, _session, socket) do
    case Shops.get_shop_for_user(socket.assigns.current_user.id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Create your shop before adding spools.")
         |> redirect(to: ~p"/sellers/onboarding")}

      shop ->
        {:ok,
         socket
         |> assign(:shop, shop)
         |> assign(:materials, Inventory.list_materials())}
    end
  end

  @impl true
  def handle_event("save", params, socket) do
    grams_total = parse_int(params["grams_total"], 1000)

    attrs = %{
      "shop_id" => socket.assigns.shop.id,
      "material_id" => params["material_id"],
      "color_name" => params["color_name"],
      "color_hex" => params["color_hex"],
      "batch_code" => params["batch_code"],
      "grams_total" => grams_total,
      "grams_remaining" => grams_total,
      "sell_price_per_gram_cents" => parse_int(params["sell_price_per_gram_cents"], 150),
      "purchase_price_cents" => parse_int(params["purchase_price_cents"], nil),
      "is_active" => true
    }

    case Inventory.create_spool(attrs) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Spool added.") |> redirect(to: ~p"/sellers")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add spool: #{inspect(changeset.errors)}")}
    end
  end

  defp parse_int(value, default) do
    case value |> to_string() |> String.trim() |> Integer.parse() do
      {n, ""} when n >= 0 -> n
      _ -> default
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto py-8 px-4">
      <.header>Add a material spool</.header>

      <form phx-submit="save" class="mt-6 space-y-4">
        <div>
          <label class="block text-sm font-medium">Material</label>
          <select name="material_id" required class="mt-1 w-full rounded border-gray-300">
            <option :for={m <- @materials} value={m.id}>
              <%= m.type %> — <%= m.brand %> <%= m.name %>
            </option>
          </select>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="block text-sm font-medium">Color name</label>
            <input name="color_name" required placeholder="Galaxy Black" class="mt-1 w-full rounded border-gray-300" />
          </div>
          <div>
            <label class="block text-sm font-medium">Hex (6 chars)</label>
            <input name="color_hex" placeholder="#1a1a1a" class="mt-1 w-full rounded border-gray-300" />
          </div>
        </div>
        <div>
          <label class="block text-sm font-medium">Batch / lot</label>
          <input name="batch_code" placeholder="PRUS-2026-04" class="mt-1 w-full rounded border-gray-300" />
        </div>
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="block text-sm font-medium">Grams total</label>
            <input type="number" name="grams_total" value="1000" required min="1" class="mt-1 w-full rounded border-gray-300" />
          </div>
          <div>
            <label class="block text-sm font-medium">Sell price (haléře / g)</label>
            <input type="number" name="sell_price_per_gram_cents" value="150" required min="0" class="mt-1 w-full rounded border-gray-300" />
            <p class="text-xs text-gray-500">150 haléře = 1.50 CZK/g</p>
          </div>
        </div>
        <div>
          <label class="block text-sm font-medium">Purchase price (haléře, optional)</label>
          <input type="number" name="purchase_price_cents" min="0" class="mt-1 w-full rounded border-gray-300" />
        </div>
        <button class="w-full rounded bg-zinc-900 text-white px-4 py-2 font-semibold">Add spool</button>
      </form>
    </div>
    """
  end
end
