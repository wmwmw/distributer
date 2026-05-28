defmodule Distributer.Inventory do
  @moduledoc """
  Materials (canonical lib) and per-shop material spools.

  Spool inventory is the source of truth for what a seller can print. The
  pricing calc uses the spool's `sell_price_per_gram_cents` directly, and
  consumption is recorded as immutable `spool_event` rows for auditability.
  """

  import Ecto.Query, warn: false
  alias Distributer.Repo
  alias Distributer.Inventory.{Material, MaterialSpool, SpoolEvent}

  # ----- Materials (canonical) -----

  def list_materials do
    Repo.all(from m in Material, order_by: [asc: m.type, asc: m.brand, asc: m.name])
  end

  def get_material!(id), do: Repo.get!(Material, id)

  def find_material(brand, name) do
    Repo.get_by(Material, brand: brand, name: name)
  end

  def create_material(attrs) do
    %Material{}
    |> Material.changeset(attrs)
    |> Repo.insert()
  end

  # ----- Spools (per-shop inventory) -----

  def list_spools(shop_id) do
    Repo.all(
      from s in MaterialSpool,
        where: s.shop_id == ^shop_id,
        preload: [:material],
        order_by: [asc: s.inserted_at]
    )
  end

  def list_active_spools_for_shop(shop_id) do
    Repo.all(
      from s in MaterialSpool,
        where: s.shop_id == ^shop_id and s.is_active == true and s.grams_remaining > 0,
        preload: [:material]
    )
  end

  def get_spool!(id), do: Repo.get!(MaterialSpool, id) |> Repo.preload(:material)

  def create_spool(attrs) do
    attrs = Map.put_new(attrs, "grams_remaining", attrs["grams_total"] || attrs[:grams_total])

    %MaterialSpool{}
    |> MaterialSpool.changeset(attrs)
    |> Repo.insert()
  end

  def update_spool(%MaterialSpool{} = spool, attrs) do
    spool
    |> MaterialSpool.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Consume `grams` from a spool, recording an immutable spool_event tied to
  the print_job. Transactional: spool decrement + event insert atomic.

  The decrement is a single conditional `UPDATE ... WHERE grams_remaining >=
  ?`, so concurrent consumes cannot oversell the spool (no lost-update race)
  and the spool can never go negative. Returns `{:ok, spool}` on success or
  `{:error, :insufficient_stock}` when there isn't enough filament — in the
  insufficient case nothing is written. Callers that consume inside their own
  transaction (e.g. `Orders.complete_print/3`) should `Repo.rollback/1` on the
  error so their other writes are undone.
  """
  def consume(%MaterialSpool{} = spool, grams, print_job_id, notes \\ nil)
      when is_number(grams) and grams >= 0 do
    grams_int = round(grams)

    result =
      Repo.transaction(fn ->
        # Atomic guarded decrement: only matches the row if enough remains.
        {count, rows} =
          Repo.update_all(
            from(s in MaterialSpool,
              where: s.id == ^spool.id and s.grams_remaining >= ^grams_int,
              select: s
            ),
            inc: [grams_remaining: -grams_int]
          )

        case {count, rows} do
          {1, [updated]} ->
            %SpoolEvent{}
            |> SpoolEvent.changeset(%{
              material_spool_id: spool.id,
              print_job_id: print_job_id,
              kind: "consume",
              grams_delta: Decimal.new("-#{grams_int}"),
              grams_remaining_after: updated.grams_remaining,
              notes: notes
            })
            |> Repo.insert!()

            {:ok, updated}

          _ ->
            # Nothing matched/changed — no rollback needed, just report.
            {:error, :insufficient_stock}
        end
      end)

    case result do
      {:ok, inner} -> inner
      {:error, reason} -> {:error, reason}
    end
  end

  def restock(%MaterialSpool{} = spool, grams, notes \\ nil) when is_number(grams) and grams >= 0 do
    grams_int = round(grams)

    Repo.transaction(fn ->
      # Lock the row so a concurrent consume/restock can't clobber the write.
      current = Repo.one!(from s in MaterialSpool, where: s.id == ^spool.id, lock: "FOR UPDATE")
      new_remaining = min(current.grams_remaining + grams_int, current.grams_total)
      applied = new_remaining - current.grams_remaining

      updated =
        current
        |> MaterialSpool.changeset(%{grams_remaining: new_remaining})
        |> Repo.update!()

      %SpoolEvent{}
      |> SpoolEvent.changeset(%{
        material_spool_id: spool.id,
        kind: "restock",
        grams_delta: Decimal.new("#{applied}"),
        grams_remaining_after: new_remaining,
        notes: notes
      })
      |> Repo.insert!()

      updated
    end)
  end
end
