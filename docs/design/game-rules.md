# Game Rules — Generic Specification

A precise, implementation-level description of the mechanics for a turn-based,
empire-building strategy game played by multiple competing players on a tiled world map.
This specification is written generically: it defines the *types* of rules, the state
they read and mutate, and the relationships between quantities, so that an independent
implementation can reproduce the behavior. Specific numbers, formulas, and named content
are intentionally treated as **configurable data** rather than fixed values.

> **Two ground rules for an implementation**
> 1. **All rule math is integer math.** Resource quantities, treasury, research, and
>    influence are stored as integers (optionally at a fixed higher precision to avoid
>    rounding loss). Fractional/real numbers are used only for display.
> 2. **All randomness uses one shared, seeded generator** consumed in a fixed, ordered
>    sequence. To stay reproducible across machines and saves, recreate the seed and the
>    exact order of draws.

---

## 1. World model

### 1.1 Map & tiles
* The world is a rectangular grid of **tiles**, with dimensions chosen at game start from
  a set of preset world sizes. The grid may wrap on one or both axes.
* Each tile has: a **landform class** (e.g. mountain, hill, flat land, open water), a
  **base terrain type**, an optional **surface feature**, an optional **resource**, an
  optional **improvement** built on it, an optional **transport link**, and an **owner**
  derived from cultural influence.
* **Regions** are connected bodies of like domain (contiguous land masses or water
  bodies), used for high-level grouping.
* **Supply groups** are connected, commonly-owned, transport-linked sets of tiles used to
  distribute resources and trade across a player's territory.

### 1.2 Directions & adjacency
* Tiles use eight compass directions and four cardinal directions for adjacency.
* Distance between tiles is measured by grid-step distance, correctly accounting for any
  map wrapping.

### 1.3 Tile output
Each tile produces a small vector of **output types** (broadly: sustenance, construction
capacity, and a generic economic output that later splits into finance, research,
culture, and intelligence). A tile's output is computed as:

```
natural output = terrain base output
               + surface-feature output adjustments
               + landform adjustments (hills, peaks, adjacency to water, rivers)
final output   = natural output
               + connected-resource output
               + improvement output (gated by technology and transport links)
               + transport-link output adjustments
               − feature/penalty adjustments
clamped so no output falls below zero
```

Improvement output can increase over time and when enabling technologies are unlocked.
Some water outputs require a specific unit action or technology before they are realized.

### 1.4 Rivers
Rivers are **borders between tiles**, not a feature painted on a tile. Each river is a
connected chain of tile-edge segments that runs from an inland high point down to the sea.

* **Storage.** A tile records only its **north** and **west** river edges; a tile's south
  edge is the north edge of the tile below it, and its east edge is the west edge of the
  tile to its right. This represents every border on the map exactly once (no
  double-counting) and serializes with the tiles, so rivers survive save/load and are part
  of the determinism gate. "Does this tile touch a river?" is the OR of its four borders.
* **Generation.** River count scales with land area (a global tunable). Each river picks an
  interior source tile (far from water, with a bias toward hills/mountains) and walks the
  lattice of tile corners toward the coast, following a breadth-first distance-to-water
  field with occasional meander, marking the border segment crossed at each step. The walk
  uses the shared map RNG, so the river network is deterministic for the map seed.
* **Effects.** A settlement whose tile touches a river has **fresh water** (§4.6), the same
  as being adjacent to a water body or an oasis. (River commerce bonuses to adjacent tiles
  and the river-crossing movement/attack penalties are described in the data spec and are
  not yet wired into the rule code.)
* **Presentation.** The renderer draws each river edge as a water-blue line *between* tiles,
  on tiles the active player has explored.

---

## 2. Time, ages, and pacing

* Play advances in discrete **turns**, each mapped to an in-world date by a pacing
  configuration.
* A **game-pace setting** scales costs and thresholds uniformly through percentage
  multipliers (growth, research, build, and special-event timers). Slower paces multiply
  thresholds and costs together so relative balance is preserved.
* **Ages/eras** gate which units and structures are available, may scale certain costs,
  and influence presentation and AI behavior. See §2.1 for the implemented model.
* A **difficulty setting** supplies a family of per-level modifiers (handicaps and
  bonuses for computer players, free starting units, comfort/health bonuses, and a number
  of "free" early combat wins against wild/raider forces).

