defmodule DistributerWeb.OrderNewLive do
  use DistributerWeb, :live_view

  alias Distributer.{Orders, Shipping}

  @impl true
  def mount(%{"quote_id" => quote_id}, _session, socket) do
    quote = Orders.get_quote!(quote_id)

    case Shipping.lookup_pickup_point("STUB-1") do
      {:ok, point} ->
        {:ok,
         socket
         |> assign(:quote, quote)
         |> assign(:default_point, point)}

      _ ->
        {:ok, assign(socket, quote: quote, default_point: nil)}
    end
  end

  @impl true
  def handle_event("place-order", params, %{assigns: %{quote: quote, current_user: user}} = socket) do
    case Orders.place_order(quote, user, params) do
      {:ok, order} ->
        {:noreply, redirect(socket, to: ~p"/orders/#{order.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not place order: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto py-8 px-4">
      <.header>
        Place order
        <:subtitle>Confirm delivery details and place the order.</:subtitle>
      </.header>

      <section class="mt-6 border rounded p-4 bg-zinc-50">
        <h3 class="font-semibold mb-2">Quote summary</h3>
        <dl class="text-sm space-y-1">
          <div class="flex justify-between"><dt>Estimated filament</dt><dd><%= @quote.estimated_grams %> g</dd></div>
          <div class="flex justify-between"><dt>Estimated time</dt><dd><%= div(@quote.estimated_print_minutes || 0, 60) %>h <%= rem(@quote.estimated_print_minutes || 0, 60) %>m</dd></div>
          <div class="flex justify-between font-bold border-t pt-2 mt-2"><dt>Total</dt><dd><%= Distributer.Pricing.format(@quote.total_cents, @quote.currency) %></dd></div>
        </dl>
      </section>

      <form phx-submit="place-order" class="mt-6 space-y-4">
        <div>
          <label class="block text-sm font-medium">Recipient name</label>
          <input name="recipient_name" required class="mt-1 w-full rounded border-gray-300" />
        </div>
        <div>
          <label class="block text-sm font-medium">Recipient email</label>
          <input name="recipient_email" type="email" value={@current_user.email} required class="mt-1 w-full rounded border-gray-300" />
        </div>
        <div>
          <label class="block text-sm font-medium">Phone</label>
          <input name="recipient_phone" type="tel" placeholder="+420 ..." class="mt-1 w-full rounded border-gray-300" />
        </div>
        <div>
          <label class="block text-sm font-medium">Packeta pickup point</label>
          <input name="packeta_point_id" placeholder="e.g. 12345" required class="mt-1 w-full rounded border-gray-300" />
          <p class="text-xs text-gray-500 mt-1">
            In production: embed Packeta widget. Stub default: <%= @default_point && @default_point.name %>
          </p>
        </div>
        <div>
          <label class="block text-sm font-medium">Notes (optional)</label>
          <textarea name="notes" rows="2" class="mt-1 w-full rounded border-gray-300"></textarea>
        </div>
        <button type="submit" class="w-full rounded bg-zinc-900 text-white px-4 py-2 font-semibold">
          Place order — pay <%= Distributer.Pricing.format(@quote.total_cents, @quote.currency) %>
        </button>
      </form>
    </div>
    """
  end
end
