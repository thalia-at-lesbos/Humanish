# Direct Reference Gaps — plan to reach data & rules parity

Status: **in progress** — sequencing step 1 (bug fixes + A12) done 2026-07-08; next
is the step-2 `[decide]`/D3 register review (user sitting) while B1–B3 proceed.
Date: 2026-07-07.

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
are flagged `[decide]` — adopt the reference value or document the deviation as
intentional in the table's section of game-data.md; don't leave it ambiguous.**

- **A1. Unit stats** (`data/units.json`; tests `tests/sim/test_combat.gd`,
  `test_unit*.gd`): apply audit §2 per-unit values — strength/cost/moves/withdrawal/
  first-strikes/cargo/air-range. Sub-decisions:
  - `[decide]` The across-the-board naval rescale (frigate 18 vs 8 …) — revert to
    reference or keep; if kept, document in game-data §5.
  - ~~Withdrawal chances on the mounted line (chariot 10, horse archer 20, cuirassier
    15, cavalry/cossack 30, gunship 25, conquistador 15, immortal 10, war chariot 10,
    keshik 20, camel archer 15, submarine line 50) look accidentally dropped — restore.~~
    **DONE 2026-07-08** (d933a61, all 13 values restored).
  - ~~`guided_missile` strength 0 vs reference 40 — verify missile combat path, then fix.~~
    **DONE 2026-07-08** (d933a61): strength 40; verification found the `one_use` tag was
    read nowhere — the air-bombard path now consumes one-use weapons on strike or
    interception (`SimFacade._consume_one_use`). Follow-up for the D3/C5 sitting:
    `Stack.get_defender` has no missile/air exclusion, so a garrisoned guided missile
    can be selected as a city's best defender at 40 (reference missiles cannot defend).
  - settler/worker moves 1 → 2, fast worker 2 → 3, musketeer 1 → 2 (reference).
- **A2. Building/wonder values** (`data/structures.json`; test `test_settlement*.gd`):
  audit §4 list — costs (barracks 50, cothon 100, forum 150, ger 60, hagia sophia 500
  + tech theology, madrassa 90, sacrificial altar 90, ziggurat 90, dun 50 + tech
  masonry, walls tech masonry, space elevator tech robotics), negative health on
  industrial buildings (forge/factory/drydock/airport/mint/assembly plant −1,
  industrial park −2), happiness rows (market/forum/odeon/ball court/hippodrome,
  cathedral-tier), granary health 0. The `science%` rows flagged "unverified" in the
  audit need the reference's `CommerceModifiers` read before changing.
- **A3. Difficulty table** (`data/difficulties.json`; tests `tests/sim/test_wild*.gd`,
  `test_turn_engine.gd`): audit §5 — research % (prince 110 …), free wins 5/4/3/2/1/0,
  `[decide]` health/happiness columns (reference never goes negative for the human),
  `ai_research_per_era` sign/semantics (reference: AI research gets *cheaper* per era
  at high difficulty — align the sign or rename the field), `[decide]` water-raider
  density ÷4 back to reference, `combat_bonus_vs_wild` semantics (reference puts the
  modifier on the barbarian side; ours on the human — pick one and document).
- **A4. World sizes** (`data/world_sizes.json`): `[decide]` grids (only duel matches)
  and research % recentring (75–120 vs reference 100–150) — both look deliberate;
  either adopt reference or mark the table "intentional deviation" in game-data §*.
  players_suggested 2/3/5/7/9/11 if parity chosen.
- **A5. Terrain & features** (`data/terrains.json`, `features.json`; tests
  `tests/world/*`, `tests/sim/test_settlement*`): `[decide]` grassland 2/1/0 → 2/0/0
  (largest single economic deviation — changing it reshapes every game); hills
  1/2/0 → net 1/1/0-equivalent; mountains workable +1P (reference: unworkable) —
  keep-or-revert; river commerce on desert/tundra (+1C, reference) — add
  `river_commerce_bonus: 1` to both; flood-plains defence −33 (reference 0).
- **A6. Improvements** (`data/improvements.json`): town 1/1/4 → 0/0/4 base
  (reference; its +1P/+1F come from civics), workshop −1F/+1P at base `[decide]`.
