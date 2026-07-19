# Direct Reference Gaps — wiring plan (parked follow-ups)

Status: **PHASE 0 COMPLETE 2026-07-18** — the sourcing sitting ran the same day
the plan was written; every 0a–0j value is recorded in `game-rules.md`
§15.13–§15.21 and `game-data.md` §29.12–§29.16 (all tagged "sourced
2026-07-18") and the XML/SDK authorization is **closed again** — phases W/M/R/T
proceed docs-only. Implementation progress: Phase W complete (2026-07-18);
M1 (2026-07-19), M2/M5/M7 (2026-07-19), M3 (2026-07-19) done — M4/M6 remain in
Phase M.
Successor to
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

**DONE 2026-07-18.** One sitting, authorized by the user for that session only,
that reads the reference XML/SDK and records into `game-rules.md` §15 (rule
specs) and `game-data.md` §29 (value tables), with design-doc consent granted
for the sitting. Nothing else in this phase — no engine work. All ten items
below were captured (spec §15.13–§15.21, values §29.12–§29.16); the exit
criterion is met and the authorization is closed. Findings that corrected a
plan assumption: **0a** the carriers are the entertainment tier (theatre /
colosseum / broadcast tower + unique variants), *not* cathedrals — cathedrals
carry no culture-rate happiness in the reference (M2 note updated); **0c** the
reference settler cost is computed dynamically but lands at exactly 100 at
normal pace (adopt flat 100); **0f** the reference keeps the GP *pool*
per-city and only escalates the *threshold* per-player — and the effective
per-birth step is +100% of base (50 own + 50 same-team), not +50 (R2 note
updated); **0i** a captured settler demotes to a worker; **W6** the medic
bonus is a single best value across same-tile and adjacent sources combined
(§29.16). Original capture list:

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

- **W1. Per-city `science_bonus`** (plan A2 note): **DONE 2026-07-18** —
  summed standing-structure `science_bonus` multiplies the city's research
  commerce share in `TurnEngine._apply_research` (truncating); direct science
  yields (specialists, STRUCT_YIELD, corporations) stay outside the multiplier.
  Tests in `test_settlement.gd` (25/50, stacking, truncation, per-city); no
  existing pinned totals shifted. Original item: research income currently has
  no per-city % multiplier site — the key (library/university/observatory/
  laboratory 25, academy 50, seowon 35; verified 2026-07-11) is read only by the
  PlayerAI heuristic and the encyclopedia. Wire: apply the summed standing-
  structure `science_bonus` as a percentage multiplier on the city's research
  commerce share at the single split site (`TileOutput`/`TurnEngine` research
  aggregation), integer truncation. **Files:** `src/sim/turn_engine.gd` (or the
  settlement research aggregation site), `src/sim/settlement.gd`. **Tests:**
  `tests/sim/test_settlement.gd` (25%/50% cases, stacking, truncation),
  recalibrate any pinned research totals.
- **W2. Three Gorges Dam `unhealthy_global: 2`** (plan A2 note): **DONE
  2026-07-18** — owner-wide standing-structures scan in
  `TurnEngine._update_wellbeing` adds the summed amount to every city of the
  owner (the dam's own city included); tests in `test_settlement.gd`. Original
  item: global
  semantics — +2 unhealth in **every** city of the owner (that is what blocked
  folding it into per-city `health_penalty`). Wire a `PolicyEffects`-style
  standing-structures scan in `_update_contentment`/wellbeing. **Files:**
  `src/sim/turn_engine.gd`. **Tests:** `tests/sim/test_settlement.gd` (owner-wide
  effect, other players unaffected).
- **W3. Hippodrome `happiness_with_horse: 1`** (plan A2 note): **DONE
  2026-07-18** — generic `happiness_with_<resource>` effects-key read in
  `TurnEngine._update_contentment` (prefix parse; gated on
  `EconOrgs.accessible_resources`, so a pillaged pasture loses the face);
  tests in `test_settlement.gd`. Original item: +1 happy in the
  city while the owner has Horse accessible (`EconOrgs.accessible_resources`).
  **Files:** `src/sim/turn_engine.gd`. **Tests:** `test_settlement.gd` (with/
  without horse, resource lost ⇒ happy lost).
- **W4. Statue of Zeus `enemy_war_weariness`** (plan C8 note): **DONE
  2026-07-18** — summed over the *enemy player's* standing structures in
  `CombatApply.accrue_war_fatigue` (the single per-event site all accrual paths
  share), applied as ×(100+pct)/100 after the forced-war modifier; a captured
  statue stops counting (the scan follows city ownership). Tests in
  `test_turn_engine.gd`. Original item: +% war-weariness
  accrual on enemies at war with the owner, summed into the C8 per-event weight
  application site. **Files:** `src/sim/turn_engine.gd` (war-weariness accrual),
  possibly `src/sim/combat_apply.gd`. **Tests:** `tests/sim/test_turn_engine.gd`
  war-weariness cases.
- **W5. `collateral_damage_protection`** (plan A8 note; drill2–4 carry 20):
  **DONE 2026-07-18** — `CombatApply.spillover_taken` cuts each stacked unit's
  spillover by its summed promotion protection (damage × (100 − protection) /
  100, truncating; ≥100 = immunity), applied at the one spillover site in
  `apply_unit_result`. Tests in `test_combat.gd` (protected vs unprotected,
  drill-line summing to 60, ≥100 immunity). Original item: spillover damage in
  `Combat.resolve`/`CombatApply` currently reads no
  promotion key — reduce spillover damage *taken* by the defender's summed
  protection %, integer truncation (semantics confirmed in 0j). **Files:**
  `src/sim/combat.gd` or `src/sim/combat_apply.gd`. **Tests:**
  `tests/sim/test_combat.gd` (protected vs unprotected spillover, stacking cap).
- **W6. `same_tile_heal` / `adjacent_tile_heal`** (plan A8/D4 notes; woodsman3
  15, medic1 10/medic2 10/medic3 15+15): **DONE 2026-07-18** — per the §29.16
  finding, `TurnEngine._medic_bonus` adds a SINGLE BEST value across same-tile
  friendly units' summed `same_tile_heal` (the healer's own value competes)
  and same-landmass-adjacent-tile friendly units' summed `adjacent_tile_heal`
  (never summed across sources, not best-of-each-category; the landmass check
  reuses the now-public `Quests.landmass_labels`, computed lazily). Tests in
  `test_turn_engine.gd` (on tile, adjacent, single-best, per-carrier summing,
  hostile medic inert, cross-strait landmass gate). Original item: healing
  reads only own-unit
  `healing_bonus`. Extend the heal phase: a unit's heal rate gains the best
  `same_tile_heal` among *other* friendly units on its tile and the best
  `adjacent_tile_heal` among friendly units on adjacent tiles (reference medic
  model — best, not summed; confirm in 0j if doubted). **Files:**
  `src/sim/turn_engine.gd` heal phase. **Tests:** `tests/sim/test_turn_engine.gd`
  (medic on tile, medic adjacent, non-stacking).
- **W7. Panzer +50% vs armor** (plan A1 note; magnitude confirmed in 0j):
  **DONE 2026-07-18** — `Unit.effective_strength` now also reads the opponent's
  mapped `vs_<class>` key from the unit's own data row (same `VS_CLASS_KEY`
  channel as promotions, stacking additively); panzer carries `vs_armor: 50`.
  Tests in `test_combat.gd` (panzer vs armor 42, vs gunpowder control 28,
  +Ambush stack 49). Original item: the
  promotion-side `vs_armor` is already live (`Unit.VS_CLASS_KEY`, ambush 25) —
  add the *unit-level* `vs_armor: 50` data key to panzer and read per-unit
  vs-class keys through the same site. **Files:** `data/units.json`,
  `src/sim/unit.gd`/`src/sim/combat.gd`. **Tests:** `tests/sim/test_combat.gd`
  (panzer vs tank vs panzer-vs-infantry control).
