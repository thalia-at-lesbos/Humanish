# Missing Engine Features

An audit of the implementation in `src/` against the rules specified in
[`docs/game-rules.md`](./game-rules.md). The engine's **structure** is faithful —
pipeline order (§3), integer-only math, the single shared RNG, data-driven tables,
and the per-phase hook seam are all correctly in place. What follows are the
**behavioral** rules that are stubbed, declared-but-never-invoked, or missing
entirely.

> Legend: **Stub** = phase runs but does nothing · **Dead** = code exists, no caller ·
> **Unhandled** = command/case declared in an enum/data with no handler · **Missing** = no code.

---

## 1. Pipeline phases that are stubbed (`turn_engine.gd`)

| Spec | Location | State |
|---|---|---|
| §3 world-step 3 — per-tile upkeep | `_tile_upkeep()` | Stub (`pass`) |
| §3 world-step 6 — assign special institutional sites | `world_step` case 6 | Stub (`pass`) |
| §3 world-step 7 — resolve assembly/voting bodies | `world_step` case 7 | Stub (`pass`) |
| §3 player-step 1 — AI pre-turn planning | `PLAYER_BOOKKEEPING` | Stub (expected — no AI yet) |

## 2. Mechanics implemented but **never invoked** (Dead)

The module exists but nothing in the pipeline or facade calls it, so the mechanic
can never occur:

- **Belief founding** (§8) — `Beliefs.try_found()` has zero callers. `spread_all()`
  *is* called each settlement step, but with no belief ever founded it is a permanent
  no-op. Missionary spread, state-adopted belief benefits, and principal-site finance
  are absent.
- **Economic organizations** (§8) — `EconOrgs.found()` and `EconOrgs.spread_all()`
  have zero callers (only `get_output_delta` is wired into growth). Orgs can never be
  founded or spread.
- **Exploration rewards** (§9) — `Events.exploration_reward()` is never called; there
  are no discovery sites or investigate action.
- **Scripted/random events** (§9) — `Events.process_player_events()` is a hard-coded
  empty stub (`# TODO: load event definitions`).
- **Regions / supply groups** (§1.1) — `Regions.compute_*` exist but are never
  consumed by any rule (no resource distribution or trade across supply groups).

## 3. Commands declared but unhandled

`IDs.CommandType` defines these, but `SimFacade.apply_command()` has no case for them
(they silently return `false`):

- `PROPOSE_TRADE`, `ACCEPT_TRADE`, `REJECT_TRADE` (§7) — no `Commands.*` factories
  either. `_resolve_trades()` only *expires* pending trades; it never executes a
  trade's effects (gold/resource/tech/settlement transfer, peace, maps, passage).
- `SPREAD_BELIEF` (§5.6, §8 missionary) — no factory, no handler.
- `JOIN_SETTLEMENT` (§5.6 join as specialist) — no factory, no handler.
- `ASSIGN_WORKERS`, `PILLAGE` (top-level) — enum entries with no factory/handler
  (pillage exists only as `MISSION_PILLAGE`).

## 4. Missing win condition

- **Diplomatic victory** (§10) is in the spec table, the `WinType` enum, *and*
  `data/win_conditions.json` (`"type": "diplomatic"`), but `WinConditions._check_one()`
  has no `"diplomatic"` case — it falls through to `-1`. Combined with the assembly
  stub (§3 step 7), diplomatic victory is unreachable.

## 5. Combat & units — computed-but-unapplied / missing

- **Flanking** (§5.4) — `Combat.resolve()` computes `flanking_damage`, but
  `_apply_combat_result()` only applies `spillover_damage`. Flanking is discarded.
- **Promotions on XP threshold** (§5.5) — combat awards XP, but nothing auto-grants a
  promotion when a threshold is crossed. Promotion only happens via the manual
  `UNIT_PROMOTE` command, with no prereq/threshold validation.
- **Healing** (§5.6) — no per-turn healing logic anywhere (location- or
  promotion-based). Damaged units never recover.
- **Entrenchment growth** (§5.3/§5.6) — `entrenchment` / `stationary_turns` are only
  ever *reset to 0* on move; never incremented for stationary units, and the
  entrenchment cap is unused. The defensive bonus can never accrue.
