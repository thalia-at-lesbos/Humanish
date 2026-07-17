# Direct Reference Gaps — plan to reach data & rules parity

Status: **in progress** — sequencing step 1 (bug fixes + A12) and Phase B items
B1–B3 done 2026-07-08; the whole A phase (A1–A13) done 2026-07-11; the D4 content
cut done 2026-07-11; the D4 promotion-additions half + the A8 leftovers done
2026-07-11 (values adopted from the reference under a user-authorized sourcing
session — see A8/D4 notes); C1–C3 (economy trio) done 2026-07-12; B4/B5, C7,
C5 (+ D3 missiles-cannot-defend), and B6 done 2026-07-17. Date: 2026-07-07.

**REMAINING (handoff for the next session):** B7 (worker-speed % modifiers —
prereq for C6), C6 (serfdom & emancipation effects), C4 + D2 together (culture-
level city defence keys off the reference geometric border curve — see the C4
entry's dependency note), C8 (optional, low priority), then D1 (tech-graph
parity) last. Also parked along the way, each recorded in its item's note:
per-city `science_bonus` wiring (A2 note), three_gorges_dam `unhealthy_global`
+ hippodrome `happiness_with_horse` dead keys (A2), panzer's missing +50% vs
armor (A1), settler food-box build model (A1), gold-rush 3-gold/hammer retune +
Slavery's Bronze-Working tech gate (C2 note), culture%-slider happiness for
cathedrals (A2), the dead promotion keys awaiting subsystems (A8/D4 notes), and
projects `count_needed` stage-model wiring (A10 note). The reference-XML
sourcing authorization was **session-scoped and has ended** — future sessions
source values from these docs only.

**DECISIONS (user, 2026-07-08) — the step-2 review is settled with one blanket rule:
everything adopts the reference value/model, and ALL Humanish-only content is
removed.** Concretely: every `[decide]` flag below resolves to "adopt reference";
D1 = adopt the reference tech graph; D2 = adopt the reference geometric border
curve; D3 = the intentional-deviation register is dissolved (nothing is an
intentional deviation — every listed divergence gets scheduled and fixed); D4 = cut
all Humanish-only content (see D4 for the enumerated list and migration notes).
A fresh session can proceed without further user input: the A-phase data passes are
unblocked, then C-phase, then D1/D2/D4 as work items.

Sources of truth for this plan:
- `docs/planning/reference-parity-audit.md` — the raw discrepancy audit (per-unit/per-table
  diffs against the reference XML). Referenced throughout as "audit §N".
- `docs/design/game-rules.md` §15 — specs (with reference values) for every mechanic
  the engine lacks. All marked unimplemented.
- `docs/design/game-data.md` §29 — the companion data tables (missing units/projects,
  culture levels, pace/handicap extras, corporation outputs, goody rosters, hurry
  types, civic effects, retune globals).

Reading order for an implementer: this file (what/why/when) → game-rules §15 (rule
spec) → game-data §29 (numbers) → audit (per-entry target values).

Conventions: every work item lists **files** and **tests**. New tests follow the
per-subsystem layout (`tests/sim/test_<module>.gd` etc.); data-shape rules are
enforced in `tests/core/test_data_db.gd`. All engine math stays integer; every roll
through `gs.rng`; every new constant in `data/*.json` (never in code).

---

## Phase A — data-only retunes (no schema or engine change)

Pure JSON edits toward reference values. Each can ship independently; the integration
playthrough gate plus the listed suites cover regressions. **Balance-sensitive items
are flagged `[decide]` — ALL RESOLVED 2026-07-08 to "adopt the reference value"
(see DECISIONS above); the inline `[decide→RESOLVED]` marks record each outcome.**

- **A1. Unit stats** (`data/units.json`; tests `tests/sim/test_combat.gd`,
  `test_unit*.gd`): apply audit §2 per-unit values — strength/cost/moves/withdrawal/
  first-strikes/cargo/air-range. **DONE 2026-07-08** (ca79f8a): all remaining §2
  value diffs applied (72 units) — naval rescale reverted, settler/worker/musketeer/
  fast_worker moves, air ranges, sub/missile cargo, first strikes, cho_ko_nu/
  numidian_cavalry withdrawal, stale `special` text fixed; pinned panther numbers in
  `test_combat.gd` recalibrated (str 3 → 2). Left unchanged (audit "?" or model
  notes): settler cost 100 (reference 0 = food-box model), icbm `air_range` 999
  (both mean unlimited), tactical_nuke/panzer/tank resource "?" entries. Follow-up
  for C/D sittings: panzer's only perk was the 3rd move — reference's +50% vs armor
  is unmodelled, so it is now a plain Tank clone. Sub-decisions:
  - ~~`[decide→RESOLVED: revert to reference]` The across-the-board naval rescale
    (frigate 18 vs 8 …) — revert every naval strength to the reference value.~~
    **DONE 2026-07-08** (ca79f8a).
  - ~~Withdrawal chances on the mounted line (chariot 10, horse archer 20, cuirassier
    15, cavalry/cossack 30, gunship 25, conquistador 15, immortal 10, war chariot 10,
    keshik 20, camel archer 15, submarine line 50) look accidentally dropped — restore.~~
    **DONE 2026-07-08** (d933a61, all 13 values restored).
  - ~~`guided_missile` strength 0 vs reference 40 — verify missile combat path, then fix.~~
    **DONE 2026-07-08** (d933a61): strength 40; verification found the `one_use` tag was
    read nowhere — the air-bombard path now consumes one-use weapons on strike or
    interception (`SimFacade._consume_one_use`). ~~Follow-up for the D3/C5 sitting:
    `Stack.get_defender` has no missile/air exclusion, so a garrisoned guided missile
    can be selected as a city's best defender at 40 (reference missiles cannot defend).~~
    **Resolved 2026-07-17 (C5/D3 sitting):** missiles are excluded from
    `Stack.get_defender` and stranded missiles die on capture — see the D3 item.
  - ~~settler/worker moves 1 → 2, fast worker 2 → 3, musketeer 1 → 2 (reference).~~
    **DONE 2026-07-08** (ca79f8a).
- **A2. Building/wonder values** (`data/structures.json`; test `test_settlement*.gd`):
  audit §4 list — costs (barracks 50, cothon 100, forum 150, ger 60, hagia sophia 500
  + tech theology, madrassa 90, sacrificial altar 90, ziggurat 90, dun 50 + tech
  masonry, walls tech masonry, space elevator tech robotics), negative health on
  industrial buildings (forge/factory/drydock/airport/mint/assembly plant −1,
  industrial park −2), happiness rows (market/forum/odeon/ball court/hippodrome,
  cathedral-tier), granary health 0. The `science%` rows flagged "unverified" in the
  audit need the reference's `CommerceModifiers` read before changing.
  **DONE 2026-07-08** (6608796): all §4 straight value diffs applied — costs/techs/
  happiness/granary as listed; laboratory/research_institute −1 health too (audit
  row). Wiring find: `effects.unhealthy` was a *dead key* (read nowhere — the engine
  reads `health_penalty`), so factory/industrial_park/coal_plant/shale_plant/
  ironworks silently had no health malus; all converted to `health_penalty`.
  Left unchanged: `science%` rows (library 25/seowon 35/academy 50 — CommerceModifiers
  unverified; **verified 2026-07-11**, feature-parity-economy-unblock: the
  reference's research commerce-modifiers are library/university/observatory/
  laboratory 25, academy 50, seowon 35 — all six match the shipped values, now
  pinned in `test_data_db.gd`. Wiring note: `science_bonus` is a **dead key** in
  the sim — research income is the commerce split plus specialist/policy adders,
  with no per-city research% multiplier applied anywhere; only the PlayerAI
  economy-structure heuristic and the encyclopedia read it. Needs its own wiring
  sitting), military_academy cost 300 (reference "not city-buildable" is a
  mechanic change, not a value diff), three_gorges_dam's still-dead
  `unhealthy_global: 2` (global semantics ≠ per-city `health_penalty`; needs its own
  wiring), hippodrome's still-dead `happiness_with_horse: 1`. Cathedral-tier flat
  happy → 0 leaves cathedrals culture-only until the reference's culture%-slider
  happiness mechanic exists. One recalibration: the `test_state_religion.gd`
  cathedral-gate test now injects its own `happiness_bonus`.
