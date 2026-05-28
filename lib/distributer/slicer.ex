defmodule Distributer.Slicer do
  @moduledoc """
  PrusaSlicer CLI wrapper. Takes an STL/3MF file and a slicer config map,
  produces a gcode file plus parsed estimates (filament grams, print time).

  Config maps are deep-merged from canonical + override + quote params
  (infill %, walls, supports) before being serialized to PrusaSlicer's INI
  format.

  IMPORTANT: this wrapper never accepts free-form params from buyer input
  directly. Buyers only set the high-level `infill_percent`, `walls`,
  `supports`, `quality_tier` — those are translated to specific INI keys here.
  """

  require Logger

  @type slice_result :: %{
          gcode_path: String.t(),
          gcode_bytes: binary(),
          grams: float() | nil,
          print_minutes: integer() | nil,
          filament_length_mm: float() | nil,
          log: String.t()
        }

  @doc """
  Slice an input file with the given config + intent params.

  ## Options
    * `:material_density` - g/cm^3, used as fallback if PrusaSlicer doesn't emit grams
    * `:filament_diameter_mm` - filament diameter, default 1.75

  Returns `{:ok, slice_result}` or `{:error, reason, log_text}`.
  """
  def slice(input_path, slicer_config, intent_params, opts \\ []) do
    config = merge_intent(slicer_config, intent_params)
    workdir = ensure_workdir()

    config_path = Path.join(workdir, "config-#{rand_suffix()}.ini")
    output_path = Path.join(workdir, "output-#{rand_suffix()}.gcode")

    try do
      File.write!(config_path, to_ini(config))

      bin = Application.get_env(:distributer, :slicer)[:binary] || "prusa-slicer"

      args = [
        "--load", config_path,
        "--export-gcode",
        "--output", output_path,
        input_path
      ]

      Logger.debug("Slicing #{input_path} with #{Enum.join(args, " ")}")

      case System.cmd(bin, args, stderr_to_stdout: true) do
        {log, 0} ->
          case File.read(output_path) do
            {:ok, gcode_bytes} ->
              {:ok,
               %{
                 gcode_path: output_path,
                 gcode_bytes: gcode_bytes,
                 grams: extract_grams(gcode_bytes, opts),
                 print_minutes: extract_minutes(gcode_bytes),
                 filament_length_mm: extract_length(gcode_bytes),
                 log: log
               }}

            {:error, reason} ->
              {:error, {:gcode_read_failed, reason}, log}
          end

        {log, exit_code} ->
          {:error, {:slicer_failed, exit_code}, log}
      end
    after
      # Always clean up the scratch config + gcode, even on failure, so the
      # slicer workdir doesn't grow unbounded.
      File.rm(config_path)
      File.rm(output_path)
    end
  end

  # ----- Intent param translation -----

  @doc """
  Translates high-level buyer intent into PrusaSlicer INI keys, merging
  with the base config (canonical + shop overrides).
  """
  def merge_intent(base, params) do
    overrides =
      %{}
      |> maybe_put(params, :infill_percent, "fill_density", &"#{clamp_int(&1, 0, 100)}%")
      |> maybe_put(params, :walls, "perimeters", &to_string(clamp_int(&1, 1, 10)))
      |> maybe_put(params, :supports, "support_material", &if(&1, do: "1", else: "0"))

    Map.merge(base, overrides)
  end

  defp maybe_put(acc, params, key, ini_key, fmt) do
    case Map.get(params, key) || Map.get(params, to_string(key)) do
      nil -> acc
      v -> Map.put(acc, ini_key, fmt.(v))
    end
  end

  # Coerce intent values to a bounded integer so they can never carry
  # arbitrary text into the generated INI.
  defp clamp_int(v, lo, hi) do
    n =
      cond do
        is_integer(v) -> v
        is_float(v) -> trunc(v)
        is_binary(v) -> with {i, _} <- Integer.parse(v), do: i, else: (_ -> lo)
        true -> lo
      end

    n |> max(lo) |> min(hi)
  end

  # ----- INI serialization -----

  def to_ini(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> "#{ini_token(k)} = #{ini_value(v)}" end)
    |> Enum.join("\n")
  end

  defp ini_value(true), do: "1"
  defp ini_value(false), do: "0"
  defp ini_value(v) when is_list(v), do: v |> Enum.map_join(",", &ini_token/1)
  defp ini_value(v), do: ini_token(v)

  # Strip CR/LF so a value can never inject extra INI directives (e.g. a
  # rogue `post_process` script) onto their own line.
  defp ini_token(v) do
    v |> to_string() |> String.replace(["\n", "\r"], " ")
  end

  # ----- Gcode output parsing -----

  defp extract_grams(gcode, opts) do
    case Regex.run(~r/;\s*total filament used \[g\]\s*=\s*([0-9.]+)/i, gcode) do
      [_, grams] ->
        {f, _} = Float.parse(grams)
        f

      _ ->
        # Fallback: compute from length + density if PrusaSlicer didn't emit grams line
        case extract_length(gcode) do
          nil -> nil
          length_mm -> length_to_grams(length_mm, opts)
        end
    end
  end

  defp extract_length(gcode) do
    case Regex.run(~r/;\s*filament used \[mm\]\s*=\s*([0-9.]+)/i, gcode) do
      [_, mm] ->
        {f, _} = Float.parse(mm)
        f

      _ ->
        nil
    end
  end

  defp extract_minutes(gcode) do
    case Regex.run(~r/;\s*estimated printing time.*=\s*(.+)/i, gcode) do
      [_, time_str] ->
        parse_duration(String.trim(time_str))

      _ ->
        nil
    end
  end

  # Parses formats like "1h 23m 45s" or "23m 45s" or "1d 2h"
  defp parse_duration(str) do
    str = String.replace(str, ~r/[\(\)]/, "")

    seconds =
      Regex.scan(~r/(\d+)\s*(d|h|m|s)/i, str)
      |> Enum.reduce(0, fn [_, num, unit], acc ->
        {n, _} = Integer.parse(num)
        acc + n * unit_seconds(String.downcase(unit))
      end)

    if seconds > 0, do: div(seconds, 60), else: nil
  end

  defp unit_seconds("d"), do: 86_400
  defp unit_seconds("h"), do: 3600
  defp unit_seconds("m"), do: 60
  defp unit_seconds("s"), do: 1

  defp length_to_grams(length_mm, opts) do
    density = Keyword.get(opts, :material_density, 1.24)
    diameter = Keyword.get(opts, :filament_diameter_mm, 1.75)
    radius = diameter / 2
    volume_mm3 = :math.pi() * radius * radius * length_mm
    volume_cm3 = volume_mm3 / 1000
    volume_cm3 * density
  end

  # ----- Workdir helpers -----

  defp ensure_workdir do
    dir = Application.get_env(:distributer, :slicer)[:workdir] || "priv/slicer_work"
    File.mkdir_p!(dir)
    dir
  end

  defp rand_suffix do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