- **Zones of control** (§5.2) — pathfinding blocks moving *through* an enemy tile but
  implements no ZoC (adjacent-enemy movement arrest).
- **Transport / embarkation** (§5.2) — `Unit.cargo` / `transported_by` exist but are
  unused; `_domain_legal` forbids land units on water, so they can never cross deep
  water. Transport capacity is dead data.
- **Air units** (§5.2) — domain `"air"` is "go anywhere" with no range, basing,
  interception, or air-strike mission. `MISSION_AIRLIFT` just teleports.
- **8-direction movement** (§1.2) — pathfinding/move-cost use `neighbours4` only;
  diagonal/8-compass movement isn't supported in pathing.
- No implementation for: bombarding settlement *defenses*, blockading, scouting,
  interception, area-effect strikes.

## 6. Players / economy / research

- **Alliance shared research** (§6.3) — `_advance_alliances()` accumulates
  `shared_research_store`, but `_apply_research()` researches per-player and never
  reads that pool. Research is not actually shared.
- **Finance supplementing research** (§6.3) — not implemented.
- **Settlement upkeep scaling** (§6.1) — upkeep counts only unit + per-structure
  upkeep. Scaling by distance-from-capital, number of settlements, and size, plus
  policy upkeep, is absent.
- **Insolvency extreme** (§6.1) — `_update_treasury` only forces the research slider
  down; it never sells/disbands structures or units.
- **Slider constraints** (§3.3/§6.2) — `_cmd_set_sliders` checks only sum==100 and ≥0.
  Policy-enforced increments, enforced channel minimums, and max-research caps are
  not enforced.
- **Specialists** (§6.5) — settlements have a `specialists` dict, but no command
  populates it (`CHANGE_SPECIALIST` widget exists but no command/handler).
  `_auto_assign_workers` only assigns tiles, so `_special_person_progress` always
  sums 0 points.
- **Special persons** (§4 step, §6.5, §5.6) — `_special_person_progress` accumulates
  points and bumps the threshold, but never produces a special person or applies any
  effect (settle bonus, build wonder, grant tech, trigger celebration age, seed econ
  org). The entire payoff is missing.

## 7. War, diplomacy, espionage

- **War success / war-fatigue** (§3 player-step 8, §7) — `Alliance.war_fatigue` is
  declared and serialized but never written or applied. War success is not tracked,
  so war-fatigue never feeds discontent.
- **Subordination / tributaries** (§7) — `is_subordinate_to` / `tributaries` fields
  exist with no logic (no tribute, shared wars, or war-loss subordination).
- **Intelligence missions** (§7) — `_apply_intelligence` only accumulates points;
  there are no covert-mission commands (steal tech, sabotage, incite unrest) or
  interception logic.

## 8. Settlement models — acknowledged simplifications

- **Contentment** (§4.5) — only size comfort, structure happiness, policy anger, rush
  penalty. Missing: garrison, dominant belief, cultural pressure, belief conflict,
  conscription, war-fatigue, assembly-defiance, subjugation/intel discontent,
  celebration, alliance/leader bonuses.
- **Wellbeing** (§4.6) — only population + structure health deltas. Missing: fresh
  water, sanitation, healthful/unhealthful resources, terrain/feature contributions.
- **Culture** (§4.7/§6.2) — `_settlement_culture` adds the **whole** `output_commerce`
  to culture rather than the culture slice of the slider split, bypassing the economic
  split's culture channel.
- **Production** (§4.4) — surplus-sustenance→production conversion and
  trait/policy/resource production modifiers aren't applied (only pace scaling).

## 9. Minor / data

- **Score** (§10) — `Scoring` weights population, land, and techs but omits **wonders**,
  which the spec lists.
- **Pollution sources** (§11) — accumulation covers population + structures but not
  area-effect strikes (unimplemented); flooding of low tiles isn't modeled (only
  feature-strip and terrain→barren chain).

---

## Prioritized checklist

Ordered by **impact ÷ effort**. The first tier are correctness bugs / one-liners where
the supporting code already exists; later tiers are whole systems.

### Tier 0 — Quick wins (code already exists; wire it up / fix the bug) — ✅ DONE

Resolved on branch `dev-missing-features`; covered by
`tests/test_tier0_missing_features.gd` (10 tests).

