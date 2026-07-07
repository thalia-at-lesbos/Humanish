# Design ↔ Implementation Gaps

Places where the documents under `docs/design/` describe behaviour or content
that the current source does **not** implement (or implements differently). This
is a living checklist — when a gap is closed, delete its entry. It is *not* a bug
list; everything here is known, deliberate scope that simply hasn't been built.

Unless noted otherwise, the design docs are treated as the source of truth and the
engine is expected to grow toward them. Findings below were spot-checked against
the source on 2026-06-05; line references drift, so grep before relying on them.

---

## 1. Terminology: design spec vs. data tables

`game-data.md` is written in player-facing design language; the JSON tables and
sim use different identifiers for the same concepts. This is intentional, but
worth stating so the two aren't mistaken for a content gap:

| `game-data.md` term | Data / code term |
|---|---|
| Factions | `societies` (in `leaders_traits.json`) |
| Civics | `policies` (`policies.json`) |
| Religions | `beliefs` (`beliefs.json`) |
| Corporations | `econ_orgs` (`econ_orgs.json`) |

Counts spot-checked and consistent: traits 11, leaders 52, societies 34, the six
win-condition types.

As of 2026-06-05 the remaining content tables (wonders, buildings, resources,
promotions, terrain) have been **reconciled entry-by-entry** against the prose.
Wonders (world + national) match the spec exactly on cost, tech, resource and
headline effect. The few drift items found were corrected (see *Recently
reconciled*). What remains is a set of **deliberate model/representation choices**,
catalogued here so they aren't re-flagged as content gaps:

- **Terrain model.** §11.2 describes Hill/Peak as landform *modifiers* on a base
  terrain; the engine instead carries standalone `hills` (food 1 / prod 2) and
  `mountain` terrains in `terrains.json`. Relatedly, the engine's base Grassland
  is `2/1/0` (it grants +1 base Production) where the §11.1 table lists `2/0/0`,
  and `mountain` is impassable with prod 1 / +50% defence where §11.2 Peak lists
  "—". These are intentional engine values.
- **Resource siting.** §10.2/§10.3 place several luxuries/bonus resources on
  *features* (Dye/Silk on Forest, Spices on Jungle, Sugar/Banana on Flood
  Plains/Jungle) that the engine models separately in `features.json`; the data
  instead attaches those resources to base terrains (grassland/plains/desert).
  Yields, happiness and health all match — only the host tile differs.
- **Specialist slots.** §14.5's per-building slot counts are approximate; the
  `specialist_slots` in `structures.json` are authoritative (e.g. Library/Madrassa
  grant 2 Scientist slots, Market/Forum 2 Merchant slots).
- **Building XP / free-promotion effects are now wired.** The per-building XP keys
  (`land_xp`, `mounted_xp`, `naval_xp`, `archery_xp`, `siege_xp`, `air_xp`,
  `military_xp`, `military_xp_city`, the empire-wide `unit_xp_all_cities`) and
  `free_promotion` / `free_promotion_all` / `heals_units` are read when a unit is
  built (`TurnEngine._structure_unit_xp` / `_grant_free_promotions`) and in the
  garrison heal (`_healing_rate`). Building XP layers on the *policy* key
  `new_unit_xp` and can itself cross a promotion threshold. Covered by
  `tests/sim/test_building_xp.gd`.
- **Minor unmodelled wonder sub-clauses.** A handful of atmospheric secondary
  effects are not represented: Stonehenge "centers world map", the Colosseum's
  culture-rate happiness, Angkor Wat "allows 3 Priest specialists", and the
  religion-building secondary lines on Apostolic Palace / Sistine Chapel. The
  headline effect of every wonder/building is present.

## 2. Policy / civic effects — most now applied; a few remain blocked

`policies.json` matches `game-data.md` §8 (five categories, 26 civics). The
*mechanical* fields were always read (`slider_increment`, `slider_min_research`
→ `sim_facade._cmd_set_sliders`; `transition_turns` → the anarchy interregnum,
ticked in `turn_engine._tick_states`; `anger_modifier` → `_update_contentment`;
`upkeep_modifier` → `_update_treasury`). As of the state-religion feature (§8.1)
the anarchy that `transition_turns` represents has teeth — switching an
established civic (first choice in a category is free; Spiritual is exempt) now
zeroes the player's commerce for its duration, the same shared interregnum a
state-religion switch incurs (`turn_engine._settlement_growth`). As of 2026-06-05 the per-civic `effects`
dictionaries are read too, through the single helper `sim/policy_effects.gd`
(`PolicyEffects.sum_int` / `has_flag`), wired into the relevant sim modules:

