# Full-Feature-From-Reference Plan

A phased development plan to bring the engine to **parity with the reference design** captured
in `humanish-full-docs/generic/` and now folded into the design docs (`docs/design/game-rules.md`,
`docs/design/game-data.md`). It splits the work into manageable, independently-testable steps,
ordered from low-risk value/formula corrections to larger new subsystems.

> **Provenance.** The gaps below were found by comparing the reference docs against the source
> tree (branch `full-docs-update`). The design docs have already been updated so the reference
> supersedes prior models; this plan implements those updated specs. Section references (§x.y)
> point at `game-rules.md` unless noted.

---

## Working principles (apply to every step)

1. **Engine invariants hold.** Integer math only in `src/sim/` and `src/world/`; one shared
   `gs.rng` consumed in fixed pipeline order; all magnitudes in `data/*.json`, no magic numbers;
   the §3 pipeline order is a rule. (See `CLAUDE.md` → "Non-negotiable engine invariants".)
2. **Determinism gate.** Every step must keep `facade.state_hash()` reproducible and survive the
   `tests/integration` save/load playthrough. Any new int-keyed dict or int-ID array must be
   coerced back to `int` in `deserialize` (the recurring JSON-key gotcha).
3. **Test per subsystem, in isolation.** New tests go in the file for the subsystem they exercise
   (`tests/sim/`, `tests/world/`, `tests/api/`, …). Run new tests **in isolation**
   (`-gunit_test_name=…`) and confirm the asserted count — GUT reports green even when a method
   errors out mid-way (the recurring "swallowed SCRIPT ERROR" gotcha). For any new scene/UI script
   add a `load(path).can_instance()` canary.
4. **Data-driven first.** Prefer adding a JSON table + a generic reader over hard-coding; that is
   how the reference keeps content moddable.
5. **One phase = one reviewable change.** Each phase below is sized to land as its own commit/PR on
   a feature branch, with its tests green and `./run_tests.sh` (unit suites + integration gate)
   passing before moving on.

---

## Phase 0 — Formula & constant corrections (highest value, lowest risk) ✅ COMPLETE

Pure rule-math corrections where the **code diverges from the reference** the design docs now
specify. No new state, no new screens — bounded edits with exact expected values, so they are the
safest first wins and they re-baseline balance for everything after.

> **Status (all sub-steps landed on `main`, each as its own branch/commit/merge).** Full unit
> suites (846 tests) + the integration save/load gate green; `tests/manual/ai_full_game_smoke.gd`
> still reaches a win condition with zero errors on Prince and Deity. Each item's commit carries
> the detail; the per-step notes below record what shipped.

### 0.1 Combat per-hit damage → `COMBAT_DAMAGE` firepower model (§5.4, game-data §15.1) ✅
**Done.** `Combat._per_hit_damage` now uses the firepower blend
(`strengthFactor = (ourFP+theirFP+1)/2`, `dmg = max(1, combat_damage×(theirFP+sf)/(ourFP+sf))`);
even matchups run ≈5 hits. Added `Unit.firepower()` (effective strength, with a `firepower` data
override for siege/special), `combat_damage=20`, and the 10%/90% per-round odds clamp (free-early-
wins applied on top). Tests in `tests/sim/test_combat.gd`.
- **Change.** Replace the flat `opponent_str × 10 / self_str` per-hit damage in `src/sim/combat.gd`
  with the reference blend: `strengthFactor = (ourFP + theirFP + 1)/2`;
  `dmg = max(1, combat_damage × (theirFP + strengthFactor)/(ourFP + strengthFactor))`. Introduce a
  **firepower** quantity on `Unit` (= effective strength for most units; distinct for siege/special).
- **Data.** Add `combat_damage = 20` to `data/constants.json` (keep `combat_scale = 1000`,
  `max_hp = 100`). Add the **10%/90% odds clamp** to `Combat.resolve` (never below 100 / above 900
  of the die), separate from the existing free-early-wins clamp.
- **Needs.** `combat.gd`, `unit.gd` (firepower accessor), `constants.json`.
- **Tests.** `tests/sim/test_combat.gd`: even-matchup combat now runs ≈5 hits (was ≈10/≈2);
  min-1 floor; clamp keeps a hopeless attacker at exactly 10%. Re-run the deterministic same-seed
  identical-outcome test and **update the golden expectations** it pins.
