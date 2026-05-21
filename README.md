# Distributer

A community-driven 3D printing marketplace. Buyers upload a model, pick a shop,
get it printed and shipped. Sellers register their printers and material spools,
set their markup, and operate an individual storefront. The platform takes a
3% commission via Stripe Connect. Czech Republic first; Packeta for shipping.

## What's here

Phase 1 vertical slice. End-to-end path through every domain context, with
real integrations (Stripe Connect, Packeta, Ollama) wired to stubs in dev.

**Implemented**

- Email/password auth with session tokens (bcrypt)
- Per-seller shops with slug, markup, handling fee, policies
- Canonical printer catalog (5 models seeded: Prusa MK4 / MK3S+ / XL, Bambu X1C / A1)
- Canonical slicer profiles per (printer × material × quality tier) with
  seller-level override JSON
- Material catalog + per-shop spool inventory with auditable consume / restock events
- File upload (STL / 3MF) with sha256 dedupe and direct local storage (S3 in prod)
- Binary STL bounding-box analysis for shop-capability matching
- PrusaSlicer CLI wrapper: serializes config to INI, parses gcode for grams +
  print time, falls back to filament length × density × diameter
- Buyer flow: upload → AI material recommendation → quote → place order →
  pay (Stripe stub) → seller print → ship (Packeta stub) → confirm delivery
- Seller dashboard: printers, spools, orders, accept / start / ship actions
- Order state machine: `quoted → paid → accepted → printing → printed →
  shipped → delivered → released` with escrow held until delivered
- Three Ollama endpoints (material recommender, intent → quality params,
  geometry anomaly check) — all use structured JSON output via Ollama's
  `format` schema constraint. LLM never emits raw slicer params — only
  chooses from constrained spaces. All AI calls logged for audit.
  Configurable backend: Ollama Cloud (`gemini-3-flash-preview`), local
  `ollama serve`, or any compatible endpoint.
- Phoenix LiveView UI throughout — real-time slicer-completion updates via
  Phoenix.PubSub
- Background workers via Oban: mesh analysis, slicing, payments, shipping, AI
- Stripe Connect destination charge with platform_fee split
- Packeta REST integration for label creation + pickup-point lookup

**Stubbed but wired**

- Stripe Connect — placeholder API key returns synthetic `pi_stub_*` IDs; the
  buyer "place order" button flips the order to `paid` directly via
  `Payments.stub_mark_paid/1`.
- Packeta — placeholder password returns synthetic labels with random tracking.
- Ollama — when `OLLAMA_BASE_URL` is unset, AI endpoints return
  deterministic stubs so the rest of the flow runs without an LLM backend.
- Mesh analysis — binary STL bbox only. ASCII STL + 3MF + watertight checks
  defer to a `trimesh` Python sidecar (not implemented in phase 1).
- Stripe webhook signature verification — controller accepts unsigned events.
  Verify in production.

## Tech stack

- **Elixir 1.14+ / Phoenix 1.7** with LiveView 1.0
- **Postgres** for persistence
- **Oban** for background jobs (queues: mesh_analysis, slicing, payments,
  shipping, ai)
- **Bandit** HTTP server
- **PrusaSlicer CLI** for slicing
- **Req** for HTTP (Stripe, Packeta, Ollama)
- **Ollama** for AI recommendations — default cloud model
  `gemini-3-flash-preview`, structured JSON output via `format` schema

## Running locally

### Prerequisites

```bash
# Elixir + Erlang (Ubuntu 24.04)
sudo apt-get install -y elixir erlang-dev erlang-os-mon erlang-tools \
    erlang-inets erlang-public-key erlang-ssl erlang-runtime-tools \
    erlang-eldap erlang-snmp postgresql postgresql-contrib build-essential \
    inotify-tools

# PrusaSlicer (Linux AppImage works; or build from source)
# https://github.com/prusa3d/PrusaSlicer/releases
# Make sure `prusa-slicer` is in PATH or set PRUSASLICER_BIN env var
```

### Database

```bash
sudo -u postgres psql -c "CREATE USER distributer WITH SUPERUSER PASSWORD 'distributer';"
```

### Bootstrap

```bash
cd distributer
mix deps.get
mix ecto.create
mix ecto.migrate
mix run priv/repo/seeds.exs
mix phx.server
```

Visit http://localhost:4000.

### Optional environment

