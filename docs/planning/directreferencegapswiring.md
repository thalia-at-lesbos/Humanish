# Direct Reference Gaps — wiring plan (parked follow-ups)

Status: **PLANNED 2026-07-18** — nothing started. Successor to
`directreferencegaps.md` (COMPLETE 2026-07-18): that plan reached full parity in
*shipped data*; this plan finishes the follow-ups it parked in its item notes —
dead keys with no engine reader, mechanics blocked on unmodelled subsystems, the
reference *model* adoptions, and the last data retunes. Date: 2026-07-18.

**DECISIONS (user, 2026-07-18) — recorded so a fresh session can proceed without
further input:**

1. **Scope: everything.** All parked follow-ups are in scope, phased below. No
   item is dropped; anything not immediately implementable is a Phase 0 sourcing
   line, not a cut.
2. **Models: adopt reference.** The reference *model* adoptions that change
   gameplay and/or the save format (settler food-box, per-player GP counter,
   free settled specialists, citizen-specialist auto-assignment,
   military-instructor +XP, fractional feature health) are all adopted —
   consistent with the 2026-07-08 blanket rule from `directreferencegaps.md`.
   Save-format-affecting items carry a version-bump note (CLAUDE.md "Releasing":
   breaking save-format changes ⇒ major bump).
3. **Missing values: source first.** The reference-XML sourcing authorization is
   closed. The plan therefore **opens with Phase 0**: a user-authorized,
   session-scoped sourcing pass that records every still-undocumented value into
   `game-rules.md` §15 / `game-data.md` §29 (design-doc edits at that sitting,
   with the usual consent) **before** any dependent implementation starts. After
   Phase 0 closes, future sessions source from the docs only — same rule as the
   predecessor plan.

Sources of truth:
- `docs/planning/directreferencegaps.md` — each parked item's originating note
  (cited per item below as "plan A2 note" etc.).
- `docs/design/game-rules.md` §15 / `docs/design/game-data.md` §29 — the recorded
  reference values (all implemented; this plan only *wires* or *extends*).
- `docs/planning/reference-parity-audit.md` — the raw audit, for Phase 0 cross-checks.

Conventions (unchanged from the predecessor): every work item lists **files** and
**tests**; new tests follow the per-subsystem layout; all engine math stays
integer; every roll through `gs.rng` in pipeline order; every constant in
`data/*.json`; int-coerce IDs/keys in every `deserialize`; design-doc updates only
with user consent (planning/ref/user docs update freely).

---

## Phase 0 — sourcing sitting (user-authorized, session-scoped; BLOCKS the items marked ⓪)

One sitting, authorized by the user for that session only, that reads the
reference XML/SDK and records into `game-rules.md` §15 (rule specs) and
`game-data.md` §29 (value tables), with design-doc consent granted for the
sitting. Nothing else in this phase — no engine work. Capture list:

- **0a. Culture%-slider happiness** — the reference `iHappinessPerXPercentCulture`
  mechanic (cathedral-tier buildings grant happiness scaled by the culture
  allocation rate): exact divisor per building, rounding, cap. Feeds M2.
- **0b. Air interception model** — how interception resolves (which missions are
  interceptable, engagement order, damage to the intercepted/evading unit, one
  intercept per turn per interceptor?), interacting fields `intercept_bonus`
  (shipped 10/20), `evasion_chance` (ace 25), unit `air_range`. Feeds M3.
- **0c. Settler food-box build** — the reference food-contributes-to-production
  model for settlers/workers (`iFoodProductionCost`-style constants, growth
  freeze while training, overflow rules). Feeds R1.
- **0d. Spaceship arrival delay** — the post-launch travel-turns model that
  `victory_delay_scale` (shipped, unread) exists to stretch. Feeds M4.
- **0e. Structure obsolescence table** — per-structure obsoleting tech
  (Hagia Sophia → Steam Power is documented in the plan B7 note; capture the full
  roster plus behaviour: effects stop, building remains, no sale — buildings are
  never sold in Humanish). Feeds M1.
- **0f. Per-player GP counter parameters** — confirm the per-player threshold
  base/increase match the shipped `gp_threshold_base`/
  `gp_threshold_increase_percent`, and the per-player (not per-city) escalation
  rule. Feeds R2.
- **0g. Citizen-specialist auto-assignment** — the reference "excess citizens
  become citizen specialists" rule (when population exceeds workable+assigned
  slots). Feeds R3.
- **0h. Military instructor (settled Great General) +XP model** — the +XP-to-
  units-built-in-city magnitude that replaces the Humanish settled +2P stand-in.
  Feeds R4.
