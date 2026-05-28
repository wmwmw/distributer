defmodule Distributer.Slicing do
  @moduledoc """
  Uploads + slicing pipeline.

  Flow:
    1. `create_upload/2` accepts the file bytes, computes sha256, stores
       via `Distributer.Storage`, creates the row in `analysis_status: pending`.
    2. `Distributer.Slicing.AnalyzeUploadWorker` (Oban) reads it back, runs
       a lightweight STL/3MF analysis to populate bbox + volume. In dev this
       is a stub; production should shell out to a Python `trimesh` sidecar.
    3. `slice_for_quote/3` runs PrusaSlicer with the resolved profile to
       produce gcode + estimates.
  """

  import Ecto.Query, warn: false
  alias Distributer.Repo
  alias Distributer.Slicing.Upload
  alias Distributer.Storage

  def get_upload!(id), do: Repo.get!(Upload, id)

  def list_uploads_for_user(user_id) do
    Repo.all(from u in Upload, where: u.user_id == ^user_id, order_by: [desc: u.inserted_at])
  end

  @doc """
  Persist an uploaded file. Dedupes by sha256: if an identical file already
  exists, returns the existing row instead of inserting a duplicate.
  """
  def create_upload(file_bytes, attrs) do
    sha = :crypto.hash(:sha256, file_bytes) |> Base.encode16(case: :lower)

    case Repo.get_by(Upload, sha256: sha) do
      %Upload{} = existing ->
        {:ok, existing}

      nil ->
        ext =
          attrs
          |> Map.get(:original_filename, Map.get(attrs, "original_filename", ""))
          |> Path.extname()
          |> String.trim_leading(".")
          |> String.downcase()

        key = Storage.new_key("uploads", ext)

        with {:ok, _} <- Storage.put(key, file_bytes) do
          %Upload{}
          |> Upload.changeset(
            Map.merge(attrs, %{
              "storage_key" => key,
              "size_bytes" => byte_size(file_bytes),
              "sha256" => sha,
              "format" => ext
            })
          )
          |> Repo.insert()
          |> case do
            {:ok, upload} ->
              %{upload_id: upload.id}
              |> Distributer.Slicing.AnalyzeUploadWorker.new()
              |> Oban.insert()

              {:ok, upload}

            err ->
              err
          end
        end
    end
  end

  def record_analysis(%Upload{} = upload, attrs) do
    upload
    |> Upload.changeset(Map.put(attrs, "analysis_status", "analyzed"))
    |> Repo.update()
  end

  def mark_analysis_failed(%Upload{} = upload, reason) do
    upload
    |> Upload.changeset(%{"analysis_status" => "failed", "analysis_error" => inspect(reason)})
    |> Repo.update()
  end

  @doc """
  Run PrusaSlicer for a candidate quote. Returns the gcode storage key and
  parsed estimates. Caller (Orders.create_quote/1) persists results.
  """
  def slice_for_quote(%Upload{} = upload, %{
        slicer_config: config,
        intent_params: intent,
        material_density: density,
        filament_diameter_mm: diameter
      }) do
    with {:ok, bytes} <- Storage.get(upload.storage_key) do
      input_path = write_temp(bytes, upload.format)

      try do
        with {:ok, result} <-
               Distributer.Slicer.slice(input_path, config, intent,
                 material_density: density,
                 filament_diameter_mm: diameter
               ) do
          gcode_key = Storage.new_key("gcode", "gcode")
          {:ok, _} = Storage.put(gcode_key, result.gcode_bytes)

          {:ok, Map.put(result, :gcode_storage_key, gcode_key)}
        end
      after
        File.rm(input_path)
      end
    end
  end

  # Only ever build a temp filename from a known-good extension so the format
  # field (derived from a user filename) can't smuggle path separators or
  # leading dashes into the slicer invocation.
  @allowed_formats ~w(stl 3mf)

  defp write_temp(bytes, ext) do
    safe_ext = if ext in @allowed_formats, do: ext, else: "stl"
    path = Path.join(System.tmp_dir!(), "input-#{System.unique_integer([:positive])}.#{safe_ext}")
    File.write!(path, bytes)
    path
  end
end