- **Happiness / health** (`turn_engine._update_contentment` / `_update_wellbeing`):
  `happiness_per_garrison`, `barracks_happiness`, `happiness_per_forest`,
  `happiness_per_religion`, `happiness_largest_cities`, `war_anger_reduction`,
  `health_empire`.
- **Output** (`_settlement_growth`): `town_production`, `town_commerce`,
  `workshop_production`, `watermill_farm_production`, `windmill_commerce`,
  `capital_commerce`, `capital_production`, `free_specialist_per_city`; and
  `culture_all_cities` in `_settlement_culture`.
- **Production** (`_settlement_production` via `_policy_production_delta`):
  `military_production`, `religious_building_production`,
  `production_per_military_unit`.
- **Research / intel** (`_apply_research` / `_apply_intelligence`):
  `science_per_scientist`, `science_output`, `espionage`.
- **Treasury** (`_update_treasury`): `free_units_per_city`,
  `no_distance_maintenance`.
- **Commands** (`sim_facade`): `can_rush_with_gold` and the bare `rush_by_pop`
  gate the two rush methods in `_cmd_rush_production`; the bare
  `worker_speed_bonus` shortens build time in `_cmd_build_improvement`.
- **Unit/GP** (`_complete_item` / `_special_person_progress`): `new_unit_xp` and
  `state_religion_unit_xp` set a new military unit's starting experience;
  `great_person_rate` scales Great-Person point accrual.
- **Specialists** (`Specialists.slots_for`, via `SimFacade._cmd_assign_specialist`):
  `unlimited_specialists` (Caste System) now lifts the per-type slot ceiling —
  the Phase 2 specialists table (`data/specialists.json`) added `default_slots`
  plus per-structure `specialist_slots`, which the flag overrides to unlimited.

Covered by `tests/sim/test_policy_effects.gd` and `tests/api/test_facade.gd`.

**Still inert — blocked on an unbuilt subsystem, not on the wiring:**

- Emancipation's cross-faction unhappiness is not modelled (the cottage→hamlet→
  village→town upgrading it speeds *is* now modelled — see below;
  `faster_cottage_growth` is wired in `TurnEngine._grow_cottages`).
- `trade_route_per_city` (Free Market) and `no_foreign_trade_routes`
  (Mercantilism) are now wired: cities run trade routes (`TurnEngine._trade_route_commerce`,
  base count `trade_routes_base` default 0, so routes appear only under a granting
  civic), restricted to domestic partners by Mercantilism and never run to a city
  at war. `corporation_maintenance_reduction` stays inert — econ orgs charge a
  per-spread cost rather than ongoing maintenance, so there is nothing to reduce.
- (`can_draft` and `missionary_without_monastery` are now wired — see the draft
  and missionary subsystems below.)

**Now wired by the state-religion feature (§8.1, provisional):** `blocks_nonstate_spread`
(Theocracy) stops non-state religions spreading into a player's cities (`Beliefs.spread_all`),
and `state_religion_unit_xp` (Theocracy) now keys off the player's adopted state religion
rather than any per-city belief. The player-level state religion is set via the
`SET_STATE_RELIGION` command and the Religion advisor screen; it also gates
`requires_state_religion` structure happiness (Cathedrals) and triggers anarchy on a switch.

## 3. UI vocabulary: the spec is a deliberate superset

`user-interface-design.md` §3.1–§3.3 enumerate the full functional command set as a
superset; the *implemented* vocabulary is whatever the `IDs` enums define
(`ControlType`, `UnitCmd`, `UnitMission`, `InterfaceMode`, `WidgetType`,
`PopupType`, `DirtyRegion`).

As of 2026-06-05 the readily-modellable items have been built (see *Recently
reconciled*): the **score-display toggle** and the **religion / corporation /
turn-log / domestic-advisor / victory-progress / options** advisor screens (plus
simple text screens wired for the previously-dangling **finance / military /
espionage / encyclopedia** controls); the **`gift to another player`** unit
command; and the **`sentry`, `heal`, `move-to-unit`, `scout/recon`, `air patrol`,
`sea patrol`** unit missions. Each is a `ControlType` / `UnitCmd` / `UnitMission`
value with a command factory, a `SimFacade` handler, and (for controls) a simple
read-only text screen under `scenes/screens/`.

