# Plan: 4X Game — Phase 1 (Deterministic Simulation Engine Core)

## Context

`./docs/game-rules.md` specifies a turn-based, empire-building 4X strategy game at
roughly **Civilization-IV scale**: tiled world, settlements with growth/production/
culture/contentment/wellbeing, units with detailed combat, players with treasury/
research/policies, alliances/diplomacy/espionage, beliefs and economic organizations,
wild forces, events, environmental degradation, and six win conditions — all explicitly
**data-driven** and **deterministic** (integer math, one shared seeded RNG with a fixed
draw order).

The workspace is greenfield (only the spec and `docs.zip` exist; no Godot project, and
the `godot` binary is not yet installed).

**Decisions locked with the user:**
- **First deliverable = engine core only.** Build a *headless, UI-agnostic* simulation
  engine + data layer + automated tests. No rendered game yet.
- **GDScript** for the engine (determinism via integer/fixed-point math is fully
  achievable in GDScript; simplest toolchain).
- **Hotseat only** → **no AI** work in scope.
- **Desktop-first, touch-friendly** UI → out of scope for this build, but the engine's
  public API is designed so that later UI can drive it from any input source.

**Intended outcome of Phase 1:** a `godot --headless`-runnable engine that, given a seed +
config data + a sequence of player commands, advances turns through the exact section-3
pipeline and produces *bit-identical* state on every machine — verified by a test suite.
This de-risks every later system (UI, input, hotseat shell) by proving the rules core first.

> Phases 6+ (presentation, input abstraction, hotseat shell) are **sketched at the end for
> continuity but are explicitly out of scope** for this deliverable; they'll get their own plan.

---

## Architecture

A strict split: **`sim` (pure rules, no Godot scene/node/UI dependency)** ↔ **`api` facade**
↔ (future) presentation. The engine only ever receives **Commands** and emits **State** +
domain **events**; it never reaches into UI. This is what makes "headless now, UI later"
real rather than aspirational.

### Project layout (`res://`)
```
project.godot
data/                         # §12 "configurable data" — all numbers live here, not in code
  constants.json              # global constants (combat scale, growth base, anger divisor, …)
  terrains.json features.json resources.json improvements.json transport.json
  units.json structures.json technologies.json policies.json promotions.json
  beliefs.json econ_orgs.json projects.json win_conditions.json
  ages.json paces.json difficulties.json world_sizes.json leaders_traits.json
src/
  core/
    rng.gd          # deterministic generator; single instance; ordered named draws
    fixed.gd        # fixed-point integer helpers (movement precision, high-precision stores)
    data_db.gd      # loads + validates all tables, resolves cross-refs, supplies defaults
    ids.gd          # typed enums / id constants
  world/
    tile.gd  world_map.gd      # grid, wrap-aware adjacency (8 compass / 4 cardinal), distance
    tile_output.gd             # §1.3 natural→final output calc, clamped ≥0
    regions.gd                 # connected-component regions + supply groups
    influence.gd               # cultural influence accumulation + ownership resolution (§4.7)
  sim/
    game_state.gd              # root aggregate; fully serializable; the single source of truth
    turn_engine.gd             # the §3 pipeline (whole-world / per-player / per-settlement)
    hooks.gd                   # override-hook seam (§3, §13.11): each phase consults a hook first
    settlement.gd              # growth, output split, production/rushing, contentment, wellbeing, culture
    unit.gd  stack.gd          # movement allowance, domains, strength modifiers
    combat.gd                  # rounds, first-strike, withdrawal, spillover, flanking, combat-limit
    pathfinding.gd             # shortest-path over movement costs, domain-legal
    player.gd  research.gd     # treasury/upkeep, allocation sliders, research graph, policies, specialists
    alliance.gd                # war/peace, trades, subordination, intelligence (stub-deep in §5)
    beliefs.gd econ_orgs.gd    # founding + spread
    wild_forces.gd events.gd   # spawning; scripted/random events
    pollution.gd               # environmental degradation (§11)
    win_conditions.gd scoring.gd
  api/
    sim_facade.gd              # public surface: apply_command(), query state, signals for events
    commands.gd                # serializable player intents (Found, MoveStack, SetSliders, …)
    save_load.gd               # deterministic (de)serialization of game_state
tests/                         # gdUnit4 headless suites (see Verification)
addons/gdUnit4/                # test framework
```

### Non-negotiable engine invariants (straight from the spec)
1. **Integer math only** in rules; `fixed.gd` provides fixed-point for movement allowance
   and high-precision resource stores. Floats are display-only and never enter `sim`.
2. **One shared seeded RNG** (`rng.gd`), consumed in a **fixed, documented draw order**.
   Every stochastic step (combat rounds, tile degradation, raider spawns, belief founding
   tie-breaks, event rolls, exploration rewards) pulls from it in pipeline order.
3. **Data-driven**: `data_db.gd` loads JSON tables and global constants (or defaults);
   no magic numbers in rule code. Cross-references (prereq tech ids, resource ids) are
   validated on load.