```bash
# Ollama — without OLLAMA_BASE_URL, AI endpoints return deterministic stubs
#
# Option A: Ollama Cloud (Gemini Flash hosted by Ollama)
export OLLAMA_BASE_URL=https://ollama.com
export OLLAMA_API_KEY=<your-ollama-cloud-key>
export OLLAMA_MODEL=gemini-3-flash-preview

# Option B: local Ollama serve
#   curl -fsSL https://ollama.com/install.sh | sh
#   ollama pull gemma3:12b
#   ollama serve
export OLLAMA_BASE_URL=http://localhost:11434
export OLLAMA_MODEL=gemma3:12b

# Stripe Connect — without it, the "pay" button bypasses Stripe
export STRIPE_SECRET_KEY=sk_test_...
export STRIPE_WEBHOOK_SECRET=whsec_...

# Packeta — without it, label creation returns synthetic labels
export PACKETA_API_PASSWORD=...

# PrusaSlicer location (defaults to `prusa-slicer` in PATH)
export PRUSASLICER_BIN=/usr/local/bin/prusa-slicer
```

## Architecture

```
lib/distributer/
  accounts/             — users, session tokens
  shops/                — per-seller storefronts
  catalog/              — canonical printer_models, canonical_profiles,
                          shop_printers, shop_profile_overrides
  inventory/            — materials, material_spools, spool_events
  slicing/              — uploads, mesh analysis, slicer pipeline
  orders/               — quotes, orders, print_jobs, state machine
  ai/                   — recommendation log; client is in ai.ex
  storage{.ex, local, s3} — pluggable file storage
  slicer.ex             — PrusaSlicer CLI wrapper
  shipping.ex           — Packeta integration
  payments.ex           — Stripe Connect integration
  pricing.ex            — deterministic price computation
  ai.ex                 — Ollama client (3 narrow endpoints)
```

### The slicing pipeline

```
1. Buyer uploads STL/3MF                      → Slicing.create_upload/2
2. Mesh analyzed (bbox, volume)               → Oban: AnalyzeUploadWorker
3. AI recommends material (Ollama)            → AI.recommend_material/3
4. AI maps intent → quality/infill/walls      → AI.match_intent_to_quality/2
5. Capable shops filtered (bed size, stock)   → Catalog.find_capable_shops/4
6. Buyer picks shop / printer / spool / tier  → LiveView form
7. Slicer runs in background                  → Oban: SliceQuoteWorker
                                                 — resolves canonical profile
                                                 + shop override + intent
                                                 — calls PrusaSlicer CLI
                                                 — parses grams + minutes
8. Quote saved with full breakdown            → Orders.update_quote_with_slice_result/3
9. LiveView updates via PubSub broadcast      → "quote:<id>" topic
10. Buyer places order → Stripe destination
    charge with 3% platform fee               → Payments.create_intent/2
11. Stripe webhook → Orders.mark_paid/2       → creates print_job, unlocks
                                                 gcode for seller
12. Seller prints, marks complete with
    grams used → atomic Orders.complete_print → decrements spool, creates
                                                 spool_event, moves order to
                                                 `printed`
13. Seller ships → Packeta label generated    → Orders.mark_shipped/2
14. Buyer confirms delivery → escrow releases → Orders.release_escrow/1
```

### Pricing formula

All amounts in minor units (haléře = CZK × 100).

```
material_cost  = grams × spool.sell_price_per_gram_cents
machine_cost   = (minutes ÷ 60) × shop_printer.hourly_rate_cents
handling       = shop.handling_fee_cents
markup         = (material + machine + handling) × shop.markup_percent / 100
seller_subtotal = material + machine + handling + markup + shipping
platform_fee   = seller_subtotal × 3 / 100
buyer_total    = seller_subtotal + platform_fee
```

Stripe Connect splits the charge: platform_fee → platform, remainder → seller's
connected account.

### Why canonical profiles + overrides

Sellers don't author raw PrusaSlicer JSON. They pick from a vetted catalog
keyed on `(printer_model, material_type, quality_tier)` and override at most a
few keys. This keeps the catalog walkable from day one, prevents a long-tail of
broken profiles, and lets the LLM safely pick a tier instead of generating
slicer params.

### Why three narrow LLM endpoints instead of one big prompt

Free-form LLM-generated slicer settings can wreck prints or damage printers
(wrong bed temp, bad retraction). Each endpoint has a constrained JSON schema:

- `recommend_material` → ranked picks from spools that are **in stock at the
  chosen shop**. Cannot invent materials.
- `match_intent_to_quality` → `{infill_percent, walls, supports, quality_tier}`
  only. Translated to PrusaSlicer INI keys by `Slicer.merge_intent/2`, not
  emitted directly.
- `scan_geometry` → severity-tagged issues for buyer awareness.

## Roadmap

- Stripe webhook signature verification
- Live Packeta widget for pickup-point selection
- Per-print photo verification (seller uploads, buyer approves before
  escrow release)
- VAT / DPH invoice generation for VAT-registered sellers
- Python `trimesh` sidecar for ASCII STL + 3MF + watertight checks
- 3D viewer in the upload flow (Three.js)
- Multi-currency (EUR alongside CZK)
- Live shipping rates (EasyPost / Shippo) as a phase 2 alternative to Packeta
- Multi-region: extend Packeta to Slovakia, Hungary, Romania (their CEE network)

## License

Not yet decided.
