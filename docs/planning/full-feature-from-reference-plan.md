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

## Phase 0 — Formula & constant corrections (highest value, lowest risk)

Pure rule-math corrections where the **code diverges from the reference** the design docs now
specify. No new state, no new screens — bounded edits with exact expected values, so they are the
safest first wins and they re-baseline balance for everything after.

### 0.1 Combat per-hit damage → `COMBAT_DAMAGE` firepower model (§5.4, game-data §15.1)
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

### 0.2 City growth food box (§4.2, game-data §15.2)
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

### 0.3 City-yield percent-modifier chain (§4.3)
- **Change.** Route percentage yield bonuses (structures/policies that grant `+x%` food/production)
  through `Fixed.apply_stacked_bonus` — `base × max(0, 100 + Σmods)/100` — instead of flat deltas.
  Keep flat deltas only for genuinely additive sources (raw tile/specialist output).
- **Needs.** `turn_engine.gd` (`_settlement_growth`, `_settlement_production`, `_policy_*` deltas),
  `policy_effects.gd`; audit which `structures.json`/`policies.json` effects are "+flat" vs "+%".
- **Tests.** `tests/sim/test_settlement.gd` / `test_policy_effects.gd`: a `+25%` production policy
  stacks multiplicatively on base, not as a fixed add; two `+%` sources sum then apply once.

### 0.4 Tech-cost percent chain (§6.3, game-data §15.4)
- **Change.** In `src/sim/research.gd` `_effective_cost`, build the canonical chain
  `base × handicap% × world% × speed% × era% × team-penalty%` then `max(1, …)`. Keep this game's
  prereq/known-by-others discounts as a clearly-labelled **post-chain** step.
- **Data.** Add `handicap_research_percent` to each `data/difficulties.json` entry (Settler 60,
  Noble 100, Deity 130 anchors); add `research_percent` to `data/world_sizes.json`; add
  `tech_cost_extra_team_member_modifier` to `constants.json`. Pace `research_scale` already exists.
- **Needs.** `research.gd`, `difficulties.json`, `world_sizes.json`, `constants.json`.
- **Tests.** `tests/sim/test_research.gd`: tech cost scales with each factor independently;
  Marathon = 3×; Deity player pays 1.3× vs Noble; discounts apply after the chain.

### 0.5 Movement denominator alignment (§5.2)
- **Change.** Align internal movement granularity to `MOVE_DENOMINATOR = 60` so route/terrain costs
  divide cleanly (currently `MOVE_PRECISION = 100`). Update `Fixed`, `Pathfinding._move_cost`, the
  serialized `movement_total`/`movement_left` scale, and the dead `transport.json` route-reduction
  path. **Save-format note:** changing the movement scale changes serialized values — bump the save
  version and add a deserialize migration, or do this before any save compatibility is promised.
- **Needs.** `fixed.gd`, `pathfinding.gd`, `unit.gd`, `transport.json`, `constants.json`.
- **Tests.** `tests/sim/test_pathfinding.gd`: road = 1/3 tile resolves exactly at denom 60; a
  2-move unit crosses the expected tiles; "always move at least one tile" preserved.

### 0.6 Difficulty handicap knobs (§2.2, game-data §15.9)
- **Change.** Add the AI **per-era research modifier** (`ai_research_per_era`) alongside the
  existing `ai_bonus`; wire the player-side `handicap_research_percent` consumed in 0.4. Keep the
  human-only city aids (`growth_bonus`/`health_bonus`/`happiness_bonus`).
- **Needs.** `difficulties.json`, `turn_engine.gd` (AI research path), `research.gd`.
- **Tests.** `tests/sim/test_turn_engine.gd` / `test_data_db.gd`: per-era AI discount compounds;
  human research cost honours the handicap; AI cities still receive no city aids.

**Phase 0 exit:** all unit suites + integration gate green; deterministic combat golden updated;
balance sanity via `tests/manual/ai_full_game_smoke.gd` (game still reaches a win condition).

