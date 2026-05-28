defmodule DistributerWeb.UploadLive do
  use DistributerWeb, :live_view

  alias Distributer.{Slicing, Inventory, Catalog, Orders, AI}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:uploaded_files, [])
     |> assign(:upload, nil)
     |> assign(:intent_text, "")
     |> assign(:capable_shops, [])
     |> assign(:selected_shop_printer_id, nil)
     |> assign(:selected_spool_id, nil)
     |> assign(:quality_tier, "standard")
     |> assign(:infill_percent, 20)
     |> assign(:walls, 3)
     |> assign(:supports, false)
     |> assign(:quantity, 1)
     |> assign(:quote, nil)
     |> assign(:ai_material_picks, [])
     |> allow_upload(:model_file,
       accept: ~w(.stl .3mf),
       max_entries: 1,
       max_file_size: 50_000_000,
       progress: &handle_progress/3,
       auto_upload: true
     )}
  end

  defp handle_progress(:model_file, entry, socket) do
    if entry.done? do
      [{path, upload}] =
        consume_uploaded_entries(socket, :model_file, fn %{path: tmp_path}, entry ->
          bytes = File.read!(tmp_path)

          {:ok, upload} =
            Slicing.create_upload(bytes, %{
              "original_filename" => entry.client_name,
              "user_id" => socket.assigns[:current_user] && socket.assigns.current_user.id
            })

          {:ok, {entry.client_name, upload}}
        end)
        |> Enum.zip([nil])

      capable =
        Catalog.find_capable_shops(
          (upload.bbox_x_mm || Decimal.new("1")) |> Decimal.to_float(),
          (upload.bbox_y_mm || Decimal.new("1")) |> Decimal.to_float(),
          (upload.bbox_z_mm || Decimal.new("1")) |> Decimal.to_float(),
          "PLA"
        )

      {:noreply,
       socket
       |> assign(:upload, upload)
       |> assign(:capable_shops, capable)
       |> put_flash(:info, "Uploaded #{path}. Analyzing geometry...")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set-intent", %{"intent_text" => text}, socket) do
    {:noreply, assign(socket, :intent_text, text)}
  end

  @impl true
  def handle_event("ai-pick", _params, %{assigns: %{upload: upload}} = socket)
      when not is_nil(upload) do
    if socket.assigns.intent_text == "" do
      {:noreply, put_flash(socket, :error, "Describe what you want to print first.")}
    else
      shop_printer =
        Enum.find(
          socket.assigns.capable_shops,
          &(&1.id == socket.assigns.selected_shop_printer_id)
        ) || List.first(socket.assigns.capable_shops)

      socket =
        case shop_printer do
          nil ->
            put_flash(socket, :error, "No capable shops found for this file.")

          sp ->
            spools = Inventory.list_active_spools_for_shop(sp.shop_id)

            with {:ok, qty_pick} <- AI.match_intent_to_quality(socket.assigns.intent_text, upload),
                 {:ok, mat_pick} <- AI.recommend_material(socket.assigns.intent_text, spools, upload) do
              socket
              |> assign(:quality_tier, qty_pick["quality_tier"])
              |> assign(:infill_percent, qty_pick["infill_percent"])
              |> assign(:walls, qty_pick["walls"])
              |> assign(:supports, qty_pick["supports"])
              |> assign(:selected_shop_printer_id, sp.id)
              |> assign(:ai_material_picks, mat_pick["recommendations"] || [])
              |> put_flash(:info, "AI recommendations applied.")
            else
              err ->
                put_flash(socket, :error, "AI call failed: #{inspect(err)}")
            end
        end

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("create-quote", params, socket) do
    %{
      "shop_printer_id" => sp_id,
      "spool_id" => spool_id,
      "quality_tier" => tier,
      "infill_percent" => infill,
      "walls" => walls,
      "quantity" => qty
    } = params

    supports = params["supports"] == "on"

    shop_printer = Catalog.get_shop_printer!(sp_id)
    spool = Inventory.get_spool!(spool_id)
    material_type = spool.material.type

    cond do
      # The spool and printer must belong to the same shop and both be usable;
      # otherwise a crafted request could pair an arbitrary spool with a printer.
      spool.shop_id != shop_printer.shop_id or not shop_printer.is_active or
          not spool.is_active or spool.grams_remaining <= 0 ->
        {:noreply, put_flash(socket, :error, "That printer and spool can't be combined.")}

      is_nil(parse_int(infill)) or is_nil(parse_int(walls)) or is_nil(parse_int(qty)) ->
        {:noreply, put_flash(socket, :error, "Infill, walls and quantity must be numbers.")}

      true ->
        canonical =
          Catalog.find_canonical_profile(shop_printer.printer_model_id, material_type, tier)

        if canonical do
          case Orders.create_quote(%{
                 upload_id: socket.assigns.upload.id,
                 shop_printer_id: sp_id,
                 material_spool_id: spool_id,
                 canonical_profile_id: canonical.id,
                 infill_percent: parse_int(infill),
                 walls: parse_int(walls),
                 supports: supports,
                 quantity: parse_int(qty)
               }) do
            {:ok, quote} ->
              Phoenix.PubSub.subscribe(Distributer.PubSub, "quote:#{quote.id}")

              {:noreply,
               socket
               |> assign(:quote, quote)
               |> put_flash(:info, "Quote queued — slicing in progress.")}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Could not create quote — check your inputs.")}
          end
        else
          {:noreply,
           put_flash(
             socket,
             :error,
             "No canonical profile for #{material_type} #{tier} on this printer."
           )}
        end
    end
  end

  defp parse_int(value) do
    case value |> to_string() |> String.trim() |> Integer.parse() do
      {n, ""} -> n
      _ -> nil
    end
  end

  @impl true
  def handle_info({:quote_sliced, quote_id}, %{assigns: %{quote: %{id: id}}} = socket)
      when id == quote_id do
    {:noreply, assign(socket, :quote, Orders.get_quote!(quote_id))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-8 px-4">
      <.header>
        Upload a model
        <:subtitle>STL or 3MF, up to 50 MB. We'll find shops that can print it.</:subtitle>
      </.header>

      <form id="upload-form" phx-submit="ignore" phx-change="noop" class="mt-6">
        <div class="border-2 border-dashed rounded-lg p-8 text-center">
          <.live_file_input upload={@uploads.model_file} class="cursor-pointer" />
          <p class="text-sm text-gray-500 mt-2">
            Drag a .stl or .3mf file here, or click to browse
          </p>
          <div :for={entry <- @uploads.model_file.entries} class="mt-3">
            <span class="text-sm"><%= entry.client_name %></span>
            <progress class="ml-2" value={entry.progress} max="100"><%= entry.progress %>%</progress>
          </div>
        </div>
      </form>

      <section :if={@upload} class="mt-8 space-y-6">
        <div class="border rounded p-4 bg-zinc-50">
          <h3 class="font-semibold"><%= @upload.original_filename %></h3>
          <dl class="mt-2 text-sm grid grid-cols-3 gap-2">
            <div>
              <dt class="text-gray-500">Size</dt>
              <dd><%= Float.round(@upload.size_bytes / 1024, 1) %> KB</dd>
            </div>
            <div>
              <dt class="text-gray-500">Bounding box</dt>
              <dd>
                <%= if @upload.bbox_x_mm do %>
                  <%= @upload.bbox_x_mm %> × <%= @upload.bbox_y_mm %> × <%= @upload.bbox_z_mm %> mm
                <% else %>
                  analyzing…
                <% end %>
              </dd>
            </div>
            <div>
              <dt class="text-gray-500">Capable shops</dt>
              <dd><%= length(@capable_shops) %></dd>
            </div>
          </dl>
        </div>

        <div class="border rounded p-4">
          <label class="block text-sm font-medium">Describe what you want to print</label>
          <textarea
            phx-blur="set-intent"
            name="intent_text"
            rows="3"
            class="mt-1 w-full rounded border-gray-300"
            placeholder="e.g. 'outdoor wall bracket for a garden hose, needs to handle weight and sunlight'"
          ><%= @intent_text %></textarea>
          <button
            type="button"
            phx-click="ai-pick"
            class="mt-2 rounded bg-blue-600 text-white px-4 py-2 text-sm font-semibold"
          >
            Get AI recommendations
          </button>
        </div>

        <form phx-submit="create-quote" class="border rounded p-4 space-y-4">
          <div>
            <label class="block text-sm font-medium">Shop / printer</label>
            <select name="shop_printer_id" required class="mt-1 w-full rounded border-gray-300">
              <option value="">— choose —</option>
              <option :for={sp <- @capable_shops} value={sp.id} selected={sp.id == @selected_shop_printer_id}>
                <%= sp.shop.name %> — <%= sp.printer_model.brand %> <%= sp.printer_model.model %>
              </option>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium">Material spool</label>
            <select name="spool_id" required class="mt-1 w-full rounded border-gray-300">
              <option value="">— choose a shop first —</option>
            </select>
            <div :if={@ai_material_picks != []} class="mt-2 text-sm text-gray-600">
              AI suggestions:
              <ul class="list-disc list-inside">
                <li :for={pick <- @ai_material_picks}>
                  spool <%= pick["spool_id"] %> — <%= pick["reasoning"] %> (confidence <%= pick["confidence"] %>)
                </li>
              </ul>
            </div>
          </div>

          <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
            <div>
              <label class="block text-sm font-medium">Quality</label>
              <select name="quality_tier" class="mt-1 w-full rounded border-gray-300">
                <option value="draft" selected={@quality_tier == "draft"}>Draft</option>
                <option value="standard" selected={@quality_tier == "standard"}>Standard</option>
                <option value="strong" selected={@quality_tier == "strong"}>Strong</option>
                <option value="detail" selected={@quality_tier == "detail"}>Detail</option>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium">Infill %</label>
              <input
                type="number"
                name="infill_percent"
                value={@infill_percent}
                min="0"
                max="100"
                class="mt-1 w-full rounded border-gray-300"
              />
            </div>
            <div>
              <label class="block text-sm font-medium">Walls</label>
              <input
                type="number"
                name="walls"
                value={@walls}
                min="1"
                max="10"
                class="mt-1 w-full rounded border-gray-300"
              />
            </div>
            <div>
              <label class="block text-sm font-medium">Quantity</label>
              <input
                type="number"
                name="quantity"
                value={@quantity}
                min="1"
                max="100"
                class="mt-1 w-full rounded border-gray-300"
              />
            </div>
          </div>

          <label class="inline-flex items-center gap-2">
            <input type="checkbox" name="supports" checked={@supports} />
            <span class="text-sm">Print with supports</span>
          </label>

          <button type="submit" class="w-full rounded bg-zinc-900 text-white px-4 py-2 font-semibold">
            Request quote
          </button>
        </form>

        <div :if={@quote} class="border rounded p-4 bg-emerald-50">
          <h3 class="font-semibold">Quote #<%= String.slice(@quote.id, 0, 8) %></h3>
          <p class="text-sm text-gray-600">Status: <%= @quote.status %></p>
          <%= if @quote.status == "sliced" do %>
            <dl class="mt-3 text-sm grid grid-cols-2 gap-2">
              <div><dt class="text-gray-500">Filament</dt><dd><%= @quote.estimated_grams %> g</dd></div>
              <div><dt class="text-gray-500">Print time</dt><dd><%= div(@quote.estimated_print_minutes || 0, 60) %>h <%= rem(@quote.estimated_print_minutes || 0, 60) %>m</dd></div>
              <div><dt class="text-gray-500">Material</dt><dd><%= Distributer.Pricing.format(@quote.material_cost_cents, @quote.currency) %></dd></div>
              <div><dt class="text-gray-500">Machine</dt><dd><%= Distributer.Pricing.format(@quote.machine_cost_cents, @quote.currency) %></dd></div>
              <div><dt class="text-gray-500">Markup</dt><dd><%= Distributer.Pricing.format(@quote.markup_cents, @quote.currency) %></dd></div>
              <div><dt class="text-gray-500">Shipping</dt><dd><%= Distributer.Pricing.format(@quote.shipping_cents, @quote.currency) %></dd></div>
              <div><dt class="text-gray-500">Platform fee (3%)</dt><dd><%= Distributer.Pricing.format(@quote.platform_fee_cents, @quote.currency) %></dd></div>
              <div class="col-span-2 border-t pt-2 mt-2 font-bold"><dt>Total</dt><dd><%= Distributer.Pricing.format(@quote.total_cents, @quote.currency) %></dd></div>
            </dl>
            <.link navigate={~p"/orders/new?quote_id=#{@quote.id}"} class="mt-3 inline-block rounded bg-zinc-900 text-white px-4 py-2 text-sm font-semibold">
              Place order
            </.link>
          <% end %>
        </div>
      </section>
    </div>
    """
  end
end