The remaining spec items are **deliberately deferred**, each blocked on a
subsystem this build does not have:

- **Camera/view modes** (orthographic/flying/top-down/isometric, globe 3D view) —
  a host-renderer concern outside the headless rules layer; intentionally skipped.
- **Hall of fame, game/admin details, world-builder/editor** — need cross-game
  persistence, an admin/host channel, and a full map editor respectively.
- **Session `retire`, `all-chat`, `team-chat`, `free-colony`** — multiplayer chat
  and colony-split subsystems (this build is single-machine hotseat).
- (Espionage verbs `sabotage` / `destroy` / `steal plans` as *unit missions* are now
  built: a spy on a foreign city tile runs any catalogue mission via `SPY_MISSION` /
  `Commands.spy_mission` — see §5.1 and `game-data.md` §25.5 — alongside the
  alliance-scope `ESPIONAGE_MISSION` screen path.)
- (`SPREAD_BELIEF` is now built: a missionary unit on a city tile spreads the
  player's religion via the `SPREAD_BELIEF` command — see the missionary
  subsystem.)
- (`DRAFT` is now built: a city can conscript a military unit from its population
  when the `can_draft` civic is active — `Commands.draft` /
  `SimFacade._cmd_draft`. City screen exposes a Draft Unit button.)
- **`establish trade route`** — trade routes now run automatically each turn
  (civic-granted via `TurnEngine._trade_route_commerce`), but there is no
  explicit player-issued "establish route" command or UI widget; this entry
  tracks the player-action form still absent.

(For reference, `LOAD_UNIT` / `UNLOAD_UNIT` and `UnitCmd.AUTOMATE` /
`STOP_AUTOMATE` already existed; `SPREAD_BELIEF`, `ESPIONAGE_MISSION`, and
Great-Person verbs via `GP_ACTION` cover other spec "missions" through their own
paths.)

## 4. Pipeline phase stubs

Two `TurnEngine` phases are intentional no-ops awaiting their subsystem:

- `IDs.Phase.PLAYER_BOOKKEEPING` — `pass` (placeholder for AI planning).
- `IDs.Phase.WORLD_ASSIGN_SITES` — `pass` (special-site assignment unimplemented).

(For the record, two phases previously labelled "stub" in `code-layout.md` are in
fact implemented and have been corrected there: `WORLD_TILE_UPKEEP` →
`_tile_upkeep` charges improvement maintenance, and `WORLD_ASSEMBLY` →
`Assembly.world_tick` runs the §7.2 world-assembly lifecycle.)

**Diplomatic win condition (interim, rework pending).** The crude
`_resolve_assembly` population poll and its `gs.diplomatic_votes` /
`WinConditions._diplomatic` consumer were **removed** — they handed the game to
whoever momentarily governed a 67% population majority, which one early city
trivially does (an all-AI smoke won by turn 2). Diplomatic victory now flows
**solely** through the §7.2 assembly's UN election
(`Assembly.apply_effect "diplomatic_victory"`). `WinConditions._check_one`'s
`"diplomatic"` case is now an explicit no-op. A full diplomatic-win rework is
slated next; the design docs (`game-rules.md` §10/§16, `game-data.md` §18) still
describe the old poll and need updating as part of that rework.

---

## 5. Reference-parity data domains — the last gaps

The seven reference-parity domains formerly tracked in `game-data.md` §20 have all
been **promoted to first-class data tables and wired into the engine** (now
`game-data.md` §22–§28). Three are at full reference parity (Specialists §22,
Corporations §23, Score victory §27) and need nothing further. Of the four that
shipped a working slice, espionage (§5.1), goody huts (was §5.3), map
start-fairness (§5.2) and diplomacy denial reasons (§5.4) have all since closed —
no reference-parity data domain remains open.

Measured against `humanish-full-docs/generic/` (the reference data set), the
shortfalls were catalogue depth, not missing machinery.

### 5.1 Espionage missions — CLOSED (18/18 mission types; `game-data.md` §25)

The mission framework (cost curve, interception, per-effect target gates, the
espionage screen), the **thirteen active missions** (each with a `case` in
`SimFacade._espionage_apply`, a gate in `_mission_target_valid`, and tests in
`tests/sim/test_intelligence.gd`), and **spy-unit-on-tile execution** (`game-data.md`
§25.5) are complete, as before.