4. **Pipeline order is itself a rule** — `turn_engine.gd` executes §3 exactly, and each
   phase first consults `hooks.gd` (if the hook handles it, the built-in is skipped).
5. **Command/event API** — the only way state changes is `apply_command()`; the only way
   the outside observes change is reading `game_state` or subscribing to emitted events.
   Commands are input-source-agnostic (mouse/keyboard/touch all just produce the same
   Command objects later).

---

## Implementation phases (this deliverable)

Each phase ends with passing headless tests before the next begins.

**Phase 0 — Scaffold & deterministic core**
- `project.godot` (Godot 4.x), install gdUnit4 addon, CI-style headless test invocation.
- `core/rng.gd` (seedable, splittable per-domain streams with a fixed order), `core/fixed.gd`,
  `core/ids.gd`, `core/data_db.gd` + a minimal default dataset under `data/`.
- Tests: RNG reproducibility (same seed → same sequence), data load + cross-ref validation,
  fixed-point round-trip.

**Phase 1 — World model (§1)**
- `world/tile.gd`, `world/world_map.gd` (preset sizes, axis wrapping, distance/adjacency),
  `world/tile_output.gd` (full §1.3 formula), `world/regions.gd`, `world/influence.gd`.
- Tests: wrap-aware distance; tile-output matches hand-computed cases; region/supply-group
  connectivity; influence→ownership awarding.

**Phase 2 — Settlements (§4)**
- `sim/settlement.gd`: growth store + threshold (pop/pace/age/difficulty scaling), output &
  economic split via sliders, production queue + rushing + carryover, contentment
  (pos/neg sentiment → discontent → disorder), wellbeing (health deficit → surplus penalty),
  culture accumulation + ring expansion feeding `influence.gd`.
- Tests: growth/starvation thresholds, slider partition sums, disorder trigger, border ring
  expansion over N turns.

**Phase 3 — Units & combat (§5)**
- `sim/unit.gd`/`stack.gd`, `sim/pathfinding.gd`, `sim/combat.gd` (effective strength from
  stacked % modifiers × health fraction; odds; per-hit damage; round loop with first-strike,
  withdrawal, combat-limit, spillover, flanking; experience + promotions; healing/entrenchment).
- Tests: movement cost + "always ≥1 tile" guarantee; pathfinding legality per domain;
  **seeded combat golden-master** (fixed seed → fixed outcome & damage trace); entrenchment cap.

**Phase 4 — Players, economy, research (§6)**
- `sim/player.gd`, `sim/research.gd`: treasury income−upkeep + insolvency, slider constraints
  from policies, research rate + discounts + prereq graph (required-all / required-any) shared
  across alliance, policy switching transition penalty, specialists → special persons.
- Tests: upkeep/insolvency cascade, research discount math, prereq-graph unlocks.

**Phase 5 — Pipeline integration + remaining systems**
- `sim/turn_engine.gd` wiring **all** §3 phases in order through `hooks.gd`.
- `sim/alliance.gd` (war/peace, trades resolved in whole-world step, subordination,
  intelligence), `beliefs.gd`, `econ_orgs.gd`, `wild_forces.gd`, `events.gd`,
  `pollution.gd`, `win_conditions.gd`, `scoring.gd`.
- `api/sim_facade.gd`, `api/commands.gd`, `api/save_load.gd`.
- Tests: **end-to-end determinism** — a fixed seed + scripted command log run twice (and
  save→load→resume mid-game) yields an identical `game_state` hash; each win condition fires
  on a constructed scenario; save/load round-trip equality.

---

## Reuse / build notes
- This is greenfield: nothing to reuse from the repo, so the spec's **§13 checklist** is the
  acceptance contract — Phases 0–5 above map 1:1 onto checklist items 1–10 (item 11, the
  override-hook seam, is `hooks.gd`).
- Prefer **JSON** for `data/` tables (human-diffable, engine-agnostic) over `.tres`, so the
  data layer stays portable and testable without the Godot editor.
- Keep `sim/*` free of any `Node`/scene/`Input` references so it runs and tests purely headless.

## Verification
1. **Install Godot 4.x** (binary not currently on PATH) and the gdUnit4 addon.
2. Run the full suite headless:
   `godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests`
   (exact runner command finalized in Phase 0).
3. **Determinism gate (the key acceptance test):** run a fixed seed + scripted command log,
   hash `game_state`; rerun → identical hash; run with a save→load in the middle → still
   identical. This proves the seeded-RNG + integer-math contract end to end.
4. Per-phase unit suites (above) all green before merging each phase.
5. Spot-check tile-output and combat traces against hand-computed values from the spec.

## Out of scope for this deliverable (future plan)
- **Phase 6+ Presentation:** abstract, flat-color 2D renderer for the square grid; clean
  HUD; animations driven by engine events.
- **Input abstraction layer** giving full mouse / keyboard / touch parity (all three emit the
  same `commands.gd` objects), desktop-first with large hit targets + gesture support.
- **Hotseat shell:** pass-and-play turn handoff, per-player fog/vision, setup screen.
- AI opponents (explicitly excluded — hotseat only).
