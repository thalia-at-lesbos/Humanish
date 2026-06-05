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
win-condition types. The remaining content tables (wonders, buildings, resources,
promotions, terrain) were **not** exhaustively audited entry-by-entry against the
prose — only structurally. A full content reconciliation is still outstanding.

## 2. Policy / civic effects are defined but not applied

`policies.json` now matches `game-data.md` §8 (five categories, 26 civics), but
only the *mechanical* policy fields are read by the sim:

- **Wired:** `slider_increment`, `slider_min_research` (→ `sim_facade._cmd_set_sliders`),
  `transition_turns` (→ anarchy tick in `turn_engine._tick_states`),
  `anger_modifier` (→ `_update_contentment`), `upkeep_modifier` (→ `_update_treasury`).
- **Inert (no reader anywhere in `src/`):** every per-civic `effects` dictionary —
  e.g. `happiness_per_garrison`, `science_per_scientist`, `can_rush_with_gold`,
  `military_production`, `war_anger_reduction`, `capital_commerce`,
  `unlimited_specialists`, `great_person_rate`, `culture_all_cities`, `can_draft`,
  trade-route bonuses — plus the bare flags `rush_by_pop` (Slavery) and
  `worker_speed_bonus` (Serfdom).

So selecting a civic currently changes upkeep, anarchy length, anger and slider
shape, but none of its headline gameplay effect from the design table. Wiring each
`effects` key into the relevant sim module (`TurnEngine`, `Combat`, `Settlement`)
is the open work.

## 3. UI vocabulary: the spec is a deliberate superset

`user-interface-design.md` §3.1–§3.3 enumerate the full functional command set as a
superset; the *implemented* vocabulary is whatever the `IDs` enums define
(`ControlType`, `UnitCmd`, `UnitMission`, `InterfaceMode`, `WidgetType`,
`PopupType`, `DirtyRegion`). Items present in the spec with **no** enum value,
command, or handler in the current build include (verified absent in `src/`, not
exhaustive):

- **Controls (§3.1):** camera/view modes (orthographic/flying/top-down/isometric,
  globe 3D view), score-display toggle, and several advisor/info screens named in
  the spec (religion, corporation, turn log, domestic advisor, victory progress,
  hall of fame, game/admin details, options, world-builder). Session controls
  `retire`, `all-chat`, `team-chat`, `free-colony` are also unmodelled.
- **Unit commands (§3.2):** `gift to another player` has no command. (Load/unload
  *do* exist — `CommandType.LOAD_UNIT` / `UNLOAD_UNIT`; automation exists as
  `UnitCmd.AUTOMATE` / `STOP_AUTOMATE`.)
- **Unit missions (§3.3):** `air patrol`, `sea patrol`, `sentry`, `heal`,
  `move-to-unit`, `scout/recon`, and the distinct espionage verbs `sabotage` /
  `destroy` / `steal plans` have no `UnitMission` value. (Many other spec
  "missions" *are* implemented through other paths — `SPREAD_BELIEF`,
  `ESPIONAGE_MISSION`, and Great-Person verbs via `GP_ACTION` — so they are not
  gaps.) `draft` (Nationhood) and `establish trade route` are likewise unbuilt,
  matching their inert policy effects in §2.

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

- **2026-06-05** — `policies.json` brought in line with `game-data.md` §8: removed
  the undocumented 6th `civic` category (communism / anarcho-communism /
  anarcho-capitalism / fascism) and the stray `monarchy` government policy, and
  re-gated Republic on Code of Laws. The orphaned `slider_max_research` cap (only
  Communism used it) was removed from `sim_facade` and its test. See §2 for the
  effects still pending.