- **W8. `unlocks_units` display sweep** (plan B1/D1 note; cosmetic): **DONE
  2026-07-18** — convention chosen and stated in `code-layout.md`: a non-unique
  unit appears under exactly ONE tech, its *final gating tech* (latest of its
  `tech_required` set by era, then cost); unique units stay omitted (they
  surface via their society's roster). Nine units re-anchored (paratrooper→
  flight, cavalry→rifling, frigate/privateer→astronomy, ironclad→steam_power,
  attack_submarine/guided_missile→radio, tactical_nuke/icbm→rocketry); the
  lists are read only by display surfaces (tech tooltip, encyclopedia,
  TextGen). `test_data_db.gd` now cross-checks every entry against
  `tech_required`, uniqueness, and pins the re-anchors. Original item: re-anchor
  each AND-set unit to the correct tech list entries (e.g. bomber appears under
  both Flight and Radio, or under its final gate only — pick one convention and
  state it in `docs/ref/code-layout.md` if it matters). **Files:**
  `data/technologies.json`. **Tests:** `tests/core/test_data_db.gd` cross-check
  that every `unlocks_units` entry's unit actually lists that tech in
  `tech_required`.

## Phase M — blocked mechanics (each a self-contained subsystem; ⓪ = needs its Phase 0 line)

