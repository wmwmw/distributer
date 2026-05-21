alias Distributer.Catalog
alias Distributer.Inventory

# -------------------- Canonical printer models --------------------

printers = [
  %{
    brand: "Prusa",
    model: "MK4",
    bed_x_mm: 250,
    bed_y_mm: 210,
    bed_z_mm: 220,
    nozzle_default_mm: Decimal.new("0.4"),
    supported_materials: ~w(PLA PETG ASA ABS TPU PC PA)
  },
  %{
    brand: "Prusa",
    model: "MK3S+",
    bed_x_mm: 250,
    bed_y_mm: 210,
    bed_z_mm: 210,
    nozzle_default_mm: Decimal.new("0.4"),
    supported_materials: ~w(PLA PETG ASA ABS TPU)
  },
  %{
    brand: "Prusa",
    model: "XL",
    bed_x_mm: 360,
    bed_y_mm: 360,
    bed_z_mm: 360,
    nozzle_default_mm: Decimal.new("0.4"),
    supported_materials: ~w(PLA PETG ASA ABS TPU PC PA Nylon)
  },
  %{
    brand: "Bambu Lab",
    model: "X1 Carbon",
    bed_x_mm: 256,
    bed_y_mm: 256,
    bed_z_mm: 256,
    nozzle_default_mm: Decimal.new("0.4"),
    supported_materials: ~w(PLA PETG ASA ABS TPU PC PA Nylon)
  },
  %{
    brand: "Bambu Lab",
    model: "A1",
    bed_x_mm: 256,
    bed_y_mm: 256,
    bed_z_mm: 256,
    nozzle_default_mm: Decimal.new("0.4"),
    supported_materials: ~w(PLA PETG TPU)
  }
]

printer_records =
  for attrs <- printers, into: %{} do
    {:ok, p} = Catalog.create_printer_model(attrs)
    {{p.brand, p.model}, p}
  end

# -------------------- Canonical slicer profiles --------------------
# A bare-minimum, vetted PrusaSlicer config per (printer × material × quality).
# Real profiles are much richer; these are pulled from PrusaSlicer's bundled
# defaults and trimmed for brevity. Sellers can override individual keys.

prusa_mk4 = printer_records[{"Prusa", "MK4"}]
prusa_mk3 = printer_records[{"Prusa", "MK3S+"}]
bambu_x1 = printer_records[{"Bambu Lab", "X1 Carbon"}]

base_pla_mk4 = %{
  "printer_model" => "Original Prusa MK4",
  "nozzle_diameter" => "0.4",
  "filament_diameter" => "1.75",
  "filament_type" => "PLA",
  "temperature" => "210",
  "first_layer_temperature" => "215",
  "bed_temperature" => "60",
  "first_layer_bed_temperature" => "60",
  "fan_always_on" => "1",
  "min_fan_speed" => "100",
  "max_fan_speed" => "100",
  "perimeters" => "3",
  "fill_density" => "20%",
  "fill_pattern" => "gyroid",
  "support_material" => "0",
  "retract_length" => "0.8",
  "retract_speed" => "35",
  "travel_speed" => "180",
  "first_layer_speed" => "20",
  "perimeter_speed" => "45",
  "infill_speed" => "80"
}

base_petg_mk4 =
  Map.merge(base_pla_mk4, %{
    "filament_type" => "PETG",
    "temperature" => "240",
    "first_layer_temperature" => "240",
    "bed_temperature" => "85",
    "first_layer_bed_temperature" => "85",
    "min_fan_speed" => "30",
    "max_fan_speed" => "50",
    "retract_length" => "1.4",
    "infill_speed" => "60"
  })