### 2.1 Eras (provisional)
> **⚠️ Provisional — preliminary, not verified.** This subsection documents a first-pass
> era model as actually implemented (`src/sim/eras.gd`). The era→effect wiring, the
> growth-scale percentages, and the revolt era term below are placeholders drawn from a
> preliminary reading of the reference game; they have **not** been checked against the
> actual mechanics and are expected to be tuned. All quantities are integer math per the
> engine invariants (percentages are integer 0–100).

The seven eras (Ancient 0 → Future 6) and their tunables live in `data/ages.json`; the
canonical table is `game-data.md` §1. Eras are **derived, not separately tracked**:

* **A player's era** is the **highest era among the technologies they have researched**
  (Ancient / 0 when they know none). Each technology carries an `era` tag
  (`data/technologies.json`); the player's era is the maximum over that set, recomputed
  whenever techs change. A wild/unknown player is Ancient.
* **Unit and structure availability** is already gated on technology (§6.3), and every
  gating tech belongs to an era, so era-gating is **transitive** — a unit/structure
  "belongs to" the era of its required tech (a structure may also carry its own `era`
  tag). No separate era gate is applied, so the two can never disagree.
* **Advancement** is automatic: when a freshly-researched tech (or a Great Scientist's
  instant tech) raises the player's maximum era, they **enter the new era** that turn. The
  transition is surfaced once as a player notification and an `era_advanced` signal.

Mechanical effects currently wired to the era:

* **Settlement growth** — the food threshold to grow a population point is scaled by the
  owner's era via `growth_threshold_scale` (Ancient/Classical 100, Medieval 110,
  Renaissance 115, Industrial 120, Modern 125, Future 130), applied **on top of** the
  game-pace growth multiplier (§4.2). Later eras therefore grow cities more slowly.
* **Cultural revolt** — the "era number" term in the §4.9 revolt-power formula is the
  challenging rival's real era (floored at 1), replacing the former technologies-count
  proxy.
* **Presentation** — the current player's era is shown on the HUD turn/score bar; the
  engine exposes it through `SimFacade.get_player_era(player_id)` → `{index, id, name}`.

Persistence and determinism: `Player.era` is a serialized **cache** used only to detect
advancement for the notification; every rule above reads the era **live** (recomputed from
techs), so the cache can never desync a mechanic. The `start_turn` field in
`data/ages.json` is currently **descriptive only** (it does not force or gate era entry —
research does).

---

## 3. Turn structure (authoritative order)

The order of operations is itself a rule; effects depend on it.

```
Whole-world step (runs once every player has ended their turn):
  1. Resolve and expire pending trades between players.
  2. For each surviving alliance: advance shared progress (research, war timers).
  3. Per-tile upkeep across the whole map.
  4. Spawn wild/raider settlements and units.
  5. Apply environmental degradation (pollution-driven terrain change).
  6. Assign or reassign special institutional sites (e.g. founding locations).
  7. Resolve assembly/voting bodies.
  8. Increment the turn counter and elapsed-turn counter.
  9. Activate the next player or set of players (sequential or simultaneous).
 10. Test every enabled win condition.

Per-player step (when a player becomes active):
  1. Pre-turn bookkeeping (computer players plan here).
  2. Assign each settlement's workers to tiles.
  3. Update treasury: income minus upkeep; handle insolvency.
  4. Apply research progress to the current project.
  5. Apply intelligence/espionage accumulation.
  6. Run each settlement's per-turn step.
  7. Tick down timed states (celebrations, transitions).
  8. Re-validate active policies; refresh trade routes; update war-fatigue.
  9. Process scripted/random events.

Per-settlement step (for each settlement):
  growth → production → culture accumulation → cultural spread to surrounding tiles
  → belief/affiliation processing → decay/upkeep → special-person progress → maintenance
```

Each phase first consults an optional **override hook**; if the hook handles the phase,
the built-in rule is skipped. This seam lets content packs replace any rule.

---

## 4. Settlements

### 4.1 Founding
* A dedicated founder unit establishes a settlement on a tile that satisfies placement
  rules: minimum spacing from existing settlements and valid landform/terrain. Founding
  consumes the unit and creates a size-one settlement that immediately claims its own
  tile and a small surrounding area of cultural influence.

### 4.2 Population growth
Surplus sustenance accumulates in a "store" each turn:

* The per-turn change equals produced sustenance minus consumed sustenance (consumption
  scales with population). If the store reaches a **growth threshold**, population
  increases by one and a configurable portion of the store is carried over. If the store
  goes negative, the settlement starves and population may decrease.