- **Risk.** Touches the most-tested path and shifts balance broadly; expect to re-tune AI attack
  margins afterward. Land this first so later phases build on correct combat length.

### 0.2 City growth food box (§4.2, game-data §15.2) ✅
**Done.** Consumption is now `(population − discontented) × food_per_citizen` with net
unhealthiness folded in as a drain (`Settlement.health_rate()`); the growth threshold uses the
affine pop-and-speed curve (`growth_threshold_base=12`, `growth_threshold_per_pop=8`, replacing the
flat `growth_base × pop`); granary carry-over capped at `threshold × max_food_kept_percent/100`
(75%). Tests in `tests/sim/test_settlement.gd`.

- **Change.** In `src/sim/turn_engine.gd` `_settlement_growth`: consumption =
  `(population − discontented) × food_per_citizen − health_rate` (angry citizens don't eat; net
  unhealthiness drains consumption) instead of `population × food_per_citizen` with a separate
  `wellbeing_deficit` subtraction. Move the growth threshold onto the reference's pop-**and**-speed
  curve (not strictly linear); cap granary carry-over at `threshold × max_food_kept_percent/100`.
- **Needs.** `turn_engine.gd`, `settlement.gd` (health rate accessor), `constants.json`
  (`max_food_kept_percent`, threshold curve coefficients), possibly `paces.json` growth fields.
- **Tests.** `tests/sim/test_settlement.gd`: a city with N angry citizens consumes for `pop−N`;
  an unhealthy city grows slower; carry-over respects the cap; threshold rises with both pop and
  pace.

### 0.3 City-yield percent-modifier chain (§4.3) ✅
**Done.** `_settlement_production` routes +% production modifiers through
`Fixed.apply_stacked_bonus` via the new `_production_percent_mods` (Forge/Factory/Assembly Plant
`production_bonus`, power-plant `power_production_bonus`, Factory `powered_production_bonus` when
powered, plus military `military_production_city` + the Police State `military_production` civic) —
previously dead data, now wired and summed-then-applied-once. `_policy_production_delta` keeps only
the genuinely flat sources. Tests in `tests/sim/test_settlement.gd` / `test_policy_effects.gd`.

- **Change.** Route percentage yield bonuses (structures/policies that grant `+x%` food/production)
  through `Fixed.apply_stacked_bonus` — `base × max(0, 100 + Σmods)/100` — instead of flat deltas.
  Keep flat deltas only for genuinely additive sources (raw tile/specialist output).
- **Needs.** `turn_engine.gd` (`_settlement_growth`, `_settlement_production`, `_policy_*` deltas),
  `policy_effects.gd`; audit which `structures.json`/`policies.json` effects are "+flat" vs "+%".
- **Tests.** `tests/sim/test_settlement.gd` / `test_policy_effects.gd`: a `+25%` production policy
  stacks multiplicatively on base, not as a fixed add; two `+%` sources sum then apply once.

### 0.4 Tech-cost percent chain (§6.3, game-data §15.4) ✅
**Done.** `Research._effective_cost` builds the chain
`base × handicap% × world% × speed% × era% × team-penalty%` (floored at 1), with the prereq and
known-by-others discounts as a labelled post-chain step. Added `handicap_research_percent` to
`difficulties.json`, `research_percent` to `world_sizes.json`, `tech_cost_extra_team_member_modifier`
to `constants.json`, and `Eras.research_scale` (era factor, no-op at 100). `GameState.world_size_id`
is now stored/serialized; alliance size feeds the team factor. Tests in `tests/sim/test_research.gd`.

- **Change.** In `src/sim/research.gd` `_effective_cost`, build the canonical chain
  `base × handicap% × world% × speed% × era% × team-penalty%` then `max(1, …)`. Keep this game's
  prereq/known-by-others discounts as a clearly-labelled **post-chain** step.
- **Data.** Add `handicap_research_percent` to each `data/difficulties.json` entry (Settler 60,
  Noble 100, Deity 130 anchors); add `research_percent` to `data/world_sizes.json`; add
  `tech_cost_extra_team_member_modifier` to `constants.json`. Pace `research_scale` already exists.