**The five passive, information-gathering missions are now built** (`game-data.md`
§25.6) — but as **standing EP thresholds, not runnable operations**, which dissolved
the "required subsystem" this entry used to block on. Instead of a serialized
per-player knowledge store with expiry rules, each passive record (`kind: "passive"`
in `data/espionage_missions.json`) reveals its intel *while* the viewer's banked EP
against the target alliance meets a threshold (base × the §25.2 EP-advantage curve ×
a capital-to-target distance surcharge). What a player knows is a pure function of
current EP: nothing new is serialized, save/load and `state_hash` are untouched, and
dropping below the threshold re-hides the intel. `see_demographics` /
`see_research` / `detect_missions` (attribution of incoming missions) are
alliance-scope; `investigate_city` / `city_visibility` are per-city. The espionage
advisor lists every rival civ/leader and each of their cities, with locked rows shown
as "have/need EP" progress.

The **information fog** the passive missions lift is likewise built: a rival city's
readout is restricted to its defensive posture (defence %, siege HP, garrison,
defensive structures — `SimFacade.city_intel_lines`) until `investigate_city` is met;
foreign spies are invisible (not rendered, absent from the tile readout, ignored by
`Pathfinding._has_enemy`, cannot be attacked, and an intercepted tile mission now
destroys the spy); `city_visibility` merges live sight into `player_visible_tiles`.
`PlayerAI` plays spies (§B7 `_manage_spy`: build to `ai_spy_count`, infiltrate the
nearest rival city, run the highest-priority affordable mission).

Not modelled (acceptable rest-gap): the full `get_state()` is still exposed to every
facade client, so the fog is honoured by the UI read paths rather than enforced by a
filtered state snapshot — a determined netcode client could still read hidden fields.
Promoting the fog into a filtered per-player state view remains possible later
without data changes.

### 5.2 Map start-fairness `normalize*` — CLOSED (9/9 steps; `game-data.md` §28)

`MapGen.normalize_starts` now implements all nine reference steps plus
`BonusBalancer`: step 1 repositions weak starts on a yield/fresh-water/resource
plot score, step 8 upgrades poor terrain in the wider start radius, and step 9
tops up below-par starts with extra resources and discovery sites. See the
2026-07-07 entry under "Recently reconciled" and `game-data.md` §28 for the
constants.

### 5.4 Diplomacy denial reasons — CLOSED (`game-data.md` §26)

The denial-reason layer now ships: a `denial_reasons` table in
`data/diplomacy.json`, `Diplomacy.evaluate_deal` returning a structured reason id
on refusal (the `deal_accept_min_attitude` gate is now one reason among five), and
the reason surfaced to the proposer as a notification and on the rival's row of
the diplomacy screen. See the 2026-07-07 entry under "Recently reconciled" and
`game-data.md` §26 for the reason table.

---

## Recently reconciled

- **2026-07-07** — Allocation sliders became three adjustable rates (§6.2): the
  player now sets **science (research), culture, espionage (intel)** via +/−
  buttons in 10% steps, and **economy (finance) is the derived remainder**
  (100 − the three), shown read-only. `Commands.set_sliders(player_id,
  research, culture, intel)` carries only the three rates;
  `SimFacade._cmd_set_sliders` validates each ≥ 0, sum ≤ 100, the policy
  `slider_increment` multiples and `slider_min_research` floor, then derives
  `slider_finance` — the four `Player` fields and the save format are
  unchanged (they still always sum to 100), and the
  `TurnEngine._update_treasury` insolvency path still mutates
  research/finance directly. `scenes/hud/slider_panel.gd` rewritten from four
  `HSlider`s to three label+−/+ rows plus an `Economy: NN%` label
  (`FOCUS_NONE` preserved); `SliderMath`
  (`src/api/slider_math.gd`) and its test deleted (no rebalancing needed —
  the remainder absorbs every change). `PlayerAI.manage_economy` submits the
  same solvency/focus finance tilt through the new signature.
  `game-rules.md` §4.3/§6.2, `user-interface-design.md`, `docs/user/`, and
  the in-game encyclopedia reworded. Tests: `tests/sim/test_policies.gd`
  (validation matrix incl. sum > 100 / negative / derived remainder),
  `tests/scenes/test_slider_panel.gd` (rewritten).
- **2026-07-07** — Insolvency never sells structures (§6.1): decided that all
  buildings and their invested costs are always retained — prolonged insolvency
  may only disband units. `TurnEngine._sell_or_disband` (newest-structure sale
  for a 25% cost refund, then unit disbanding) became
  `_disband_for_insolvency` (units only); with no units left the research
  slider is still forced down and the treasury clamps at 0, unchanged.
  `game-rules.md` §6.1 and `game-data.md` (`insolvent_turns`) reworded to
  units-only. Tests: `tests/sim/test_economy.gd`
  (`test_insolvency_never_sells_structures`,
  `test_insolvency_with_no_units_clamps_treasury_at_zero`).
