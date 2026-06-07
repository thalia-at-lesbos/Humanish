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

- ~~**Belief founding** (§8)~~ — resolved in Tier 1 (`dev-missing-features`):
  `player_step` now calls `Beliefs.try_found()`; missionary spread wired via
  `SPREAD_BELIEF` command (`1014892`).
- ~~**Economic organizations** (§8)~~ — resolved in Tier 2 (`dev-missing-features`):
  `EconOrgs.spread_all()` runs each world step; `_apply_special_person()` seeds
  an unfounded org via `EconOrgs.found()`.
- **Exploration rewards** (§9) — `Events.exploration_reward()` is never called; there
  are no discovery sites or investigate action.
- **Scripted/random events** (§9) — `Events.process_player_events()` is a hard-coded
  empty stub (`# TODO: load event definitions`).
- **Regions / supply groups** (§1.1) — `Regions.compute_*` exist but are never
  consumed by any rule (no resource distribution or trade across supply groups).

## 3. Commands declared but unhandled

`IDs.CommandType` defines these, but `SimFacade.apply_command()` has no case for them
(they silently return `false`):

- ~~`PROPOSE_TRADE`, `ACCEPT_TRADE`, `REJECT_TRADE` (§7)~~ — resolved in Tier 2
  (`dev-missing-features`): factories added, handlers wired, `_execute_trade()`
  moves gold + techs and applies peace clause.
- ~~`SPREAD_BELIEF` (§5.6, §8 missionary)~~ — resolved: factory + handler wired
  (`1014892`); missionary unit on a city tile spreads the player's religion.
- `JOIN_SETTLEMENT` (§5.6 join as specialist) — no factory, no handler.
- `ASSIGN_WORKERS`, `PILLAGE` (top-level) — enum entries with no factory/handler
  (pillage exists only as `MISSION_PILLAGE`).

## 4. Missing win condition

- **Diplomatic victory** (§10) is in the spec table, the `WinType` enum, *and*
  `data/win_conditions.json` (`"type": "diplomatic"`), but `WinConditions._check_one()`
  has no `"diplomatic"` case — it falls through to `-1`. Combined with the assembly
  stub (§3 step 7), diplomatic victory is unreachable.

## 5. Combat & units — computed-but-unapplied / missing

> Most of this section's original gaps are now resolved (see the Tier checklists
> below): **flanking** (§5.4), **auto-promotion on XP threshold** (§5.5), **per-turn
> healing** (§5.6), **entrenchment growth** (§5.3), **zones of control** &
> **8-direction movement** (§1.2/§5.2), **transport / embarkation** (§5.2), **air
> strikes & interception** with range (§5.2), **scouting/recon** (§9), and the
> **class-versus-class / settlement & cultural defence** strength modifiers (§5.3).

What remains:

- **Residual §5.3 strength modifiers** — `effective_strength()` applies promotions
  (incl. `vs_<class>`, `vs_fortified`, `attack_vs_settlement`,
  `defense_in_settlement`), terrain/feature defence, entrenchment, the city's
  structure + cultural defence, and now the terrain-keyed `defense_on_hills`
  promotion (Guerrilla line). `Combat.resolve()` now also applies the
  **river-crossing** and **amphibious attack penalties** (constants existed but
  were unused), waived by the Amphibious promotion / `amphibious` unit tag. Still
  unwired: domain-specific modifiers and self-sacrifice.
- **Air basing** (§5.2) — air strikes and interception work, but there is no
  carrier/airfield basing requirement; `MISSION_AIRLIFT` teleports within range.
- ~~**Blockading** (§5.6)~~ — done: a hostile naval unit within `blockade_range`
  of a coastal city cuts its commerce by `blockade_commerce_penalty`
  (`TurnEngine._blockade_penalty`, applied in `_settlement_growth`).
- **Bombarding settlement *defenses*** (§5.6) — city defence is folded into siege HP
  (`city_max_health`); there is no separate, recoverable "defence" stat to bombard
  down before an assault.

## 6. Players / economy / research

- **Alliance shared research** (§6.3) — `_advance_alliances()` accumulates
  `shared_research_store`, but `_apply_research()` researches per-player and never
  reads that pool. Research is not actually shared.
- **Finance supplementing research** (§6.3) — done: when the research slider is 0,
  `_apply_research()` supplements the project with `finance_research_supplement_pct`
  of the player's finance income (without double-deducting from treasury).
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

### Tier 2 — New subsystems — ✅ DONE

Resolved on branch `dev-missing-features`; covered by
`tests/test_tier2_missing_features.gd` (18 tests).

- [x] **Trades** (§7) — `propose/accept/reject_trade` factories + `SimFacade`
      handlers; `_execute_trade()` moves gold + techs and applies a peace clause.
      Trades still expire via `_resolve_trades()` in the world step.
- [x] **War-fatigue → discontent** (§4.5, §7) — `_accrue_war_fatigue()` charges the
      losing unit's alliance on each combat; `_update_contentment()` converts pooled
      fatigue into anger (`war_fatigue_anger_divisor`).
- [x] **Specialists** (§6.5) — `assign_specialist` command (population-capped); each
      specialist yields `specialist_commerce` in `_settlement_growth` and is reserved
      out of tile workers in `_auto_assign_workers`. Feeds special-person points.
- [x] **Economic organizations** (§8) — `EconOrgs.spread_all()` runs each world step;
      `_apply_special_person()` seeds an unfounded org via `EconOrgs.found()`.
- [x] **Intelligence missions** (§7) — `espionage_mission` command spends
      `intel_mission_cost` points with an `intel_interception_chance`; `steal_tech`
      and `sabotage` missions implemented.