- **A7. Specialists & settled GPs** (`data/specialists.json`; test
  `test_great_people.gd`): citizen +1 production; artist 4 culture (+1 research);
  spy 4 esp (+1 research); settled greats per audit §8 (great_priest +2P/+5 gold …).
  `[decide]` GPP 1-per-specialist scaling: either ×3 with reference thresholds or
  keep the ⅓ scale — verify `gp_threshold` progression matches the chosen scale.
- **A8. Promotions values** (`data/promotions.json`): combat6 +25; flanking2 +20;
  interception 10/20; guerrilla3 +50 withdrawal; woodsman3 +2 FS & same-tile heal;
  drill line per game-data §29.3 (needs B2 for chance-FS/collateral fields).
- **A9. Traits & leaders** (`data/leaders_traits.json`; test `test_data_db.gd`):
  imperialistic GG 50 → 100; creative drop `library` from its building list;
  charismatic-25%-XP model `[decide]`; Hammurabi aggressive+organized, Brennus
  charismatic+spiritual, Gilgamesh creative+protective. (The free-vs-double-speed
  model itself is B4.)
- **A10. Projects/spaceship** (`data/projects.json`; test `test_win_conditions*.gd`):
  costs 1000–2000 per game-data §29.2/audit §4; counts casing ×5, thrusters ×5,
  engines ×2; Apollo 1600, Manhattan 1500 (they may stay buildings — the cost is the
  parity item).
- **A11. Globals** (`data/constants.json`): growth 12+8·pop → 20+2·pop `[decide]`;
  `min_settlement_distance` 3 → 2 `[decide]`; heal rates → 20/15/10/5 (city/friendly/
  neutral/enemy) `[decide]` (settlement 30 and hostile 0 are ours); XP-per-combat cap
  10 (new constant — currently uncapped below 100); `experience_vs_wild_cap` 20 → 10;
  ~~`animal_xp_lifetime_cap` 10 → 5 **and fix the cap-of-10 claim in game-rules
  §9.3 — the reference value is 5**~~ **DONE 2026-07-08** (2093ccb, constant + code
  fallback + doc together); max withdrawal clamp 90 (new).
- **A12. Goody weights** (`data/goodies.json`): ~~give `settler`/`worker` the
  per-difficulty weights from game-data §29.7 (per-difficulty weighting already
  supported per §24). Tests: `tests/sim/test_goodies*.gd`.~~ **VERIFIED ALREADY
  SHIPPED 2026-07-08**: `difficulties.json` `goody_weights` columns already carry the
  §24-normalised settler/worker weights (10/10/5/0/0/0/0/0/0); the base `weight: 0`
  in goodies.json is the documented "difficulty-enabled only" convention. Goody data
  tests live in `tests/core/test_data_db.gd` (no `test_goodies*.gd` exists). No change.
- **A13. Tech-tree eras/costs** (`data/technologies.json`): future_tech 10000;
  calendar+iron_working → classical, genetics+stealth → future `[decide]` (interacts
  with era-driven systems: wild spawns, `Eras.player_era`). Full rewiring is D1.

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
- **B5. `defensive_only` unit flag** (for Machine Gun): reject attack orders in
  `_cmd_unit_command`/`can_stack_move` targeting logic; AI must not select it for
  attack passes (`player_ai.gd` attack pass filter).
- **B6. Per-resource corporation outputs** (game-rules §15.10, game-data §29.6):
  outputs scale with accessible input-resource count (×1/100 fixed math); optional
  `produces_resource` (Oil/Aluminum) granted to the org's cities' owner; maintenance
  per resource instance. Files: `econ_orgs.json`, `src/sim/econ_orgs.gd`, tests
  `test_econ_orgs.gd`.
- **B7. Worker-speed % modifiers** (serfdom, fast worker, golden ages): build-turn
  math honours a percentage; read from civic effects + unit tag. Prereq for C6.

## Phase C — new mechanics (each is a self-contained subsystem; specs in game-rules §15)

- **C1. Inflation** (§15.1): apply in the §3 upkeep/treasury phase
  (`turn_engine.gd:_update_treasury`); per-pace percent/offset (`paces.json` §29.5),
  per-difficulty multiplier (`difficulties.json` §29.10). Tests: treasury progression
  at fixed turns across paces. AI solvency sliders (`manage_economy`) must see the
  inflated expense total.