- **A3. Difficulty table** (`data/difficulties.json`; tests `tests/sim/test_wild*.gd`,
  `test_turn_engine.gd`): audit §5 — research % (prince 110 …), free wins 5/4/3/2/1/0,
  `[decide→RESOLVED: adopt reference]` health/happiness columns (reference never
  goes negative for the human),
  `ai_research_per_era` sign/semantics (reference: AI research gets *cheaper* per era
  at high difficulty — align the sign or rename the field), `[decide→RESOLVED]`
  water-raider density back to reference (undo the ÷4), `combat_bonus_vs_wild`
  semantics → reference model (modifier on the barbarian side).
  **DONE 2026-07-08** (a3d1078): all §5 columns to reference; sign flipped in the
  `Research._effective_cost` read (×(100+per_era), negative = cheaper); dead
  `combat_bonus_vs_wild` replaced by `wild_combat_modifier` (barbarian-side percent,
  0 at every level) newly wired in `Combat.resolve` with human-opponent gating;
  `wild_water_per_unit` fallback 2000→500. New semantics pinned in `test_research`/
  `test_combat`; one wellbeing pin recalibrated (prince health floor 2).
- **A4. World sizes** (`data/world_sizes.json`): `[decide→RESOLVED: adopt reference]`
  grids, research % 100–150, players_suggested 2/3/5/7/9/11.
  **DONE 2026-07-08** (a3d1078): all three columns to reference (standard now 84×52
  at 130% research); research-cost chain tests recalibrated (default "standard"
  gs now scales ×130). ~~Follow-up for a design-doc sitting: game-data §15.8/§15.9
  tables and ai-design §4's `combat_bonus_vs_wild` mention still show the old
  values/name (docs/design/ needs user consent).~~ **Addressed 2026-07-11**
  (design-doc value-sync pass, user-consented).
- **A5. Terrain & features** (`data/terrains.json`, `features.json`; tests
  `tests/world/*`, `tests/sim/test_settlement*`): `[decide→RESOLVED: adopt reference
  on all]` grassland 2/1/0 → 2/0/0 (largest single economic change — expect broad
  seeded-test recalibration); hills 1/2/0 → net 1/1/0-equivalent; mountains become
  unworkable (reference); river commerce on desert/tundra (+1C) — add
  `river_commerce_bonus: 1` to both; flood-plains defence −33 → 0.
  **DONE 2026-07-08** (221871c): all five diffs applied. Wiring finds:
  `river_commerce_bonus` was a *dead key* (read nowhere — grass/plains carried it
  with no river commerce actually paid); `TileOutput.compute` gained a `has_river`
  param fed from `WorldMap.tile_has_river` at all four call sites. Mountains got an
  `unworkable` terrain flag read by new `TileOutput.workable()`, gated in
  auto-assign, the SET_TILE_WORKED command, and the city-screen grid. 9 new pinning
  tests; **zero seeded recalibration needed** — the fixture maps' expectations
  survived the grassland hammer removal. Left unchanged: fractional feature health
  (forest +0.5 / jungle −0.25 / flood-plains −0.4) — needs a fractional-health
  accumulation model, not a value edit; hills river commerce (reference grass-hill
  river gets +1C via underlying terrain — our hills are their own terrain, no
  underlying grass/plains to read). Specialists/GP rows of audit §8 are A7.
- **A6. Improvements** (`data/improvements.json`): town 1/1/4 → 0/0/4 base
  (reference; its +1P/+1F come from civics), workshop −1F/+1P at base
  `[decide→RESOLVED: adopt reference]`.
  **DONE 2026-07-08** (2b6ec0f): town 0/0/4, workshop −1F/+1P. An extra village
  1F/3C → 0/0/3 edit shipped in the same commit was **reverted 2026-07-11**
  (bugfix-village-yield-doc-source): it was sourced from the local reference XML,
  which was off-limits per the then-current source rule — the audit flags only
  town, and game-data's Improvements table documented Village as +3C **+1F**.
  **Re-verified and re-applied 2026-07-11** (feature-parity-economy-unblock,
  user-authorized source): the reference's cottage line is pure commerce
  1/2/3/4 with zero food/production at every tier, so village is 0F/3C after
  all; the game-data Improvements table row was the artifact and is corrected
  (village +3C; town +4C with the +1F/+1P note moved to its civics). Pinned in
  `test_tile_output.gd` (`test_cottage_line_base_yields_match_reference`).
  Data-only:
  `TileOutput` already takes negative deltas and clamps per-tile totals ≥ 0.
  Civics effects untouched (town_production/town_commerce already exist; the rest
  is C6). Left unchanged: the flat-vs-conditional improvement yield *model*
  (audit §1.5 [schema] — resource-less pasture/camp/quarry etc. keep their flat
  deltas), roads' commerce, and all rows the audit does not flag.
- **A7. Specialists & settled GPs** (`data/specialists.json`; test
  `test_great_people.gd`): citizen +1 production; artist 4 culture (+1 research);
  spy 4 esp (+1 research); settled greats per audit §8 (great_priest +2P/+5 gold …).
  `[decide→RESOLVED: adopt reference]` GPP scaling ×3 with the reference
  `gp_threshold` progression.
  **DONE 2026-07-08** (2b6ec0f): all rows applied — citizen +1P, artist 4Cu+1R,
  spy 4E+1R, gp_points 3 on all seven working specialists, settled-great yields
  per audit §8. Wiring find: the `great_*` records were *dead data* — both settle
  sites (`GreatPeople._act_join_city`, events SGP verb) collapsed settled GPs
  into their working type; both now add the `great_*` record (so settled greats
  stop banking GPP, per reference). Threshold progression adopted: base 100,
  +50%-of-base per birth, accelerating ×(births/10+1) (reference
  GREAT_PEOPLE_THRESHOLD/_INCREASE; was hardcoded ×1.25 compounding) — constants
  `gp_threshold_base`/`gp_threshold_increase_percent` in `data/constants.json`.
  Left unchanged / model notes: settled great_general keeps +2P (reference
  military-instructor +XP model unbuilt); the GP counter stays per-settlement
  (reference: per-player); settled specialists still consume a population worker
  slot (reference: free); the working `citizen` record has no assignment path
  (reference "excess citizens become citizen specialists" mechanic unbuilt), so
  its +1P is parity data only. **Spy row verified 2026-07-11**
  (feature-parity-economy-unblock): the reference specialist table's spy carries
  research 1 / espionage 4 — exactly the shipped 4E+1R; pinned in
  `test_data_db.gd`.