- **0i. Unit capture** (adjacent gap, optional) — the reference capture of
  non-combat units (worker/settler captured instead of killed). If adopted, also
  unblocks the C8 unit-capture war-weariness weights (2/1) that were left
  unshipped because the mechanic does not exist. Feeds M6.
- **0j. Cross-checks** — confirm `collateral_damage_protection` semantics
  (% reduction of spillover damage taken) against the recorded §29.3/§13 notes,
  and panzer's `vs_armor` magnitude (+50, plan A1 note) before W7.

Exit criterion: every value above recorded in §15/§29 with a "sourced 2026-MM-DD"
note; the authorization is then closed again and implementation phases proceed
docs-only.

---

## Phase W — dead-key wirings (values already shipped; small, independent; no Phase 0 dependency except W7's 0j check)

- **W1. Per-city `science_bonus`** (plan A2 note): research income currently has
  no per-city % multiplier site — the key (library/university/observatory/
  laboratory 25, academy 50, seowon 35; verified 2026-07-11) is read only by the
  PlayerAI heuristic and the encyclopedia. Wire: apply the summed standing-
  structure `science_bonus` as a percentage multiplier on the city's research
  commerce share at the single split site (`TileOutput`/`TurnEngine` research
  aggregation), integer truncation. **Files:** `src/sim/turn_engine.gd` (or the
  settlement research aggregation site), `src/sim/settlement.gd`. **Tests:**
  `tests/sim/test_settlement.gd` (25%/50% cases, stacking, truncation),
  recalibrate any pinned research totals.
- **W2. Three Gorges Dam `unhealthy_global: 2`** (plan A2 note): global
  semantics — +2 unhealth in **every** city of the owner (that is what blocked
  folding it into per-city `health_penalty`). Wire a `PolicyEffects`-style
  standing-structures scan in `_update_contentment`/wellbeing. **Files:**
  `src/sim/turn_engine.gd`. **Tests:** `tests/sim/test_settlement.gd` (owner-wide
  effect, other players unaffected).
- **W3. Hippodrome `happiness_with_horse: 1`** (plan A2 note): +1 happy in the
  city while the owner has Horse accessible (`EconOrgs.accessible_resources`).
  **Files:** `src/sim/turn_engine.gd`. **Tests:** `test_settlement.gd` (with/
  without horse, resource lost ⇒ happy lost).
- **W4. Statue of Zeus `enemy_war_weariness`** (plan C8 note): +% war-weariness
  accrual on enemies at war with the owner, summed into the C8 per-event weight
  application site. **Files:** `src/sim/turn_engine.gd` (war-weariness accrual),
  possibly `src/sim/combat_apply.gd`. **Tests:** `tests/sim/test_turn_engine.gd`
  war-weariness cases.
- **W5. `collateral_damage_protection`** (plan A8 note; drill2–4 carry 20):
  spillover damage in `Combat.resolve`/`CombatApply` currently reads no
  promotion key — reduce spillover damage *taken* by the defender's summed
  protection %, integer truncation (semantics confirmed in 0j). **Files:**
  `src/sim/combat.gd` or `src/sim/combat_apply.gd`. **Tests:**
  `tests/sim/test_combat.gd` (protected vs unprotected spillover, stacking cap).
- **W6. `same_tile_heal` / `adjacent_tile_heal`** (plan A8/D4 notes; woodsman3
  15, medic1 10/medic2 10/medic3 15+15): healing reads only own-unit
  `healing_bonus`. Extend the heal phase: a unit's heal rate gains the best
  `same_tile_heal` among *other* friendly units on its tile and the best
  `adjacent_tile_heal` among friendly units on adjacent tiles (reference medic
  model — best, not summed; confirm in 0j if doubted). **Files:**
  `src/sim/turn_engine.gd` heal phase. **Tests:** `tests/sim/test_turn_engine.gd`
  (medic on tile, medic adjacent, non-stacking).
- **W7. Panzer +50% vs armor** (plan A1 note; magnitude confirmed in 0j): the
  promotion-side `vs_armor` is already live (`Unit.VS_CLASS_KEY`, ambush 25) —
  add the *unit-level* `vs_armor: 50` data key to panzer and read per-unit
  vs-class keys through the same site. **Files:** `data/units.json`,
  `src/sim/unit.gd`/`src/sim/combat.gd`. **Tests:** `tests/sim/test_combat.gd`
  (panzer vs tank vs panzer-vs-infantry control).
