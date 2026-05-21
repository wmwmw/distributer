defmodule Distributer.Catalog do
  @moduledoc """
  Canonical printer models, canonical slicer profiles (vetted per
  printer_model + material_type + quality_tier), and per-shop assignments
  with optional overrides.

  Design: profiles are canonical-with-overrides. Sellers don't ship raw
  PrusaSlicer JSON — they pick a canonical profile and override at most a
  few keys. This keeps the catalog walkable from day one.
  """

  import Ecto.Query, warn: false
  alias Distributer.Repo
  alias Distributer.Catalog.{PrinterModel, CanonicalProfile, ShopPrinter, ShopProfileOverride}

  # ----- Printer models (canonical) -----

  def list_printer_models do
    Repo.all(from p in PrinterModel, where: p.is_active == true, order_by: [asc: p.brand, asc: p.model])
  end

  def get_printer_model!(id), do: Repo.get!(PrinterModel, id)

  def create_printer_model(attrs) do
    %PrinterModel{}
    |> PrinterModel.changeset(attrs)
    |> Repo.insert()
  end

  # ----- Canonical profiles -----

  def list_profiles_for_printer(printer_model_id) do
    Repo.all(
      from p in CanonicalProfile,
        where: p.printer_model_id == ^printer_model_id,
        order_by: [asc: p.material_type, asc: p.quality_tier]
    )
  end

  def get_canonical_profile!(id), do: Repo.get!(CanonicalProfile, id)

  def find_canonical_profile(printer_model_id, material_type, quality_tier \\ "standard") do
    Repo.get_by(CanonicalProfile,
      printer_model_id: printer_model_id,
      material_type: material_type,
      quality_tier: quality_tier
    )
  end

  def create_canonical_profile(attrs) do
    %CanonicalProfile{}
    |> CanonicalProfile.changeset(attrs)
    |> Repo.insert()
  end

  # ----- Shop printer assignments -----

  def list_shop_printers(shop_id) do
    Repo.all(
      from p in ShopPrinter,
        where: p.shop_id == ^shop_id,
        preload: [:printer_model],
        order_by: [asc: p.inserted_at]
    )
  end

  def get_shop_printer!(id) do
    Repo.get!(ShopPrinter, id) |> Repo.preload(:printer_model)
  end

  def create_shop_printer(attrs) do
    %ShopPrinter{}
    |> ShopPrinter.changeset(attrs)
    |> Repo.insert()
  end

  def update_shop_printer(%ShopPrinter{} = sp, attrs) do
    sp
    |> ShopPrinter.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Find shops whose active printers can accept a given upload + material.
  Filters by:
    - printer is active
    - bed_x/y/z fits the bbox
    - printer supports the material_type
    - shop has a compatible canonical profile
  """
  def find_capable_shops(bbox_x_mm, bbox_y_mm, bbox_z_mm, material_type) do
    query =
      from sp in ShopPrinter,
        join: pm in assoc(sp, :printer_model),
        join: shop in assoc(sp, :shop),
        where: sp.is_active == true and shop.is_active == true,
        where: pm.bed_x_mm >= ^bbox_x_mm,
        where: pm.bed_y_mm >= ^bbox_y_mm,
        where: pm.bed_z_mm >= ^bbox_z_mm,
        where: ^material_type in pm.supported_materials,
        preload: [printer_model: pm, shop: shop]

    Repo.all(query)
  end

  # ----- Profile overrides -----

  def upsert_override(attrs) do
    %ShopProfileOverride{}
    |> ShopProfileOverride.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:overrides_json, :notes, :updated_at]},
      conflict_target: [:shop_printer_id, :canonical_profile_id]
    )
  end

  @doc """
  Resolve the effective slicer config for a (shop_printer, canonical_profile)
  pair by deep-merging the override JSON on top of the canonical config.
  """
  def effective_slicer_config(%ShopPrinter{id: shop_printer_id}, %CanonicalProfile{} = profile) do
    override =
      Repo.get_by(ShopProfileOverride,
        shop_printer_id: shop_printer_id,
        canonical_profile_id: profile.id
      )

    base = profile.slicer_config || %{}

    case override do
      nil -> base
      %ShopProfileOverride{overrides_json: nil} -> base
      %ShopProfileOverride{overrides_json: extra} -> deep_merge(base, extra)
    end
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _k, l, r -> deep_merge(l, r) end)
  end

  defp deep_merge(_left, right), do: right
end
