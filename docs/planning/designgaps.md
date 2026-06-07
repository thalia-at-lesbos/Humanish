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

Covered by `tests/sim/test_policy_effects.gd`.

**Still inert — blocked on an unbuilt subsystem, not on the wiring:**

- `unlimited_specialists` (Caste System) — the sim caps specialists only by
  population; there is no per-building specialist *slot* ceiling to lift, so the
  flag has nothing to relax until a slot system exists.
- Emancipation's cross-faction unhappiness is not modelled (the cottage→hamlet→
  village→town upgrading it speeds *is* now modelled — see below;
  `faster_cottage_growth` is wired in `TurnEngine._grow_cottages`).
- `trade_route_per_city`, `no_foreign_trade_routes` (Free Market / Mercantilism)
  and `corporation_maintenance_reduction` — trade routes are unbuilt (§3), and
  econ orgs charge a per-spread cost rather than ongoing maintenance.
- `can_draft` (Nationhood), `missionary_without_monastery` (Organized Religion)
  — tied to the unbuilt draft / missionary mechanics noted in §3.

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
- **Espionage verbs `sabotage` / `destroy` / `steal plans` as *unit missions*** —
  the mechanic exists at alliance scope via `ESPIONAGE_MISSION`; a spy-unit-on-tile
  mission model is unbuilt.
- **`draft` (Nationhood) and `establish trade route`** — unbuilt mechanics already
  tracked in §2 (inert policy effects).

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
`_resolve_assembly` tallies population-weighted `gs.diplomatic_votes`.)

---

## Recently reconciled

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
  persistence/editor/MP, unit-mission espionage, draft/trade-route).
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