- **W8. `unlocks_units` display sweep** (plan B1/D1 note; cosmetic): re-anchor
  each AND-set unit to the correct tech list entries (e.g. bomber appears under
  both Flight and Radio, or under its final gate only — pick one convention and
  state it in `docs/ref/code-layout.md` if it matters). **Files:**
  `data/technologies.json`. **Tests:** `tests/core/test_data_db.gd` cross-check
  that every `unlocks_units` entry's unit actually lists that tech in
  `tech_required`.

## Phase M — blocked mechanics (each a self-contained subsystem; ⓪ = needs its Phase 0 line)

- **M1. Structure obsolescence** ⓪(0e): per-structure `obsolete_tech`; at
  research, the structure's `effects` stop being read (building remains, never
  sold). Single choke point: wherever standing-structure effects are aggregated
  (worker speed, `PolicyEffects`-style scans, W1–W3 sites) filter obsolete
  structures. Then wire the parked **Steam Power +50 worker speed**
  (`worker_speed_modifier` on the tech or a player-level effects read — decide at
  implementation; plan B7 note) *without* double-stacking Hagia Sophia, which
  obsoletes at the same tech. **Files:** `data/structures.json`,
  `data/technologies.json`, `src/sim/turn_engine.gd`, `src/core/data_db.gd`
  validation. **Tests:** `tests/sim/test_policy_effects.gd` (Hagia Sophia stops at
  Steam Power; net worker speed unchanged across the transition),
  `test_data_db.gd` shape.
- **M2. Culture%-slider happiness** ⓪(0a): cathedral-tier buildings grant
  happiness scaled by the culture allocation rate; ends the A2 stand-in that left
  cathedrals culture-only (flat happy 0). **Files:** `src/sim/turn_engine.gd`
  (`_update_contentment`), `data/structures.json` (key per 0a). **Tests:**
  `test_settlement.gd` (0%/50% slider cases, truncation).
- **M3. Air interception** ⓪(0b): make `intercept_bonus` (10/20) and ace
  `evasion_chance` (25) live per the sourced model; rolls through `gs.rng` in
  pipeline order. **Files:** `src/sim/combat.gd`, `src/api/sim_facade.gd` (air
  mission command path), `src/sim/combat_apply.gd`. **Tests:**
  `tests/sim/test_combat.gd` (intercepted/evaded/clean cases, deterministic
  seeds).
- **M4. Spaceship part counts + arrival delay** ⓪(0d): wire the dead
  `count_needed` (casing ×5, thrusters ×5, engines ×2 — 16 parts total, plan A10
  note) into the space-race win: per-part-type tallies replace the flat
  `stages_required: 7` stage count (duplicate parts of a filled type no longer
  advance the race), and completion starts the sourced arrival-delay countdown
  stretched by the finally-read `victory_delay_scale`. Save-format note: the
  per-alliance stage tally becomes a per-type dict — int-coerce keys on
  deserialize. **Files:** `src/sim/win_conditions.gd`, `src/sim/projects.gd`,
  `data/win_conditions.json`. **Tests:** `tests/sim/test_win_conditions.gd`
  (per-type fill, duplicate-part no-op, delay countdown, pace stretch),
  integration playthrough gate.
- **M5. Gold-hurry retune** (documented — §15.2/§29.8; no Phase 0): 3 gold per
  hammer of remaining cost, available **always** (drop the Universal Suffrage
  gate), keep `new_hurry_modifier` +50%; decide at implementation whether the
  flat 5-turn rush anger survives (reference gold hurry has **no** anger — adopt
  reference: none). **Files:** `src/api/sim_facade.gd` (`_cmd_rush_production`),
  `data/constants.json`, `data/policies.json` (retire the gate flag if unused
  elsewhere). **Tests:** `tests/sim/test_settlement.gd` (cost math), AI solvency
  reads unaffected (`tests/api/test_player_ai.gd`).
- **M6. Unit capture** ⓪(0i, optional adoption): non-combat units are captured,
  not killed, when their tile is taken; then ship the C8 unit-capture
  war-weariness weights (2/1). **Files:** `src/sim/combat_apply.gd`,
  `data/constants.json`. **Tests:** `tests/sim/test_combat.gd` (worker captured,
  ownership flip, weariness weights).
- **M7. Military academy not-city-buildable** (documented — plan A2 note; no
  Phase 0): remove it from the city build list; it remains constructible only via
  the Great General `build_military_academy` action (the generic
  `build_<structure_id>` verb already exists). **Files:**
  `data/structures.json` (a `not_buildable`/`gp_only` flag), `src/api/
  sim_facade.gd` SET_PRODUCTION validation, `src/core/data_db.gd`. **Tests:**
  `tests/api/test_sim_facade.gd` (queue rejected), `tests/sim/
  test_great_people.gd` (GP build still works).

## Phase R — reference model adoptions (gameplay/save-format changes; version-bump review at the end of the phase)