- **C2. Population rush** (§15.2, §29.8): new command (`Commands.rush_population`),
  `_cmd_rush_production` split gold/pop paths, Slavery civic gate via
  `PolicyEffects.has_flag("pop_rush")`, stacking timed anger on the settlement
  (10-turn entries, like existing timed-anger events). Tests: `test_settlement*.gd`
  hurry math, anger stacking/expiry, AI never whips below pop 1.
- **C3. Pace scaling** for anarchy/golden ages/victory delay/wild timing (§15.3,
  §29.5): multiply policy `transition_turns`, `golden_age_base_turns`, cultural/time
  victory turn thresholds, and give wild spawning its own pace column (marathon 400).
- **C4. Culture-level city defence** (§15.4, §29.4): defence modifier from the
  settlement's culture tier in `Combat` city-defence math; bombard reduces it, heals
  5%/turn. `[decide]` first whether the border-expansion curve itself moves to the
  reference geometric thresholds (D2) — the defence tiers can key off either curve.
- **C5. SDI + The Internet + nuke interception** (§15.7, §29.2): projects.json
  entries (non-spaceship projects with effects — small `projects` model extension),
  interception roll in the nuke-strike path (`src/sim/nuclear.gd`), tech-share check
  in the research phase. Also retune §5.7 nuke magnitudes to the reference block.
- **C6. Serfdom & emancipation effects** (§15.9, §29.9): worker speed (needs B7),
  cottage upgrade-rate % (generalize `faster_cottage_growth`), emancipation-pressure
  anger (contentment penalty scaled by adopter share).
- **C7. Missing units** (§29.1): Machine Gun (needs B5), War Elephant (needs B1),
  Lion (animal roster in `WildForces.spawn_animals` between wolf/panther weights).
- **C8. War-weariness deepening** (§15.8) — *optional*: keep the 2-constant model or
  adopt per-event weights; if adopted, wire into `CombatApply` outcomes. Low priority.

## Phase D — decision items (need a call before any work)

- **D1. Tech-graph parity** (largest divergence; audit §3): the reference graph
  (AND + OR prereqs, full 92-tech table below) vs the current flat all-AND rewiring.
  Adopting it needs: `prereqs_any` actually honoured in research gating + AI
  cheapest-tech choice, then a pure data pass. Affects: era pacing, wild-forces
  timing, AI openings, every playthrough test. Recommendation: adopt — costs already
  match, and OR-prereqs are what give the reference tree its multiple paths.
- **D2. Border-expansion curve**: near-linear 10 rings (current) vs reference
  geometric 5 levels ×4 speeds (§29.4). Interacts with `CultureRevolt`, `Influence`,
  fat-cross reach. If keeping ours, C4 defence tiers key off ring count.
- **D3. Intentional-deviation register**: naval rescale (A1), difficulty philosophy
  (A3), map grids/research % (A4), grassland hammer (A5), mountains workable (A5),
  building upkeep model + no-inflation interplay (C1 changes the economy's total
  load — retune `upkeep`s when C1 lands), missiles-as-defenders (2026-07-08:
  `Stack.get_defender` selects purely by strength, so the now-40-strength guided
  missile can defend a city; reference missiles cannot defend — decide with C5's
  nuke/interception work). Whatever survives review gets an
  "intentional, differs from reference" note in its game-data section; the rest gets
  scheduled.
- **D4. Humanish-only content**: `anti_tank` unit; `merchant_guild`/
  `overseas_trading_co`/`nationalist_mutual` orgs; invented promotions (accuracy I/II,
  boarding, dogfighting, air supremacy, escort, evasion, withdrawal); `sun_faith`/
  `earth_covenant` religions. Keep (and document as extensions) or cut. Reference
  promotions we lack regardless: ace, ambush, charge, leader, medic3, mobility,
  range1/2, tactics — add in A8 if promotion parity is wanted.

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
2. A-phase data passes behind the `[decide]` register (D3 review first — one sitting).
3. B1–B3 (schema; unblock A1's prereq sets and A8's drill line).
4. C1–C3 (economy trio: inflation, whipping, pace scaling — retune building upkeep
   here), then C4/C5/C7, then C6.
5. D1 tech graph last among the big items (touches everything; do when A/B are green).

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

