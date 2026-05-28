defmodule Distributer.InventoryTest do
  use Distributer.DataCase, async: true

  import Distributer.Fixtures

  alias Distributer.Inventory
  alias Distributer.Inventory.SpoolEvent

  setup do
    shop = shop_fixture()
    %{shop: shop}
  end

  describe "consume/4" do
    test "decrements the spool and records an audit event", %{shop: shop} do
      spool = spool_fixture(shop, nil, %{"grams_total" => 1000, "grams_remaining" => 1000})

      assert {:ok, updated} = Inventory.consume(spool, 250, nil, "test")
      assert updated.grams_remaining == 750

      assert [event] = Repo.all(from e in SpoolEvent, where: e.material_spool_id == ^spool.id)
      assert event.kind == "consume"
      assert Decimal.equal?(event.grams_delta, Decimal.new("-250"))
      assert event.grams_remaining_after == 750
    end

    test "rounds fractional grams to the nearest integer", %{shop: shop} do
      spool = spool_fixture(shop, nil, %{"grams_total" => 1000, "grams_remaining" => 1000})

      assert {:ok, updated} = Inventory.consume(spool, 12.6, nil)
      assert updated.grams_remaining == 987
    end

    test "refuses to oversell and writes nothing", %{shop: shop} do
      spool = spool_fixture(shop, nil, %{"grams_total" => 10, "grams_remaining" => 10})

      assert {:error, :insufficient_stock} = Inventory.consume(spool, 50, nil)

      reloaded = Inventory.get_spool!(spool.id)
      assert reloaded.grams_remaining == 10
      assert Repo.aggregate(from(e in SpoolEvent, where: e.material_spool_id == ^spool.id), :count) == 0
    end

    test "two consumes can't drive the spool negative (no lost update)", %{shop: shop} do
      spool = spool_fixture(shop, nil, %{"grams_total" => 100, "grams_remaining" => 100})

      # Both callers start from the same stale struct (grams_remaining: 100).
      assert {:ok, _} = Inventory.consume(spool, 60, nil)
      assert {:error, :insufficient_stock} = Inventory.consume(spool, 60, nil)

      assert Inventory.get_spool!(spool.id).grams_remaining == 40
    end
  end

  describe "restock/3" do
    test "adds filament, capped at grams_total", %{shop: shop} do
      spool = spool_fixture(shop, nil, %{"grams_total" => 1000, "grams_remaining" => 200})

      assert {:ok, updated} = Inventory.restock(spool, 300)
      assert updated.grams_remaining == 500

      # Cap: can't exceed grams_total.
      assert {:ok, capped} = Inventory.restock(updated, 9_999)
      assert capped.grams_remaining == 1000
    end
  end
end
