defmodule Distributer.AI do
  @moduledoc """
  Ollama LLM integration. Three narrow, structured-output endpoints — the LLM
  never produces raw slicer params, only chooses from constrained spaces:

    1. `recommend_material/3` — pick a material from a shop's spool inventory
       based on free-text intent ("outdoor bracket, sunlight, light load").
    2. `match_intent_to_quality/2` — high-level intent → infill %, walls,
       supports, quality_tier. These are translated to slicer params by
       `Distributer.Slicer.merge_intent/2`, not emitted directly.
    3. `scan_geometry/2` — flag issues before order (thin walls, scale errors,
       support overhangs).

  All calls use the Ollama `/api/chat` endpoint with `format` set to a JSON
  schema, which constrains the model's output to valid JSON matching the
  schema. Works against local `ollama serve` (no auth) or Ollama Cloud
  (Bearer auth, `gemini-3-flash-preview` and similar hosted models).

  Falls back to deterministic stubs when no base URL is configured.
  """

  require Logger
  alias Distributer.Repo
  alias Distributer.AI.Recommendation

  # -------------------- Material recommender --------------------

  @material_system_prompt """
  You are a 3D printing material recommendation assistant for a marketplace
  in the Czech Republic. Given a buyer's free-text description of what they
  want to print and a list of available material spools at a specific seller's
  shop, recommend the best 1-3 materials.

  Consider:
  - Strength requirements (PETG and ASA stronger than PLA)
  - UV/weather resistance (ASA, PETG for outdoor; PLA degrades in sun)
  - Temperature exposure (ABS/ASA above 60°C; PLA softens)
  - Flexibility (TPU for flexible parts)
  - Detail / visual quality (PLA prints cleanest)
  - Food safety, aesthetics, cost

  Respond ONLY with the available materials. Never invent materials not in the list.
  """

  def recommend_material(intent_text, available_spools, upload \\ nil) do
    spool_descriptions =
      available_spools
      |> Enum.map(fn s ->
        m = s.material
        "spool_id=#{s.id} | #{m.type} #{m.brand} #{m.name} (#{s.color_name}) — #{s.grams_remaining}g remaining | properties: #{Enum.join(m.properties, ", ")}"
      end)
      |> Enum.join("\n")

    user_msg = """
    Buyer intent: #{intent_text}

    Available spools at this shop:
    #{spool_descriptions}

    Return your top 1-3 picks, ordered by best fit. For each, include the spool_id, a one-sentence reasoning, and confidence (0.0-1.0).
    """

    schema = %{
      "type" => "object",
      "properties" => %{
        "recommendations" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "spool_id" => %{"type" => "string"},
              "reasoning" => %{"type" => "string"},
              "confidence" => %{"type" => "number"}
            },
            "required" => ["spool_id", "reasoning", "confidence"]
          }
        }
      },
      "required" => ["recommendations"]
    }

    call_ollama(
      system: @material_system_prompt,
      user: user_msg,
      schema: schema,
      kind: "material",
      upload_id: upload && upload.id
    )
  end

  # -------------------- Intent → quality params --------------------

  @intent_system_prompt """
  You translate free-text 3D printing intent into a small set of high-level
  slicer-agnostic parameters. You do NOT emit raw slicer settings — only
  these four keys. The system applies them to a vetted profile downstream.

  Mapping rules:
  - Decorative / display / "looks nice" → infill 10-15, walls 2-3, quality_tier "detail"
  - General purpose / functional → infill 20-25, walls 3, quality_tier "standard"
  - Strong / load bearing / "must not break" → infill 40-60, walls 4-5, quality_tier "strong"
  - Quick prototype / "just to test fit" → infill 10, walls 2, quality_tier "draft"
  - Has overhangs > 45° from vertical → supports = true; otherwise default false
  """

  def match_intent_to_quality(intent_text, upload \\ nil) do
    schema = %{
      "type" => "object",
      "properties" => %{
        "infill_percent" => %{"type" => "integer"},
        "walls" => %{"type" => "integer"},
        "supports" => %{"type" => "boolean"},
        "quality_tier" => %{"type" => "string", "enum" => ["draft", "standard", "strong", "detail"]},
        "reasoning" => %{"type" => "string"}
      },
      "required" => ["infill_percent", "walls", "supports", "quality_tier", "reasoning"]
    }

    call_ollama(
      system: @intent_system_prompt,
      user: "Intent: #{intent_text}",
      schema: schema,
      kind: "intent",
      upload_id: upload && upload.id
    )
  end

  # -------------------- Geometry anomaly check --------------------

  @geometry_system_prompt """
  Given basic mesh metrics for a 3D model, flag potential printability issues:
  - Very large bounding box (>250mm in any dim) - may not fit common printers
  - Very thin overall (<1mm in any dim) - likely scale error
  - Very small (<5mm largest dim) - may be missing scale
  - Tall narrow geometry (height > 3x footprint) - may need supports/brim
  - Unusual aspect ratios

  Severity: info | warn | block
  """

  def scan_geometry(mesh_features, upload \\ nil) do
    schema = %{
      "type" => "object",
      "properties" => %{
        "issues" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "issue" => %{"type" => "string"},
              "severity" => %{"type" => "string", "enum" => ["info", "warn", "block"]},
              "suggestion" => %{"type" => "string"}
            },
            "required" => ["issue", "severity", "suggestion"]
          }
        }
      },
      "required" => ["issues"]
    }

    call_ollama(
      system: @geometry_system_prompt,
      user: "Mesh features: #{Jason.encode!(mesh_features)}",
      schema: schema,
      kind: "geometry",
      upload_id: upload && upload.id
    )
  end

  # -------------------- Shared Ollama call --------------------

  defp call_ollama(opts) do
    cfg = config()

    if cfg[:base_url] in [nil, ""] do
      Logger.info("Ollama stub: returning empty result for #{opts[:kind]}")
      {:ok, stub_response(opts[:kind])}
    else
      do_call_ollama(cfg, opts)
    end
  end

  defp do_call_ollama(cfg, opts) do
    model = cfg[:model] || "gemini-3-flash-preview"

    body = %{
      "model" => model,
      "messages" => [
        %{"role" => "system", "content" => opts[:system]},
        %{"role" => "user", "content" => opts[:user]}
      ],
      "format" => opts[:schema],
      "stream" => false,
      "options" => %{
        # Lower temp for structured output reliability
        "temperature" => 0.2
      }
    }

    headers =
      [{"content-type", "application/json"}] ++
        case cfg[:api_key] do
          k when is_binary(k) and k != "" -> [{"authorization", "Bearer #{k}"}]
          _ -> []
        end

    url = String.trim_trailing(cfg[:base_url], "/") <> "/api/chat"

    started = System.monotonic_time(:millisecond)
    result = Req.post(url, json: body, headers: headers, receive_timeout: 120_000)
    latency = System.monotonic_time(:millisecond) - started

    case result do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}} = response_body}} ->
        case Jason.decode(content) do
          {:ok, parsed} ->
            log_recommendation(opts, parsed, response_body, latency, model)
            {:ok, parsed}

          {:error, reason} ->
            Logger.error("Ollama returned non-JSON: #{inspect(reason)}; content=#{inspect(content)}")
            {:error, :parse_failed}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("Ollama API error #{status}: #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Ollama API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp log_recommendation(opts, parsed, response_body, latency, model) do
    case opts[:upload_id] do
      nil ->
        :ok

      upload_id ->
        %Recommendation{}
        |> Recommendation.changeset(%{
          upload_id: upload_id,
          kind: opts[:kind],
          model: model,
          prompt: String.slice(opts[:user] || "", 0, 5000),
          response_json: parsed,
          latency_ms: latency,
          # Ollama returns prompt_eval_count / eval_count instead of input/output tokens
          input_tokens: response_body["prompt_eval_count"],
          output_tokens: response_body["eval_count"]
        })
        |> Repo.insert()
    end
  end

  # -------------------- Stubs --------------------

  defp stub_response("material"),
    do: %{"recommendations" => [%{"spool_id" => "stub", "reasoning" => "Stub recommendation — set OLLAMA_BASE_URL", "confidence" => 0.0}]}

  defp stub_response("intent"),
    do: %{
      "infill_percent" => 20,
      "walls" => 3,
      "supports" => false,
      "quality_tier" => "standard",
      "reasoning" => "Stub — set OLLAMA_BASE_URL"
    }

  defp stub_response("geometry"), do: %{"issues" => []}
  defp stub_response(_), do: %{}

  defp config, do: Application.fetch_env!(:distributer, :ollama)
end