- **A8. Promotions values** (`data/promotions.json`): combat6 +25; flanking2 +20;
  interception 10/20; guerrilla3 +50 withdrawal; woodsman3 +2 FS & same-tile heal;
  drill line per game-data §29.3 (needs B2 for chance-FS/collateral fields).
  **DONE 2026-07-11**: all documented §9 value diffs applied — combat6 25,
  flanking2 20, interception1/2 10/20, guerrilla3 +50 withdrawal, woodsman3
  first_strikes_bonus 2, drill line per §29.3 literally (drill1 stripped to no
  combat fields, drill2 +1 FS, drill3 protection-only, drill4 +2 FS + the dead
  invented `hit_damage_reduction: 50` replaced; drill2–4 carry
  `collateral_damage_protection: 20`). Dead-key notes: `collateral_damage_
  protection` has **no engine reader** (spillover damage reads no promotion
  key) and `intercept_bonus` was already dead (no air-interception combat
  model) — both are correct parity data awaiting mechanics. Recalibrated
  `test_drill_promotions_grant_first_strikes` (drill1 no longer grants a
  strike); new pin `test_promotion_roster_carries_a8_reference_values`
  (`tests/sim/test_combat.gd`). ~~**Not applied — values not documented, needs a
  design-doc sitting** (user rule 2026-07-11: source values only from
  audit/§29/game-rules, never the local reference XML): woodsman3's same-tile
  heal *magnitude*; the drill line's chance-first-strike values (§29.3 marks
  drill1 "verify before port"; game-rules §15.5 promises the chance numbers
  with A8 but no doc records them — so B2's promotion
  `chance_first_strikes_bonus` field still has **no data carrier**); and the
  **entire D4 promotions fold-in** (see D4).~~ **LEFTOVERS DONE 2026-07-11**
  (promotions-unblock pass; values adopted from the reference under a
  user-authorized sourcing session, recorded in game-data §13/§29.3): drill1
  `chance_first_strikes_bonus: 1`, drill3 `: 2` — B2's field now has live
  shipped carriers (pin `test_drill_line_chance_first_strikes_live`); drill4
  regained its +10 vs mounted (live — `vs_mounted` was already wired in
  `Unit.VS_CLASS_KEY`); woodsman3 `same_tile_heal: 15`; medic
  line retuned to the reference tile model — medic1 `same_tile_heal: 10`,
  medic2 `adjacent_tile_heal: 10` (their old `adjacent_heal_bonus`/
  `adjacent_heal_in_enemy_territory` keys were dead *and* semantically wrong).
  **Dead-key note:** `same_tile_heal`/`adjacent_tile_heal` have no engine
  reader (unit healing reads only own-unit `healing_bonus`) — correct parity
  data awaiting a stack/adjacent-heal mechanic. Roster pin:
  `test_promotion_roster_carries_reference_additions` (`test_combat.gd`).
  The D4 promotions fold-in is also done — see D4.
- **A9. Traits & leaders** (`data/leaders_traits.json`; test `test_data_db.gd`):
  imperialistic GG 50 → 100; creative drop `library` from its building list;
  charismatic-25%-XP model `[decide→RESOLVED: adopt reference model]`; Hammurabi
  aggressive+organized, Brennus
  charismatic+spiritual, Gilgamesh creative+protective. (The free-vs-double-speed
  model itself is B4.)
  **DONE 2026-07-11** (8d6cf6d): all four applied. Findings: the trait's
  `great_general_rate_bonus` is a *dead key* — the live read is the
  `imperialistic_great_general_pct` constant (both now 100, code fallback too);
  charismatic's old `xp_bonus`/`promotion_cost_reduction` keys were **also dead**
  (read nowhere — charismatic had no wired effect beyond +1 happy), replaced by
  `promotion_xp_reduction: 25` newly read in `CombatApply.award_promotions`
  (threshold × (100−reduction)/100, truncating integer scale, summed across
  traits, clamped ≤100 — the single threshold-read site, so combat and
  new-unit-XP promotion paths both get it). Pins:
  `test_traits_and_leaders_carry_a9_reference_values` (`test_data_db.gd`),
  `test_charismatic_lowers_promotion_xp_needed` (`test_combat.gd`); the
  imperialistic GG test recalibrated (15 XP × 2 = 30). Babylonian society
  blurb retuned off "ordered defence" (protective gone).
- **A10. Projects/spaceship** (`data/projects.json`; test `test_win_conditions*.gd`):
  costs 1000–2000 per game-data §29.2/audit §4; counts casing ×5, thrusters ×5,
  engines ×2; Apollo 1600, Manhattan 1500 (they may stay buildings — the cost is the
  parity item).
  **DONE 2026-07-11** (8d6cf6d): counts (casing/thrusters ×5, engines ×2) and
  Apollo 1600 / Manhattan 1500 applied (both stay buildings). Findings for a
  later wiring sitting: `count_needed` is a **dead field** (read nowhere) — the
  space-race win reads `win_conditions.json` `stages_required: 7` and every
  completed project increments one alliance stage tally, so part *counts* have
  no engine effect and duplicate parts of one type count as distinct stages.
  Pin: `test_projects_carry_a10_reference_counts_and_costs`
  (`test_win_conditions.gd`).
  **Leftover CLOSED 2026-07-11** (feature-parity-economy-unblock): the per-part
  costs, previously held back as "not documented", were read from the reference
  and adopted — casing 250→1200, cockpit 400→1000, docking bay 250→2000, engine
  600→1600, life support 400→1000, stasis chamber 300→1200, thrusters 250→1200.
  game-data §17 table (and the §16 "all 9 parts" → 16, Apollo 1000→1600 /
  Manhattan 1250→1500 wonder rows) corrected with user consent; the
  `test_win_conditions.gd` pin now covers the per-part costs too.
- **A11. Globals** (`data/constants.json`): growth 12+8·pop → 20+2·pop
  `[decide→RESOLVED: adopt]`; `min_settlement_distance` 3 → 2
  `[decide→RESOLVED: adopt]`; heal rates → 20/15/10/5 (city/friendly/
  neutral/enemy) `[decide→RESOLVED: adopt, dropping our settlement-30/hostile-0
  extras]`; XP-per-combat cap
  10 (new constant — currently uncapped below 100); `experience_vs_wild_cap` 20 → 10;
  ~~`animal_xp_lifetime_cap` 10 → 5 **and fix the cap-of-10 claim in game-rules
  §9.3 — the reference value is 5**~~ **DONE 2026-07-08** (2093ccb, constant + code
  fallback + doc together); max withdrawal clamp 90 (new).
  **DONE 2026-07-11** (f6e4e20): all remaining items applied. Growth 20+2·pop;
  min distance 2; heal keys retuned in place (`healing_in_settlement` 20,
  `healing_friendly_territory` 15, `healing_neutral_territory` 10,
  `healing_hostile_territory` 5; `healing_allied_territory` — a tier with no
  reference analogue — aligned to friendly at 15); new
  `experience_per_combat_cap: 10` clamps both sides' per-fight XP in
  `Combat.resolve` (the min-5 clamp still applies below it); new
  `withdrawal_chance_max: 90` clamps total unit+promotion withdrawal there too.
  Finding: `max_xp_from_barbarians: 10` was a *dead duplicate* of
  `experience_vs_wild_cap` (read nowhere) — retired. Code fallbacks updated in
  step. Pins: `test_globals_carry_a11_reference_values` (`test_data_db.gd`),
  `test_xp_per_combat_capped_at_ten` / `test_withdrawal_chance_clamped_at_max`
  (`test_combat.gd`). One recalibration: `test_unhealthy_city_grows_slower` now
  starts both cities below the lower threshold (growth resets the food box to
  50% of threshold, which erased the measured difference). ~~Note for a
  design-doc sitting: game-rules §4.2/§5.6 and game-data still cite the old
  growth curve, min distance 3, and the five-tier heal table.~~ **Addressed
  2026-07-11** (design-doc value-sync pass; game-data §15.7 was already current).