- **Needs.** `research.gd`, `difficulties.json`, `world_sizes.json`, `constants.json`.
- **Tests.** `tests/sim/test_research.gd`: tech cost scales with each factor independently;
  Marathon = 3×; Deity player pays 1.3× vs Noble; discounts apply after the chain.

### 0.5 Movement denominator alignment (§5.2) ✅
**Done.** `Fixed.MOVE_PRECISION` renamed to `MOVE_DENOMINATOR = 60`; all movement data rescaled
×3/5 (`units.json` movement, `terrains.json` movement_cost, `features.json` movement_cost_add,
defaults, `constants.movement_precision`). `Pathfinding._move_cost` now reads route reductions from
`transport.json`'s `movement_cost_divisor` (road = exact 20 = 1/3 tile, railroad floored at 1),
retiring the hardcoded `/3` and the dead `movement_cost_override`. Save format bumped to
`GameState.SAVE_VERSION=2` with a pre-2 deserialize migration (unit movement ×60/100). Tests in
`tests/sim/test_pathfinding.gd`, `tests/core/test_fixed.gd`, `tests/api/test_save_load.gd`.

- **Change.** Align internal movement granularity to `MOVE_DENOMINATOR = 60` so route/terrain costs
  divide cleanly (currently `MOVE_PRECISION = 100`). Update `Fixed`, `Pathfinding._move_cost`, the
  serialized `movement_total`/`movement_left` scale, and the dead `transport.json` route-reduction
  path. **Save-format note:** changing the movement scale changes serialized values — bump the save
  version and add a deserialize migration, or do this before any save compatibility is promised.
- **Needs.** `fixed.gd`, `pathfinding.gd`, `unit.gd`, `transport.json`, `constants.json`.
- **Tests.** `tests/sim/test_pathfinding.gd`: road = 1/3 tile resolves exactly at denom 60; a
  2-move unit crosses the expected tiles; "always move at least one tile" preserved.

### 0.6 Difficulty handicap knobs (§2.2, game-data §15.9) ✅
**Done.** `Research._effective_cost` is now player-aware: the human pays `handicap_research_percent`
while the AI does not (its handicap stays the `ai_bonus` beaker boost) and instead gets the new
per-era `ai_research_per_era` modifier (compounds with era; negative on easy levels, positive on
hard; Noble/Prince 0 so default balance is unchanged). City aids stay human-only. Tests in
`tests/sim/test_research.gd` / `test_settlement.gd`.

- **Change.** Add the AI **per-era research modifier** (`ai_research_per_era`) alongside the
  existing `ai_bonus`; wire the player-side `handicap_research_percent` consumed in 0.4. Keep the
  human-only city aids (`growth_bonus`/`health_bonus`/`happiness_bonus`).
- **Needs.** `difficulties.json`, `turn_engine.gd` (AI research path), `research.gd`.
- **Tests.** `tests/sim/test_turn_engine.gd` / `test_data_db.gd`: per-era AI discount compounds;
  human research cost honours the handicap; AI cities still receive no city aids.

**Phase 0 exit:** all unit suites + integration gate green; deterministic combat golden updated;
balance sanity via `tests/manual/ai_full_game_smoke.gd` (game still reaches a win condition).

---

## Phase 1 — Score victory (small, self-contained) (§10, game-data §16) ✅ COMPLETE
**Done.** Score is now the 7th enabled win condition, evaluated each periodic check independently
of Time: `WinConditions._score` returns the lowest-id alliance whose summed score reaches the
`score_threshold` (so it can award mid-game, unlike Time which only tiebreaks at the turn limit).
Added the `score` entry (`type=score`, `score_threshold=400`, provisional) to
`data/win_conditions.json`; extracted `Scoring.score_by_alliance` (shared by `highest_scoring_alliance`
and the new evaluator); enabled `"score"` in `setup_screen.gd`'s condition list. No new serialized
state. Tests in `tests/sim/test_win_conditions.gd` (at/over threshold wins, just-under does not,
fires before the turn limit with Time also enabled). Full unit suites + integration save/load gate
green; `ai_full_game_smoke.gd` still reaches a win condition with zero errors.