* The growth threshold rises with current population, is scaled by the global pacing
  setting and the starting age, and (for computer players) by difficulty modifiers. A
  fraction of stored sustenance may be retained across growth, capped relative to the
  threshold.

### 4.3 Output & the economic split
* A settlement's base output for each type is the sum of its worked tiles, assigned
  specialists, structures, and trade routes, then scaled by a percentage modifier.
* The generic economic output is partitioned by the player's adjustable **allocation
  sliders** into finance, research, culture, and intelligence. The slider values sum to a
  whole, may be constrained to allowed increments by the player's governing policies, and
  some channels may have enforced minimums.

### 4.4 Production
* A settlement processes an **order queue** of buildable items (units, structures,
  large projects, or continuous conversion processes).
* Construction capacity accumulates each turn, scaled by modifiers from structures,
  policies, resources, and traits. For certain items, surplus sustenance may be converted
  into construction capacity.
* An item completes when accumulated capacity meets its required cost; any surplus carries
  over to the next item, within bounds.
* **Rushing**: an item may be completed immediately by spending treasury or by sacrificing
  population. Rushing introduces a temporary discontent penalty.

### 4.5 Contentment (happiness model)
A settlement tracks separate **positive** and **negative** sentiment totals; their
difference yields discontented citizens.

* **Positive sentiment** is the sum of all favorable contributions (size-related comfort,
  garrisoned forces, dominant belief, favorable structures, favorable features and
  resources, favorable cultural output, empire-wide and regional bonuses, leader/trait
  bonuses, alliance bonuses, and temporary celebration effects).
* **Negative sentiment** is driven by an accumulated "anger percentage" applied to the
  population — sourced from overcrowding, lack of garrison, cultural pressure, belief
  conflict, recent rushing, conscription, defiance of assembly rulings, war-fatigue, and
  policy effects — reduced by all the unfavorable structure/feature/resource/belief
  contributions, plus subjugation discontent and intelligence-driven discontent.
* Discontented citizens equal the clamped difference of negative over positive sentiment,
  bounded by population. Discontented citizens work no tiles and produce nothing. If
  discontent meets or exceeds population, the settlement falls into **disorder** and
  produces no output that turn. (Certain policies/states can suppress discontent entirely.)

### 4.6 Wellbeing (health model)
A parallel positive/negative model for **wellbeing**: favorable contributions from fresh
water, sanitation structures, healthful resources, and certain features; unfavorable
contributions from population, polluting structures, unhealthful resources, and certain
terrain/features. A net wellbeing deficit reduces the settlement's sustenance surplus each
turn.

### 4.7 Culture & borders
* Each settlement accumulates cultural output and crosses **influence-level thresholds**
  that expand its working/claim radius outward in rings.
* Each turn the settlement adds cultural influence to every tile within range, weighted by
  distance. Ownership of a tile is awarded to whichever player has the greatest accumulated
  influence on it. This is how borders form, expand, and shift between players.

### 4.8 Conquest, occupation, and razing
> **⚠️ Incomplete — needs verification.** This subsection describes a first-pass conquest
> model. Its specific numbers and formulas (siege-health maximum, regeneration rate, assault
> damage, revolt duration, the auto-raze conditions) are provisional placeholders and have
> **not** been checked against the actual Civ IV mechanics this project targets for parity.
> Before relying on it, verify the rules and constants against Civ IV's real combat/city-
> capture calculations (city defence/bombardment, occupation/resistance length, capture
> population loss, building survival on capture, etc.) and update both this section and the
> implementation (`SimFacade` conquest helpers, `TurnEngine.city_max_health`, and the
> `city_*`/`revolt_*` keys in `data/constants.json`) accordingly.

A settlement has a **siege health** value — its defensive integrity — with a maximum derived
from a base value, its population, and its defensive structures (walls, castle, …). Health
regenerates a fixed amount each owner turn, up to that maximum.

* **Assault.** A settlement is taken through its tile. Any defending units must be defeated
  first (normal combat, §5.4); defeating the last defender does **not** by itself put the
  attacker inside the settlement. Once the tile is undefended, an attack on it instead
  **assaults the settlement**, lowering its siege health by the attacker's effective combat
  strength. The settlement **falls** when its health reaches zero, and the attacking stack
  enters the tile only at that point.