- **2026-07-07** — Diplomacy denial-reason layer completed (§5.4): trade refusals
  now carry a structured reason. `Diplomacy.evaluate_deal` (sim) owns the one
  deal-evaluation path — the decision is the unchanged pair of gates (net value
  ≥ 0 AND attitude ≥ `deal_accept_min_attitude`; `deal_net_value` moved from
  `PlayerAI` into `Diplomacy`) and returns "" to accept or the most specific of
  five reason ids: `no_trade_with_warring_party` (proposer's alliance at war with
  ours, no peace clause), `worst_enemy` (proposer is the lowest-scoring met rival
  at the furious level — `Diplomacy.is_worst_enemy`, a pure attitude derivation),
  `attitude_too_low`, `tech_refusal` (the offer pries techs off us and still
  values negative), `insufficient_value`. Display text lives in the new
  `denial_reasons` table in `data/diplomacy.json` (validated by
  `DataDB._validate_diplomacy_refs`; read via `Diplomacy.denial_text`). The
  reason rides `Commands.reject_trade(…, reason)`; `_cmd_reject_trade` remembers
  it in the serialized `gs.deal_denials` (proposer → rejector → {reason, turn},
  int-key coerced on load) and queues a `deal_rejected` event that
  `_drain_deal_events` surfaces as a notification naming the rejector and the
  reason text; the diplomacy screen shows each rival's last denial on its row.
  Gates *not* added (no modelled input / would change decisions the design
  doesn't call for): "too advanced" (refusing tech trades to the tech leader)
  and "you are at war with our friend" (no attitude factor models a rival
  fighting one's ally, so a refusal never stems from it). Tests: evaluation +
  reason-id assertions per gate, denial-table coverage, reject-command
  recording, drain notification, and int-key save/load in
  `tests/sim/test_diplomacy.gd`; AI end-to-end reason in
  `tests/api/test_player_ai.gd`; screen surfacing in
  `tests/scenes/test_diplomacy_screen.gd`.
- **2026-07-07** — Map start-fairness `normalize*` completed (§5.2): all 9
  reference steps now run in `MapGen.normalize_starts`. Step 1
  (`normalizeStartingPlotLocations`): `_normalize_reposition_starts` scores each
  start plot (`_start_plot_score`: terrain base yields in `score_radius`, food
  weighted, + per-resource and fresh-water bonuses) and shifts a start to the
  best plot within `reposition_radius` when it wins by `reposition_min_gain`,
  never below the layout's minimum pairwise spacing and never outside per-map
  `start_bounds`; purely score-driven, no RNG draw. Step 8
  (`normalizeAddGoodTerrain`): `_normalize_add_good_terrain` upgrades up to
  `good_terrain_quota` resource-free poor tiles at distance 2..`good_terrain_radius`
  one step toward grass/plains (snow→tundra, tundra→grassland, desert→plains).
  Step 9 (`normalizeAddExtras`): `_normalize_add_extras` gives starts scoring
  more than `extras_tolerance` below the richest extra food/luxury resources
  within `extras_radius`, then up to `extras_huts` extra discovery sites (within
  `extras_hut_radius`, kept `goody_hut_min_distance_from_start` clear of every
  start) if still short — the §24 "extras step" hut scatter. Steps 8/9 draw from
  the shared map RNG in fixed start order; twelve `start_normalize_*` constants
  added to `data/constants.json`, all overridable per-map via the `normalize`
  block. Same-seed reproducibility + behavioural tests per step in
  `tests/world/test_map_gen.gd`.
- **2026-07-07** — Goody-hut reward catalogue completed (was §5.3): all 12
  `game-data.md` §24 records now ship in `data/goodies.json` (`gold_large`,
  `settler`, `worker`, `scout`, `ambush_strong` added), plus the §24 parameter
  refinements (`map` offset/reveal_chance, `heal` damage_prereq, `ambush` raider
  spawns, `bad: true` re-roll rules with recon immunity — implemented as
  eligibility zero-weighting in `Events.exploration_reward`). Ambush raiders
  spawn via `WildForces._spawn_wild_unit` (owner −2) and are surfaced through
  `unit_created`. Every difficulty in `data/difficulties.json` carries the full
  12-column `goody_weights` table (each summing to 100). "Wild forces disabled"
  is interpreted as the era's `no_wild_units` quiet phase (no game-level toggle
  exists).
- **2026-06-07** — Conscription / draft implemented (`026dc9d`): `DRAFT` command
  (`Commands.draft` / `SimFacade._cmd_draft`) conscripts a military unit from a
  city's population when `can_draft` is active; city screen exposes a Draft Unit
  button alongside the Hurry (gold/pop) buttons. §3 updated accordingly.
- **2026-06-07** — Resources generated and rendered on tiles (`946e099`):
  `MapGen` now places resource tokens during world generation; `WorldView`
  renders a coloured dot per resource type visible to the current player. This
  closes the presentation gap for §10 resource tiles.
- **2026-06-07** — Gold/treasury shown in HUD turn bar (`db1c80b`):
  `turn_score_bar.gd` now displays the current player's treasury balance
  alongside turn number and score, making fiscal state visible at a glance.
- **2026-06-07** — Encyclopedia replaced with interactive tabbed reference
  (`277dd66`): the flat `OPEN_ENCYCLOPEDIA` text screen became a full tabbed
  browser (`encyclopedia_screen.gd`) covering units, structures, techs,
  promotions, resources, and terrains — data pulled live from `DataDB`.

- **2026-06-05** — Built the readily-modellable §3 UI vocabulary. New
  `IDs.ControlType` values (`TOGGLE_SCORE`, `OPEN_RELIGION`, `OPEN_CORPORATION`,
  `OPEN_TURN_LOG`, `OPEN_DOMESTIC_ADVISOR`, `OPEN_VICTORY_PROGRESS`,
  `OPEN_OPTIONS`) plus simple read-only text screens (`scenes/screens/`, a shared
  `info_screen.gd` scaffold), also wiring the previously-dangling
  finance/military/espionage/encyclopedia controls to screens in `main.gd`. New
  `UnitCmd.GIFT` (+ `CommandType.UNIT_GIFT`) transfers unit ownership; new
  `UnitMission` values `SENTRY` / `HEAL` / `MOVE_TO_UNIT` / `RECON` /
  `AIR_PATROL` / `SEA_PATROL` (+ matching `CommandType`s, `Commands` factories,
  `_cmd_mission` / `_cmd_unit_command` handlers, and `Unit` stance flags
  `is_sentry` / `is_patrolling` / `is_healing`, serialized). Covered by
  `tests/api/test_ui_contract.gd` and `tests/scenes/test_info_screens.gd`. The
  remaining §3 items are deferred on unbuilt subsystems (camera modes,
  persistence/editor/MP, unit-mission espionage, establish-trade-route). Draft
  was subsequently implemented (see 2026-06-07 entry).
- **2026-06-05** — Full content reconciliation of the §1 tables (wonders,
  buildings, resources, promotions, terrain), entry-by-entry against
  `game-data.md`. Wonders matched exactly. Drift corrected in `structures.json`:
  Granary now requires Pottery (was unconstrained); Library cost 80→90 and gained
  its documented +2 Culture; Market cost 100→150; Walls cost 60→50; Barracks's
  undesigned `disciplined`-promotion + heal effect replaced with the spec's
  `land_xp: 3`. Removed the undesigned `disciplined` promotion from
  `promotions.json` (absent from §13, zero code refs). Corrected a prose typo in
  `game-data.md` §10.3 (Pig improvement Farm→Pasture, matching the engine and the
  other pasture animals). Remaining differences are deliberate model choices, now
  catalogued under §1. Full suite green (unit + integration playthrough).
- **2026-06-05** — Most civic `effects` are now applied (§2). Added
  `sim/policy_effects.gd` as the single reader and wired the headline gameplay
  bonuses into `TurnEngine` and `SimFacade`; `tests/sim/test_policy_effects.gd`
  covers each. Only effects blocked on an unbuilt subsystem (specialist slots,
  cottage growth, trade routes, draft/missionary/religion-spread) remain inert —
  see the list under §2.
- **2026-06-05** — `policies.json` brought in line with `game-data.md` §8: removed
  the undocumented 6th `civic` category (communism / anarcho-communism /
  anarcho-capitalism / fascism) and the stray `monarchy` government policy, and
  re-gated Republic on Code of Laws. The orphaned `slider_max_research` cap (only
  Communism used it) was removed from `sim_facade` and its test. See §2 for the
  effects still pending.