- **Goal.** Expose **Score** as its own selectable win condition (7th), distinct from the Time
  tiebreak: first alliance past a configured absolute score threshold wins immediately.
- **Needs.** `data/win_conditions.json` (+`score` entry with threshold), `src/sim/win_conditions.gd`
  (evaluate against `Scoring`), `setup_screen.gd` (offer it), `win_conditions` doc rows (done).
- **Tests.** `tests/sim/test_win_conditions.gd`: a player at/over the threshold wins; under it does
  not; interaction with Time tiebreak unchanged.
- **Risk.** Minimal. Good warm-up after Phase 0.

---

## Phase 2 — Specialists as a first-class table (§6.5, game-data §14.5/§20) ✅ COMPLETE
**Done.** Specialists are now a first-class data table. Added `data/specialists.json` (14 types:
7 working `citizen/priest/artist/scientist/merchant/engineer/spy` + 7 great-person counterparts),
each carrying a per-head `output` vector over six yield channels
(food/production/commerce/science/culture/espionage), `gp_points`/`gp_type`, the `great_person_unit`
it births, and slot rules (`default_slots`, −1 = unlimited). New pure reader `Specialists`
(`src/sim/specialists.gd`, registered in `project.godot`) is the single consumer of the table:
`settlement_output`/`settlement_channel` sum the output vectors, `settlement_gp_points` weights GPP,
`slots_for`/`assignable_types` drive slot ceilings and the city-screen roster. `TurnEngine` routes
each channel into its pipeline — f/p/c into city output (`_settlement_growth`), science into
`_apply_research`, culture into `_settlement_culture`, espionage into `_apply_intelligence` — and
`_special_person_progress` banks GPP by table weight. `GreatPeople.gp_unit_for_type` now reads the
table first (falling back to the unit `generated_by` scan for the General's `combat_xp`). `DataDB`
gained the `specialists` table, `get_specialist`/`get_specialists`, and validation that every
`great_person_unit` and structure `specialist_slots` key resolves. `SimFacade._cmd_assign_specialist`
enforces the per-type slot ceiling (and rejects unknown types); `city_screen.gd` reads the table for
the offered roster, per-type slot display, output tooltips, and a slot-capped + button (replacing the
hard-coded `SPECIALIST_TYPES`). No new serialized state (specialist counts already persisted). Tests:
`tests/core/test_data_db.gd` (14 types present, records well-formed, GP-unit/slot cross-refs resolve);
`tests/sim/test_settlement.gd` (merchant→commerce, engineer→production, scientist→science-not-commerce
all match the table); `tests/sim/test_great_people.gd` (birth maps through the table); `tests/api/test_facade.gd`
(slot ceiling + unknown-type rejection). Full unit suites + integration save/load gate green;
`ai_full_game_smoke.gd` reaches a win condition with zero errors.

- **Goal.** Promote specialists to `data/specialists.json` (14 types: 7 working + 7 great-person)
  with per-head output vector, GP-point type/amount, and slot rules — replacing the implicit
  unit-tag/structure-slot model.
- **Needs.** New `data/specialists.json`; `data_db.gd` loader + validation + `get_specialist(id)`;
  `settlement.gd`/`great_people.gd` read specialist output and GP-point type from the table;
  `structures.json` slot fields keyed to specialist ids; `city_screen.gd` specialist +/- reads the
  table.
- **Tests.** `tests/api/test_data_db.gd` (table loads/validates, all referenced ids exist);
  `tests/sim/test_settlement.gd` (specialist output matches the table); `tests/sim/test_great_people.gd`
  (dominant-specialist birth uses the table's GP-point type).
- **Risk.** Low–medium; mostly a data-extraction refactor. Keep behaviour identical first, then
  tune values to the reference.

---

## Phase 3 — Goody huts & map start-fairness (§9, §1, game-data §20) ✅ COMPLETE
**Done.** Both map-generation parity items landed. `SimFacade.setup` now chooses start positions
once (right after `MapGen.generate`) and runs two RNG-fixed-order post-passes on those starts —
`MapGen.normalize_starts` then `MapGen.place_goody_huts` — before creating players/units, so the
shared `gs.rng` stream stays deterministic and the same starts feed unit placement (no recompute).
This shifted the seeded AI stream, so one seed-locked personality spot-check
(`test_contrasting_leaders_play_rounded_game`) was re-pinned from `20260609` → `20260610` (the
adjacent seed still exercises the intended rounded game; the all-AI `ai_full_game_smoke.gd` gate
still wins with zero errors). No new serialized state — goody huts reuse the already-persisted
`Tile.has_discovery`, so the integration save/load determinism gate covers them. Full unit suites +
integration gate green. The reference's `BonusBalancer` is implemented as the strategic-resource
equalisation pass; the dual map/gameplay RNG streams stay deliberately out of scope (one shared
`gs.rng`, per the working principles).

### 3.1 Goody huts ✅
**Done.** Added `data/goodies.json` — a weighted reward table (`treasury`/`map`/`experience`/`heal`/
`unit`/`tech`/`ambush`) with per-reward magnitudes, loaded + validated by `DataDB`
(`get_goodies()`, `_validate_goody_refs` checks ids/weights and that any `unit_type` resolves).
`Events.exploration_reward` was rewritten data-driven: it rolls one goody from `gs.rng` (weights
overridable per-difficulty via `difficulties.json` `goody_weights` — gentler on Settler, harsher on
Deity) and applies pure-state effects in `_apply_goody` — gold to the owner, XP/heal to the
discoverer, a free unit spawned on the tile (`_spawn_reward_unit`), the cheapest researchable tech
granted (`_grant_free_tech`), a map-reveal descriptor (presentation-only), or an ambush that floors
the discoverer at 1 HP (never killing it mid-move). `MapGen.place_goody_huts` scatters huts
(generalising the Terra-only discovery site, still `Tile.has_discovery`) one per
`goody_hut_land_per_hut` land tiles, kept `goody_hut_min_distance_from_start` clear of every start
and skipping already-flagged tiles. `SimFacade` keeps the on-enter discovery hook, now also emitting
the new `goody_received` signal (and `unit_created` for a spawned reward unit). The dead
`exploration_reward_weights` constant was retired.
- **Tests.** `tests/world/test_map_gen.gd` (huts on passable land, ≥ min distance from starts,
  seed-deterministic); `tests/sim/test_events.gd` (table loads; each reward verb's effect via
  `_apply_goody`; same-seed reward determinism); `tests/core/test_data_db.gd` (table well-formed,
  unit refs resolve); `tests/api/test_facade.gd` (entering a hut consumes it, applies the reward,
  emits `goody_received`).

### 3.2 `normalize*` start-fairness pass ✅
**Done.** `MapGen.normalize_starts(map, db, rng, starts, map_type_id)` runs the reference fairness
pass per start in fixed order — remove adjacent peaks (→ hills), strip jungle, upgrade poor terrain
on/around the city tile (snow/desert → grassland; ring snow → tundra, desert → plains), guarantee
fresh water (carving a short river on the start tile when none is adjacent, matching
`TurnEngine._has_fresh_water`), and top the inner ring up to `start_normalize_min_food_bonuses` food
resources — then a global `_balance_start_resources` equalises strategic-resource access so no start
sits more than `start_normalize_resource_tolerance` below the richest within
`start_normalize_balance_radius`. Tunables live in `constants.json`; a per-script `normalize` block
in `map_types.json` may override them. Every random choice draws from the shared map RNG in fixed
order.
- **Tests.** `tests/world/test_map_gen.gd`: every start has fresh water; no start tile/neighbour is a
  peak; each inner ring holds ≥ the configured food bonuses; strategic-resource counts near starts
  fall within tolerance; the full pass (normalize + goody placement) is seed-deterministic.

---

## Phase 4 — Random-events lifecycle (§9, game-data §20) ✅ COMPLETE
**Done.** The one-shot treasury list is replaced by the reference's **trigger → begin(choice) →
apply → expire** lifecycle. `src/sim/events.gd` is now a trigger-scan engine: each player step (§9,
phase `PLAYER_EVENTS`) it first `tick_active_events` (decrements every timed event the player owns
and applies its `expire_effects` at zero), then `_scan_and_fire` evaluates each trigger's predicate
conjunction (`trigger_holds`) and arms the eligible ones — a prob-100 trigger arms **without a roll**
(so a lone certain event never perturbs the shared RNG stream), sub-100 triggers roll `gs.rng`, and a
weighted pick chooses one when several arm. The fired event either applies its begin `effects`
immediately (no choices), **auto-resolves a branch for an AI** (`ai_choice_id`), or **parks a pending
choice** for a human. Effect verbs (`_apply_effect`): `gold`/`research`/`culture` deltas, `tech`
(named or cheapest researchable), `unit` (spawn at the capital), `building` (free structure),
`capital_health` (timed-plague drain), `heal_units`. Magnitudes are **fixed integers**, so applying a
choice draws no RNG and is identical whenever the human answers.
- **Data.** `data/events.json` rewritten as event definitions (name/text, optional `choices`, begin
  `effects`, `duration` + `expire_effects` for timed events); new `data/event_triggers.json` holds the
  predicates (`min_turn`/`max_turn` pace-scaled, `tech_required`, `building_required`,
  `terrain_required`, `at_war`/`at_peace`, `probability`, `weight`, `one_shot`). `DataDB` loads both
  (`get_event`/`get_events`/`get_event_triggers`) and `_validate_event_refs` checks every trigger's
  `event_id`/tech/building and every effect verb + unit/structure/tech reference resolves.
- **Serialized state.** `GameState.active_events` (timed instances) and `pending_event_choices`
  (humans' unresolved choices) are serialized with int-key coercion on deserialize; `pending_events`
  is the transient surfacing queue. The facade `_drain_events` turns fired/expired records into
  message-log notifications + the existing `event_emitted` signal; `_maybe_raise_event_popup` raises a
  `PopupType.EVENT` popup at a human's turn start (mirroring `CHOOSE_ELECTION`), `get_pending_event`
  lets presentation re-raise it after a load, and the new `RESOLVE_EVENT` command
  (`Commands.resolve_event`, `_cmd_resolve_event`) commits the chosen branch and pops the popup.
- **Tests.** `tests/sim/test_events.gd` (trigger predicates: turn window / tech / building / war /
  one-shot; begin effect verbs; capital-of-prefers-Palace; AI auto-resolve; **human choice popup
  blocks then applies exactly the chosen branch**; **timed event expires on schedule**; save/load
  roundtrip of active events + parked choice). `tests/core/test_data_db.gd` (tables well-formed,
  trigger→event and effect refs resolve). `tests/integration/test_full_playthrough.gd`
  (`test_playthrough_save_load_determinism_midevent`: a mid-flight timed plague + parked human choice
  roundtrip to the same `state_hash` and resume identically). Full unit suites (889) + integration
  gate (10) green in isolation and via `./run_tests.sh`; `ai_full_game_smoke.gd` still reaches a win
  (alliance 1, turn 500) with **zero errors** — and no seed-pinned test needed re-pinning (the
  no-roll-for-certain-triggers rule kept existing RNG streams stable).
- **Deliberate scope.** Happiness/health-over-time and terrain/feature-mutation effect verbs, event
  chaining, and per-trigger cooldowns are left out of the first cut (the begin+expire timed model and
  the `capital_health` verb already cover persisting effects); revisit when a specific event needs
  them. A dedicated `events_screen` is deferred — events surface through the message log, consistent
  with the assembly-ballot popup which likewise has no bespoke scene UI yet.

---

## Phase 5 — Corporations (full model) (§8, game-data §14.6/§20) ✅ COMPLETE
**Done.** `econ_orgs` is extended in place to the reference corporation system (the existing
`data/econ_orgs.json` is reused rather than a new `corporations.json`). Each corporation now carries
a **headquarters structure** (`hq_structure`, erected in the founding city by `EconOrgs.found`), an
**executive unit** (the already-present `executive`, `spread_corporation`-tagged), per-city
**maintenance**, and an **HQ gold-per-input** rate. `EconOrgs.get_output_delta(gs, s)` now scales
output with the **count of distinct input resources the city owner has connected** (flat
`output_delta` + `output_per_input_resource × count`); Cereal Mills/Mining Inc. became pure
per-input (+1 Food / +2 Production per type), the rest stay flat, matching the §14.6 table.
`EconOrgs.maintenance_for` (charged per member city, halved by Free Market's
`corporation_maintenance_reduction`) and `EconOrgs.hq_gold_for` (founder gold per unit of input
consumed in every member city worldwide) are wired into `TurnEngine._update_treasury`. Mercantilism
and State Property gained the `corporations_disabled` effect flag (read via
`EconOrgs.corporations_banned`/`PolicyEffects.has_flag`): under either, a player's corporations
produce nothing, owe no maintenance, and cannot be spread into.
- **Spread.** Organic `spread_all` is retained (now skips ban-civic owners); the deliberate
  executive path is the new `SPREAD_CORPORATION` command (`Commands.spread_corporation`,
  `SimFacade._cmd_spread_corporation`, mirroring the missionary `SPREAD_BELIEF` path) — it spreads
  the player's founded corporation into the city on the executive's tile for
  `corporation_executive_spread_cost` (deterministic, no RNG, like the missionary), consuming the
  unit.
- **Data.** 10 `<corp>_hq` entries added to `structures.json`, each flagged `corporation_hq: true`
  (granted by founding, excluded from the AI build catalog in `PlayerAI._sorted_options`, and never
  in the city-screen quick-build list). New constants `corporation_maintenance`,
  `corporation_hq_gold_per_input`, `corporation_executive_spread_cost` in `constants.json`. `DataDB`
  gained `_validate_econ_org_refs` (HQ structure exists + flagged, executive unit exists, input
  resources resolve). `corporation_screen.gd` now lists each corporation's inputs, per-city output
  (distinguishing flat from per-input), and maintenance.
- **No new serialized state** — corporations reuse the already-persisted `founded_econ_orgs` and
  `settlement.econ_org_id`, so the integration save/load determinism gate already covers them.
- **Tests.** `tests/sim/test_econ_orgs.gd` (HQ erected on founding; output scales with accessible
  input count; flat-output corp ignores inputs; maintenance per member city + Free Market discount;
  HQ pays the founder per input; banning civic disables output + maintenance; executive spread costs
  treasury / consumes the unit / is deterministic; spread blocked under a ban). `tests/core/test_data_db.gd`
  (table well-formed; HQ/executive/resource refs resolve). Full unit suites (902) + integration gate
  (10) green in isolation and via `./run_tests.sh`; `ai_full_game_smoke.gd` still reaches a win
  (alliance 1, turn 500) with **zero errors**, and no seed-pinned test needed re-pinning.

- **Goal.** Extend `econ_orgs` to the reference corporation system: HQ structure (founder gold per
  unit of input consumed worldwide), executive spreader unit, input-resource **count**-scaled
  per-city output, per-city maintenance, and civic interactions (e.g. state-property bans them).
- **Needs.** `data/corporations.json` (or extend `econ_orgs.json`); HQ entries in `structures.json`;
  executive entries in `units.json` with a `SPREAD_CORPORATION` action; `econ_orgs.gd` +
  `turn_engine.gd` (per-turn maintenance + HQ gold + resource-count output); `policy_effects.gd`
  (civic ban); `corporation_screen.gd` to show members/inputs.
- **Tests.** `tests/sim/test_econ_orgs.gd`: output scales with accessible input count; maintenance
  charged per member city; HQ pays the founder; banned under the relevant civic; executive spread
  costs treasury and draws RNG deterministically.
- **Risk.** Medium; mostly additive on an existing subsystem.

---

## Phase 6 — Espionage missions (§7.1, game-data §20)
- **Goal.** Turn accrued intel points into spendable **missions** from a `data/espionage_missions.json`
  table (steal tech, sabotage production, incite unrest, …) with costs, target gates, and
  interception — both the alliance-scope screen path and (optionally) spy-unit-on-tile missions.
- **Needs.** `data/espionage_missions.json`; `sim_facade.gd` `ESPIONAGE_MISSION` validation/handler
  (cost check, interception roll on `gs.rng`, effect apply); `espionage_screen.gd`/`espionage_menu.gd`
  wiring to the data table; constants in `constants.json`.
- **Tests.** `tests/api/test_sim_facade.gd` / `test_espionage` (if added): a mission spends points,
  may be intercepted (deterministic), applies its effect; insufficient points rejected.
- **Risk.** Medium; the screen scaffolding already exists.

---

## Phase 7 — Diplomacy: deals, attitude & memory (§7)
- **Goal.** Promote trades to persistent **deal objects** (one-off + per-turn items, executed each
  world step, cancellable past a minimum duration) and add an **AI attitude/memory** layer
  (5 levels from weighted factors + decaying memory of acts) that gates deal acceptance, war
  declaration, and assembly votes (closing the §7.2 "attitude ignored" provisional note).
- **Needs.** A `Deal` structure on `GameState` (serialize + int-key discipline); `alliance.gd`
  trade rework; new `data/diplomacy.json` (attitude factors, memory kinds + decay, denial reasons);
  `player_ai.gd` attitude evaluation + deal acceptance + assembly-vote weighting;
  `diplomacy_screen.gd` trade table UI (currently war/peace/alliance only).
- **Tests.** `tests/sim/test_alliance.gd` (per-turn deal delivery, cancellation, expiry);
  `tests/api/test_player_ai.gd` (attitude responds to acts; AI refuses a bad deal; votes by
  attitude); save/load determinism with active deals + memory.
- **Risk.** High: broad AI behaviour change + new serialized relational state + a new interactive
  screen. Do after the economy/combat phases are stable.

---

## Phase 8 — Team/vassalage parity (§7)
- **Goal.** Complete the subordination model toward the reference team tier: capitulation after a
  lost war and liberation when strong again, with shared war/peace and (optionally) tech-sharing,
  layered onto `Alliance` (`is_subordinate_to`/`tributaries`).
- **Needs.** `alliance.gd` capitulation/liberation thresholds (in `constants.json`); `turn_engine.gd`
  hooks at war resolution; `player_ai.gd` willingness; `diplomacy_screen.gd` surfacing.
- **Tests.** `tests/sim/test_alliance.gd`: a crushed alliance capitulates; it is freed past the
  liberation threshold; vassal shares the master's wars and votes (ties to Phase 7).
- **Risk.** Medium–high; depends on Phase 7 diplomacy.

---

## Sequencing & dependencies

```
Phase 0  (formulas/constants)  ── must land first; re-baselines balance
  └─ Phase 1 (score victory)        independent, quick
  └─ Phase 2 (specialists)          independent
        └─ Phase 5 (corporations)   leans on specialists/resources
  └─ Phase 3 (goody huts + normalize) independent (map gen)
  └─ Phase 4 (events lifecycle)     after 0–2 (balance + popup queue)
  └─ Phase 6 (espionage missions)   independent of 3–5
        └─ Phase 7 (diplomacy deals/attitude)
              └─ Phase 8 (vassalage)   depends on 7
```

Recommended order: **0 → 1 → 2 → 3 → 5 → 6 → 4 → 7 → 8**, interleaving the cheap independent
phases (1, 3, 6) between the heavier ones.

## Definition of done (per phase)
- Design-doc spec exists and matches the implementation (it does — see `game-rules.md` /
  `game-data.md`); update `docs/ref/code-layout.md` if the module map changes.
- New/changed `data/*.json` validated by `DataDB.load_all()` (cross-refs resolve).
- Unit suite for the subsystem green **in isolation** (asserted count verified) and as part of
  `./run_tests.sh`; integration save/load determinism gate green.
- `tests/manual/ai_full_game_smoke.gd` still runs to a win condition with zero errors.
- For any new serialized state: deserialize coerces int IDs/keys; a mid-state save/load roundtrip
  is added to `tests/integration`.

## Out of scope (deliberate non-goals)
Pure presentation/meta surfaces the reference has but this project intentionally omits or defers —
not blocking gameplay parity: Hall of Fame, Replay viewer, WorldBuilder/scenario editor & fixed-map
loading, Dawn-of-Man / wonder movies, spaceship build screen, advanced-start editor, full
localization/`TXT_KEY` indirection, and the dual map/gameplay RNG streams (this engine deliberately
uses one shared `gs.rng`). Revisit only if a specific feature is later requested.