* **Raze or keep.** When a settlement falls, the attacker chooses to **raze** it (destroyed
  and removed from the game) or **keep** it (ownership transfers to the attacker). Two cases
  remove the choice: **barbarian/wild attackers always raze**, and a **size-one settlement
  that has never been larger is razed automatically** (a settlement that once grew bigger and
  later shrank back to size one may still be kept).
* **Occupation (revolt).** A kept settlement enters a **revolt** lasting a base number of
  turns plus half its population. While in revolt it produces **nothing** — no output/yields,
  no culture, and therefore no border expansion or growth — until the revolt subsides. On
  capture its production queue and specialists are cleared and its siege health is restored;
  if the captured settlement held the loser's seat of government (the Palace, §6.1), the
  Palace is removed, so the loser re-establishes a capital elsewhere on their next turn.
* **Disband.** At any other time a player may voluntarily **disband** one of their own
  settlements, which destroys it exactly as razing does.

### 4.9 Cultural revolt and city flipping (provisional)
> **⚠️ Provisional — preliminary, not verified.** This subsection is a first-pass model of
> capturing a settlement through **cultural pressure** rather than combat. It is based only on
> a preliminary reading of the reference game's behaviour and has **not** been checked against
> the actual mechanics, nor is it implemented yet. The named factors, the 10% check rate, the
> revolt-power and garrison-strength formulas, and all constants below are placeholders to be
> verified and tuned before relying on them. (All quantities are integer math per the engine
> invariants; the "ratios" below are expressed as integer percentages, e.g. a culture ratio of
> 100–200.)

Independently of military conquest (§4.8), a settlement may **flip** to a rival player when
that rival's accumulated cultural influence (§4.7) on the settlement's tile exceeds the
owner's. This makes culture a **strategic resource** that converts settlements over time, not
merely a victory condition (§10), and makes a garrison matter **defensively** against cultural
pressure as well as against assault.

* **Eligibility.** A settlement is a flip candidate when a rival player both (a) controls a
  settlement within cultural radius of it and (b) holds **more** accumulated influence than the
  owner on the candidate's own tile.
* **Revolt check.** Each owner turn, an eligible settlement has a fixed **revolt-check chance**
  (placeholder: 10%, a tunable constant) of rolling a revolt, drawn from the shared generator
  (§ground rules). A revolt then **succeeds or fails** by comparing the challenging rival's
  **revolt power** against the settlement's **garrison strength**.
* **Revolt power** (of the strongest eligible rival) is the product of:
  * **Base** = `1 + 2 × highest historical population + (adjacent rival-controlled tiles × era number)`
    (so a larger settlement, more surrounding rival territory, and a later era all raise the
    pressure);
  * **Culture ratio** = `1 + (rival_culture − owner_culture) / rival_culture`, clamped to the
    range 1.0–2.0 (as integer percent, 100–200) — the more the rival out-cultures the owner on
    that tile, the stronger the revolt;
  * **Belief modifier** = ×2 if the rival has the relevant state belief (§8), ÷2 if the owner
    does — belief acts as a cultural amplifier/dampener;
  * **War modifier** = the garrison's contribution doubles while the owner is at war (war status
    sharply raises rebellion risk; see the garrison term below).
* **Garrison strength** = `1 + Σ(garrison value of each military unit stationed in the
  settlement)`, where each unit's garrison value scales with its type (placeholder: early units
  ≈ 3, late-era units ≈ 16). While the owner is at war this term is doubled (per the war
  modifier above).
* **Outcome.** If revolt power exceeds garrison strength the settlement **changes hands** to the
  challenging rival. A **non-barbarian** settlement may require **multiple** successful revolts
  before it actually flips (a revolt counter that must accumulate), whereas barbarian/wild
  settlements flip on the first. A game setting governs whether a recently **conquered**
  settlement (still in revolt, §4.8) is eligible to flip immediately or is shielded until its
  occupation ends.

When a settlement flips, ownership transfers exactly as a kept capture (§4.8) — the same
queue/specialist clearing, siege-health restore, and Palace handling apply — but no combat or
attacking stack is involved.

---

## 5. Units

### 5.1 Definition
Each unit type is defined by data: its movement domain (land, sea, air, or immobile),
base combat strength, movement allowance, cost, prerequisite technologies and resources,
a classification, special-ability tags, allowed upgrades, transport capacity, and any
build/work abilities. A unit is owned by a player, occupies a tile, and belongs to a
**stack** that shares orders.