- **R1. Settler food-box build** ⓪(0c): settlers/workers consume the city's food
  surplus as production (reference cost model; settler `cost` returns to the
  reference value with food contribution), growth pauses while training.
  Save-format: production-queue entries unchanged, but settlement growth state
  interacts — full determinism pass required. **Files:**
  `src/sim/turn_engine.gd` (`_settlement_growth`/production), `data/units.json`,
  `data/constants.json`. **Tests:** `test_settlement.gd` (food-to-hammers cases,
  growth freeze), integration playthrough, save/load determinism midgame.
- **R2. Per-player GP counter** ⓪(0f): the GP-point pool and threshold move from
  per-settlement to per-player (`Player`), threshold escalating per GP born
  (shipped `gp_threshold_base`/`gp_threshold_increase_percent`). Save-format:
  new `Player` fields, migrate/ignore old per-settlement counters on load —
  **major version bump candidate**. **Files:** `src/sim/great_people.gd`,
  `src/sim/player.gd`, `src/sim/settlement.gd`, `src/sim/game_state.gd`
  (serialize). **Tests:** `tests/sim/test_great_people.gd` rewrite of threshold
  cases; save/load roundtrip with int-coercion.
- **R3. Free settled specialists + citizen auto-assignment** ⓪(0g): settled
  specialists stop consuming a population worker slot, and excess citizens
  auto-assign as `citizen` specialists (making the shipped +1P citizen row
  live). **Files:** `src/sim/specialists.gd`, `src/sim/settlement.gd`,
  `scenes/screens/city_screen.gd` (slot display). **Tests:**
  `tests/sim/test_specialists.gd`, `tests/scenes/test_city_screen.gd` canary.
- **R4. Military instructor model** ⓪(0h): settled Great General grants +XP to
  units built in the city (replacing the +2P stand-in). **Files:**
  `src/sim/great_people.gd`, `src/sim/turn_engine.gd` (unit-completion XP).
  **Tests:** `tests/sim/test_great_people.gd`.
- **R5. Fractional feature health** (documented — plan A5 note: forest +0.5,
  jungle −0.25, flood plains −0.4; no Phase 0): adopt by scaling city health
  accounting ×100 (integer centi-health, `Fixed`-style; **no floats** — the
  engine invariant stands), features carry `health_delta_centi` (+50/−25/−40),
  display rounds toward zero. **Files:** `src/sim/turn_engine.gd` wellbeing,
  `data/features.json`, `src/world/tile_output.gd`. **Tests:**
  `test_settlement.gd` (rounding at the boundary, three-forest = +1 net).

## Phase T — remaining data retunes (documented; no Phase 0)

- **T1. §29.10 AI handicap columns**: ship `ai_train_percent`,
  `ai_construct_percent`, `ai_unit_cost_percent`, `ai_growth_percent` per
  difficulty (§29.10 table) and read them at the AI's production/upkeep/growth
  sites, narrowing `ai_bonus` to the residual yield scaler (decide at
  implementation whether `ai_bonus` retires entirely — record either way in
  `ai-design.md` §with consent). **Files:** `data/difficulties.json`,
  `src/sim/turn_engine.gd`, `src/api/player_ai.gd`. **Tests:**
  `tests/sim/test_turn_engine.gd`, `tests/api/test_player_ai.gd`.
- **T2. Corporation spread columns** (§29.6 note): adopt spread factor 200 /
  base cost 50 over the Humanish `spread_cost` 200 / `spread_chance_base` 15
  once the semantics are mapped (the two models differ in shape — if they do not
  map 1:1, add a 0-line to the Phase 0 sitting instead of guessing). **Files:**
  `data/econ_orgs.json`, `src/sim/econ_orgs.gd`. **Tests:**
  `tests/sim/test_econ_orgs.gd`.

---

## Sequencing recommendation

1. **Phase W first** (except W7 waits for 0j) — independent, small, each a
   one-sitting item with existing shipped values; burns down the dead-key list.
2. **Phase 0 sitting** — one authorized session capturing 0a–0j into §15/§29.
3. **M1 → M2/M3/M5/M7** (M1 unblocks the Steam Power leftovers; M5/M7 are
   doc-ready any time), then **M4/M6**.
4. **Phase R last** (largest blast radius; R1/R2 touch save format — run the
   full integration gate + midgame save/load determinism after each, version
   review at phase end).
5. **Phase T** whenever convenient after Phase 0 (T1/T2 are data + small reads).

Every item lands via the standard workflow: work-type branch, suites green
(`./run_tests.sh`), doc-tier updates (design docs only with consent), merge to
main.