- **A12. Goody weights** (`data/goodies.json`): ~~give `settler`/`worker` the
  per-difficulty weights from game-data §29.7 (per-difficulty weighting already
  supported per §24). Tests: `tests/sim/test_goodies*.gd`.~~ **VERIFIED ALREADY
  SHIPPED 2026-07-08**: `difficulties.json` `goody_weights` columns already carry the
  §24-normalised settler/worker weights (10/10/5/0/0/0/0/0/0); the base `weight: 0`
  in goodies.json is the documented "difficulty-enabled only" convention. Goody data
  tests live in `tests/core/test_data_db.gd` (no `test_goodies*.gd` exists). No change.
- **A13. Tech-tree eras/costs** (`data/technologies.json`): future_tech 10000;
  calendar+iron_working → classical, genetics+stealth → future
  `[decide→RESOLVED: adopt]` (interacts with era-driven systems: wild spawns,
  `Eras.player_era`). Full rewiring is D1.
  **DONE 2026-07-11** (f6e4e20): the era/cost pass is done — all four era
  moves + future_tech 10000 applied; the AND/OR prereq-graph rewiring remains
  **D1** (untouched here). No seeded recalibration turned out to be needed:
  the era-driven suites (`test_eras`, `test_wild_*`, playthroughs) stayed
  green because no test pinned these four techs' eras. Pin:
  `test_techs_carry_a13_reference_eras_and_cost` (`test_data_db.gd`).

## Phase B — schema extensions (DataDB + sim reads; small, mechanical)

- **B1. Compound unit prereqs** (game-rules §15.12) — **DONE 2026-07-08** (f77a574):
  new pure-static `src/core/unit_prereqs.gd` (`UnitPrereqs.tech_ok`/`resource_ok`) is
  the one reader, shared by the city-screen offer list, `PlayerAI`, draft, upgrade,
  `Eras.era_of_unit`, and wild spawn tables; availability side =
  `EconOrgs.accessible_resources` (made public). Audit-§2 tech/resource sets applied
  in full — **nothing blocked on D1** (all referenced techs/resources exist).
  Findings: `resource_required` was previously *never enforced anywhere* (display
  only), and `UNIT_UPGRADE` had no prereq gate at all — both gates are new behaviour.
  Panzer/tank/tactical_nuke resource entries left unchanged (audit marks them "?").
  Follow-up (display-only): `technologies.json` `unlocks_units` lists are slightly
  stale for AND-set units (e.g. flight still lists bomber, which also needs radio).
  ~~`tech_required` list-AND,
  `resource_required` all/any split. Files: `data/units.json`, `src/core/data_db.gd`
  (validation), `src/sim/*` production/upgrade gates, `src/api/player_ai.gd` (build
  choice reads), tests `test_data_db.gd`, `test_settlement_production*.gd`. Then apply
  the audit-§2 tech/resource sets (data pass).~~
