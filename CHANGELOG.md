# Changelog

All notable changes to Humanish are recorded here. Versions follow
[semantic versioning](https://semver.org).

## [Unreleased]

### Changed
- **Goody-hut discovery messages now name the actual reward.** The terse
  "Discovery: unit" log line is replaced by a descriptive message per reward
  type — "Discovery! A wandering Warrior joins your explorer.", "Discovery!
  Found 45 gold.", "Discovery! Learned Pottery.", the XP / map-reveal / heal
  lines, and an "Ambush!" variant for the wounding/raider goodies.

### Fixed
- **The economy sliders now live-update the gold-per-turn readout.** Moving
  commerce into Finance raises gold income, but the HUD's net gold/turn figure
  (in the turn/score bar) stayed stale until an unrelated repaint because the
  `SET_SLIDERS` command only marked the `HUD_GROUPS` dirty region, not the
  `DATA_PANES` region the gold readout repaints on. A slider change now dirties
  both, so the gold/turn display updates immediately.
- **Insolvency disbands are no longer silent.** When a bankrupt player's unit was
  disbanded to relieve upkeep it vanished with no log entry (a confusing "my units
  disappeared" report). The disband now surfaces a clear notification —
  "Bankruptcy: your Warrior was disbanded (treasury empty)."
- **The City screen's Output totals are now live and correct.** Food /
  Production / Commerce showed the values last computed by the turn pipeline, so
  locking or unlocking a worked tile left the totals stale. The output-summation
  is now a pure shared helper (`TurnEngine.compute_settlement_output`) that the
  growth pipeline and the screen (via `SimFacade.settlement_output`) both use, so
  the displayed total always equals what the city is actually credited.
- **The city-centre tile can no longer be un-worked.** The centre is worked for
  free; its work-grid button is now inert and the `SET_TILE_WORKED` command
  rejects any attempt to un-work the centre (defense-in-depth).
- **Working a new tile at the worker cap is now a no-op.** `SET_TILE_WORKED`
  rejects a lock that would exceed the city's worker budget (population minus
  discontented and specialists); a slot must first be freed by un-working a tile.
- **The City screen's "Hurry (Gold)" button is only offered when it can be
  used.** It is now gated through a single facade predicate
  (`SimFacade.can_rush_gold`) — a queued item with hammers still owed and a
  treasury that covers the cost — and hidden entirely when there is nothing to
  rush.
- **Insolvency no longer scraps a player's whole army in one turn.** When a
  player went broke past the grace period, the disband loop compared every
  disband against the same stale negative treasury and never recomputed upkeep,
  so a single insolvent turn disbanded *every* unit the player owned. It now
  recomputes net gold from the reduced unit set after each disband and stops the
  instant the player is solvent again — shedding only as many units as upkeep
  requires.
- **A city founded on barren terrain now produces.** The city-centre tile was
  given no minimum yield, so a city on grassland (2 food / 0 production) made 0
  hammers. The centre is now floored to the reference minimum of 2 food /
  1 production / 1 commerce.
- **Mines can be built on flat-land resources.** Iron and copper can sit on
  plains/grassland but the connecting Mine was hills-only, leaving the resource
  permanently unimprovable. A landform-restricted improvement is now allowed on a
  tile whose resource requires exactly that improvement.
- **The "Build Mine" button now actually appears on flat-land resources.** The
  earlier flat-land mine fix corrected the build command, but the HUD worker
  panel still pre-filtered its candidate improvements by raw landform, so it
  silently dropped Mine on flat iron/copper before the resource-aware legality
  check ever ran and the button never showed. The panel now delegates every
  improvement's legality to the facade's `can_build_improvement` predicate, so
  its offered list can no longer diverge from what the command accepts.
- **"Open City" now works with a non-city unit selected.** Pressing Open City
  while a scout (or any unit) stood on one of your cities did nothing, because the
  city id was discarded and the screen resolved the wrong (empty) selection. The
  city is now selected first so the advisor opens.
- **The Diplomacy screen shows civilization and leader names** for each met civ,
  instead of the bare "Player N".
- **The new-game setup screen scrolls.** With many players configured the form
  overflowed the window and pushed the lower options and Start button off-screen;
  it is now hosted in a scroll container.
- **Goody huts are drawn on the map.** Discovery sites rendered nothing, so a
  scout that walked onto one produced a "free" unit with no visible cause. A hut
  glyph now marks visible discovery tiles.

## [0.6.1] - 2026-07-19 "beta 1"

### Added
- **Selection-panel buttons for Spread Belief, Spread Corporation, and Great
  Person actions.** Three command families that previously existed only in the
  API now have clickable buttons on the selected unit's panel, each shown only
  when the order would actually succeed: a **Missionary** on a faithless city
  offers *Spread \<Religion\>*; an **Executive** on an eligible city offers
  *Spread \<Corporation\> (N gold)* with the computed cost on the label (and
  only while you can afford it); a **Great Person** offers one button per
  ability it can use right now, with cost/effect previews on the labels —
  e.g. *Golden Age (2 GP)*, *Trade Mission (+2000 gold)*, *Hurry Production
  (+500 hammers)*, *Great Work (+4000 culture)*, *Build Academy*. Great
  Person buttons sit in a second column beside the main action buttons, act
  immediately (no confirmation), and a Great Spy's *Infiltration (+3000 EP)*
  targets the foreign city it stands in.

### Changed
- **Mercantilism now bans only foreign corporations.** The two
  corporation-banning civics are split: **State Property** still shuts down
  every corporation, while **Mercantilism** now suspends only corporations
  whose **headquarters city you do not own** — your own-HQ corporation keeps
  operating and its executives can still open franchises in your cities. The
  ownership test is strict: an ally's or vassal's headquarters still counts
  as foreign. A banned corporation's franchises are not removed — they go
  **dormant** (no yields, no upkeep, no produced resource, no headquarters
  gold) and resume automatically when you change civics; executives cannot
  spread a corporation into a city where it would sit dormant.
- **Corporations no longer spread on their own.** The passive
  religion-style spread channel is removed (the reference model has no
  organic corporation spread): a corporation now reaches a new city only
  via the deliberate **Executive** action, at founding, or with a captured
  city. The executive's price follows the reference formula — base **50**
  gold scaled by the current inflation rate, **doubled** into a foreign
  (non-vassal) city — replacing the old flat 100-gold fee, and the target
  city must have access to at least one of the corporation's input
  resources. Spreading into an empty city always succeeds; a city already
  hosting a corporation refuses another (one corporation per city, as
  before). The founder's treasury is no longer silently drained by
  automatic spread.

## [0.6.0] - 2026-07-19 "Reference Wiring"

Completes the direct-reference-gaps wiring plan (Phases W, M, R, T).
Save-format note: saves from 0.5.x load and migrate automatically; saves
written by 0.6.0 are **not** loadable by older builds (the Great Person
threshold moved from per-city to per-player state). Shipped as a minor
bump per the pre-1.0 alpha versioning policy.

### Changed
- **AI difficulty handicaps now follow the reference cost model.** Each
  difficulty carries four per-difficulty AI columns (the reference §29.10
  table): AI **unit** and **building costs** scale from 160% at Settler
  (easy levels penalize the computer) down to 60% at Deity, AI **unit
  upkeep** scales 100% → 60% from Noble to Deity, and the AI **growth
  threshold** scales from 160% at Settler (slower growth) to 80% at Deity
  (faster). The old flat production-yield boost is retired — AI hammer
  output now equals a human's — while the `ai_bonus` column remains solely
  as the AI research-yield scaler (0 at Noble → 70 at Deity). Human players
  are unaffected by all four columns; whip and gold-hurry prices follow the
  AI's discounted costs coherently.

### Changed
- **Terrain features now give fractional city health.** A worked Forest
  contributes **+0.5** health to its city (was +1), a worked Jungle **−0.25**
  (was −1), and worked Flood Plains **−0.4** (was −1) — the reference values.
  The fractions from all worked tiles are added up and the net rounds toward
  zero: two forests give +1 health, three forests still only +1, and a single
  jungle or flood plains costs nothing until several accumulate. Oasis (+1)
  and Fallout (−1) keep their whole-point values. The Encyclopedia shows the
  fractional value on each feature's page.

### Added
- **Idle citizens now work as Citizen specialists.** A citizen with no tile
  left to work and no specialist post — because the city outgrew its land,
  tiles are blockaded away, or citizen automation is off with too few locked
  tiles — automatically becomes a **Citizen specialist** worth +1 production
  (no Great Person points). Citizens return to the land as soon as tiles or
  slots open up; the city screen shows the auto-filled count separately.

### Changed
- **Settled Great People no longer consume a population slot.** A Great
  Person who joins a city is now a **free** specialist on top of the
  population: its yields no longer cost the city a tile worker, and it no
  longer counts against the population cap when assigning specialists.
- **The settled Great General is now a military instructor.** Instead of the
  former +2 production stand-in, a settled Great General yields nothing
  directly but grants **+2 starting experience** to every combat-capable
  unit trained in its city (stacking with barracks-style building XP and
  with each other). Drafted units now receive **half the city's total
  starting XP** (rounded down) instead of only the civic bonus.
- **Great Person threshold is now empire-wide.** Each city still banks its own
  Great Person point pool, but the threshold a pool must reach is shared by
  the whole civilization: it starts at 100 (scaled by game pace — Quick 67,
  Epic 150, Marathon 300) and rises by 100 for every Great Person born
  anywhere in your empire (100, 200, 300, …), with the increase doubling from
  the 10th Great Person on. A Great Person born to an allied player raises
  your threshold by half as much. Previously each city escalated its own
  threshold independently, so wide empires farmed cheap Great People from
  every new city. Great Generals remain a separate counter. **Save format:**
  the threshold state moved from cities onto players; older saves migrate
  automatically (birth counts are rebuilt from each city's tally).

### Added
- **Settlers and Workers are built with food.** While a Settler or Worker
  heads a city's production queue the city's food surplus is added to
  production toward it — on top of the normal hammers, after all percentage
  modifiers — and **growth pauses**: the food box is frozen (stored food is
  kept, nothing new banks) until the unit finishes, though a starving city
  still drains its store and can lose population. The city screen's Growth
  line reads "paused — training" while in effect. Settler cost stays at the
  reference 100 (Worker 60); both can still be whipped or gold-hurried on
  their remaining hammer cost as before.
- **Spaceship part counts and arrival countdown.** The Space Race now counts
  parts **per type** — SS Casing ×5, SS Thrusters ×5, SS Engine ×2, and one
  each of Cockpit, Life Support, Stasis Chamber, and Docking Bay (16 parts at
  full build); building a duplicate of an already-filled type no longer
  advances the race. One of every part type **launches the ship**: arrival
  takes a 10-turn countdown, scaled by game pace (Quick 6 / Epic 15 /
  Marathon 30) and stretched by missing optional parts (each missing engine
  +25%, each missing thruster +20%). Missing casings risk the arrival —
  −20% success per missing casing; a failed arrival loses the launch (the
  built parts remain and the ship re-launches). Losing your capital destroys
  a spaceship in flight. Older saves migrate their flat stage count.
- **Civilian units are captured, not killed.** Overrunning a tile that falls
  with a Worker or Settler on it now hands the attacker a fresh Worker
  (a captured Settler demotes to a Worker); the captured unit arrives at
  full health with no experience and cannot act until the next turn. Wild
  raiders never capture — against them the unit simply dies. Losing a unit
  to capture adds war fatigue (2 weight), capturing one adds a little (1).
- **Air interception.** Air strikes and air bombardments can now be contested
  over the target tile (the reference model). Fighters on **Air Patrol** (the
  intercept stance, once per turn per interceptor) and ground/naval anti-air —
  SAM Infantry, Mobile SAM, Machine Gun, Mechanized Infantry, Destroyer —
  may engage an inbound air mission within their interception range. The
  striker may evade first (Stealth Bomber 50%, Guided Missile, Ace +25%);
  otherwise the best interceptor rolls its interception chance (fighters
  100%, boosted by the Interception promotions, scaled by an air
  interceptor's health) and, on a hit, fights up to five engagement rounds:
  the intercepted mission is aborted with no ground damage, and interception
  damage flows both ways against air interceptors (ground/naval interceptors
  engage unharmed). One-use weapons are still consumed when intercepted.
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