- [x] Add the `"diplomatic"` case to `WinConditions._check_one()`, reading an
      assembly tally from new `GameState.diplomatic_votes` (serialized). Returns no
      winner until the assembly phase casts votes. *(§10)*
- [x] Apply `flanking_damage` in `SimFacade._apply_combat_result()`, mirroring the
      existing `spillover_damage` loop. *(§5.4)*
- [x] Grow `entrenchment` / `stationary_turns` (up to the data cap) for units that
      neither moved nor attacked, in the player-step movement-reset loop. *(§5.3)*
- [x] Count wonders in `Scoring.compute_all()` via a data-driven `is_wonder` structure
      flag and `score_weight_wonder` constant. *(§10)*
- [x] Fix the withdrawal line in `combat.gd` (`max(1, a_health - a_dmg + a_dmg)` was a
      no-op); the attacker now retreats without taking the fatal hit. *(§5.4)*

### Tier 1 — High-impact systems with partial scaffolding — ✅ DONE

Resolved on branch `dev-missing-features`; covered by
`tests/test_tier1_missing_features.gd` (15 tests).

- [x] **Per-turn healing** (§5.6) — `TurnEngine._heal_unit()` heals stationary units by
      location (settlement / friendly / allied / neutral / hostile rates from data) plus
      promotion `healing_bonus`, capped at full; never on a move/fight turn.
- [x] **Auto-promotion on XP threshold** (§5.5) — `SimFacade._award_promotions()` levels a
      survivor up per `experience_thresholds` and grants the first eligible promotion
      (prereqs + `applies_to` class/domain validated).
- [x] **Alliance shared research** (§6.3) — multi-member alliances pool a donated share of
      each member's research in `_advance_alliances()`; `_apply_research()` draws each
      member's per-capita share. Solo alliances pool nothing, so per-player behavior is
      unchanged (documented simplification: mild over-count of a member's own donation).
- [x] **Belief founding** (§8) — `player_step` calls `Beliefs.try_found()`; founding now
      requires a settlement to host the holy site, and an adopted belief feeds
      contentment (`happiness_bonus`) and wellbeing (`health_bonus`).
- [x] **Special-person production** (§6.5) — `_apply_special_person()` fires when points
      cross the rising threshold: grants the in-progress technology, or settles for gold
      when none. Tracked via new `Settlement.special_persons_produced` (serialized).

### Tier 2 — New subsystems

- [ ] **Trades** (§7) — `PROPOSE_/ACCEPT_/REJECT_TRADE` factories + handlers; execute
      trade effects in `_resolve_trades()`.
- [ ] **War success → war-fatigue → discontent** (§3.8, §7, §4.5) — track war success
      from combat, accumulate fatigue, feed contentment.
- [ ] **Specialists** (§6.5) — `CHANGE_SPECIALIST` command + handler so specialist
      output and special-person points actually accrue.
- [ ] **Economic organizations** (§8) — invoke `EconOrgs.found()` (via special person)
      and `EconOrgs.spread_all()` in the pipeline.
- [ ] **Intelligence missions** (§7) — covert-mission commands with cost/interception.
- [ ] **Transport / embarkation** (§5.2) — use `cargo` / `transported_by` so land units
      can cross deep water.

### Tier 3 — Breadth & depth (larger or lower-frequency)

- [ ] **Assemblies / voting bodies** (§3.7) — unblocks diplomatic victory.
- [ ] **Scripted/random events + exploration rewards** (§9) — load event content; wire
      `exploration_reward()` to an investigate action.
- [ ] **Zones of control & 8-direction movement** (§1.2, §5.2).
- [ ] **Air units** — range, basing, interception, air strikes (§5.2).
- [ ] **Subordination / tributaries** (§7).
- [ ] **Upkeep scaling** (distance/count/size) + **insolvency** sell/disband (§6.1).
- [ ] **Slider policy constraints** (increments, minimums, research cap) (§6.2).
- [ ] **Contentment & wellbeing breadth** (§4.5/§4.6) — remaining sentiment sources.
- [ ] **Culture channel fix** — use the culture slice of the split, not raw commerce
      (§4.7/§6.2).
- [ ] **Per-tile upkeep** (§3.3) and **pollution** breadth (area strikes, flooding)
      (§11).
