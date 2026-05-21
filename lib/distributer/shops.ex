defmodule Distributer.Shops do
  @moduledoc """
  Storefronts. One shop per seller user. Buyers browse shops as the entrypoint
  to ordering. Activation requires a printer + at least one stocked spool.
  """

  import Ecto.Query, warn: false
  alias Distributer.Repo
  alias Distributer.Shops.Shop

  def list_active_shops do
    Repo.all(from s in Shop, where: s.is_active == true, order_by: [asc: s.name])
  end

  def get_shop!(id), do: Repo.get!(Shop, id)

  def get_shop_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Shop, slug: slug)
  end

  def get_shop_for_user(user_id) do
    Repo.get_by(Shop, user_id: user_id)
  end

  def create_shop(attrs) do
    %Shop{}
    |> Shop.changeset(attrs)
    |> Repo.insert()
  end

  def update_shop(%Shop{} = shop, attrs) do
    shop
    |> Shop.changeset(attrs)
    |> Repo.update()
  end

  def change_shop(%Shop{} = shop, attrs \\ %{}) do
    Shop.changeset(shop, attrs)
  end

  @doc """
  Activate a shop if it has at least one active printer and one stocked spool.
  """
  def activate_shop(%Shop{} = shop) do
    if can_activate?(shop) do
      update_shop(shop, %{is_active: true})
    else
      {:error, :requires_printer_and_spool}
    end
  end

  def deactivate_shop(%Shop{} = shop), do: update_shop(shop, %{is_active: false})

  defp can_activate?(%Shop{id: shop_id}) do
    printer_count =
      Repo.aggregate(
        from(p in Distributer.Catalog.ShopPrinter,
          where: p.shop_id == ^shop_id and p.is_active == true
        ),
        :count
      )

    spool_count =
      Repo.aggregate(
        from(s in Distributer.Inventory.MaterialSpool,
          where: s.shop_id == ^shop_id and s.is_active == true and s.grams_remaining > 0
        ),
        :count
      )

    printer_count > 0 and spool_count > 0
  end
end