### 5.2 Movement
* A unit has a movement allowance per turn (tracked at higher precision to support
  fractional terrain costs). Entering a tile costs the destination's terrain/feature
  movement cost, reduced by transport links, with a guarantee that a unit can always move
  at least one tile per turn.
* Domain rules constrain travel: land units require transport to cross deep water; naval
  units remain in water (and adjacent tiles for bombardment); air units are based in
  settlements or carriers and fly limited-range missions. Zones of control and impassable
  terrain further restrict movement.
* Pathfinding uses a shortest-path search over movement costs; per-move legality is
  validated against the unit's domain and the destination tile's contents.

### 5.3 Combat strength
A unit's effective strength is its base strength scaled by the sum of percentage
modifiers. Modifiers accumulate from many conditional sources:

* general bonuses; handicap modifiers versus wild/raider forces; tile defensive bonuses
  (terrain, feature, landform); entrenchment bonus that grows over consecutive stationary
  turns up to a cap; settlement defensive bonuses including cultural defense;
  landform-specific attack/defense; feature- and terrain-specific attack/defense;
  attack-into-settlement bonuses; domain-specific modifiers; class-versus-class modifiers;
  river-crossing and amphibious **attack penalties**; and self-sacrifice modifiers.
* Defenders gain defensive bonuses; attackers gain offensive bonuses; many modifiers apply
  only to one combat role.

Effective strength is further scaled by the unit's current health fraction (a damaged unit
fights at reduced strength). A separate **firepower** quantity feeds the damage model.

### 5.4 Combat resolution
Before a fight, the engine derives each side's per-round win odds and per-hit damage:

* **Odds** for a side are proportional to that side's strength relative to the combined
  strength of both sides. Special clamping applies for the "free early wins" rule against
  wild/raider forces.
* **Per-hit damage** for each side is proportional to the opponent's firepower relative to
  its own firepower, blended with a combined-firepower factor, and is at least one point
  per hit.

The fight proceeds in rounds until one unit dies (or a cap is reached):

```
each round: draw from the shared generator
  - one outcome: the attacker takes a hit (unless it has unspent first-strikes)
      * if the hit would be fatal, a withdrawal chance may let the attacker retreat
  - other outcome: the defender takes a hit
      * if cumulative damage would exceed a "combat limit" for the attacker's type,
        the defender is merely reduced to that limit and the fight ends (some units
        cannot deliver killing blows)
  - first-strike opportunities are consumed before normal exchanges begin
  - the loop ends when either unit is destroyed
```

Outcomes and side effects:
* The destroyed unit is removed; a victorious attacker may advance into a now-undefended
  tile if it retains movement and the combat limit did not prevent a kill.
* **Spillover damage**: certain siege-type attackers first inflict bounded damage on other
  units stacked with the defender.
* **Flanking**: fast units can damage a fraction of a stack upon winning.
* **Withdrawal**: a losing attacker may retreat, gaining experience.

### 5.5 Experience & upgrades
* On victory a unit gains experience proportional to the relative strength of the loser,
  clamped between a minimum and a maximum per fight. Experience from wild/raider kills is
  capped lower.
* Reaching the next experience threshold grants a **promotion** chosen from data-defined
  options (combat bonuses, first strikes, withdrawal, extra movement, faster healing,
  terrain specialties, and more), subject to prerequisites. Elite "leader" units can grant
  bonus experience or attach to other units.

### 5.6 Healing, entrenchment, and special actions
* Per-turn healing depends on location (own/allied territory, neutral territory, hostile
  territory, or inside a settlement) and on healing-related promotions. A unit does not
  heal on a turn it moves or fights.
* **Entrenchment** raises defensive strength over consecutive stationary turns up to a cap.
* Other actions include: building improvements (worker-type units, with data-defined
  terrain/technology time costs), pillaging, bombarding settlement defenses, blockading,
  scouting and air strikes, interception of air missions, area-effect strikes, spreading
  beliefs, establishing trade routes, founding settlements, joining a settlement as a
  specialist, and special-person actions (instant technology, rushed construction,
  triggering a celebration age, or seeding an economic organization).

---

## 6. Players, economy, and research

### 6.1 Treasury
* Net treasury change per turn equals finance income from settlements minus total upkeep
  (which scales with distance from the capital, number of settlements, and settlement
  size), minus policy upkeep and unit costs.