- **B2. Chance first strikes** (game-rules §15.5) — **DONE 2026-07-08** (1d90307):
  `Combat.rolled_first_strikes` = unit `first_strikes` + promotion
  `first_strikes_bonus` + one 0..chance roll (`chance_first_strikes` on units,
  `chance_first_strikes_bonus` on promotions); the roll draws only when a chance stat
  is present, so pre-existing seeded streams are unchanged. Data: navy_seal 1+1chance,
  skirmisher 1+1chance (the audit's two carriers). **Finding: promotion
  `first_strikes_bonus` was previously read nowhere — the whole drill line was inert;
  it is now wired.** A8's drill chance values remain a pure data pass.
  ~~`chance_first_strikes` on units +
  promotions; one `gs.rng` roll per combat in `Combat.resolve()`. Tests:
  `test_combat.gd` (same-seed determinism + distribution bounds).~~
- **B3. Per-unit siege caps** (game-rules §15.6) — **DONE 2026-07-08** (c10ecdf):
  catapult/trebuchet/hwacha 25, cannon 20, artillery/mobile artillery 15 (floor =
  100 − reference limit; 0 = no cap). The engine already treated `combat_limit` as a
  per-unit defender-health floor, so this was data + tests only.
  ~~replace global `combat_limit: 1`
  floor with per-unit damage-floor values (catapult/trebuchet/hwacha 25, cannon 20,
  artillery/mobile artillery 15); `src/sim/combat.gd:97-123` already reads per-unit —
  data + semantics only (floor = 100 − reference limit).~~
- **B4. Trait production-speed modifiers** (audit §1.8): new trait key
  `double_production_structures: [...]` (+100% build speed on listed structures)
  replacing `free_structures` for the seven reference traits; keep `free_structures`
  as a mechanism for any genuinely-free grants. Files: `leaders_traits.json`,
  production math in `turn_engine.gd`, `PolicyEffects`-style reader or trait reader.
  **DONE 2026-07-12**: six traits' lists moved to `double_production_structures`
  (magnitude = `trait_double_production_pct` constant, 100), read by the new
  `TraitEffects` module (`src/sim/trait_effects.gd`, the `PolicyEffects` analogue
  for traits) and summed into `TurnEngine._production_percent_mods` — trait
  modifiers stack additively with the §4.3 chain. **Settler decision**: the
  reference tags production traits per-item with a percent, and settler is **+50,
  not double** (XML-sourced this session: UNIT_SETTLER/TRAIT_IMPERIALIST 50); so
  units use a sibling magnitude-carrying dict `unit_production_modifiers:
  {unit_id: +%}` — imperialistic `{settler: 50}` (its dead
  `settler_cost_reduction` key retired), plus the audit-missed expansive
  `{worker: 25}` (XML: UNIT_WORKER/TRAIT_EXPANSIVE 25). **Key finding:
  `free_structures` was a DEAD key** — no engine read site ever existed, so the
  seven traits gained nothing from it in play and the swap is a buff from
  nothing → reference speed, not a nerf (no seeded recalibration was needed; the
  full gate passed untouched). The free-grant *mechanism* therefore still does
  not exist in the engine; `free_structures` remains a validated (see below)
  vacant schema slot should a genuinely-free grant ever ship.
  `DataDB._validate_trait_refs` (new) checks `free_structures` /
  `double_production_structures` members against the structures table and
  `unit_production_modifiers` keys against the units table. **XML notes for
  later decisions** (recorded, NOT adopted — outside the audit's seven lists):
  the reference's expansion rules also tag creative→library, organized→factory,
  philosophical→university, spiritual→Cristo Redentor, and every unique-building
  variant of a listed base (ikhanda, terrace, cothon, …) with the same +100;
  A9's "creative drops library (not in reference)" was true of the base game
  only. Pins: `test_traits_carry_b4_double_production_model` +2 validation tests
  (`test_data_db.gd`), 4 production-math pins (`test_settlement.gd`, incl. the
  half-the-turns double and the +125 additive stack with a Forge), new suite
  `tests/sim/test_trait_effects.gd`.
- **B5. `defensive_only` unit flag** (for Machine Gun): reject attack orders in
  `_cmd_unit_command`/`can_stack_move` targeting logic; AI must not select it for
  attack passes (`player_ai.gd` attack pass filter).
  **DONE 2026-07-12**: wired into `Unit.can_attack` — the documented single
  sim-side gate already consulted by `can_stack_move`, `_cmd_move_stack`, and the
  per-unit `MISSION_MOVE_TO` (which delegates to `_cmd_move_stack`), so the UI
  legality probe and every attack-order path refuse it at once. AI:
  `PlayerAI._manage_free_military` early-outs through the same `can_attack`
  gate — a defensive-only unit skips both the adjacent-attack and the
  advance-on-threat passes (whose final step the move command would refuse) and
  fortifies in place; garrison assignment (pass 2) still uses it as a defender.
  The shipped carrier is the Machine Gun (C7, 2026-07-12); flag-only synthetic
  db-override pins: `test_defensive_only_unit_cannot_initiate_combat`
  (`test_units.gd`), `test_defensive_only_unit_cannot_attack_at_command_layer`
  (`test_facade.gd`), `test_defensive_only_unit_never_attacks`
  (`test_player_ai.gd`).
- **B6. Per-resource corporation outputs** (game-rules §15.10, game-data §29.6):
  outputs scale with accessible input-resource count (×1/100 fixed math); optional
  `produces_resource` (Oil/Aluminum) granted to the org's cities' owner; maintenance
  per resource instance. Files: `econ_orgs.json`, `src/sim/econ_orgs.gd`, tests
  `test_econ_orgs.gd`.
  **DONE 2026-07-17**: full §29.6 table adopted (inputs, ×1/100 rates, produced
  resources, `maintenance_per_resource` 100, HQ `hq_gold_per_franchise` 4 — all
  confirmed against the reference XML; spread columns deliberately left
  Humanish-tuned). `EconOrgs.accessible_resource_counts` counts instances (one
  per connected tile copy, per supplying deal, per operating `produces_resource`
  org — the grant also feeds the §15.12 unit resource gate and other orgs'
  inputs); channels route food/production into the city yield, culture into
  `_settlement_culture`, research into `_apply_research`, gold into
  `gold_income`, all `rate × instances / 100` truncating. New DataDB validation
  (`produces_resource` resolves, `output_per_resource` channels known); the
  corporation advisor + encyclopedia render the new schema. PlayerAI untouched
  (it reads only `accessible_resources`, whose presence-set contract held).
  Tests: instance scaling 0/1/N + duplicate-copy and truncation pins, traded
  instance, research/culture/gold channel routing, produced-resource
  grant/lapse/ban and cross-org instance feed, per-instance maintenance ×
  franchises + Free Market halving, HQ per-franchise — `test_econ_orgs.gd`
  (15 tests); recalibrations in `test_data_db.gd`/`test_quests.gd`.
- **B7. Worker-speed % modifiers** (serfdom, fast worker, golden ages): build-turn
  math honours a percentage; read from civic effects + unit tag. Prereq for C6.

## Phase C — new mechanics (each is a self-contained subsystem; specs in game-rules §15)

- **C1. Inflation** (§15.1) — **DONE 2026-07-12.** `TurnEngine.inflation_rate`
  (rate = clamped `(turn + inflation_offset) × inflation_percent / 100 ×
  difficulty inflation_percent / 100`, integer math) applied inside
  `TurnEngine.gold_upkeep`, the single shared expense total — so `_update_treasury`,
  the HUD gold rate (`get_player_gold_rate`) and the AI's solvency reads all see the
  inflated figure; the finance-advisor breakdown gained an inflation line. Data:
  `inflation_percent`/`inflation_offset` per pace (`paces.json`, §29.5 values) and
  `inflation_percent` per difficulty (`difficulties.json`, §29.10 values). Tests:
  progression at fixed turns across paces, difficulty multiplier, zero at game start,
  treasury delta, AI finance shift, data-column presence. Companion building-upkeep
  retune done with it — see D3.
- **C2. Population rush** (§15.2, §29.8) — **DONE 2026-07-12.** New
  `RUSH_POPULATION` command (`Commands.rush_population` →
  `SimFacade._cmd_rush_population`; the legacy `RUSH_PRODUCTION`
  method="population" delegates to it, so `_cmd_rush_production` is now
  gold-only). Slavery's shipped `rush_by_pop` flag renamed to `pop_rush` and
  gated via `PolicyEffects.has_flag`. Math in `TurnEngine.rush_pop_cost`/
  `rush_hammers_per_pop`: 30 hammers per citizen (`rush_production_per_pop`)
  × per-pace `hurry_scale` (67/100/150/300, new `paces.json` column), pop cost
  = ceiling of remaining hammers, never below `rush_min_population` 1 (also the
  AI floor — the AI does not initiate whips; the handler enforces the floor for
  every client). `new_hurry_modifier` +50% when the head item was queued this
  turn (`SET_PRODUCTION` now stamps `queued_turn` per queue item; coerced to
  int in `Settlement.deserialize`). Each whip stacks a −1 × 10-turn entry on
  the settlement's §9 `timed_happiness` channel (replaces the old flat
  `rush_anger_turns = 5` on the pop path; the gold path keeps it); the Aztec
  Sacrificial Altar's previously inert `halve_slavery_anger` effect now halves
  that duration. City screen
  "Hurry (Pop: N)" button shows the cost via `facade.rush_population_cost`.
  Tests: `test_settlement.gd` (hurry math, pace scaling, surcharge, stamp
  preservation, pop floor, anger stacking/expiry, JSON int-key roundtrip),
  `test_policy_effects.gd` (civic gate, legacy routing), `test_data_db.gd`
  (`hurry_scale` column). Gold path tuning untouched — its 3-gold-per-hammer
  reference retune and Slavery's Bronze-Working tech gate remain open gaps.
- **C3. Pace scaling** for anarchy/golden ages/victory delay/wild timing (§15.3,
  §29.5) — **DONE 2026-07-12.** Four new `paces.json` columns (`Fixed.scale`
  truncation everywhere): `anarchy_scale` 67/100/150/200 — `SimFacade._anarchy_turns`
  stretches civic `transition_turns` (`_cmd_set_policy`) and
  `state_religion_anarchy_turns` (`_cmd_set_state_religion`), clamped to the
  reference bounds `anarchy_min_turns` 1 / `anarchy_max_turns` 100 (new in
  `constants.json`; espionage anarchy stays mission-priced, unscaled);
  `golden_age_scale` 80/100/125/200 — `GreatPeople._golden_age_duration` (8 turns →
  6/8/10/16), replacing its old `build_scale` read; `victory_delay_scale`
  67/100/150/300 — `WinConditions._cultural` now checks each city's `culture_total`
  against the top `culture_ring_thresholds` entry × the scale (368/550/825/1650;
  identical to the old top-ring check at normal), while the Time victory keeps the
  already-per-pace `max_turns` (no double scaling); `wild_scale` 67/100/150/**400** —
  `WildForces._scaled_turns` (was `growth_scale`, i.e. marathon 300 → 400).
  Tests: `test_data_db.gd` (full four-column table pin), `test_policies.gd` +
  `test_state_religion.gd` (anarchy per pace incl. the quick-pace min-clamp),
  `test_great_people.gd` (golden-age lengths), `test_win_conditions.gd` (cultural
  threshold per pace; legacy tests moved from ring to culture_total),
  `test_wild_forces.gd` (26/40/60/160 gate pins). All normal-pace behaviour —
  and thus every seeded playthrough — is unchanged (all four scales are 100).
- **C4. Culture-level city defence** (§15.4, §29.4): defence modifier from the
  settlement's culture tier in `Combat` city-defence math; bombard reduces it, heals
  5%/turn. `[decide→RESOLVED]` the border-expansion curve moves to the reference
  geometric thresholds (D2 adopted) — the defence tiers key off that curve.
- **C5. SDI + The Internet + nuke interception** (§15.7, §29.2): projects.json
  entries (non-spaceship projects with effects — small `projects` model extension),
  interception roll in the nuke-strike path (`src/sim/nuclear.gd`), tech-share check
  in the research phase. Also retune §5.7 nuke magnitudes to the reference block.
  **DONE 2026-07-17** (with the D3 missiles-cannot-defend item): `sdi` /
  `the_internet` ship as **effects projects** — entries without
  `win_condition: "endgame_project"`, carrying `instances` ("player"/"world"),
  `requires_wonder_any` and an `effects` dict. Completion records them on the new
  serialized `Player.projects` (spaceship stages keep the alliance stage tally);
  the new `Projects` reader (`src/sim/projects.gd`, the PolicyEffects analogue)
  is the single effects read path, and `can_build` gates the SET_PRODUCTION
  queue (endgame stages stay ungated as before). SDI: `Nuclear.try_intercept`
  now assembles ONE chance per strike — the best of the existing in-range
  anti-air roll and any target-side owner's `nuke_interception` (75) — rolled at
  the same pre-detonation point, drawing nothing when no source exists. The
  Internet: `TurnEngine._apply_tech_share` runs in the PLAYER_RESEARCH phase
  right after `_apply_research` (no RNG; techs scanned in data order; a shared
  tech that was under research completes for free). §5.7 magnitudes retuned to
  the reference block (`constants.json`): unit damage 30+rand(50)+rand(50)
  rolled per unit with combat units floored at 1 health and **non-combatants
  killed at the 60 threshold** (new), population death 30+rand(20)+rand(20) %,
  **building destruction 40% per structure** (new roll), fallout 50% /
  gw_nuclear_ratio 50 (already matched); the old flat
  `nuke_blast_unit_damage_pct`/`nuke_population_loss_pct` placeholders are
  removed. Tests: `test_projects.gd` (new suite — data pins, reader, gating,
  completion, tech-share, save/load hash), `test_nuclear.gd` (SDI interception:
  forced/never/attacker-own/determinism + both outcomes across seeds at the real
  75%; threshold kills; building rolls; population band),
  `test_data_db.gd` magnitude pins, `test_conquest.gd` missile-defender block.
- **C6. Serfdom & emancipation effects** (§15.9, §29.9): worker speed (needs B7),
  cottage upgrade-rate % (generalize `faster_cottage_growth`), emancipation-pressure
  anger (contentment penalty scaled by adopter share).
- **C7. Missing units** (§29.1): Machine Gun (needs B5), War Elephant (needs B1),
  Lion (animal roster in `WildForces.spawn_animals` between wolf/panther weights).
  **DONE 2026-07-12**: pure data pass — all three §29.1 rows verified against the
  reference and added to `units.json`; `railroad`/`construction` gained the
  `unlocks_units` entries. Machine Gun is the first shipped `defensive_only`
  carrier (B5 gate re-pinned on the real unit at sim + command layer); War
  Elephant is a compound-prereq mounted unit (B1 AND-techs + ivory; the Khmer
  `ballista_elephant`'s descriptive `replaces` now points at it per the
  reference); Lion joins the uniform animal spawn roster (str 2 / 1 move —
  `_spawn_animal_unit` draws equally from every classification-"animal" unit
  through the shared `gs.rng`, so no weight table was needed). One wiring find:
  both wild raider-stock pickers (`WildForces`/`WildAI._strongest_wild_unit_type`)
  would have picked the Machine Gun as the strongest land unit in its era, but
  raiders initiate combat, which B5 bars — both now skip `defensive_only` units.
  Everything else (encyclopedia, AI production/garrison, draft, upgrade,
  `Eras.era_of_unit`) reads `units.json` generically. Tests:
  `test_units_carry_c7_missing_unit_stats` (data pins),
  `test_machine_gun_is_defensive_only` / `test_machine_gun_cannot_attack_at_command_layer`,
  `test_war_elephant_prereqs_gate_on_both_techs_and_ivory`,
  `test_lion_is_in_the_animal_spawn_roster`,
  `test_raider_stock_never_picks_a_defensive_only_unit`.
- **C8. War-weariness deepening** (§15.8) — *optional*: keep the 2-constant model or
  adopt per-event weights; if adopted, wire into `CombatApply` outcomes. Low priority.

## Phase D — decided 2026-07-08 (all resolved "adopt reference"); now work items

- **D1. Tech-graph parity** — **DECIDED: adopt** the reference graph (AND + OR
  prereqs, full 92-tech table below). Work: (1) honour `prereqs_any` in research
  gating + the AI cheapest-tech choice; (2) pure data pass from the appendix table
  (eras + AND/OR columns; costs already match except future_tech, A13); (3) rename
  our `communism` tech to the reference `utopia` (audit §3) — grep data + tests for
  the id. Affects era pacing, wild-forces timing, AI openings, every playthrough
  test — do last among the big items, when A/C are green.
- **D2. Border-expansion curve** — **DECIDED: adopt** the reference geometric
  5 levels ×4 speeds (§29.4), replacing the near-linear 10 rings. Touches
  `culture_ring_thresholds` (constants.json), `CultureRevolt`, `Influence`,
  fat-cross reach; C4's defence tiers key off the new curve.
- **D3. Intentional-deviation register** — **DECIDED: dissolved.** Nothing is an
  intentional deviation; every formerly-listed divergence is now scheduled inside
  its phase item: naval rescale (A1), difficulty philosophy (A3), map grids/research %
  (A4), grassland hammer (A5), mountains workable (A5). Two engine follow-ups it
  held become work items:
  - **Building upkeep retune** — **DONE 2026-07-12 (with C1).** Semantics change:
    reference buildings pay **no** per-building gold upkeep (audit §1.6) — the
    economy's drag is city maintenance + civic upkeep + inflation — so under the
    blanket adopt-the-reference decision the `upkeep` field was **removed** from
    every `structures.json` entry (was 0–3 gold each) rather than retuned. The
    engine read path (`_settlement_upkeep`, encyclopedia display) stays intact
    for mods; `test_data_db` pins the shipped table at zero. Own commit,
    separately revertable.
  - **Missiles cannot defend** (reference): exclude `classification: "missile"` from
    `Stack.get_defender` (mirror the espionage-tag exclusion) and destroy missiles
    left stackless/cityless on capture — schedule with C5's nuke/interception work.
    **DONE 2026-07-17 (with C5).** `Stack.get_defender` skips missiles (the A1
    guided-missile-defends-at-40 quirk is a regression test now); the new
    `CombatApply.destroy_stranded_missiles(gs, x, y, captor_pid)` removes hostile
    missiles from a tile with no surviving defender when it is taken — called
    after a victorious advance (`apply_unit_result`), on city capture and raze
    (`SimFacade._capture_city`/`_raze_city` — a voluntary self-disband spares
    them via the hostility check), on a wild raze advance (`WildAI`), and when a
    stack walks onto a lone missile's tile (`_cmd_move_stack` step loop; a
    missile-only tile has no defender so entry is a move, not an attack).
    Not covered (noted, out of scope): a culture-flipped city leaves the old
    owner's missiles standing — the flip transform is peaceful and
    `destroy_stranded_missiles` only fires on hostile takeovers.
    Tests: `test_conquest.gd` §15.7/D3 block (defender pick, missile-only city
    falls + missile dies, stack-wipe strand, defender-still-alive survival,
    walk-on destruction).
- **D4. Humanish-only content** — **DECIDED: cut it all.** Remove: `anti_tank` unit;
  `merchant_guild`/`overseas_trading_co`/`nationalist_mutual` orgs; invented
  promotions (accuracy I/II, boarding, dogfighting, air supremacy, escort, evasion,
  withdrawal); `sun_faith`/`earth_covenant` religions **including their
  `temple_of_sun`/`grove_sanctuary` structures** (added 2026-07-08 by the
  dangling-holy-sites bugfix — that fix's *validator and tests* stay; only the
  content goes). Also add the reference promotions we lack: ace, ambush, charge,
  leader, medic3, mobility, range1/2, tactics — ~~fold into A8~~ **NOT added in
  A8 (2026-07-11): none of their reference stats (effects, magnitudes, prereqs,
  unit classes) are documented in the audit/§29/game-rules, and per the user
  rule values may not be sourced from the local reference XML — a design-doc
  sitting must record their reference stats first, then the additions are a
  pure data pass (the cut pass should not assume they exist).** Known engine
  gaps for when they land: `vs_armor`/`vs_siege` need `Unit.VS_CLASS_KEY`
  entries (one line each); air-range/upgrade-discount/move-discount/tile-heal
  promotion keys have no readers; the Great-General attach path grants our
  `leadership`, not a reference-style `leader` marker.
  **Migration notes for the cut pass:** long-standing tests bind some of these ids
  (`sun_faith`, `merchant_guild` were kept bespoke precisely because tests reference
  them — update test id references, not test logic); check `data/leaders_traits.json`
  society/trait references, `data/events.json`/`quests` effects, and encyclopedia
  rendering for dangling ids; DataDB validators (`_validate_belief_refs`,
  `_validate_econ_org_refs`, …) will catch stragglers at load — run the full gate
  after each table's cut.
  **CUT HALF DONE 2026-07-11** (3988c5a): all four tables cut, table by table with
  green suites between — `anti_tank` (+ removed from artillery's `unlocks_units`);
  the three orgs **plus their `corporation_hq` structures** (`merchant_guild_hq`/
  `overseas_trading_co_hq`/`nationalist_mutual_hq`); the 10 invented promotion
  entries (accuracy1/2, boarding1/2, escort, dogfighting1/2, air_supremacy,
  evasion, withdrawal — 54 → 44 entries; reference interception1/2 and
  navigation1/2 kept); `sun_faith`/`earth_covenant` + `temple_of_sun`/
  `grove_sanctuary` (7 reference religions remain; the dangling-holy-sites
  validator `_validate_belief_refs` and `test_belief_refs_resolve` stay). Test id
  migrations only (no logic changes): `merchant_guild` → `civilized_jewelers`
  (`test_econ_orgs.gd` ×6, `test_quests.gd` ×3), `sun_faith` → `buddhism`
  (`test_beliefs.gd` ×1). Findings: no code fallbacks referenced any cut id
  (`GreatPeople._act_found_corporation` picks the first *unfounded* org
  generically; `pick_promotion` iterates data order — cut ids all sat behind
  earlier same-class picks, so award order is unchanged); no `free_promotions`,
  events/quests effects, leaders/traits, or `docs/user/` references existed;
  full gate green (1462 unit + 11 integration, zero SCRIPT ERROR; count
  unchanged — pure id swaps). ~~The **additions half** (ace, ambush, charge,
  leader, medic3, mobility, range1/2, tactics) remains blocked on the
  design-doc sitting above.~~ **ADDITIONS HALF DONE 2026-07-11**
  (promotions-unblock pass; values adopted from the reference under a
  user-authorized sourcing session; all nine exist in the reference, none
  dropped; recorded in game-data §13/§19.4; 44 → 53 entries, new entries at
  the file tail so XP pick order for pre-existing promotions is unchanged):
  ambush `vs_armor: 25`, charge `vs_siege: 25` (**both live** — the two known
  engine gaps got their one-line `Unit.VS_CLASS_KEY` entries, `armor`/`siege`);
  tactics `withdrawal_chance_bonus: 30` (live — existing withdrawal sum);
  medic3 same/adjacent tile heal 15/15; mobility `move_discount: 1`; range1/2
  `air_range_bonus: 1` each; ace `evasion_chance: 25`. **`leader` resolution:**
  the reference model is an attach-granted marker (never XP-picked, 100%
  upgrade discount) that *gates* the General-only promotions — so
  `GreatPeople._act_attach_to_unit` now grants `leader` alongside `leadership`,
  `leader` carries `granted_only: true` (new one-line gate in
  `pick_promotion`), and `leadership`/`tactics`/`medic3` prereq on it
  (leadership's prereq [] → ["leader"], per reference). Schema note:
  `applies_to` now also accepts a *list* of classes/domains
  (`CombatApply.promo_applies`, shared with `_grant_free_promotions`;
  encyclopedia renders the list) so ambush/charge/mobility carry their real
  reference class rosters (helicopter class omitted — no such classification
  here; reference OR-prereqs simplified to the primary prereq, matching the
  existing medic1 convention, e.g. ambush keeps combat2 and drops the drill2
  alternative). **Dead keys flagged** (correct parity data, no engine reader —
  do not build subsystems for them piecemeal): `move_discount`,
  `air_range_bonus` (air missions read the *unit* `air_range` only),
  `evasion_chance`, `upgrade_discount`, medic/woodsman `same_tile_heal`/
  `adjacent_tile_heal`. Reference deviations kept (pre-existing, unchanged):
  attach grants to the whole tile stack (reference: one unit); morale's prereq
  stays combat3 (reference: leader); woodsman3 keeps `combat_in_forest: 20`
  (reference: +50% forest/jungle *attack* only). Pins:
  `test_promotion_roster_carries_reference_additions`,
  `test_granted_only_promotion_never_picked_from_xp`,
  `test_list_applies_to_matches_class_or_domain`,
  `test_vs_armor_and_vs_siege_promotions_apply_against_mapped_class`,
  `test_tactics_withdrawal_bonus_live` (`test_combat.gd`); attach test extended
  (`test_great_people.gd`). ~~Design-doc mentions of the cut content (game-data.md
  §§ unit/promotion/corporation tables and the §29-era notes) are left in place
  pending a consented design-doc pass.~~ **Addressed 2026-07-11** (design-doc
  value-sync pass: anti_tank/promotion/corporation/religion rows removed,
  §23/§29.6 notes updated to record the cut).

## Bug fixes (do now, independent of phases) — ALL DONE 2026-07-08

1. **Dangling holy sites** — **DONE** (c4122e8): added the two structures (mirroring
   `shrine`) + names + founding techs (`sun_faith` → calendar, `earth_covenant` →
   agriculture), keeping D4's keep-or-cut open. Added `DataDB._validate_belief_refs()`
   + `test_belief_refs_resolve` (covers temple/monastery/cathedral/holy_site_structure
   and founding_tech). **Finding — the bug was inverted from the wording below**:
   `founding_tech: null` did not make them unfoundable, it made them *always eligible*,
   so every game silently founded `earth_covenant` on turn 1 and its +1 health masked
   base size-1 city unhealthiness (two tests were calibrated against that freebie).
   ~~`beliefs.json` `sun_faith`/`earth_covenant` reference
   `temple_of_sun`/`grove_sanctuary` which don't exist in `structures.json`, and both
   have `founding_tech: null` (unfoundable). Either add the two structures + founding
   path or strip the two entries. Add a `test_data_db.gd` cross-reference check
   (every `holy_site_structure` exists) so this class of dangling id fails CI.~~
2. **game-rules §9.3 doc error** — **DONE** (2093ccb): cap now 5 in constant, code
   fallback, and doc. ~~animal lifetime XP cap cited as 10 with a reference attribution;
   reference `ANIMAL_MAX_XP_VALUE` is **5** (10 is the barbarian cap). Fix doc +
   constant together (A11).~~
3. **Audit follow-ups already suspicious** — **DONE**: mounted withdrawal zeros
   restored (d933a61), `guided_missile` fixed + one-use wired (d933a61, see A1 note
   for the open defender quirk), settler/worker goody weights verified already
   shipped (A12).

## Sequencing recommendation

1. ~~Bug fixes + A12 (small, safe).~~ **DONE 2026-07-08.**
2. ~~A-phase data passes behind the `[decide]` register.~~ **DONE 2026-07-11 —
   all of A1–A13 shipped (A12 verified already present); ~~fold the new
   reference promotions (D4) into A8~~ (A8 done 2026-07-11; the D4 promotion
   additions + A8 leftovers done later the same day in the promotions-unblock
   pass — see A8/D4 notes).**
3. ~~B1–B3 (schema; unblock A1's prereq sets and A8's drill line).~~ **DONE
   2026-07-08 (B1 f77a574, B2 1d90307, B3 c10ecdf).**
4. ~~D4 content cut (independent of A; see migration notes) — can go before or after
   the A passes, but before D1 so the graph pass doesn't have to carry dead ids.~~
   **DONE 2026-07-11 (cut 3988c5a; additions half done later the same day in the
   promotions-unblock pass — see D4 note).**
5. ~~C1–C3 (economy trio: inflation, whipping, pace scaling — retune building upkeep
   here)~~ **DONE 2026-07-12 (C1 f08abc2, C2 ea59121, C3 7badc5b)**, ~~then C4/C5
   (+ the missiles-cannot-defend item)/C7~~ **C5+missiles 0e4b578 and C7 c1c5798
   done 2026-07-17 (B4/B5 44becde and B6 79fa8e0 landed alongside); C4 remains —
   do it WITH D2 (its defence tiers key off the D2 curve), then C6 (needs B7)**.
6. D1 tech graph + D2 border curve last among the big items (touch everything; do
   when A/C are green). Suggested remaining order: B7 → C6 → D2+C4 → C8
   (optional) → D1.

Each phase ends green on `./run_tests.sh` including the integration playthrough gate;
save/load determinism tests must pass after every schema change (int-coercion rule for
any new int-keyed data).

---

## Appendix — reference tech graph (92 techs; parity target for D1)

Cost = reference research cost (matches current data except future_tech). AND = all
required; OR = any one. `utopia` is our `communism` (rename note: audit §3).

| Tech | Cost | Era | AND-prereqs (all required) | OR-prereqs (any one) |
|---|---|---|---|---|
| fishing | 40 | ancient | - | - |
| hunting | 40 | ancient | - | - |
| mining | 50 | ancient | - | - |
| mysticism | 50 | ancient | - | - |
| agriculture | 60 | ancient | - | - |
| archery | 60 | ancient | - | hunting |
| priesthood | 60 | ancient | - | meditation,polytheism |
| the_wheel | 60 | ancient | - | - |
| masonry | 80 | ancient | - | mining,mysticism |
| meditation | 80 | ancient | - | mysticism |
| pottery | 80 | ancient | the_wheel | agriculture,fishing |
| animal_husbandry | 100 | ancient | - | hunting,agriculture |
| polytheism | 100 | ancient | - | mysticism |
| sailing | 100 | ancient | - | fishing |
| bronze_working | 120 | ancient | - | mining |
| monotheism | 120 | ancient | masonry | polytheism |
| writing | 120 | ancient | - | priesthood,animal_husbandry,pottery |
| iron_working | 200 | classical | - | bronze_working |
| literature | 200 | classical | polytheism | aesthetics |
| horseback_riding | 250 | classical | - | animal_husbandry |
| mathematics | 250 | classical | - | writing |
| aesthetics | 300 | classical | - | writing |
| alphabet | 300 | classical | - | writing |
| drama | 300 | classical | - | aesthetics |
| monarchy | 300 | classical | - | priesthood,monotheism |
| calendar | 350 | classical | sailing | mathematics |
| code_of_laws | 350 | classical | writing | priesthood,currency |
| construction | 350 | classical | masonry | mathematics |
| compass | 400 | classical | sailing | iron_working |
| currency | 400 | classical | - | mathematics,alphabet |
| metal_casting | 450 | classical | pottery | bronze_working |
| theology | 500 | medieval | writing | monotheism |
| music | 600 | medieval | mathematics | literature,drama |
| optics | 600 | medieval | machinery | compass |
| paper | 600 | medieval | - | theology,civil_service |
| banking | 700 | medieval | currency | guilds |
| feudalism | 700 | medieval | writing | monarchy |
| machinery | 700 | medieval | - | metal_casting |
| civil_service | 800 | medieval | mathematics | code_of_laws,feudalism |
| philosophy | 800 | medieval | meditation | code_of_laws,drama |
| engineering | 1000 | medieval | machinery | construction |
| guilds | 1000 | medieval | feudalism | machinery |
| divine_right | 1200 | medieval | theology,monarchy | - |
| gunpowder | 1200 | renaissance | - | guilds,education |
| economics | 1400 | renaissance | banking | education |
| liberalism | 1400 | renaissance | philosophy | education |
| corporation | 1600 | renaissance | constitution | economics |
| printing_press | 1600 | renaissance | machinery,alphabet | paper |
| chemistry | 1800 | renaissance | engineering | gunpowder |
| education | 1800 | renaissance | - | paper |
| nationalism | 1800 | renaissance | civil_service | divine_right,philosophy |
| replaceable_parts | 1800 | renaissance | banking | printing_press |
| astronomy | 2000 | renaissance | calendar,optics | - |
| constitution | 2000 | renaissance | code_of_laws | nationalism |
| military_science | 2000 | renaissance | - | chemistry |
| military_tradition | 2000 | renaissance | music | nationalism |
| rifling | 2400 | renaissance | gunpowder | replaceable_parts |
| democracy | 2800 | renaissance | printing_press | constitution |
| fascism | 2400 | industrial | nationalism | assembly_line |
| scientific_method | 2400 | industrial | printing_press | chemistry,astronomy |
| steel | 2800 | industrial | iron_working | chemistry |
| utopia | 2800 | industrial | liberalism | scientific_method |
| steam_power | 3200 | industrial | chemistry | replaceable_parts |
| biology | 3600 | industrial | chemistry | scientific_method |
| combustion | 3600 | industrial | - | railroad |
| artillery | 4000 | industrial | physics,steel | rifling |
| physics | 4000 | industrial | astronomy | scientific_method |
| electricity | 4500 | industrial | - | physics |
| medicine | 4500 | industrial | optics | biology |
| railroad | 4500 | industrial | steam_power | steel |
| assembly_line | 5000 | industrial | corporation | steam_power |
| fission | 5500 | industrial | - | electricity |
| industrialism | 6500 | industrial | electricity | assembly_line |
| mass_media | 3600 | modern | - | radio |
| refrigeration | 4000 | modern | biology | electricity |
| advanced_flight | 5000 | modern | satellites | flight |
| flight | 5000 | modern | physics,combustion | - |
| rocketry | 5000 | modern | rifling | flight,artillery |
| ecology | 5500 | modern | biology | plastics,fission |
| radio | 6000 | modern | - | electricity |
| satellites | 6000 | modern | radio | rocketry |
| computers | 6500 | modern | plastics | radio |
| superconductors | 6500 | modern | - | refrigeration,computers |
| laser | 7000 | modern | plastics | satellites |
| plastics | 7000 | modern | combustion | industrialism |
| composites | 7500 | modern | satellites | plastics |
| fiber_optics | 7500 | modern | - | computers,laser |
| robotics | 8000 | modern | - | computers |
| genetics | 7000 | future | medicine | superconductors |
| fusion | 8000 | future | fission | fiber_optics |
| stealth | 8000 | future | composites | advanced_flight |
| future_tech | 10000 | future | stealth | genetics |