- [x] **Transport / embarkation** (§5.2) — `load_unit`/`unload_unit` commands use
      `cargo`/`transported_by` (capacity-checked); carried units ride with their
      transport and are excluded from the independent moving stack.

### Tier 3 — Breadth & depth (larger or lower-frequency) — ✅ DONE

Resolved on branch `dev-missing-features`, one commit per item; covered by
`tests/test_tier3_missing_features.gd` (31 tests).

- [x] **Assemblies / voting bodies** (§3.7) — `_resolve_assembly()` tallies votes by
      governed population each world step, unblocking the diplomatic win.
- [x] **Scripted events + exploration rewards** (§9) — `data/events.json` loads into
      DataDB; `process_player_events()` fires turn/tech-gated once-only events;
      entering a `Tile.has_discovery` site triggers `exploration_reward()`.
- [x] **Zones of control & 8-direction movement** (§1.2, §5.2) — pathfinding uses
      `neighbours8`; entering a tile adjacent to a hostile unit ends movement.
- [x] **Air units** (§5.2) — data-driven `fighter`; range-limited air strikes that
      don't advance, with interceptors; range-limited airlift.
- [x] **Subordination / tributaries** (§7) — `set_subordination` command + world-step
      `_collect_tribute()`; tributaries inherit the overlord's wars.
- [x] **Upkeep scaling + insolvency** (§6.1) — settlement upkeep scales by
      distance-from-capital and size, less policy modifier; insolvency sells/disbands
      after `insolvency_grace_turns`.
- [x] **Slider policy constraints** (§6.2) — `_cmd_set_sliders` enforces policy
      increment, min research, and an optional max-research cap.
- [x] **Contentment & wellbeing breadth** (§4.5/§4.6) — garrison comfort, overcrowding
      anger, fresh-water wellbeing.
- [x] **Culture channel fix** (§4.7/§6.2) — culture accrues from the culture slice of
      the split, not raw commerce.
- [x] **Per-tile upkeep + pollution flooding** (§3.3, §11) — improvement maintenance in
      `_tile_upkeep()`; polluted flat tiles beside water flood to coast.

> Remaining known simplification: area-effect strikes (a pollution/contamination
> source) are not modelled, as no area-strike action exists yet.

### Tier 4 — Combat strength modifiers — ✅ DONE

Resolved on branch `feature/combat-class-settlement-modifiers`; covered by
`tests/sim/test_combat.gd` (6 new tests).

- [x] **Class-versus-class modifiers** (§5.3) — `Unit.effective_strength()` now reads
      its `versus_class` argument (previously ignored), applying a promotion's
      `vs_<class>` bonus via the `Unit.VS_CLASS_KEY` map (melee/mounted/gunpowder →
      naval=`vs_ships`, air=`vs_fighters`), plus `vs_fortified` when the opponent is
      entrenched. Makes `shock`/`pinch`/`formation`/`boarding`/`dogfighting`/`barrage`
      live.
- [x] **Settlement attack/defence + cultural defence** (§5.3) — combat at a city tile
      (detected via `GameState.get_settlement_at`) now grants the attacker
      `attack_vs_settlement` and the defender `defense_in_settlement` plus the city's
      structure `defence_bonus` + `cultural_defence_bonus` (summed by
      `Combat._settlement_defence`). Replaces the dead `terrain.is_settlement` branch
      (a key that was never set); `_assault_city`/`WildAI` pass `at_settlement` too.

### Tier 5 — Nuclear weapons & radiation (§5.7) — ✅ DONE

Resolved on branch `dev-nuclear-and-gaps`; covered by `tests/sim/test_nuclear.gd`
(20 tests). Previously the §5.7 data scaffolding existed (`tactical_nuke`/`icbm`,
the `nuke`/`one_use`/`global_range` tags, Manhattan Project, Bomb Shelter, the
Fallout feature, the `no_nuclear` resolution) with **zero** behaviour in code.

- [x] **Launch** (§5.7) — new `NUCLEAR_STRIKE` command + `_cmd_nuclear_strike`
      handler: requires the `nuke` tag and globally-enabled nukes (Manhattan
      Project's `enable_nukes_global`), enforces range (`air_range`; `global_range`
      reaches any tile), consumes the missile on launch, and is forbidden while the
      `no_nuclear` standing effect is in force.
- [x] **Interception** — an enemy `anti_air` unit (SAM / Missile Cruiser) within
      `nuke_interception_range` rolls `nuke_interception_chance`; a hit aborts the
      strike with no effect (rng drawn only when an interceptor exists).
- [x] **Blast** (`sim/nuclear.gd`, pure static like `CombatApply`) — area effect over
      a Chebyshev `blast_radius`: softens every unit (all owners, floored at 1 HP),
      strips a settlement's population / stored production / siege integrity without
      destroying it, and strips tile improvements & vegetation. Bomb Shelter applies
      `nuke_damage_reduction`.
- [x] **Fallout** — the blast and a one-tile ring gain the Fallout feature on a
      per-tile `nuke_fallout_chance` / `nuke_fallout_ring_chance` roll (allowed
      landforms only); the `MISSION_CLEAN_FALLOUT` worker action scrubs it.
- [x] **Meltdown** — `Nuclear.meltdown_tick()` runs in the world-step environmental
      phase: each Nuclear Plant has a `nuclear_meltdown_chance` of contaminating its
      surroundings.
- [x] **Consequences** — the attacker's alliance accrues `nuke_war_fatigue` against
      each victim and declares war on them. Strike results surface via the new
      `nuclear_detonated` signal.

> Provisional: every magnitude is a placeholder (`data/constants.json` `nuke_*` /
> `nuclear_meltdown_chance`, per-unit `blast_radius`) pending tuning against the
> reference game. The assembly-defiance *penalty* for defying `no_nuclear` is moot
> here because launching is simply rejected.