* Upkeep is reduced by administrative structures and certain policies. If the treasury
  cannot cover upkeep, the research allocation is forced down and, in the extreme,
  structures and units are sold or disbanded (insolvency).

### 6.2 Allocation sliders
The player sets percentages across finance, research, culture, and intelligence,
constrained to increments allowed by the governing policies and summing to a whole. Some
policies cap the maximum research rate (a minimum research share). The slider partitions
each settlement's generic economic output.

* **Starting allocation.** A new player begins at **100% research** (everything else at
  0%), so the tech tree advances from turn one without the player having to touch the
  sliders. With no finance income this draws the treasury down, so the player is expected
  to dial finance back up once gold runs low.
* **Computer players** manage this allocation automatically: they keep the slider
  research-heavy while solvent and shift it toward finance when the treasury runs thin,
  always within the policy-imposed increment and research-floor constraints. (This mirrors
  the human starting default; without it the all-research start would slowly bankrupt the
  AI, since 0% finance earns no gold.)
  > **⚠️ Provisional — needs verification.** This computer-player allocation behaviour
  > (and its solvency threshold) is a first-pass heuristic added alongside the 100%-research
  > starting default; it has **not** been balance-tested across full games. Verify that it
  > actually keeps the AI solvent without starving its research before relying on it.

### 6.3 Research
* The research rate derives from net research output (optionally supplemented by net
  finance when research is not independently funded). Each turn, the rate plus any carried
  surplus is applied to the current research project, shared across all members of an
  alliance.
* Research cost is reduced by discounts: cheaper when known to players one has met or trades
  openly with, cheaper when prerequisites are held, and cheaper per number of others who
  already know it. A project completes when accumulated progress meets its cost (scaled by
  pacing and difficulty). Completed research unlocks units, structures, policies,
  improvements, resources, trade abilities, wonders, and victory projects, following a
  prerequisite graph that supports both required-all and required-any dependencies.

### 6.4 Policies
Governing choices are organized into several mutually exclusive categories (such as
government form, legal system, labor system, economic system, and belief system). Each
choice supplies modifiers (contentment, upkeep, free units, output changes, war-fatigue,
anger) and may require an enabling technology. Switching choices typically imposes a
transition period of reduced output, unless a trait waives it.

### 6.5 Specialists & special persons
Citizens may be assigned as **specialists** that yield economic output and points toward a
**special person**. When a settlement's accumulated special-person points cross a
rising threshold, a special person is produced, who can settle for a permanent bonus,
construct a wonder, grant a technology, trigger a celebration age, or seed an economic
organization.

---

## 7. Alliances, diplomacy, and war

* An **alliance** is the unit of war, diplomacy, shared vision, and shared research. A
  single player may form an alliance of one, or several players may share one.
* **Contact** is established when alliances first meet; each alliance tracks whom it has
  met.
* **War and peace** are declared at the alliance level and toggle a war state. **War
  success** accrues from combat actions and feeds war-fatigue, which raises discontent over
  time.
* **Trades** exchange treasury, recurring payments, resources, technologies, settlements,
  maps, passage rights, mutual-defense agreements, and peace. They are resolved and expired
  during the whole-world step. Computer willingness depends on attitude and a cost/benefit
  evaluation.
* **Subordination**: a weaker alliance may become a tributary of a stronger one, sharing
  its wars and paying tribute, sometimes as a result of losing a war.
* **Intelligence/espionage**: each alliance accumulates intelligence points against every
  alliance it has met, spent on covert missions (stealing technology, sabotage, inciting
  unrest, and more) with costs and interception chances governed by configuration.

---

## 8. Beliefs & economic organizations

* **Beliefs**: the first player to satisfy a belief's founding prerequisite founds it
  (chosen randomly among eligible unfounded ones if several qualify) in one of its
  settlements, which becomes that belief's principal site. Beliefs spread passively each
  turn and via dedicated missionary units, with spread chance falling as distance and
  existing competing beliefs increase. A state-adopted belief confers contentment,
  diplomatic, and (with dedicated structures) economic benefits. The principal site's
  dedicated structure yields finance scaled by the number of settlements worldwide holding
  that belief. A belief-based assembly may act as a diplomatic voting body.
* **Economic organizations**: founded by a special person, they spread like beliefs but
  consume input resources to produce output in member settlements; spreading them costs
  treasury. Competing organizations cannot coexist in the same settlement.

### 8.1 State religion (provisional)

