defmodule Distributer.Slicing.AnalyzeUploadWorker do
  @moduledoc """
  Background analysis of an upload: extracts bounding box from binary STL.

  Phase 1 stub: parses binary STL header + triangles to compute axis-aligned
  bounding box. Returns empty attrs (still marks analyzed) for ASCII STL or
  3MF — those are deferred to a Python `trimesh` sidecar in a later phase.
  """
  use Oban.Worker, queue: :mesh_analysis, max_attempts: 3

  alias Distributer.Slicing
  alias Distributer.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"upload_id" => id}}) do
    upload = Slicing.get_upload!(id)

    case Storage.get(upload.storage_key) do
      {:ok, bytes} ->
        attrs = analyze(bytes, upload.format)
        Slicing.record_analysis(upload, attrs)
        :ok

      {:error, reason} ->
        Slicing.mark_analysis_failed(upload, reason)
        {:error, reason}
    end
  end

  defp analyze(bytes, "stl") do
    case binary_stl_bbox(bytes) do
      {:ok, {dx, dy, dz}} ->
        %{
          "bbox_x_mm" => Decimal.from_float(dx) |> Decimal.round(3),
          "bbox_y_mm" => Decimal.from_float(dy) |> Decimal.round(3),
          "bbox_z_mm" => Decimal.from_float(dz) |> Decimal.round(3)
        }

      :error ->
        %{}
    end
  end

  defp analyze(_bytes, _format), do: %{}

  @doc false
  # Binary STL = 80-byte header + uint32 triangle count + N × 50-byte triangle records.
  # Each triangle: 3×float32 normal + 3×(3×float32 vertex) + uint16 attr = 50 bytes.
  def binary_stl_bbox(<<_header::binary-size(80), count::little-32, rest::binary>>)
      when byte_size(rest) >= count * 50 do
    init = {1.0e30, 1.0e30, 1.0e30, -1.0e30, -1.0e30, -1.0e30}

    {min_x, min_y, min_z, max_x, max_y, max_z} = reduce_triangles(rest, count, init)

    {:ok, {max_x - min_x, max_y - min_y, max_z - min_z}}
  end

  def binary_stl_bbox(_), do: :error

  defp reduce_triangles(_bin, 0, acc), do: acc

  defp reduce_triangles(
         <<_nx::little-float-32, _ny::little-float-32, _nz::little-float-32,
           x1::little-float-32, y1::little-float-32, z1::little-float-32,
           x2::little-float-32, y2::little-float-32, z2::little-float-32,
           x3::little-float-32, y3::little-float-32, z3::little-float-32,
           _attr::little-16, rest::binary>>,
         remaining,
         {mnx, mny, mnz, mxx, mxy, mxz}
       ) do
    acc =
      {Enum.min([mnx, x1, x2, x3]), Enum.min([mny, y1, y2, y3]), Enum.min([mnz, z1, z2, z3]),
       Enum.max([mxx, x1, x2, x3]), Enum.max([mxy, y1, y2, y3]), Enum.max([mxz, z1, z2, z3])}

    reduce_triangles(rest, remaining - 1, acc)
  end

  defp reduce_triangles(_, _, acc), do: acc
end