- **M1. Structure obsolescence** ⓪(0e): **DONE 2026-07-19** — the shipped data
  key is the pre-existing (dead) `obsoleted_by`; the full §29.15 roster is now
  carried (23 entries — 14 wonders already had it, 9 added: walls, dun, castle
  was present, citadel, stable, ger, obelisk, stele, totem_pole, monastery).
  The single predicate is `Player.structure_obsolete(db, sid)`; the existing
  `TurnEngine._structure_effect_active` choke (contentment + production, the
  religion gate) now folds it in, and every other standing-structure
  aggregation loop filters through the predicate: output_delta yields, granary
  carry, wellbeing (health_bonus/penalty + the W2 `unhealthy_global` scan),
  barracks-civic comfort, power gate, unit XP (city + Pentagon empire scan),
  free promotions, worker speed, `heals_units`, siege HP
  (`city_max_health(s, db, owner=null)`), the W1 `science_bonus`, espionage
  flat/`espionage_output`; `Combat.settlement_defence(settle, db, owner=null)`
  (defence_bonus AND cultural_defence_bonus stop — walls/castle cases);
  `CombatApply` W4 `enemy_war_weariness`; `Specialists.slots_for` (slots
  close; already-assigned specialists persist until reassigned, the standing
  rule for every slot-shrinking event); `GlobalWarming._building_unhealth`;
  `Nuclear` nukes-enabled/shelter/meltdown scans; `Assembly` founding-wonder
  gates (an obsolete Apostolic Palace hosts no religious assembly — real
  shipped pair, AP→mass_media); `GreatPeople._player_has_active_structure`
  (Great Wall/Mausoleum effect gates; the plain variant stays for the
  build-uniqueness identity check); facade whip-anger/espionage-defense/
  city-intel readouts; `PlayerAI` missionary gate. Identity uses (presence,
  wonder score, **upkeep — still charged**, build-target lists,
  destroy-building targeting, names) deliberately unfiltered. Steam Power +50
  worker speed shipped as `worker_speed_modifier: 50` **on the tech entry**
  (summed over researched techs in `worker_build_turns` — chosen over a
  player-level effects read because worker speed already aggregates per-source
  there); net speed pinned unchanged across the Hagia Sophia transition.
  `DataDB._validate_structure_obsolete_refs` rejects dangling tech ids. Tests
  (+19): `test_policy_effects.gd` (tech source, no double-stack, transition
  pin), `test_data_db.gd` (roster pin, tech-source pin, validator),
  `test_settlement.gd` (science %, wellbeing, happiness, slots, yields),
  `test_combat.gd` (defence + resolve), `test_conquest.gd` (siege HP, never
  sold), `test_building_xp.gd`, `test_turn_engine.gd` (W4),
  `test_intelligence.gd` (castle→economics), `test_assembly.gd` (AP→
  mass_media). NOTE: §29.15 lists the monument's unique variants (obelisk/
  stele/totem_pole) but not base `monument` itself — followed exactly;
  flagged as a possible roster gap for a design-doc sitting. Buildability of
  already-obsolete structures is NOT gated (spec silent; reference blocks it —
  candidate follow-up alongside M7's `not_buildable` flag). Original item:
  per-structure `obsolete_tech`; at
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
- **M2. Culture%-slider happiness** ⓪(0a — sourced; spec §15.13, values
  §29.12): **DONE 2026-07-19** — the key is `culture_rate_happiness` in each
  carrier's `effects` dict (§29.12 named no key; flag it at the next design-doc
  sitting): theatre/pavilion 10, hippodrome 20, colosseum/odeon/ball_court/
  garden 5, broadcast_tower 10 — the full entertainment tier, nothing else.
  Read inside `_update_contentment`'s existing structures loop (so the
  `_structure_effect_active` filter — obsolescence + religion gate — applies
  per carrier for free), summed per city, then
  `pos += sum * player.slider_culture / 100` — one integer truncation over the
  per-city sum, no cap. Tests (+4 in `test_settlement.gd`): 0% inert, 50%
  scaling, the single-truncation pin (theatre+colosseum at 35% ⇒ 5, not the
  per-building 4), and a synthetic obsolete carrier excluded (no shipped
  carrier is obsoletable); `test_data_db.gd` pins the §29.12 roster and that
  no structure outside it carries the key. No existing pinned totals shifted
  (`slider_culture` defaults to 0 in every fixture). Original item:
  **entertainment-tier** buildings (theatre/colosseum/broadcast tower
  + unique variants — *not* cathedrals, which carry nothing in the reference)
  grant happiness scaled by the culture allocation rate (Σ carrier values ×
  culture% / 100, truncated once per city). **Files:** `src/sim/turn_engine.gd`
  (`_update_contentment`), `data/structures.json` (key per §29.12). **Tests:**
  `test_settlement.gd` (0%/50% slider cases, truncation).