> **⚠️ Provisional — preliminary, not verified.** This subsection is a first-pass model of
> the **player-level state religion** and has **not** been checked against the reference
> game's mechanics. The anarchy length, the exact set of effects it gates, and the adoption
> eligibility rule are placeholders to be verified and tuned before relying on them.

Distinct from a settlement's per-city belief (§8), each **player** may adopt one empire-wide
**state religion** — the belief the civilisation officially follows. Rules:

* **No religion to start.** Every player begins with **no state religion**, and "none" is
  always a valid selection. A player may adopt only a belief that is **founded** and present
  in at least one of their own settlements.
* **Switching causes anarchy.** Changing the state religion away from an existing one (to a
  different religion *or* back to none) plunges the player into **anarchy** for a fixed number
  of turns (`state_religion_anarchy_turns`): while it lasts the player's settlements yield
  **no commerce** — no gold, research, culture, or intelligence (food and production are
  unaffected). The **first** adoption (from none) is **free**, and a **Spiritual** leader
  never suffers anarchy from a switch. Anarchy is a **single shared interregnum** — it is the
  same `transition_turns` state that **switching an established civic** (§6.2) now incurs, with
  the identical commerce blackout, free-first-choice, and Spiritual exemption. Religion and
  civic switches do not stack a second anarchy on top of one already running.
* **Effects.** The state religion is what gates religion-dependent bonuses: a **Cathedral**
  (and its religious-building tier marked `requires_state_religion`) only comforts a city
  whose religion is the player's state religion; **Theocracy** grants its new-unit experience
  bonus only to units raised in such cities, and its non-state-spread block keeps other
  religions from spreading into the player's cities.
* **Selection.** The state religion is chosen at runtime through the Religion advisor screen
  (§3.1 `OPEN_RELIGION`), which lists "none" plus every religion present in the player's
  cities; the AI adopts the religion its empire already follows but never switches afterward.

---

## 9. Wild forces, exploration rewards, and events

* **Wildlife** appears in unclaimed territory early, with combat modifiers from difficulty.
  **Raider forces** spawn in unexplored or unclaimed areas with increasing frequency and can
  establish their own settlements; an optional setting increases their aggression.
  Difficulty grants players a number of "free wins" against these forces (the odds clamp in
  combat resolution).
* **Exploration rewards**: investigating a discovery site yields, by weighted random,
  treasury, map knowledge, experience, a unit, a technology, or a hostile ambush.
* **Events**: periodic scripted/random events with prerequisites, player choices, and
  effects, largely defined in external content data.

### 9.1 Wild-forces behaviour (provisional)
> **⚠️ Provisional — preliminary, not verified.** This subsection is a first-pass model of how
> spawned wild/raider forces *act* (as opposed to merely spawning, §9 bullet 1). It is a
> deliberately simple deterministic AI and has **not** been tuned against the reference game.
> The radii, wave lengths, cooldowns, caps, and the aggression scaling below are placeholders to
> be balanced before relying on them. All quantities are integer math per the engine invariants,
> and every stochastic choice is drawn from the shared generator so wild turns are reproducible
> and captured by save/load.

Wildlife and raiders are owned by the **wild faction** (`owner_player_id = -2`) and have no slot
in the round-robin, so they act once per **whole-world step** (§3 world-step 4), immediately
after spawning. The behaviour is a four-stage loop:

* **Refresh.** Wild units never receive a per-player step, so their movement allowance is
  restored at the start of the wild phase.
* **Act.** Each wild unit either marches toward a **raid goal** (the target tile of the wave it
  was mustered for) or, as a free **scout** with no goal, **chases** the nearest player unit or
  city it can see (within `wild_detect_radius`, widened under the aggression setting). A scout
  that sees no one **wanders** one tile. Movement uses the standard pathfinder; stepping into a
  player unit resolves **combat** (§5), and stepping onto an **undefended** player city
  **assaults** it (§4.8) — wild captors **always raze** (§4.5), never hold.
* **Detect & alert.** A scout that sights a player **rouses the nearest idle raider camp**
  (a wild settlement, §9). The camp records the sighted tile as its **alert target** and begins
  mustering. A camp already mustering or cooling down is skipped, and with **no camp present no
  wave forms** — camps are the only muster point.