---

## Phase 1 — Score victory (small, self-contained) (§10, game-data §16)
- **Goal.** Expose **Score** as its own selectable win condition (7th), distinct from the Time
  tiebreak: first alliance past a configured absolute score threshold wins immediately.
- **Needs.** `data/win_conditions.json` (+`score` entry with threshold), `src/sim/win_conditions.gd`
  (evaluate against `Scoring`), `setup_screen.gd` (offer it), `win_conditions` doc rows (done).
- **Tests.** `tests/sim/test_win_conditions.gd`: a player at/over the threshold wins; under it does
  not; interaction with Time tiebreak unchanged.
- **Risk.** Minimal. Good warm-up after Phase 0.

---

## Phase 2 — Specialists as a first-class table (§6.5, game-data §14.5/§20)
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

## Phase 3 — Goody huts & map start-fairness (§9, §1, game-data §20)
Two map-generation parity items; ship as two sub-steps.

### 3.1 Goody huts
- **Goal.** Place `GOODY_HUT`-style huts on land tiles away from starts at generation; first land
  unit to enter consumes it and rolls a weighted reward (`data/goodies.json`): gold, map reveal,
  XP, free unit, free tech, heal, or hostile ambush. Generalises the Terra-only "discovery site".
- **Needs.** `map_gen.gd` placement stage + predicate; `data/goodies.json`; `sim_facade.gd`
  on-enter resolution (reuse the discovery-site hook); per-difficulty reward weights in
  `difficulties.json`; a `goody_received` signal.
- **Tests.** `tests/world/test_map_gen.gd` (huts placed, min distance from starts, deterministic for
  seed); `tests/api/test_sim_facade.gd` (entering consumes hut, applies reward, draws from `gs.rng`).

### 3.2 `normalize*` start-fairness pass
- **Goal.** After `find_start_positions`, run the reference's fairness pass on each capital's
  surroundings: guarantee fresh water, remove adjacent peaks, strip bad features/terrain, add food
  bonuses/good terrain, and equalise strategic-resource access near starts (`BonusBalancer`).
- **Needs.** New `MapGen.normalize_starts(...)` ordered steps; tunables in `map_types.json`; draws
  from the shared map RNG in fixed order.
- **Tests.** `tests/world/test_map_gen.gd`: every start has fresh water and ≥ the configured food
  bonuses in its inner ring; no start sits on/adjacent to a peak; resource counts near starts fall
  within the balance tolerance; output still deterministic for the seed.
- **Risk.** Medium; interacts with determinism (fixed RNG draw order) and with start spacing.

---

## Phase 4 — Random-events lifecycle (§9, game-data §20)
- **Goal.** Replace the one-shot event list with the reference's **trigger → begin(choice) →
  apply → expire** lifecycle: trigger predicates (turn/tech/building/terrain/war/probability,
  speed-scaled timers), optional player **choice popup**, an apply phase with multiple effect verbs
  (gold, units, buildings, tech, terrain/feature change, happiness/health, quests), and timed
  events that persist and expire. Grow the catalogue.
- **Needs.** Expanded `data/events.json` + `data/event_triggers.json`; rewrite `src/sim/events.gd`
  into a trigger-scan + apply/expire engine drawing from `gs.rng`; a `CHOOSE_EVENT` popup routed
  through the existing `push_popup`/`resolve_popup` facade queue (mirror `CHOOSE_ELECTION`); active
  events stored on `GameState` (serialize + int-key discipline); `events_screen` or message-log
  surfacing.
- **Tests.** `tests/sim/test_events.gd`: a trigger fires only when its predicate holds; a choice
  popup blocks until resolved then applies the chosen branch; a timed event expires on schedule;
  determinism across save/load mid-event (add to the integration playthrough).
- **Risk.** Medium–high: new player-interaction popup + new serialized state on the determinism
  gate. Land Phase 0–2 first so balance is stable.

---

## Phase 5 — Corporations (full model) (§8, game-data §14.6/§20)
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