- **M3. Air interception** ⓪(0b — sourced; spec §15.14, values §29.13):
  **DONE 2026-07-19** — the §15.14 model replaces the old placeholder
  (`interception_range`/`interception_chance` constants removed; the whole
  engagement was previously a full `Combat.resolve`). Pure helpers in
  `Combat` (`air_evasion_chance`, `intercept_chance_max`/`_current`,
  `find_interceptor`, `resolve_air_engagement`); the rolls live in
  `SimFacade._resolve_interception` at the head of the `MISSION_BOMBARD` air
  branch, so air strikes AND air city-bombardments are contested (air
  rebase/AIRLIFT is not; nuke-tagged strikers are excluded — §15.7 channel).
  Roll order per engagement: evasion (unit `evasion_chance` + Ace, cap
  `air_evasion_cap` 90; skipped when 0) → intercept roll at the best
  interceptor's current chance (unit `intercept_chance` + promotion
  `intercept_bonus`, cap `air_intercept_chance_cap` 100; air interceptors
  health-scaled, and gated on unmoved + `is_patrolling` — Air Patrol finally
  has a sim meaning; reach = `air_range`, default 0, SAMs 1) → up to
  `air_engagement_rounds` (5) rounds at `a/(a+i)` odds, damage = opponent's
  current chance × `air_interception_damage_max` (50)/100, air-interceptor
  return damage floored at `air_interception_damage_min` (10), ground/naval
  interceptors unharmed. Per the §15.5 discipline an *uncontested* mission
  consumes NO rng draws (the spec's step order rolls evasion even with no
  interceptor in reach; selection is pure, so outcomes are identical).
  New serialized per-unit state: `Unit.has_intercepted` (bool; reset with
  the per-turn flags in `player_step`). The engagement result is
  CombatResult-shaped, applied via the existing
  `CombatApply.apply_unit_result(advance=false)` (XP/promotions/war-fatigue/
  GG accrual shared); both-survive pays the striker the new
  `experience_from_withdrawal` (1). Data: units.json ships the §29.13
  columns — `intercept_chance` (fighter/jet 100, mobile_sam 50, sam_infantry
  40, destroyer 30, machine_gun/mech_inf 20; replaces the dead
  `intercept_strength` 35/60), `evasion_chance` (guided_missile 100,
  stealth_bomber/tactical_nuke 50, paratrooper 25), `air_range: 1` on both
  SAMs. NOT shipped (out of M3 scope, candidates for follow-ups): the
  §29.13 strike-cap column (`iAirCombatLimit` → air `combat_limit`), the
  paradrop leg of §15.14 (no paradrop mission exists in the engine),
  `air_range_bonus` (Range I/II) remains a dead key, and tactical_nuke's
  evasion is inert (nukes use §15.7). Tests: +12 in `test_combat.gd`
  (chance/evasion caps + promotion stacking, health scaling, interceptor
  selection gates, engagement damage quantization + min-damage floor,
  both-survive withdrawal XP, kill-XP bounds, same-seed determinism,
  serialize roundtrip), +7 in `test_air_units.gd` (facade path: intercepted
  abort, once-per-turn, evaded, missile consumed-when-intercepted, ground
  interceptor unharmed, clean run past an idle fighter, flag reset next
  turn). Original item: make `intercept_bonus` (10/20) and ace
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
- **M5. Gold-hurry retune** (documented — §15.2/§29.8; no Phase 0): **DONE
  2026-07-19** — `_cmd_rush_production` now charges
  `TurnEngine.rush_remaining_cost × rush_gold_per_hammer` (new constant, 3 —
  reference `iGoldPerProduction`); routing through `rush_remaining_cost` means
  the whip's `new_hurry_modifier` +50% just-queued surcharge applies to gold
  identically. The Universal Suffrage `can_rush_with_gold` gate is **retired**
  (flag removed from `policies.json` — the civic keeps `town_production`; the
  facade and `city_screen.gd` reads are gone; the `test_policy_effects.gd`
  nested-flag example now uses Nationhood's `can_draft`). **Anger scope
  decision:** reference adopted — NO gold-hurry anger (the `rush_anger_turns=5`
  write is deleted); pop-whip anger is a separate path (§9 timed-happiness
  channel) and stays, as does the draft's use of the `rush_anger_turns`
  channel. New facade read `rush_gold_cost(settlement_id)` mirrors
  `rush_population_cost` for the city screen's Hurry button. AI solvency is
  untouched (`PlayerAI` never gold-rushes; `test_player_ai.gd` green). Tests
  (+4 in `test_settlement.gd`): 3/hammer math + store fill, the +50% surcharge
  (450 vs 300 gold on a 100-hammer item), no anger of either kind,
  poor/nothing-to-rush/empty-queue refusals; the integration debug-console
  slice keeps adopting Universal Suffrage but notes the hurry is ungated.
  Original item: 3 gold per
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
  Phase 0): **DONE 2026-07-19** — flag name decision: **`not_buildable`**
  (top-level, general — chosen over `gp_only` so the M1-note follow-up of
  blocking already-obsolete builds can reuse it), carried by
  `military_academy` only. Enforced at `SimFacade._cmd_set_production` (the
  whole queue set is refused if any entry is a `not_buildable` structure) and
  filtered out of `PlayerAI._sorted_options`; the city screen's hardcoded
  quick-build list never offered it. `GreatPeople._act_build_structure` does
  not consult the flag, so the Great General's `build_military_academy` verb
  (and the shipped event reward granting the structure) still work.
  `DataDB._validate_structure_not_buildable` requires the flag to be a boolean
  and the structure to keep a non-queue grant path (a GP `build_<sid>` action
  in `units.json`, or an event/quest `building` reward) so a flagged entry can
  never be silently unobtainable. Tests: queue rejection in
  `tests/api/test_facade.gd` (the facade suite — the plan's
  `test_sim_facade.gd` name does not exist), GP build in
  `test_great_people.gd`, AI exclusion in `test_player_ai.gd`, flag/validator
  pins in `test_data_db.gd`. Original item: remove it from the city build
  list; it remains constructible only via
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
- **R2. Per-player GP counter** ⓪(0f — sourced; spec §15.18): **the reference
  keeps the pool per-city** and escalates only the *threshold* per-player
  (effective step +100% of base per birth — 50 own + 50 same-team — with the
  `(born÷10)+1` multiplier; shipped `gp_threshold_base` 100 confirmed,
  `gp_threshold_increase_percent` 50 is the raw define but half the effective
  step). Decide at implementation whether to adopt the reference split
  (per-city pool + per-player threshold) or the plan's original full
  per-player pool move. Save-format:
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

1. **Phase W first** — independent, small, each a one-sitting item with
   existing shipped values; burns down the dead-key list. (W7's 0j check is
   done — no waits remain.)
2. **Phase 0 sitting** — ~~one authorized session capturing 0a–0j into
   §15/§29~~ **done 2026-07-18**; every later phase now sources from the docs
   only.
3. **M1 → M2/M3/M5/M7** (M1 — **done 2026-07-19** — unblocked the Steam Power
   leftovers; M2/M5/M7 — **done 2026-07-19**; M3 — **done 2026-07-19**), then
   **M4/M6** (the Phase M remainder).
4. **Phase R last** (largest blast radius; R1/R2 touch save format — run the
   full integration gate + midgame save/load determinism after each, version
   review at phase end).
5. **Phase T** whenever convenient after Phase 0 (T1/T2 are data + small reads).

Every item lands via the standard workflow: work-type branch, suites green
(`./run_tests.sh`), doc-tier updates (design docs only with consent), merge to
main.