* **Muster.** A roused camp spawns **one raider per world step** aimed at its alert target for
  the wave's length (`wild_wave_length`), then enters a **cooldown** (`wild_alert_cooldown`)
  before it can be roused again. Wave units are the **strongest generic (non-unique) land unit
  the most-advanced player has unlocked** — chosen **globally** (one wave strength worldwide),
  honouring tech prerequisites but **ignoring resource requirements** (raiders are never gated on
  copper/iron/horse). Total wild population is held under a land-based cap plus a small wave
  headroom (`wild_wave_unit_bonus`) so a wave can mass without permanently flooding the map.

The **optional aggression setting** (§9 bullet 1; a new-game toggle, serialized on the game
state) lengthens waves (`wild_aggression_wave_bonus`), shortens cooldowns
(`wild_aggression_cooldown_cut`), and widens scout sight (`wild_aggression_detect_bonus`).

Combat and conquest the wild AI performs are applied through the same shared rules as player
actions (the `CombatApply` module and the §4.8 city-fall path), and the few results the UI must
surface — each fight, each razed city — are queued on the game state and drained by the facade
into the usual `combat_resolved` / `city_razed` signals, exactly as §4.9 culture flips are.

**Known gaps / simplifications (to revisit):** scouts target the *tile* a player occupied when
sighted and do not re-home if the target moves; "nearest camp" ignores distance, so a wave can
muster far from the sighted player; raiders never upgrade or retreat; and there is no naval or
air wild presence.

---

## 10. Win conditions

Checked at the end of each whole-world step; the enabled set is chosen at setup. Typical
conditions:

| Condition | Trigger |
|-----------|---------|
| **Last standing** | Only one alliance retains any settlements or units. |
| **Dominance** | An alliance controls a configured share of both land area and total population. |
| **Endgame project** | An alliance completes and launches all parts of a multi-stage endgame project; its arrival ends the game. |
| **Cultural** | A required number of an alliance's settlements each reach the highest influence level. |
| **Diplomatic** | A candidate is elected by a diplomatic assembly with the required share of votes. |
| **Time** | If no other condition is met by the final turn, the highest **score** wins. |

**Score** is a weighted sum of population, land, technologies, and wonders, normalized
against the map and age.

---

## 11. Environmental degradation

Accumulated pollution (from population, polluting structures, and area-effect strikes)
produces a per-turn chance of randomly degrading a tile — stripping vegetation, shifting
terrain toward barrenness, or flooding low tiles — scaled by game settings. Area-effect
strikes also add lingering contamination and pollution.

---

## 12. Configurable data

Everything numeric and every named game object is treated as **external configuration**
rather than hard-coded logic, including:

* **Global constants**: combat resolution scale and damage magnitude, maximum health,
  spillover/ranged/air damage, withdrawal/evasion caps, entrenchment cap,
  minimum/maximum experience per fight, healing rates by location, movement precision,
  visibility and blockade ranges, growth-threshold base and per-population multiplier,
  consumption per population, the anger-to-population divisor, minimum settlement spacing,
  upgrade costs, war-success values, war-fatigue contributions, and intelligence/mission
  costs.
* **Object tables**: unit types, structure types, technologies, policies, promotions,
  terrains, features, resources, improvements, leaders/traits, ages, game paces,
  difficulties, world sizes, win conditions, projects, beliefs, economic organizations,
  and more.

The simulation engine implements the algorithms in sections 1–11; the configuration
supplies the values they read. A faithful implementation must reproduce both.

---

## 13. Minimum viable implementation checklist

1. **Data layer**: load object tables and global constants (or supply defaults).
2. **World**: tile grid with terrain/feature/resource/improvement/transport; tile-output
   calculation; regions and supply groups; influence-based ownership.
3. **Deterministic generator** with a fixed draw order; integer math throughout.
4. **Turn pipeline** in the exact order of section 3.
5. **Settlements**: growth, output and economic split, production and rushing, contentment
   and wellbeing, culture and borders.
6. **Units**: movement, combat strength, combat resolution including spillover, flanking,
   first-strike, and withdrawal, experience and promotions, healing and special actions.
7. **Players**: treasury and upkeep, allocation sliders, research, policies, specialists
   and special persons.
8. **Alliances/diplomacy**: war and peace, trades, subordination, intelligence.
9. **Beliefs and economic organizations**; **wild forces, exploration rewards, events**.
10. **Win conditions** and **scoring**; **environmental degradation**.
11. (Recommended) an **override-hook seam** mirroring the phase-override pattern so content
    can replace any rule.
