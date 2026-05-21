defmodule DistributerWeb.SellerOnboardingLive do
  use DistributerWeb, :live_view

  alias Distributer.{Accounts, Shops}
  alias Distributer.Shops.Shop

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if Shops.get_shop_for_user(user.id) do
      {:ok, redirect(socket, to: ~p"/sellers")}
    else
      changeset = Shops.change_shop(%Shop{user_id: user.id})
      {:ok, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("validate", %{"shop" => attrs}, socket) do
    changeset =
      %Shop{user_id: socket.assigns.current_user.id}
      |> Shops.change_shop(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"shop" => attrs}, socket) do
    attrs = Map.put(attrs, "user_id", socket.assigns.current_user.id)

    case Shops.create_shop(attrs) do
      {:ok, _shop} ->
        {:ok, _} = Accounts.promote_to_seller(socket.assigns.current_user)

        {:noreply,
         socket
         |> put_flash(:info, "Shop created. Next: add a printer and a spool.")
         |> redirect(to: ~p"/sellers")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto py-8 px-4">
      <.header>
        Open a shop
        <:subtitle>Set up your storefront. You'll add printers and material spools next.</:subtitle>
      </.header>

      <.simple_form for={@form} phx-change="validate" phx-submit="save" class="mt-6">
        <.input field={@form[:name]} label="Shop name" required />
        <.input field={@form[:slug]} label="URL slug" placeholder="my-print-lab" required />
        <.input field={@form[:tagline]} label="Tagline" />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input field={@form[:markup_percent]} type="number" step="0.1" label="Markup %" />
        <.input field={@form[:handling_fee_cents]} type="number" label="Handling fee (haléře)" />
        <:actions>
          <.button class="w-full">Create shop</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