profiles = [
  %{printer_model_id: prusa_mk4.id, material_type: "PLA", quality_tier: "draft",
    layer_height_mm: Decimal.new("0.3"),
    slicer_config: Map.put(base_pla_mk4, "layer_height", "0.3"),
    is_default: false},
  %{printer_model_id: prusa_mk4.id, material_type: "PLA", quality_tier: "standard",
    layer_height_mm: Decimal.new("0.2"),
    slicer_config: Map.put(base_pla_mk4, "layer_height", "0.2"),
    is_default: true},
  %{printer_model_id: prusa_mk4.id, material_type: "PLA", quality_tier: "detail",
    layer_height_mm: Decimal.new("0.15"),
    slicer_config: Map.put(base_pla_mk4, "layer_height", "0.15"),
    is_default: false},
  %{printer_model_id: prusa_mk4.id, material_type: "PLA", quality_tier: "strong",
    layer_height_mm: Decimal.new("0.2"),
    slicer_config: base_pla_mk4 |> Map.put("layer_height", "0.2") |> Map.put("perimeters", "5") |> Map.put("fill_density", "50%"),
    is_default: false},
  %{printer_model_id: prusa_mk4.id, material_type: "PETG", quality_tier: "standard",
    layer_height_mm: Decimal.new("0.2"),
    slicer_config: Map.put(base_petg_mk4, "layer_height", "0.2"),
    is_default: true},
  %{printer_model_id: prusa_mk3.id, material_type: "PLA", quality_tier: "standard",
    layer_height_mm: Decimal.new("0.2"),
    slicer_config: Map.merge(base_pla_mk4, %{"printer_model" => "Original Prusa i3 MK3S+", "layer_height" => "0.2"}),
    is_default: true},
  %{printer_model_id: bambu_x1.id, material_type: "PLA", quality_tier: "standard",
    layer_height_mm: Decimal.new("0.2"),
    slicer_config: Map.merge(base_pla_mk4, %{"printer_model" => "Bambu Lab X1 Carbon", "layer_height" => "0.2", "perimeter_speed" => "120", "infill_speed" => "180", "travel_speed" => "300"}),
    is_default: true}
]

for attrs <- profiles, do: {:ok, _} = Catalog.create_canonical_profile(attrs)

# -------------------- Canonical materials --------------------

materials = [
  %{type: "PLA", brand: "Prusament", name: "PLA Galaxy Black",
    density: Decimal.new("1.24"), nozzle_temp_min: 200, nozzle_temp_max: 230,
    bed_temp_min: 55, bed_temp_max: 65, properties: ~w(food_safe biodegradable easy_to_print)},
  %{type: "PLA", brand: "Prusament", name: "PLA Vanilla White",
    density: Decimal.new("1.24"), nozzle_temp_min: 200, nozzle_temp_max: 230,
    bed_temp_min: 55, bed_temp_max: 65, properties: ~w(food_safe biodegradable easy_to_print)},
  %{type: "PETG", brand: "Prusament", name: "PETG Jet Black",
    density: Decimal.new("1.27"), nozzle_temp_min: 230, nozzle_temp_max: 250,
    bed_temp_min: 80, bed_temp_max: 90, properties: ~w(strong uv_resistant chemical_resistant)},
  %{type: "PETG", brand: "Prusament", name: "PETG Carmine Red",
    density: Decimal.new("1.27"), nozzle_temp_min: 230, nozzle_temp_max: 250,
    bed_temp_min: 80, bed_temp_max: 90, properties: ~w(strong uv_resistant chemical_resistant)},
  %{type: "ASA", brand: "Prusament", name: "ASA Signal White",
    density: Decimal.new("1.07"), nozzle_temp_min: 240, nozzle_temp_max: 260,
    bed_temp_min: 100, bed_temp_max: 110, properties: ~w(uv_resistant outdoor heat_resistant strong)},
  %{type: "TPU", brand: "Fillamentum", name: "Flexfill 98A Traffic Black",
    density: Decimal.new("1.22"), nozzle_temp_min: 220, nozzle_temp_max: 240,
    bed_temp_min: 50, bed_temp_max: 60, properties: ~w(flexible shock_absorbing)},
  %{type: "ABS", brand: "Prusament", name: "ABS Galaxy Black",
    density: Decimal.new("1.04"), nozzle_temp_min: 250, nozzle_temp_max: 270,
    bed_temp_min: 100, bed_temp_max: 110, properties: ~w(heat_resistant strong machinable)}
]

for attrs <- materials, do: {:ok, _} = Inventory.create_material(attrs)

IO.puts("Seeded #{length(printers)} printer models, #{length(profiles)} canonical profiles, #{length(materials)} materials.")
