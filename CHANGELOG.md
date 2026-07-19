# Changelog

All notable changes to Humanish are recorded here. Versions follow
[semantic versioning](https://semver.org).

## [Unreleased]

### Added
- **Entertainment buildings reward the culture slider.** Theatres, Colosseums,
  Broadcast Towers, and their society-unique variants now grant city happiness
  scaling with your culture allocation rate (a Theatre reads "+1 happy per 10%
  culture rate", a Colosseum "+1 per 20%") — the reference culture-rate
  happiness mechanic. The bonus is summed per city, scaled once, and stops for
  obsolete or otherwise inactive carriers.
- **Structure obsolescence.** Buildings can now go obsolete: once you research
  a structure's obsoleting technology (walls at Rifling, monasteries at
  Scientific Method, Hagia Sophia at Steam Power, the Apostolic Palace at Mass
  Media, … — the full reference roster), every one of its bonuses stops —
  yields, happiness, health, defence, unit XP, specialist slots, and special
  effects. The building remains in the city (never sold, no refund).
- **Steam Power speeds workers.** Researching Steam Power grants +50% worker
  build speed empire-wide — taking over from Hagia Sophia's identical bonus,
  which goes obsolete at the same technology.
- **Compound unit prerequisites.** Units can now require several technologies
  (all of them) and strategic resources in "all of these" / "any one of these"
  combinations — knights need Guilds + Horseback Riding and Horse + Iron;
  macemen accept Copper or Iron. The reference prerequisite sets are applied
  across the unit roster.
- **Strategic resource requirements are enforced.** Previously they were
  display-only: cities could build, players could draft, and the AI could
  queue any unit without the listed resource. Building, drafting, upgrading,
  and AI production now all require the resources (connected or imported).
- **Unit upgrades check prerequisites.** Upgrading into a unit now requires
  its technologies and resources, not just gold.
- **Chance first strikes.** Units and promotions can carry a chance stat that
  grants 0–N extra first strikes rolled once per battle; Navy SEALs and
  Skirmishers now fight at their reference 1 + 0–1 first strikes.
- **Per-unit siege damage caps.** Siege weapons soften defenders down to a
  per-unit health floor (catapult/trebuchet/hwacha 25%, cannon 20%,
  artillery 15%) instead of near-killing them — other arms finish the job.

### Changed
- **Gold hurry retuned to the reference model.** Hurrying production with gold
  now costs 3 gold per hammer of the remaining cost (was 1), is available
  under every government (the Universal Suffrage requirement is gone — the
  civic keeps its +1 town production), keeps the +50% surcharge on an item
  queued the same turn, and no longer angers the city (the old flat 5-turn
  rush anger is removed; whipping population still angers as before).
- **The Military Academy is no longer city-buildable.** It can only be raised
  by a Great General's Build Military Academy action — it no longer appears in
  any production queue, and the AI no longer builds it directly.

### Fixed
- **Sun Faith and Earth Covenant are real religions now.** Both referenced
  holy-site structures that didn't exist and, having no founding technology,
  were silently auto-founded on turn 1 of every game (masking base city
  unhealthiness with a free health bonus). They now have proper holy-site
  structures (Temple of the Sun, Grove Sanctuary) and founding technologies
  (Calendar, Agriculture), and the data loader cross-checks every belief's
  structure and tech references.
- **Animal lifetime XP cap corrected to 5** (was 10, which is the reference's
  barbarian cap, not the animal cap).
- **Mounted and submarine withdrawal chances restored** — chariot through
  cavalry/cossack, gunship, the unique mounted units, and the submarine line
  had lost their withdrawal values.
- **Guided Missile works.** It shipped with strength 0 (strikes could never
  hurt anything); it now strikes at its reference strength 40 and is consumed
  on use — launch, hit, miss, or interception — like the nuclear weapons.
- **Drill promotions do something.** Their first-strike bonus was read
  nowhere; Drill I–IV now actually grant their first strikes in combat.

## [0.5.2] - 2026-07-07 "Full Feature Alpha 3"

### Added
- **Three-rate economy slider panel.** Finance and research set directly in ±10%
  steps; the economy (treasury) rate is the derived remainder.
- **Espionage system (§7.1).** Passive intel with information fog, spy
  invisibility, and AI spies; spy-unit-on-tile missions; and the complete active
  mission catalogue.
- **Quest subsystem.** Multi-turn quest tracking with the full 18-quest
  catalogue (aim/constraint predicates), quest-armed popups with descriptions, a
  random era-chance trigger, and a 20-turn quest grace period.
- **Reworked random-event system (§9).** Data-driven framework plus a broad
  catalogue: pure-verb events; STRUCT_YIELD/SPEC/SGP/SPREAD, ESP, PEACE-WAR,
  DESTROY_BLDG, PILLAGE, and REVOLT effect verbs; niche-system prereqs; and an
  event-choice popup. Events (and quests) can be toggled off per game.
- **Global warming (§11)** replaces per-tile pollution.
- **Complete 12-record goody-hut reward catalogue (§5.3).**
- **Map start-fairness normalization** (steps 1, 8, 9) for more even starts (§5.2).
- **Diplomacy denial-reason layer** — deal refusals now explain themselves (§5.4).
- **Society-driven city naming** with historical city-name lists for all 34
  civilizations, plus city-screen navigation.
- **Combat unit strength** (base + net effective) shown in the selection panel.
- **All combat units can Explore**, not just recon units.
- **Work boats** apply a sea improvement instantly and are consumed on use.

### Changed
- Insolvency now disbands units only — structures are never sold.
- Fortify is restricted to land combat units (no bonus for mounted units).
- Quick Load rebound to **F9** as documented (was `KEY_F14`).
- Selection panel gains a dark-charcoal background hugged to its content.
- `run_tests.sh` now exits non-zero when tests fail.

### Fixed
- Economy slider readouts and on-tile stack member buttons are left-justified.
- Selection panel's action list now reflects the selected unit.
- Save lists are date-sorted; the main bar shows a signed gold rate.
- Map clicks release HUD focus, arrow keys pan only, and turn start focuses the
  next idle unit.
- Workers consume work boats on build and no longer place cottages on zero-food
  tiles.
- Remembered fog lightened; culture water reach capped; capital no longer
  floods; scout coast-trap fixed.
- New Game from the pause menu unpauses the tree before returning to the title.

## [0.5.1] - 2026-06-20 "Full Feature Alpha 2"

### Added
- **Reference-parity simulation pass (Phases 0.1–8).** Eight phases align core
  mechanics with the original reference: firepower-blended per-hit combat damage
  (Phase 0.1); affine food-box growth with carry cap (Phase 0.2); stacked
  production-yield percent chain (Phase 0.3); canonical tech-cost percent chain
  (Phase 0.4); MOVE_DENOMINATOR=60 with transport route costs (Phase 0.5);
  research handicaps split human vs AI (Phase 0.6).
- **Score win condition.** Score added as the 7th win condition (Phase 1).
- **Specialists promoted to first-class data table** (Phase 2).
- **Goody huts** added to map generation with start-fairness normalization
  (Phase 3).
- **Full random event lifecycle** (Phase 4): trigger → begin (with player
  choice) → apply effects → expire, all data-driven via `data/events.json` and
  `data/event_triggers.json`. Influenza outbreak replaces the Great Plague as a
  canonical multi-choice event.
- **Corporations** (Phase 5): full HQ + executive model, resource-count output,
  per-turn maintenance, and city-level corporation screen.
- **Espionage mission catalogue** (Phase 6): costs, target gates, interception
  risk, all data-driven via `data/espionage.json`.
- **Persistent diplomatic deals + AI attitude & memory** (Phase 7): deal
  resource access wired into corporation inputs; AI tracks deals and attitude
  across turns.
- **Vassalage** (Phase 8): capitulation, liberation, and shared war/peace.
- **Ocean entry gated by tech + hull**, with friendly-territory waiver.
- **Terrain-aware sight + line-of-sight blocking**: hills/mountains extend range
  for units on high ground and block vision through them.
- **Cultural borders grant live vision** plus a one-tile surrounding ring.
- **Persistent fog of war**: explored tiles stay dimly revealed, and the
  last-seen tile contents are remembered across save/load.
- **Open-borders agreement** + cultural border movement blocking for closed
  borders.
- **City assault** (§4.8): a player or wild raider captures/razes an undefended
  city in one attack; the capital is always off-limits to raiders.
- **Raider camp defender**: a garrisoned unit always defends raider camps.
- **First-contact notification** when two players meet for the first time.
- **Tile terrain readout** shown in the HUD alongside a selected unit or city.
- Mine improvement restricted to hills tiles (terrain gating).
- **Enter/Numpad-Enter** ends the turn from the main view.
- **Sleep order** exposed for all units in the selection panel.
- **Explore mission** steers toward unrevealed map edges instead of wandering.
- **Auto-center** the world view on the next idle unit when a unit finishes its
  orders.

### Fixed
- City centre tile is always worked so cities grow even with no manual
  assignments.
- Full 5×5 work-radius grid in the city view shows usable tiles only, with a
  `#` marker on currently worked tiles; repeat-queue unit items now work.
- Work boat builds Fishing Boats and docks in its own city in one turn.
- Tile readout shows the computed yield including all improvements.
- Timed events no longer re-fire while still active.
- Raider's Camp tile now shows cultural borders correctly.
- City assault UI surfaces feedback when an attack holds (defender wins).
- Worker build/improve actions hidden on settlement tiles.
- Right-click correctly attacks a wild or enemy city via an on-tile escort.
- Minimap click re-centers the main world view.
- New maps now vary each launch (randomized default seed + stretched
  height-field contrast).
- Load screen save list is scrollable on long file lists.

## [0.5.0] - 2026-06-09

### Added
- **Three-phase AI overhaul.** Phase A — difficulty handicap (`ai_bonus`) wired
  to AI production and research (§2.2). Phase B — competent deterministic
  `PlayerAI` brain: role-ranked production, four-pass unit playbook, settler
  city-site scoring, worker automation, recon exploration (§B1–B7). Phase C —
  trait-driven strategic focus (`expand`/`military`/`economy`/`science` axes)
  layered on top (§C1–C5). Phase D — AI tuning, per-turn cost audit, and
  documentation (§D1–D3).
- **Diplomatic victory.** UN / Apostolic Palace elections with a two-candidate
  runoff; the rival candidate must be a non-defiant full member (§7.3).
- **Worker chop/clear orders.** Explicit forest and jungle removal (chop)
  with tech bonus and border-based scaling (§4.11).
- **City health and growth display.** The city screen now shows health and
  growth status.
- **Production queue editing.** Up/down reorder buttons; duplicate-item
  prevention.
- **Leader selection.** Pick a leader for your society in the New Game menu.
- **Left-button click-and-drag** pans the map; middle-click drag also pans.
- **City produce-nothing.** Cities can explicitly choose to produce nothing.
- **Base unit availability.** City build chooser always offers warrior,
  settler, and worker.
- **Difficulty per-city handicaps.** Growth, health, and happiness modifiers
  per difficulty, limited to human players (§2.2).
- **Trait health.** Leader/society trait health (Expansive +2) wired into
  wellbeing.
- **Feature health.** Worked-tile feature health wired into wellbeing (§4.6).

### Changed
- Difficulty city handicaps apply to human players only (§2.2).
- Diplomatic victory comes solely from the assembly UN election (§10).

### Fixed
- Peace-clause trade notification and bare\_facade null hooks.
- City build chooser missing base units (warrior/settler/worker).
- AI workers now automate construction (resources, then roads, then sleep).
- Work boat gated by tech and coastal access; water units in general.
- Resource-bound worker improvements require a visible resource.
- Moving a worker cancels its in-progress improvement build.
- Worker improvement builds complete over time.
- City health/growth display now visible.
- Middle-click panning was unreliable on some setups.

## [0.4.4] - 2026-06-09

### Added
- **Wild-forces overhaul.** Barbarians, raider camps, and wildlife now spawn
  with an original-reference–derived model tuned per difficulty
  and game pace, keeping early turns calm and scaling threat with the world.
- **Wild animals.** Wolves, panthers, and bears roam unexplored land, hunt
  lone or unfortified units, and stay out of cities. They grant limited combat
  experience and no promotions.
- **Naval raiders.** Sea-domain wild forces patrol open water and attack
  coastal shipping once any civilization can sail.
- **Worker improvement actions.** Workers show a "Build" button for every
  improvement valid on their current tile, with full landform, tech, river,
  and feature validation.
- **Scout Explore mission.** Recon units can be set to auto-explore; they
  wander toward unseen tiles, avoid combat, skip the idle-unit cycle, and stop
  (with an alert) when an enemy comes into view.
- **Heal stances.** New "Sleep Until Healed" and "Fortify Until Healed" orders
  hold an injured unit in place until it recovers, then wake it automatically.
- **Minimap.** A fog-aware minimap in the lower-right shows explored terrain
  and your settlements; it can be toggled from the Options screen.
- **Permanent alliances.** An optional new-game rule lets allied civilizations
  form unbreakable alliances; the diplomacy screen offers the action when both
  sides are at peace.
- **Production queue editing.** Click a queued item in the City screen to
  remove it.
- **Larger games.** Setup now offers all six world sizes (Duel through Huge)
  and removes the four-player cap; the suggested player count scales with the
  chosen world size and is shown the moment the screen opens.
- **Debug builds** gain a "Toggle Fog of War" button on the Options screen.

### Changed
- **Diplomacy screen** now lists only civilizations you have actually met.
  Contact is made when either side sights the other's unit, city, or border,
  and is permanent once established.
- **Capitals can no longer be disbanded** — the Disband action is both hidden
  and rejected for the city holding your palace.
- Advisor and info screens have a consistent bottom Close/Cancel button,
  including the tech chooser.

### Fixed
- Maps now wrap correctly east–west; routes and fog reveal across the map seam.
  Island maps keep a hard geographic edge.
- Zooming now keeps the point under the cursor fixed instead of drifting.
- Wild units can no longer stack onto a city tile after winning a fight, and
  can damage but never destroy a capital.
- A confirming flash now marks the destination tile when you issue a move.
- Wild units read as "Wild …"/"Bandit …" in the tile readout instead of a
  broken owner label.
- City growth now posts a "grew to population N" notification each turn.
- Losing a unit in combat — including to wild forces — now always posts a
  notification.
- Resumed saved games stay in sync: alliance and intel data is no longer
  mismatched after a load, fixing a determinism break.
