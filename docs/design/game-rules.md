---
title: "Game Rules"
role: design
summary: >
  Authoritative behavioural specification for the Humanish 4X simulation engine.
  Defines every rule the engine enforces: the world model, the turn pipeline, settlement
  growth and culture, unit movement and combat, the economy, diplomacy, beliefs,
  wild forces, and win conditions. The sim layer (src/sim/, src/world/) implements
  these rules exactly; this document is the source of truth when code and spec disagree.
audience:
  - Coding agents implementing or auditing src/sim/, src/world/, src/api/
  - Contributors adding new mechanics or data-driven content
  - Reviewers checking that a feature matches the design intent
key_files:
  - src/sim/turn_engine.gd       # §3 pipeline implementation
  - src/sim/settlement.gd        # §4 settlement model
  - src/sim/unit.gd              # §5 unit definition and stances
  - src/sim/combat.gd            # §5.4 combat resolution
  - src/sim/combat_apply.gd      # §5.4 state mutation after combat
  - src/sim/player.gd            # §6 economy / research / policies
  - src/sim/alliance.gd          # §7 diplomacy / war / espionage
  - src/sim/beliefs.gd           # §8 religion founding and spread
  - src/sim/econ_orgs.gd         # §8 economic organizations
  - src/sim/culture_revolt.gd    # §4.9 cultural city flipping
  - src/sim/culture_levels.gd    # §15.4 culture levels / border curve / city defence
  - src/sim/nuclear.gd           # §5.7 nuclear weapons
  - src/sim/assembly.gd          # §7.2 world-government voting
  - src/sim/eras.gd              # §2.1 derived era system
  - src/sim/wild_ai.gd           # §9.1 wild-forces behaviour
  - src/sim/great_people.gd      # §14 Great People / Golden Ages
  - data/constants.json          # all tunable numeric constants
sections:
  "§1  World model":           "Map & tiles, adjacency, tile output, rivers"
  "§2  Time, ages, pacing":    "Turn length, eras (§2.1 provisional), difficulty handicaps (§2.2: research %, AI per-era cost, city aids)"
  "§3  Turn structure":        "Authoritative world-step / player-step order"
  "§4  Settlements":           "Growth, output split, production, contentment, wellbeing, culture, conquest (§4.8), cultural revolt (§4.9 provisional), tile maturation (§4.10 provisional), feature clearing & chopping (§4.11 provisional)"
  "§5  Units":                 "Definition, movement, combat strength, combat resolution, XP & upgrades, healing & entrenchment, nuclear weapons (§5.7 provisional), naval blockade (§5.8 provisional)"
  "§6  Economy & research":    "Treasury, allocation rates (economy derived as the remainder), research graph, policies, specialists & Great People, draft (§6.6 provisional), trade routes (§6.7 provisional)"
  "§7  Diplomacy & war":       "Alliances, trades, subordination, espionage (§7.1 provisional), world assemblies (§7.2 provisional), diplomatic victory (§7.3 provisional)"
  "§8  Beliefs & orgs":        "Religion founding/spread, state religion (§8.1 provisional), missionary spread (§8.2 provisional)"
  "§9  Wild forces & events":  "Wild spawning (§9.2 provisional), wild-AI behaviour (§9.1 provisional), animals (§9.3 provisional), exploration rewards, scripted events"
  "§10 Win conditions":        "Last standing, dominance, endgame project, cultural, diplomatic, time"
  "§11 Environmental":         "Global warming — building unhealthiness + nukes degrade random tiles toward desert; radioactive fallout (provisional)"
  "§12 Configurable data":     "Data-driven constants — what lives in JSON, not in code"
  "§13 Checklist":             "Minimum viable implementation checklist"
  "§14 Great People":          "Types, GP points, thresholds, Golden Ages, specialist slots, corporations"
  "§15 Reference-parity mechanics": "Parity targets with reference values — goody rosters (unimplemented); inflation (15.1), whipping (15.2), pace scaling (15.3), culture levels & culture-level city defence (15.4), chance first strikes (15.5), siege caps (15.6), SDI/Internet/nuke retune (15.7), war weariness per-event weights (15.8), worker-speed/serfdom/emancipation civic effects (15.9), per-resource corporations (15.10) and compound prereqs (15.12) are implemented"
provisional_sections:
  - "§2.1  Eras — growth scaling and revolt-era term (placeholder constants)"
  - "§4.9  Cultural revolt / city flipping — all constants placeholder"
  - "§4.10 Tile maturation — cottage upgrade rates"
  - "§4.11 Feature clearing & chopping — base chop yield, tech bonus, and border scaling placeholder"
  - "§5.7  Nuclear weapons — blast/population/building magnitudes reference-tuned (§15.7, 2026-07-17); interception range, fallout-ring chance and meltdown chance still placeholder"
  - "§5.8  Naval blockade"
  - "§6.6  Conscription / draft"
  - "§6.7  Trade routes — yields placeholder"
  - "§7.1  Espionage — accumulation formula and mission effects"
  - "§7.2  World assemblies — session cadence, AI voting, resolution effects"
  - "§7.3  Diplomatic victory — UN/Apostolic Palace thresholds, eligibility gates, the too-big rule"
  - "§8.1  State religion"
  - "§8.2  Missionary spread"
  - "§9.1  Wild-forces behaviour — all radii and cooldowns placeholder"
  - "§9.2  Wild-forces spawning — reference-derived port, per-difficulty tables provisional"
  - "§9.3  Wild animals — spawning, behaviour, and combat limits (reference-derived)"
  - "§9.4  Naval raiders — placeholder (sea-domain wild forces)"
  - "§15   Reference-parity mechanics — each subsection is a reference-parity target with final values (from reference XML); 15.5/15.6/15.12 implemented 2026-07-08, 15.1/15.2/15.3 implemented 2026-07-12, 15.8/15.9/15.10 implemented 2026-07-17, the rest unbuilt"
editorial_rule: >
  Modify only with explicit user consent. This is the upstream source of truth;
  the engine grows toward it. When a gap is closed, update the relevant section to
  remove any "not implemented" qualifier and (if still unverified) keep the
  Provisional tag. Add new provisional sections for newly implemented subsystems.
---

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
  of "free" early combat wins against wild/raider forces). See §2.2 for the implemented
  per-city handicaps.

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

### 2.2 Difficulty handicaps

> **Canonical handicap ladder (reference-grounded).** The nine difficulty levels are
> `settler, chieftain, warlord, noble, prince, monarch, emperor, immortal, deity`, with
> **`noble` as the balanced baseline** (every percentage = 100, every bonus = 0). Each level
> is a player aid applied to **human players only** (`player.is_ai == false`); a computer
> player's cities receive none of the city handicaps below. The AI's own catch-up is the
> separate `ai_bonus` / per-era cost modifier.

**The two canonical handicap knobs (these supersede any earlier model):**

* **Player research percent** (`handicap_research_percent`) scales the **player's own tech
  cost** (§6.3): `settler 60` (techs 40% cheaper) … `noble 100` (baseline) … `deity 135`
  (techs 35% dearer). This is the primary lever that makes harder levels harder, replacing
  the previous approach of folding all difficulty into an AI-side beaker bonus.
* **AI per-era cost modifier** (`ai_research_per_era`) makes the **AI's** research cheaper as
  the game progresses on the higher levels (e.g. `deity −5` per era), the reference's way of
  letting the AI keep pace late. This is distinct from the flat `ai_bonus` yield handicap.

**City handicaps (applied to human cities only).** On top of
the canonical knobs, each difficulty level also carries three integer city modifiers
(`TurnEngine._settlement_growth`, `_update_wellbeing`, `_update_contentment`, reading
`data/difficulties.json`; values are the reference columns — see game-data §15.9):

* **`growth_bonus`** (percent, `+25` Settler … `−20` Deity) scales the food-to-grow
  **threshold** inversely: the threshold is multiplied by `(100 − growth_bonus)`, so a
  positive bonus on easier levels lowers it (cities grow sooner) and a negative one on
  harder levels raises it. Applied on top of the pace and era threshold scaling (§4.2).
* **`health_bonus`** (`+4` Settler … `+2` Warlord and above) is added to each city's
  wellbeing **positive** total (§4.6). Per the reference it **never goes negative** for
  the human — the floor is +2 at every level.
* **`happiness_bonus`** (`+6` Settler … `+4` Warlord and above) is added to each city's
  contentment **positive** sentiment (§4.5); likewise floored at +4, never negative.

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
  *(⚠️ Provisional: a new settlement may never be adjacent to an existing settlement
  (Chebyshev distance ≥ 2 — at least one tile between cities). Enforced by
  `min_settlement_distance = 2` in `data/constants.json`, the reference spacing.)*

### 4.2 Population growth
Surplus sustenance accumulates in a "store" (food box) each turn:

* **Surplus** = produced sustenance − **consumption**, where consumption is the
  reference's food box: `consumption = (population − angryPop) × FOOD_CONSUMPTION_PER_POPULATION
  − healthRate`. That is, **angry/discontented citizens do not eat**, and net unhealthiness
  is **subtracted from consumption** (it is a food drain), not booked as a separate deficit.
  `FOOD_CONSUMPTION_PER_POPULATION` is the canonical 2 food/citizen (`data/constants.json`
  `food_per_citizen`). *(This supersedes the earlier model that consumed full `population`
  and subtracted a separate `wellbeing_deficit` from food after the fact.)*
* If the store reaches the **growth threshold**, population increases by one and the granary
  carry-over (a configurable fraction, capped at `threshold × max_food_kept_percent / 100`)
  is retained while the rest spills. If the store goes negative the settlement starves and
  population may decrease (a size-1 city is floored so it does not starve to zero).
* The **growth threshold** rises with current population on the reference's `growthThreshold`
  curve — a base scaled by population **and** by game speed (`GameSpeedInfo.getGrowthPercent`,
  e.g. Marathon 300 = ×3) and the starting age — and (for human players) by the difficulty's
  `growth_bonus` handicap (§2.2). Larger cities need a larger box. *(The engine currently
  scales the threshold strictly linearly in population — the reference base
  `20 + 2×pop` (`growth_threshold_base` / `growth_threshold_per_pop`), then pace, era,
  and difficulty scaling; the canonical curve is the pop+speed table — align it for
  reference-faithful pacing.)*

### 4.3 Output & the economic split
* A settlement's base output for each type is the sum of its worked tiles, assigned
  specialists, structures, and trade routes, then scaled by a **percentage-modifier chain**.
  The canonical form is the reference's floored sum:

  ```
  yield = baseYield × max(0, 100 + Σ(yield-rate modifiers)) / 100
  ```

  where the modifiers (buildings/policies on the city, connected resources, powered-building
  bonus, region-wide and empire-wide modifiers, and the capital modifier) are **summed as
  percentages** and applied as one `(100 + Σ)/100` multiply — the leading `100 +` being the
  identity baseline. *(The engine currently adds most city food/production bonuses as flat
  deltas; route the percentage bonuses through this chain — the same `apply_stacked_bonus`
  idiom already used for combat strength — so structures/policies that grant `+x%` yield
  behave as the reference specifies.)*
* The generic economic (commerce) output is partitioned by the player's
  **allocation rates** into the four commerce types — **finance (gold), research,
  culture, and intelligence (espionage)** — by `commerce = commerceYield × ratePercent /
  100`. The player adjusts three rates (research, culture, intelligence) in policy-allowed
  increments; **finance is the derived remainder** (100 − the three), so the four always
  sum to 100 and no commerce is lost to rounding. Some channels may have enforced
  minimums. Per-commerce building/specialist bonuses and a further commerce-rate
  modifier layer on after the split.

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

Currently wired contributions: per-population base (negative), structure
`health_bonus`/`health_penalty`, the adopted belief's `health_bonus`, the empire-wide
`health_empire` civic effect, the owner's **leader/society trait** `health_bonus`
(`data/leaders_traits.json` — e.g. **Expansive grants +2 health per city**, the Beyond the
Sword value), the difficulty `health_bonus` handicap (§2.2), fresh water, and **worked-tile
feature** health (below).

* **Worked-tile features (`data/features.json`).** Each **worked** tile carrying a feature
  contributes its `health_bonus` to the positive total and its `health_penalty` to the
  negative total — healthful features (forest, oasis +1) and unhealthful ones (jungle,
  flood plains, fallout −1). Only worked tiles count, mirroring the happiness model's
  worked-forest scan (§4.5); an unworked feature in the city radius is inert. This is also
  the path by which **Fallout** (§5.7) harms a city working a contaminated tile.

### 4.7 Culture & borders
* Each settlement accumulates cultural output and crosses **influence-level thresholds**
  that expand its working/claim radius outward in rings — since D2 the reference
  geometric per-pace culture-level curve (§15.4; 5 levels, ring = level + 1).
* Each turn the settlement adds cultural influence to every tile within range, weighted by
  distance. Ownership of a tile is awarded to whichever player has the greatest accumulated
  influence on it. This is how borders form, expand, and shift between players.

### 4.8 Conquest, occupation, and razing
> **⚠️ Incomplete — needs verification.** This subsection describes a first-pass conquest
> model. Its specific numbers and formulas (siege-health maximum, regeneration rate, assault
> damage, revolt duration, the auto-raze conditions) are provisional placeholders and have
> **not** been checked against the actual original-reference mechanics this project targets for parity.
> Before relying on it, verify the rules and constants against the reference's real combat/city-
> capture calculations (city defence/bombardment, occupation/resistance length, capture
> population loss, building survival on capture, etc.) and update both this section and the
> implementation (`SimFacade` conquest helpers, `TurnEngine.city_max_health`, and the
> `city_*`/`revolt_*` keys in `data/constants.json`) accordingly.

A settlement retains a **siege health** value — its defensive integrity — with a maximum
derived from a base value, its population, and its defensive structures (walls, castle, …),
regenerating a fixed amount each owner turn up to that maximum. It is **currently vestigial**:
since an undefended settlement now falls to a single attack (below), siege health no longer
gates conquest. It is kept as settlement state pending the parity pass noted above (a future
model may reintroduce a multi-hit assault), but no combat path reads it today.

* **Assault.** A settlement is taken through its tile. Any defending units must be defeated
  first (normal combat, §5.4); defeating the last defender does **not** by itself put the
  attacker inside the settlement (it takes a further attack into the now-undefended tile).
  Once the tile is **undefended**, an attack on it **captures or razes the settlement
  immediately** — there is no siege-health wear-down — and the attacking stack enters the tile
  (a kept settlement becomes the attacker's; a razed tile is empty land). This applies in both
  directions: a player takes an undefended enemy settlement, and **wild raiders** (§9) raze an
  undefended player settlement outright. **Exception — the capital.** The palace-bearing seat
  of government (§6.1) **cannot be attacked by wild forces at all**: wild raiders never march on
  it and treat its tile as an impassable wall, so a civilization always survives a raid even
  when its capital is undefended. (Siege health and its per-turn regeneration are retained as
  vestigial settlement state but no longer affect conquest.)
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
> **⚠️ Provisional — implemented, not verified.** This subsection documents the cultural-revolt
> model as implemented in `src/sim/culture_revolt.gd` (called from the owner's player step via
> `TurnEngine`). The named factors, the 10% check rate, the revolt-power and garrison-strength
> formulas, and all constants below are placeholders drawn from a preliminary reading of the
> reference game; they have **not** been checked against the actual mechanics and are expected to
> be tuned. (All quantities are integer math per the engine invariants; the "ratios" below are
> expressed as integer percentages, e.g. a culture ratio of 100–200.)

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
* **Garrison strength** = `revolt_garrison_base + Σ(base_strength of each non-civilian military
  unit stationed in the settlement)`. Unlike the earlier placeholder, garrison value is the
  unit's actual `base_strength` from data, so veteran or late-era units defend more effectively.
  While the owner is **at war** with the rival's alliance this total is multiplied by
  `revolt_war_garrison_multiplier` (placeholder: ×2).
* **Outcome.** If revolt power exceeds garrison strength the settlement accrues one
  **revolt success** on `Settlement.revolt_progress`. A **non-barbarian** settlement requires
  `revolt_required_successes` (placeholder: 2) accumulated successes before it actually flips —
  so cultural pressure builds over multiple rounds. A **wild/barbarian** settlement
  (`owner_player_id == -2`) flips on the first success. A freshly-conquered settlement still
  under occupation (`revolt_turns > 0`) is **shielded** from revolt progress by default
  (`revolt_shield_during_occupation`; configurable), and its counter is reset each skipped turn.

When a settlement flips, ownership transfers exactly as a kept capture (§4.8) — production
queue, specialists, and worked tiles cleared; siege HP restored; Palace stripped; new
occupation revolt period set to `revolt_base_turns + population / 2` — but no combat or
attacking stack is involved. The flip is queued on `gs.pending_flips` and drained by the
facade into a `city_flipped` signal and player notification.

**Constants (`data/constants.json`):**

| Key | Placeholder value | Meaning |
|-----|-------------------|---------|
| `revolt_check_chance` | 10 | Percent chance an eligible settlement is checked each turn |
| `revolt_base_per_pop` | 2 | Population multiplier in the revolt-power base |
| `revolt_garrison_base` | 1 | Minimum garrison strength (before unit contributions) |
| `revolt_war_garrison_multiplier` | 2 | Multiplier applied to garrison while owner is at war |
| `revolt_state_belief_multiplier` | 2 | Amplifier/dampener for state belief mismatch |
| `revolt_required_successes` | 2 | Successful revolts needed for a non-barbarian city to flip |
| `revolt_shield_during_occupation` | 1 (true) | Shield recently conquered cities from flipping |
| `revolt_base_turns` | 3 | Base occupation turns after a cultural flip |

### 4.10 Tile improvement maturation (provisional)

> **⚠️ Provisional — implemented, not verified.** The cottage-line chain and its growth
> rates live in `improvements.json` (`upgrades_to` / `upgrade_turns`) and are placeholders to
> be tuned against the reference game.

Some tile improvements **mature** as they are worked. A commerce improvement built on a tile
(the **cottage**) accumulates worked-turns and, on reaching its `upgrade_turns`, advances to
the next stage — **cottage → hamlet → village → town** — each stage yielding more commerce
than the last.

* **Only worked tiles grow.** A tile advances only on a turn its settlement actually works it;
  an unworked or abandoned improvement holds its current stage.
* **Labor civics accelerate growth.** A civic carrying an
  `improvement_upgrade_rate_modifier` percentage (Emancipation, +100 — the reference
  value, §15.9) shortens the maturation threshold: `upgrade_turns × 100 / (100 + mod)`,
  truncating, never below 1.
* Each stage's output is still gated by the owning player's technology in the normal way, so an
  advanced stage reached before its enabling tech yields its lower, tech-gated output until the
  tech is researched.

### 4.11 Feature clearing and chopping (provisional)

> **⚠️ Provisional — implemented, not verified.** The base chop yield and clear duration live
> in `features.json` (`chop_yield`, `clear_turns`); the tech-bonus and border magnitudes live in
> `constants.json` (`chop_yield_tech`, `chop_yield_tech_bonus_pct`, `chop_outside_borders_pct`,
> `chop_default_turns`) and are placeholders to be tuned against the reference game.

A *removable* surface feature (forest or jungle, flagged `removable` in `features.json`) is felled
in **two ways**, both available only to worker-type (can-build) units:

1. **Implicitly, by building over it.** When a worker **completes an improvement** on a tile
   carrying a removable feature, the feature is **cleared** as part of placing the improvement —
   **unless** the improvement preserves it. An improvement preserves the feature when it is flagged
   `preserves_feature` (camp, lumbermill, forest preserve, fort) or when it `requires_feature` that
   same feature; those keep their vegetation.
2. **Explicitly, as a standalone chop order.** A worker on a tile with a removable feature may be
   ordered to **clear it on its own**, placing no improvement. The order takes the feature's
   `clear_turns` (forest = 4, jungle = 6; falling back to `chop_default_turns`) worker-turns, runs
   over the turn pipeline exactly like an improvement build (no progress on the issuing turn), and
   is **abandoned if the worker leaves the tile**. On completion the feature is removed and any
   chop yield is delivered.

Either way, clearing a **forest** yields a one-time burst of **production** (the *chop*), delivered
to the **nearest city the clearing player owns**:

* The base amount is the feature's `chop_yield` (forest = 20).
* **Tech bonus.** Once the player has researched the **chop tech** (`chop_yield_tech`, Mathematics)
  the yield is raised by `chop_yield_tech_bonus_pct` (+50% → 30).
* **Border scaling.** The full amount lands when the chopped tile lies **inside the clearing
  player's borders**; a tile **outside** their borders delivers `chop_outside_borders_pct` of the
  amount (half). The tech bonus is applied first, then the border scaling.
* **Jungle** has no `chop_yield`, so clearing it removes the feature but produces nothing.
* If the player owns **no city**, the feature is still cleared but no production is delivered.

Delivery is deterministic — the nearest city is chosen by integer map distance in settlement
order, and no randomness is consumed — so it is reproducible and captured by save/load through
the existing tile-feature and city-production serialization.

---

## 5. Units

### 5.1 Definition
Each unit type is defined by data: its movement domain (land, sea, air, or immobile),
base combat strength, movement allowance, cost, prerequisite technologies and resources,
a classification, special-ability tags, allowed upgrades, transport capacity, and any
build/work abilities. A unit is owned by a player, occupies a tile, and belongs to a
**stack** that shares orders.

### 5.2 Movement
* A unit has a movement allowance per turn, held internally at a fixed higher precision so
  fractional terrain and route costs divide cleanly. The canonical reference granularity is
  **`MOVE_DENOMINATOR = 60`** (one whole tile of movement = 60 internal points; a unit's XML
  `iMoves` is multiplied up by 60). Entering a tile subtracts that tile's movement cost
  (terrain/feature `iMovement × 60`, reduced by transport links/routes) from the remaining
  allowance, with a guarantee that a unit with **any** movement left can always move at
  least one tile. *(The current engine carries movement at a `MOVE_PRECISION = 100` scale;
  align it to `60` to match the reference's route/terrain divisions exactly.)*
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

> **Canonical values (reference-grounded).** The combat scale, the per-hit damage
> coefficient, and the hit-point ceiling below are the authoritative reference constants
> and supersede any earlier placeholder. They live in `data/constants.json`
> (`combat_scale = 1000`, `combat_damage = 20`, `max_hp = 100`).

Before a fight, the engine derives each side's per-round win odds and per-hit damage. All
work is integer math over each side's **effective strength** (§5.3) and a separate
**firepower** quantity (for most units firepower equals strength; siege and a few special
types carry a distinct firepower).

* **Odds.** A side's per-round win chance is its strength over the combined strength,
  expressed in thousandths against the combat die (`combat_scale = COMBAT_DIE_SIDES = 1000`):

  ```
  theirOdds = 1000 * theirStrength / (ourStrength + theirStrength)
  ```

  Each round draws one number in `[0, 999]` from the shared generator and compares it to the
  defender's odds — this single draw is the **entire** source of combat randomness. The odds
  are **clamped so neither side is ever hopeless**: a side's win chance is never below
  `10%` nor above `90%` of the die (`min 100 / max 900` of 1000). The separate "free early
  wins" clamp against wild/raider forces (a difficulty aid) is applied **on top** of this.
* **Per-hit damage.** Damage is proportional to the opponent's firepower relative to one's
  own, blended with a combined-firepower factor, scaled by the base damage coefficient
  `combat_damage = COMBAT_DAMAGE = 20`, and floored at one point:

  ```
  strengthFactor = (ourFirepower + theirFirepower + 1) / 2
  ourDamage      = max(1, 20 * (theirFirepower + strengthFactor)
                            / (ourFirepower   + strengthFactor))
  ```

  Against an evenly-matched opponent a hit removes ≈ 20 of the loser's `max_hp = 100`, so a
  fight runs **≈ 5 hits to a kill**. (This supersedes the earlier flat `strength × 10 /
  strength` model, which ran combats roughly twice as long.)

The fight proceeds in rounds until one unit dies (or a cap is reached):

```
each round: draw one number in [0,999] from the shared generator
  - draw < defenderOdds: the attacker takes a hit (unless it has unspent first-strikes)
      * if the hit would be fatal, a withdrawal chance may let the attacker retreat
  - otherwise: the defender takes a hit
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

### 5.7 Nuclear weapons & radiation (provisional)
> **⚠️ Provisional — implemented; core magnitudes reference-tuned (C5, 2026-07-17).**
> The damage block now carries the §15.7 reference values: unit damage
> 30 + rand(50) + rand(50) with a non-combatant death threshold of 60 (combat units are
> floored at 1 health; non-combatants either die at the threshold or are untouched),
> population death 30 + rand(20) + rand(20) %, building destruction 40% per structure,
> fallout 50% per blast tile, global-warming nuke weight 50, SDI interception 75%
> (`data/constants.json` `nuke_*`, `data/projects.json` `sdi`). Still placeholder:
> the anti-air interception chance/range, the fallout ring chance, the meltdown
> chance, and the per-unit blast radii. This subsection models the
> **nuclear-weapon** units (`tactical_nuke`, `icbm`) and the **radioactive fallout** they
> leave behind. The data scaffolding exists — the units, the `nuke`/`one_use`/`global_range`
> tags, the `fission` tech, the **Manhattan Project** national wonder (`enable_nukes_global`),
> the **Bomb Shelter** structure (`nuke_damage_reduction`), the **Fallout** feature, the
> **Non-Proliferation** assembly resolution and the `no_nuclear` standing effect (§7.2) — and
> the detonation/radiation rules below are now **implemented** in `sim/nuclear.gd` (launch via
> the `NUCLEAR_STRIKE` command; meltdowns tick in the world step; fallout is scrubbed by the
> `MISSION_CLEAN_FALLOUT` worker action). The core damage magnitudes are now the §15.7
> reference values (see the banner above); the anti-air interception chance/range, the
> fallout-ring chance, the meltdown chance and the per-unit `blast_radius` remain
> **placeholders** to be verified and tuned. All quantities are integer math per the
> engine invariants; chances are integer percentages, and every stochastic step draws from the
> shared `gs.rng` in a fixed tile order so replays reproduce the same craters and fallout.

A **nuclear strike** is a one-use area-effect attack, distinct from the round-by-round duel of
§5.4. It does not "fight" a single defender: it detonates over a **target tile** and damages
*everything* in an area, friend and foe alike, then **contaminates** the ground.

* **Eligibility & range.** Nuclear units carry the `nuke` + `one_use` tags. A `tactical_nuke`
  is a short-range missile (data `air_range`, placeholder 12) launched from a settlement,
  carrier, or missile-cruiser within range; an `icbm` carries `global_range` (`air_range` 999)
  and may target **any** tile on the map. Both require the **Uranium** resource to build and a
  player who has either completed the **Manhattan Project** or for whom nukes are globally
  enabled. The unit is **consumed** on launch whether or not it is intercepted.
* **Interception.** Before detonation, one interception chance is assembled from two
  sources: an enemy **anti-air unit** (SAM Infantry, Missile Cruiser — the `anti_air` tag)
  within `nuke_interception_range` contributes `nuke_interception_chance` (placeholder),
  and the **SDI project** (§15.7) contributes its `nuke_interception` effect (reference 75%)
  for any target-side owner — a player, other than the attacker, with a settlement or unit
  on the target tile. The **best** available chance is rolled **once** per strike; a
  successful interception destroys the missile **with no effect on the target** (the launching
  player is still notified). This roll is drawn from the shared generator in pipeline order.
* **Blast & damage.** On detonation the engine resolves an **area effect** centred on the target
  tile out to a **blast radius** (placeholder: Tactical Nuke = the single target tile only
  ("0", point strike); ICBM = the target tile plus all adjacent tiles, "radius 1"):
  * **Units** in the blast each roll damage 30 + rand(50) + rand(50) (reference values,
    each part uniform 0..n−1; two draws per unit in blast-scan order). A **combat unit**
    (base strength > 0) takes the damage **non-lethal-floored** at ≥ 1 health — a strike
    alone never wipes a stack, it **softens** defenders. A **non-combatant** is instead
    **killed outright** when its roll reaches the death threshold (60) and untouched
    otherwise. Damage applies to **all** owners in the area, **including the attacker's
    own** units — there is no friendly-fire exemption.
  * **Settlements** in the blast lose 30 + rand(20) + rand(20) % of current **population**
    (reference values), each standing **structure is destroyed with 40% probability**
    (per-structure roll in list order), and the accumulated **defensive/garrison bonus**
    and stored production are reduced; a settlement is **never destroyed outright** by a
    strike (it can still be taken only by capture, §4.8).
  * **Bomb Shelter** in a struck settlement reduces the population loss and unit damage there by
    its `nuke_damage_reduction` (data, placeholder 50%).
  * **Tile improvements & features** in the blast are **pillaged/stripped** (improvements
    destroyed; vegetation removed), as with a heavy area strike (§11).
* **Radiation (fallout).** Each tile in the blast — and a ring of tiles around it — has a
  **contamination chance** (placeholder) of gaining the **Fallout** feature (data: output
  `−3/−3/−3` food/production/commerce, `+50` movement cost, `health_penalty 1`, `removable`).
  Fallout therefore:
  * **poisons tile yield** (worked Fallout tiles produce almost nothing),
  * **slows movement** through the contaminated zone,
  * **harms wellbeing** (§4.6) of any settlement working a Fallout tile in its radius, and
  * **lingers** until cleaned. A worker-type unit removes Fallout with a `clean_fallout` work
    action (cost in data; the **Ecology** tech / Recycling Center speeds it — see §11). Fallout
    may **also** be created independently by ordinary heavy area strikes and by a **Nuclear Plant
    meltdown** (provisional: a small per-turn meltdown chance that spawns Fallout around the
    plant's settlement), not only by nuclear weapons.
* **Diplomatic & global consequences.** Launching a nuclear strike is an act of war and a
  **global** event:
  * it adds a large amount of **war-fatigue** (§ combat/economy) to the *attacker* (and unhappiness
    across that player's settlements), reflecting domestic and world revulsion;
  * it may **break peace** and sour standing with all third parties, not just the victim;
  * while a **Non-Proliferation** resolution / `no_nuclear` standing effect is in force (§7.2),
    building or launching nuclear units is **forbidden**, and a player who defies it incurs the
    assembly-defiance penalty (§4.5) once that hook is wired.

**Determinism.** Every stochastic step — interception, per-unit blast damage spread, the
per-tile contamination roll, and any meltdown check — draws from `gs.rng` in strict pipeline
order, so a replay reproduces the same craters and fallout. Strike results and the list of newly
contaminated tiles are surfaced through the normal area-effect/event channel for the
presentation layer (notifications + a `combat_resolved`/area-strike signal).

### 5.8 Naval blockade (provisional)

> **⚠️ Provisional — implemented, not verified.** The blockade reach and the commerce
> penalty (`blockade_range`, `blockade_commerce_penalty`) are placeholders to be tuned.

A **coastal** settlement (one that borders water) whose sea approaches are held by a hostile
fleet has its **trade choked**: while one or more hostile naval units — an enemy the owner is
at war with, or a wild fleet — sit within `blockade_range` of the city, its **commerce** is cut
by `blockade_commerce_penalty` (a percentage) for as long as the blockade holds.

* Only **naval** units blockade, and only **coastal** cities can be blockaded; inland cities
  and a city's own (or a peaceful third party's) fleet have no effect.
* The penalty applies to the city's total commerce — and therefore to its trade-route income
  (§6.7) — before the economic split, so it reduces gold, research, culture, and intelligence
  alike. (A blockade does not reduce food or production.)

---

## 6. Players, economy, and research

### 6.1 Treasury
* Net treasury change per turn equals finance income from settlements minus total upkeep
  (which scales with distance from the capital, number of settlements, and settlement
  size), minus policy upkeep and unit costs.
* Upkeep is reduced by administrative structures and certain policies. If the treasury
  cannot cover upkeep, the research allocation is forced down and, in the extreme,
  units are disbanded (insolvency). Structures are never sold — buildings and their
  invested costs are always retained; with no units left the treasury simply clamps
  at zero.

### 6.2 Allocation rates
The player adjusts **three** rates — research (science), culture, and intelligence
(espionage) — in 10% steps via +/− controls, constrained to increments allowed by the
governing policies; the three may sum to at most 100 and **finance (economy) is the
derived remainder** (100 − the three), shown read-only. Some policies cap the maximum
research rate (a minimum research share). The resulting four-way split partitions each
settlement's generic economic output.

* **Starting allocation.** A new player begins at **100% research** (everything else at
  0%), so the tech tree advances from turn one without the player having to touch the
  rates. With no finance income this draws the treasury down, so the player is expected
  to dial research down (raising the derived economy remainder) once gold runs low.
* **Computer players** manage this allocation automatically: they keep the split
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
* **Tech cost — the canonical percent chain.** A technology's base cost is scaled by a fixed
  chain of independent rule-table percentages, then floored at 1:

  ```
  cost = baseCost
       × handicapResearchPercent / 100      # difficulty (§2.2): Settler 60 … Noble 100 … Deity 135
       × worldResearchPercent    / 100      # map size (larger maps cost more)
       × speedResearchPercent    / 100      # pace: Quick 67 / Normal 100 / Epic 150 / Marathon 300
       × eraResearchPercent      / 100      # advanced-start era
       × max(0, TECH_COST_EXTRA_TEAM_MEMBER_MODIFIER × (teamMembers − 1) + 100) / 100
  cost = max(1, cost)
  ```

  *(The engine applies the full chain in `Research._effective_cost`: the human pays the
  difficulty handicap, the AI instead pays the per-era `ai_research_per_era` modifier
  (negative = cheaper per era), then world size, speed, era, and team factors; see §2.2.)*
* **Humanish discounts (additive on top).** Beyond the canonical chain, this game also makes
  a tech **cheaper when prerequisites are held** and **cheaper per number of others who
  already know it** (a catch-up discount). These are intentional extensions, not part of the
  reference cost; they apply after the percent chain.
* A project completes when accumulated progress meets its cost. Completed research unlocks
  units, structures, policies, improvements, resources, trade abilities, wonders, and victory
  projects, following a prerequisite graph that supports both required-all and required-any
  dependencies.

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

**Specialists are a first-class data table** (reference parity). The canonical roster is
**14 specialist types** — the working specialists `citizen, priest, artist, scientist,
merchant, engineer, spy` plus their great-person counterparts `great_priest, great_artist,
great_scientist, great_merchant, great_engineer, great_general, great_spy`. Each specialist
record defines its per-head output vector (food/production/commerce, and which commerce
type), the great-person points it generates and of which type, and any prerequisite. *(The
engine currently models specialists only implicitly via unit `generated_by` tags and
per-structure slot counts; promote them to an explicit `data/specialists.json` table so
output, GP-point type, and slot rules are data-driven rather than hard-coded.)*

### 6.6 Conscription / the draft (provisional)

> **⚠️ Provisional — implemented, not verified.** The population cost, minimum city size,
> and unhappiness (`draft_population_cost`, `draft_min_population`, `draft_anger_turns`) are
> placeholders to be tuned.

A player running a civic that permits conscription (`can_draft`, e.g. **Nationhood**) may
**draft** a military unit directly from a city's population instead of building one:

* The city must be at or above a **minimum size** and **not in disorder**; the draft spends
  population and stirs **conscription unhappiness** (the same anger channel as rushing, §4.5).
* The unit raised is the **most advanced draftable unit** the player has the technology for
  (data flag `draftable`, e.g. the gunpowder infantry line). Drafted units arrive with reduced
  training — only their civic starting-experience, no building experience (§5.5).

### 6.7 Trade routes (provisional)

> **⚠️ Provisional — implemented, not verified.** Route counts and yields (`trade_routes_base`,
> `trade_route_per_city`, `trade_route_base_yield`, `trade_route_pop_pct`,
> `trade_route_foreign_bonus`) are placeholders to be tuned. The base route count is **0**, so
> routes appear only once a civic grants them.

Each city runs a number of **trade routes** to other cities, each route adding **commerce** to
the city's output (§4.3):

* **Route count** is a base plus a per-city civic bonus (`trade_route_per_city`, e.g.
  **Free Market**).
* Each route connects to a **distinct other city**; the highest-yielding partners are chosen.
  A route's yield is a base plus a share of the two cities' combined size, with an extra bonus
  for a **foreign** partner.
* **Restrictions.** A civic carrying `no_foreign_trade_routes` (**Mercantilism**) confines a
  player's routes to its **own** cities, and no route ever runs to a city the player is **at
  war** with. Route income is part of the city's commerce, so a **naval blockade** (§5.8)
  chokes it along with the rest.

---

## 7. Alliances, diplomacy, and war

* An **alliance** is the unit of war, diplomacy, shared vision, and shared research. A
  single player may form an alliance of one, or several players may share one.
* **Contact** is established when alliances first meet; each alliance tracks whom it has
  met.
* **War and peace** are declared at the alliance level and toggle a war state. **War
  success** accrues from combat actions and feeds war-fatigue, which raises discontent over
  time.
* **Trades & deals.** A **deal** is a first-class, persistent object (reference parity): a
  bundle of items given by each side, which may be **one-off** (gold, a technology, a city,
  maps) or **recurring per-turn** (gold-per-turn, a resource, open-borders/passage rights, a
  defensive pact). Deals are stored on the game state, **executed each whole-world step**
  (recurring items deliver; one-off items deliver once then close), and **cancellable**
  subject to a minimum duration. Tradeable item kinds: treasury, gold-per-turn, resources,
  technologies, settlements, maps, passage/open-borders, mutual-defense pacts, and peace.
  *(Implemented: a recurring trade promotes to a persistent deal on `GameState.deals`,
  executed each world step by `TurnEngine._execute_deals` and cancellable past a minimum
  duration via the `CANCEL_DEAL` command. The currently-delivered recurring items are
  gold-per-turn and resource access; the remaining item kinds — cities, maps, open-borders,
  defensive pacts — are carried on the deal object but not yet enforced at their consuming
  sites.)*
* **Attitude & memory (AI diplomacy).** Each AI player holds a per-rival **attitude**
  (Furious → Annoyed → Cautious → Pleased → Friendly) computed from weighted factors:
  shared/again belief, shared war, fair/again trades, border friction, recent demands, and a
  decaying **memory** of past acts (declared war, broke a deal, razed a city, spread culture,
  traded techs, …). Attitude gates what deals an AI will accept, whether it will declare war,
  and how it votes in assemblies (§7.2). *(Implemented in the `Diplomacy` module
  (`src/sim/diplomacy.gd`) per `data/diplomacy.json`: a deterministic 0..100 attitude from a
  neutral base + live factors (at-war, shared war, permanent ally, an active deal,
  shared/clashing state religion) + a decaying memory of acts on `Player.diplo_memory`,
  bucketed into the five levels. `PlayerAI.manage_diplomacy` reads it to accept/refuse deals
  and to declare war (only on a loathed, weaker rival), and `Assembly.ai_vote` now reads it for
  resident elections and embargoes — closing the §7.2 "attitude ignored" note. Border-friction
  and demand-fatigue factors remain a future refinement.)*
* **Subordination / vassalage**: a weaker alliance may become a **tributary or vassal** of a
  stronger one — sharing its wars, paying tribute, and (for full vassalage) capitulating after
  a lost war and being freed when strong enough again. The reference models this on a **team**
  tier that also groups tech-sharing and shared war/peace; this game folds the team concept
  into the alliance object, so vassalage rules live on `Alliance` (`is_subordinate_to`,
  `tributaries`). *(Capitulation/liberation thresholds are a parity gap to close.)*
* **Intelligence/espionage**: each alliance accumulates intelligence points against every
  alliance it has met, spent on covert missions (stealing technology, sabotage, inciting
  unrest, and more) with costs and interception chances governed by configuration (§7.1).

### 7.1 Espionage points & missions (provisional)

> **⚠️ Provisional — preliminary, not verified.** This subsection documents the
> first-pass espionage model now wired into the engine. The accumulation/output/defense
> formulas, the mission-cost curve, and the mission effects are placeholders to be
> verified and tuned against the reference game before being relied on. There is **no AI
> behaviour** for espionage yet (the computer player neither funds the espionage rate nor
> launches missions); missions are reachable from the human espionage advisor and through
> `apply_command`.

**Espionage point (EP) accumulation.** Each turn, a player's espionage output is banked as
EP and **spread evenly across every alliance it has met** (its `contacts`), tracked per
target alliance. A player's per-turn output is the sum, over its settlements, of:

* the **intelligence slice** of that city's commerce (the espionage allocation rate, §6.2);
  plus
* the **flat espionage** of the city's structures (Palace +4, Courthouse +2, Jail +4,
  Security Bureau +8, Intelligence Agency +8, …);

with that per-city subtotal then scaled up by the city's **`espionage_output`** percent
(Intelligence Agency +50%, the Castle line +25%, Scotland Yard +100%; these stack
additively). Empire-wide **civic** espionage (e.g. Nationhood +4) is added on top before
distribution.

**Mission cost (§15.5).** A mission's cost is

```
cost = base_cost × (1 + EP_advantage / 100)
```

where `base_cost` is `intel_mission_cost` and `EP_advantage` (a percent, capped at
`intel_cost_advantage_max`) measures how much more EP the **target** alliance holds against
the attacker than the attacker holds against the target — i.e. hitting a rival who has been
spying on you harder costs more. When the attacker is ahead the advantage is zero and the
cost floors at `base_cost`. The mission spends its cost in EP whether or not it succeeds.

**Interception.** After the cost is paid, the mission is intercepted with probability
`intel_interception_chance` **plus** the strongest **`espionage_defense`** percent among the
target alliance's cities (Jail/Security Bureau/Mausoleum +50%), capped at
`intel_interception_max`. An intercepted mission is announced and produces no effect.

**Missions implemented.** `steal_tech` (copies one technology the attacker lacks from the
target), `sabotage` (halves a target city's stored production), and `incite_unrest` (tips
the target alliance's most populous city into disorder for its owner's next turn). Other
missions named in the design narrative are not yet modelled.

### 7.2 World assemblies, elections & resolutions (provisional)

> **⚠️ Provisional — newly implemented, not verified.** This subsection documents the
> **world government** mechanics — the religious assembly (Apostolic Palace) and the secular
> assembly (United Nations) that elect a presiding leader and pass binding resolutions — as
> now wired into the engine (`src/sim/assembly.gd`, the `Assembly` module). The offices, the
> resolution catalogue and its **flavour text**, the vote-weight rules, the session cadence,
> the AI voting heuristic, and every constant are placeholders drawn from a preliminary reading
> of the reference game and have **not** been balance-tested. The effect set is partly wired and
> partly recorded-only (called out below). All quantities are integer math per the engine
> invariants (vote shares are integer percents 0–100), and every random draw goes through the
> shared `gs.rng`, so sessions are reproducible and captured by save/load.

A **diplomatic assembly** is a periodic voting body that lets the players collectively elect
a presiding **resident** and enact binding **resolutions**. The game models two, each **founded
by a world wonder**:

* the **religious assembly** (founded by the **Apostolic Palace**, `effects.religious_assembly`),
  a Medieval-era body organised around a single belief (§8); and
* the **secular assembly** (founded by the **United Nations**, `effects.un_elections`),
  a Modern-era body organised around all players, which **supersedes** the religious one.

The legacy **population poll** still runs: each whole-world step (§3 world-step 7)
`_resolve_assembly` tallies a population-weighted vote count per alliance into
`gs.diplomatic_votes`, and the §10 **Diplomatic** win still awards victory to any alliance
holding at least `vote_share_required` (placeholder 67%) of that total. The new assembly
lifecycle runs **immediately after**, via `Assembly.world_tick`, and is the interactive layer
on top of that standing.

* **Founding & gating.** `Assembly.active_body` returns the secular body if any city holds the
  United Nations, else the religious body if any city holds the Apostolic Palace, else **none**
  — so with no founding wonder there is no assembly (and razing the wonder dissolves it). The
  religious body organises around the **belief of the city holding the Apostolic Palace**.
* **Membership & vote weight.** A **religious** member weights by the population of its cities
  **holding the assembly's belief** (a player with no such city is not a member); a **secular**
  member weights by **total governed population** (the United Nations guarantees eligibility, so
  every non-eliminated player is a member). *(Provisional: the secular body does not yet filter
  on met-contact, §7.)*
* **Sessions.** The body convenes on a fixed cadence (`assembly_session_interval` turns). A
  session records **one proposal** — a **leadership election** while the chair is vacant,
  otherwise a random eligible **resolution** drawn from `data/resolutions.json` (§18) with the
  shared RNG. The proposal opens one world step and **resolves on the next**, giving every member
  exactly one player-turn to vote in between (one assembly action per world tick).
* **Voting.** Each member casts **Yea / Nay / Abstain** through the `CAST_VOTE` command
  (`SimFacade.cast_assembly_vote` / `Commands.cast_vote`). On a human member's turn the facade
  raises a **choose-election** popup (`IDs.PopupType.CHOOSE_ELECTION`); computer players vote in
  `PlayerAI.manage_assembly` via the deterministic self-interest heuristic `Assembly.ai_vote`
  (back your own bloc's candidate, never hand a rival the game, sue for peace when at war, resist
  embargoes aimed at you, …). At resolution, non-voters **abstain**; votes are tallied by weight
  and the proposal **passes** when the Yea share of the whole chamber's weight reaches
  `resolution_pass_share` (or a per-resolution `pass_share`). Abstentions count present but not
  for, so they make passage harder.
* **Leadership election.** Members elect a **resident** (the presiding player — a "Pope" for the
  religious body, a "Secretary-General" for the secular one); the front-runner (highest-weight
  member) stands as candidate. The resident sets the agenda (every later session proposes a
  resolution) until the chair falls vacant again.
* **Resolutions & effects.** A passed proposal applies its effect. **Fully wired:**
  `elect_resident` (seat the resident); `diplomatic_victory` (when the Diplomatic win is enabled,
  the candidate's alliance **wins**, §10); `force_peace` (global cease-fire — clears all war and
  war-fatigue); `civic_mandate` (members adopt the resident's government civic where tech allows);
  `religion_mandate` (members harbouring the assembly belief adopt it as **state religion**, §8.1,
  bypassing the switch anarchy as a compelled change); `resident_aid` (grant the resident gold).
  **Recorded as standing effects** (stored on the assembly, partial enforcement):
  `trade_embargo` (the sanctioned alliance is blocked from proposing/receiving trades, §7);
  `free_religion_spread` and `no_nuclear` (recorded; full enforcement pending the relevant
  subsystems). The "defiance of assembly rulings" contentment penalty (§4.5) is **not yet** wired
  to the contentment model.

Persistence and determinism: the assembly record (`kind`, organising belief, `resident_player_id`,
the open `pending` proposal and its cast `votes`, and standing effects) is serialized on
`GameState.assembly`, so a session in progress survives save/load and stays on the determinism
gate; `pending_assembly_events` is the transient queue the facade drains into notifications and
the `assembly_event` signal.

### 7.3 Diplomatic victory (provisional)

> **⚠️ Provisional — preliminary, not verified.** The thresholds, the Apostolic-Palace
> cadence, the eligibility gates, and the "too big" share are placeholder constants in
> `data/constants.json` (`un_diplo_pass_share`, `ap_diplo_pass_share`,
> `ap_diplo_victory_interval`, `diplo_too_big_share`) and have **not** been balance-tested.

A **Diplomatic victory** (§10) is won by carrying a **supreme-leadership** election (the
`diplomatic_victory` resolution, §7.2) in a world assembly. It is available only when
`"diplomatic"` is among the enabled win conditions. There are **two paths**, one per founding
wonder, with different thresholds and gates; on success the **candidate's alliance** wins the
game immediately (`Assembly.apply_effect` sets `winning_alliance_id`). The per-resolution
`pass_share` in `data/resolutions.json` is **not** used for this motion — the threshold is
body-dependent and computed in code (`Assembly._pass_share_for`).

* **United Nations (secular).** Any player may build the United Nations (it requires the
  **Mass Media** technology), but only a player who has itself **researched Mass Media** may
  stand as the winning candidate. Once a **Secretary-General** (the secular resident) is seated,
  the body may put the supreme-leadership motion forward from the resident's session agenda. The
  motion carries at **`un_diplo_pass_share` (60%)** of the chamber's total vote weight. Secular
  vote weight is a member's **total governed population**.

* **Apostolic Palace (religious).** The supreme-leadership motion **appears automatically every
  `ap_diplo_victory_interval` (50) turns**, independent of the resident's agenda, but only while
  **every living civilisation holds the assembly belief** in at least one city (the *AP
  eligibility rule*). It is a **two-candidate runoff**: the **wonder owner** (who stands by right
  of holding the wonder, regardless of weight or faith) and the strongest **full member** both
  stand. A *full member* is a member that runs the assembly belief as its **state religion**
  (§8.1) and is **not in defiance** of the assembly (§4.5); the wonder owner aside, only a full
  member may be elected. The slate collapses to a single candidate when no other full member
  qualifies. Each member casts its full weight **for one candidate or abstains** (no Yea/Nay); the
  **leading** candidate (ties → lowest id) wins if its share of the whole chamber's weight reaches
  **`ap_diplo_pass_share` (75%)** — so a roughly even split elects no one. Religious vote weight is
  the population of a member's cities holding the belief, **doubled** for a member running that
  belief as its state religion; a member need **not** run it as state religion (nor be a full
  member) to **vote**, only to **stand** as the rival candidate.

> **Defiance (provisional).** A member enters **defiance** of the assembly when it votes against a
> binding **mandate** that passes (`civic_mandate` / `religion_mandate`); a defiant member is no
> longer a "full member" and cannot stand in a runoff. The set is recorded on `GameState.assembly`
> (reset when the founding wonder changes or is lost). The matching §4.5 *defiance-of-rulings*
> contentment penalty is still **not wired** — defiance currently affects only candidacy.

* **The "too big" rule.** Regardless of the tally, a candidate **cannot win** if its own
  **alliance** already casts **`diplo_too_big_share` (75%)** or more of the total vote weight —
  there must be a genuine pool of other voters to carry it past the bar. A motion that clears the
  vote but trips this rule (or the path-specific gate above) awards nothing and is surfaced as a
  `victory_blocked` assembly event. (Measuring the share at the **alliance** level — rather than
  the single candidate civ of the reference rule — keeps it consistent with the alliance-based
  resolution of every other win condition, §10.)

* **AI voting.** A computer member casts its weight for a candidate from its own bloc — itself
  if it stands, else a bloc-mate, else its **overlord** if it is that overlord's **vassal** (a
  subordinate alliance, §7). With no friendly candidate it **abstains** rather than push a rival
  past the threshold — an AI never casts for a rival. *(The supreme-leadership motion stays
  bloc-only by design — attitude never moves it, so an AI cannot be talked into handing a rival
  the game. Attitude **does** now sway the lower-stakes motions: `Assembly.ai_vote` backs a
  Pleased-or-better candidate in a resident election and resists an embargo aimed at a favoured
  alliance, §7 `Diplomacy`.)*

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
* **Economic organizations / corporations**: founded by a special person, they spread like
  beliefs but consume input resources to produce output in member settlements; spreading them
  costs treasury. Competing organizations cannot coexist in the same settlement. The reference
  models these as a full **corporation** subsystem — **7 corporations**, each with:
  * a **headquarters structure** (`BUILDING_CORPORATION_n`) built once, in the founding city,
    which earns the founder gold per franchise (member city) worldwide;
  * an **executive unit** (`EXECUTIVE_n`, the corporate analogue of a missionary) that spreads
    the corporation to a new city for a treasury cost;
  * a set of **input resources** the corporation consumes in each member city to produce a
    per-city output bonus (commerce/production/food/health), scaling with the **count of those
    resources** the owner has access to;
  * a **maintenance cost** per member city, and an exclusion rule (a city cannot host two
    corporations that compete for the same inputs), plus interactions with civics (e.g. a
    state-property economy bans corporations).

  *(Implemented in `econ_orgs.gd` / `data/econ_orgs.json`: the HQ building, executive unit,
  per-resource-instance output/maintenance scaling, produced strategic resources, and civic
  bans — see §15.10 for the shipped model and §29.6 in `game-data.md` for the rates.)*

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

### 8.2 Missionary belief spread (provisional)

> **⚠️ Provisional — implemented, not verified.** The single-belief-per-city conversion rule
> and the build-gate are a first-pass model not yet checked against the reference game.

Beyond the passive turn-by-turn spread (§8), a player may spread a religion deliberately with a
**missionary** unit (data tag `spread_religion`):

* **Spreading.** A missionary standing on a city's tile converts that city to the player's
  religion — its **state religion** if adopted, otherwise a belief the player **founded** or
  one its cities already follow. In this single-belief-per-city model a missionary only
  converts a **faithless** city, and the missionary is **consumed** on a successful spread.
* **Theocracy block.** A target whose owner runs **Theocracy** (`blocks_nonstate_spread`)
  rejects any religion other than that owner's state religion.
* **Training missionaries.** A city can train missionaries only when the player **has a
  religion** and the city holds a `trains_missionaries` structure (a **Monastery**) — or the
  player runs **Organized Religion** (`missionary_without_monastery`), which lifts the
  monastery requirement.

---

## 9. Wild forces, exploration rewards, and events

* **Wildlife** appears in unclaimed territory early, with combat modifiers from difficulty.
  **Raider forces** spawn in unexplored or unclaimed areas with increasing frequency and can
  establish their own settlements; an optional setting increases their aggression.
  Difficulty grants players a number of "free wins" against these forces (the odds clamp in
  combat resolution). The spawning model — turn/era/city gates and the per-area density
  formula that governs *how many* wild units and cities appear — is detailed in §9.2; the
  behaviour of forces once spawned is §9.1.
* **Exploration rewards / goody huts**: the reference scatters **goody huts** (tribal
  villages) across the map at generation time on land tiles away from starts, as a dedicated
  generation stage with a placement predicate (`canPlaceGoodyAt`). The **first land unit** to
  enter a hut consumes it and rolls a weighted reward from a `data/goodies.json`-style table:
  treasury, map knowledge, experience, a free unit (scout/settler/worker), a free technology,
  a heal, or a hostile ambush. *(The engine currently places "discovery sites" only on
  Terra-style maps; generalise goody-hut placement to all map scripts and make the reward
  table data-driven with per-difficulty weights.)*
* **Events — selection, choice, apply, expire**: the random-event system is data-driven and
  far richer than a one-shot table. Every event is a single record in `data/events.json`
  carrying its own **prereq** predicate, **obsolete** techs, an **active** inclusion percent, a
  selection **weight**, and either begin `effects` or a set of **non-skippable choices** (and an
  optional `duration`/`expire_effects` for timed events). **Selection** runs once per player per
  turn: a flat **grace period** (`event_grace_turns`, *not* pace-scaled) suppresses events at
  game start; thereafter a single roll at **`event_era_chance[era]`** (1/2/4/4/6/8/10% by era,
  Ancient→Future) decides whether *any* event fires, and if so one **eligible** event is drawn
  **weighted** by `weight`. An event is eligible when it is in this game's **roster** (each
  event's `active`% is rolled once at setup into `GameState.active_event_ids`), every prereq
  holds, it holds no obsolete tech, it is not a still-running timed instance, and (if one_shot)
  has not already fired. **Choices** are mandatory: a human cannot end their turn while an event
  decision is unresolved. **Determinism**: any random magnitudes (`range`) and probabilistic
  branches (`chance`) are rolled **once at fire time** in fixed order and baked into the begin
  effects / the parked choice's branches, so applying a resolved choice draws no RNG and a human
  may answer the popup at any point in their turn without perturbing the shared stream. The
  prereq vocabulary, the full effect-verb list, and the catalogue roadmap (porting the
  reference's ~174 events + 18 quests, and the subsystems each needs) live in
  `docs/planning/event-subsystem-planning.md`. *(The shipped catalogue is a representative
  vertical slice; map-size / game-speed scaling of magnitudes and the multi-turn Quest subsystem
  are deferred — see the planning doc.)*

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

### 9.2 Wild-forces spawning (provisional)
> **⚠️ Provisional — preliminary, not verified.** This subsection ports the original reference's
> barbarian-generation model (its barbarian unit/city creation processes; constants from the
> reference handicap table) and adapts it to this engine's difficulty/pace tables.
> The per-difficulty tables in `data/difficulties.json` are transcribed from the reference game
> and **not yet retuned** for this engine's map sizes or unit roster. All math is integer per the
> engine invariants, and every roll is drawn from the shared `gs.rng` in pipeline order, so
> spawning is deterministic and captured by save/load. This describes *how many* forces appear and
> *where*; §9.1 describes how they then act.

Ambient wild **units** top up toward a target density, gated by three checks evaluated each
world step (§3 world-step 4, before the wild AI acts):

1. **Turn gate.** Nothing spawns until `wild_creation_turns_elapsed` turns have passed
   (per-difficulty: Settler 50 → Deity 10). The gate is **scaled by game pace** via the pace's
   `growth_scale` (Quick 67%, Normal 100%, Epic 150%, Marathon 300%), so a 40-turn gate becomes
   ~120 turns on Marathon — mirroring the reference's game-speed barb-percent scaling.
2. **Era gate.** Organised wild units appear only once the game's **current era** (the most
   advanced any living player has reached) clears the per-era `no_wild_units` flag in
   `data/ages.json`. The starting (Ancient) era carries the flag — the reference's `bNoBarbUnits`, the
   "quiet animal phase." *This engine has no fauna subsystem yet, so that early window is simply
   silent rather than populated with wildlife (a known gap).*
3. **City-density gate.** Wild units hold off until the world has settled in:
   `civ_cities ≥ (wild_city_ratio_num / wild_city_ratio_den) × living_civs` — the reference's
   `numCivCities < 1.5 × civsAlive` check (default 3/2).

Once the gates clear, the map is partitioned into **contiguous land areas** (8-connectivity).
For each area, the target is one wild unit per `unowned_tiles_per_wild_unit` **unowned** tiles
(Settler 150 → Deity 25; "unowned" = no player culture), and roughly a quarter of the shortfall
is filled per step:

```
target = area_unowned_tiles / unowned_tiles_per_wild_unit
needed = ((target − area_existing_wild_units) / 4) + 1      # only when target − existing > 0
```

New units are placed on random unowned, unoccupied land tiles kept at least
`wild_spawn_min_distance` (reference `MIN_BARBARIAN_STARTING_DISTANCE`) from any civ unit or city, and
spawn as the **strongest generic land unit** the leading player has unlocked (resources ignored,
as in §9.1). A global ceiling of `total_unowned / divisor + 1` guards against many small areas
each contributing their `+1`. (Naval raiders — `unowned_water_tiles_per_wild_unit`, Settler 750
→ Deity 250 — are the sea counterpart; see §9.4.)

Wild **cities** (raider camps, §9.1's muster points) spawn on their own, later schedule:

* **Turn gate** `wild_city_creation_turns_elapsed` (Settler 55 → Deity 15), pace-scaled as above.
* **Per-area density cap**: a camp is allowed only while
  `area_wild_cities < area_unowned_tiles / unowned_tiles_per_wild_city` (Settler 160 → Deity 80).
* **Creation roll**: `wild_city_creation_prob` % per eligible area per step (Settler 4 → Deity 8).
* **Distance rule**: a camp is placed at least `wild_city_min_distance` (default 6) tiles from
  any civ settlement and any civ cultural tile — the reference's minimum barbarian-city spacing.

**Known gaps / simplifications (to revisit):** the per-difficulty tables are reference values, untuned
here; naval/air wild spawning is covered by §9.4; and the "current era" gate uses the
most-advanced living player rather than a distinct game-era track.

### 9.3 Wild animals (provisional)
> **⚠️ Provisional — preliminary, not verified.** Animals model the reference's *GameAnimal* layer — the
> wildlife that prowls the unexplored early map before organised raiders appear. Magnitudes are
> reference-derived and untuned. All math is integer and every roll is from the shared `gs.rng`.

Animals are a **subset of wild units** (`owner_player_id = -2`, `is_wild = true`, plus
`is_animal = true`) defined by data — `data/units.json` entries with `"classification": "animal"`
(Wolf, Lion, Panther, Bear). They are the **quiet-phase** population: spawning fills the early game,
*before* the §9.2 gates open, and hands off to raiders once they do.

* **Spawning (`WildForces.spawn_animals`).** While the §9.2 wild-*unit* gates are **not** yet
  satisfied, animals spawn on tiles that are **unowned**, passable land, unoccupied, and **outside
  every player's sight** (the same `unit_sight` / `city_sight` Manhattan fog model the UI uses —
  i.e. in the dark / unrevealed map), up to one animal per `unowned_tiles_per_animal` unowned land
  tiles (Settler 100 → Deity 20), a few per step. Once the wild-unit gates **do** open, no new
  animals appear and the existing ones are **thinned one per world step** (the reference's animal→barbarian
  handoff). Animals are a **separate population**: they do not count toward the §9.2 raider density
  and are never chosen as raider/wave stock.
* **Behaviour (`WildAI._act_animal`).** Each animal hunts the **nearest weak prey** within
  `animal_detect_radius`: a **civilian or unfortified** player unit that is **not standing in a
  city** (animals leave cities and garrisons alone). It moves toward and attacks that unit, but
  **never assaults a city** and — on most difficulties — **never enters player borders**
  (`animals_enter_borders`, true only on the higher difficulties). With no prey in range it
  **wanders** one tile (also refusing borders). Animals do not rouse raider camps.
* **Combat limits.** Animals **earn no promotions** from combat (`CombatApply.award_promotions`
  is a no-op for them), and a player unit's **lifetime XP from killing animals is capped** at
  `animal_xp_lifetime_cap` (5, per the reference `ANIMAL_MAX_XP_VALUE`; 10 is the *barbarian* cap) — tracked on `Unit.xp_from_animals`; beyond it, hunting
  animals yields no further experience. (This is in addition to the existing per-fight
  `experience_vs_wild_cap`.)

**Known gaps / simplifications (to revisit):** the silent pre-animal era no longer exists (animals
fill it), but animals are land-only; "weak" is a coarse civilian-or-unfortified test rather than a
real threat assessment; and visibility is computed from current sight only (no per-player explored
memory in the sim), so an animal may spawn on a tile a player has seen before but cannot currently
see.

### 9.4 Naval raiders (provisional)
> **⚠️ Provisional — preliminary, not verified.** Sea-domain wild forces, the water
> counterpart of §9.2's land raiders. Magnitudes are reference-derived and untuned.

Naval raiders are wild units (`owner_player_id = -2`, `is_wild = true`) of a **sea-domain** type
(`data/units.json` `"domain": "sea"`).

* **Spawning (`WildForces.spawn_naval`).** Gated identically to land raiders (the three §9.2
  gates), they fill each **contiguous water area** toward one raider per
  `unowned_water_tiles_per_wild_unit` unowned sea tiles (Settler 750 → Deity 250 — far sparser
  than land, so only real oceans see them), using the same `((unowned/divisor) − existing)/4 + 1`
  top-up and a global ceiling. The raider type is the **strongest generic sea unit any player has
  unlocked**, so the seas stay **empty until someone can sail** (no naval tech ⇒ no naval raiders).
* **Behaviour (`WildAI._act_naval`).** A deliberately simple **random patrol**: each step the
  raider picks a random adjacent passable-sea tile and sails there; if that tile holds a player
  unit, it **attacks** the unit it "lands on" instead of moving (resolved through the shared
  `CombatApply`, surfaced via `pending_wild_events` like every other wild fight). It never chooses
  a tile already held by its own kind, so it cannot stall. It takes no part in land-camp musters.

**Known gaps / simplifications (to revisit):** no transport/coastal-raid behaviour (raiders never
disembark or bombard land/cities), no naval raider "camps", and the patrol has no goal-seeking —
it wanders until it bumps into something.

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
| **Diplomatic** | A candidate carries the supreme-leadership election in a world assembly — **60%** of the vote via the United Nations (candidate must hold Mass Media) or **75%** via the Apostolic Palace (every living civ must hold its belief). A candidate whose own alliance casts ≥ **75%** of the vote is barred ("too big"). See §7.3. |
| **Score** | The reference exposes **Score** as its own enabled condition (the 7th, alongside the six above). When enabled with a score target, the first alliance to reach a configured absolute **score** threshold wins immediately. |
| **Time** | If no other condition is met by the final turn, the highest **score** wins (the time-limit tiebreak). |

> **Seven canonical conditions.** The reference set is **Conquest (Last standing), Domination
> (Dominance), Space Race (Endgame project), Cultural, Diplomatic, Score, and Time** — seven
> in all. This game previously shipped six, folding Score into Time; expose **Score** as its
> own selectable condition to match the reference.

**Score** is a weighted sum of population, land, technologies, and wonders, normalized
against the map and age.

---

## 11. Environmental degradation

### Global warming

Industrial pollution is modelled at the **whole-map** scale as *global warming*, run once
per world step (`GlobalWarming.tick`). Two global pressures drive it: the unhealthiness
produced by **buildings** across every city, and the running count of **nuclear explosions**
ever detonated (ICBM, tactical nuke, or Nuclear Plant meltdown). Each turn that pressure
yields a number of degradation **strikes**; **forest and jungle cover defends** against them.
Every landed strike degrades one **random non-city land tile** a single step toward the base
terrain (`gw_base_terrain`, *desert*) — stripping any vegetation feature first, then eroding the
terrain one rung along its `degrades_to` chain. **Every** land terrain participates (not just
flat farmland): the chains converge on the barren base, e.g. `mountain → hills → plains → desert`,
`grassland → plains → desert`, `tundra → snow → desert`. A terrain with no declared successor
collapses straight to the base, so the pass always terminates; the base terrain itself is inert.
City tiles are never chosen. Higher building unhealthiness or more nukes means more strikes; more
forest cover means fewer land.

The mechanic is specified by the following formulae, where `#LAND`/`#PLOTS` are the land-tile
and total-tile counts, `#FOREST` is the number of tiles carrying a feature with a positive
`growth_probability` (Forest and Jungle), `#BAD_HEALTH` is the summed building (structure)
unhealthiness across all cities (population/feature unhealthiness is **excluded**), and
`#NUKES_EXPLODED` is the cumulative explosion count:

```
GW_DEFENSE = #FOREST / #LAND * gw_forest_ratio
GW_VALUE   = #BAD_HEALTH / #PLOTS * gw_global_unhealth_ratio
             + #NUKES_EXPLODED * gw_nuclear_ratio / 100
PROB(≥1 strike) = 1 - ( (100 - gw_chance)/100 + #FOREST/#LAND * gw_forest_ratio/100 ) ^ GW_VALUE
```

`PROB` above is the probability of at least one strike across `GW_VALUE` independent trials,
each landing with chance `p = gw_chance - GW_DEFENSE` (integer percent, floored at 0). Because
the engine is integer-only, `GlobalWarming.tick` runs that **trial process directly** — it
takes `GW_VALUE` strike attempts (its fractional part resolved by one RNG roll) and rolls `p`
for each — rather than evaluating the fractional-exponent closed form; the distribution is the
same. Tunables `gw_base_terrain`, `gw_chance`, `gw_forest_ratio`, `gw_global_unhealth_ratio`,
and `gw_nuclear_ratio` live in `data/constants.json` (§12).

**Radioactive fallout (provisional).** The strongest form of lingering contamination is the
**Fallout** feature created by nuclear strikes, heavy area strikes, and (provisionally) Nuclear
Plant meltdowns (§5.7). Fallout is modelled as a removable tile feature that poisons yield,
slows movement, and harms settlement wellbeing (§4.6) until a worker-type unit clears it with a
`clean_fallout` action. The **Ecology** tech and the **Recycling Center** structure speed
cleanup; see §5.7 for the strike/meltdown side and the data tables for the Fallout feature's
exact penalties. (Provisional — not yet implemented; constants are placeholders.)

---

## 12. Configurable data

Everything numeric and every named game object is treated as **external configuration**
rather than hard-coded logic, including:

* **Global constants**: combat resolution scale and damage magnitude, maximum health,
  spillover/ranged/air damage, withdrawal/evasion caps, entrenchment cap, nuclear blast
  radius/damage, interception and per-tile contamination chances, and meltdown chance (§5.7),
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

## 15. Reference-parity mechanics (parity targets; unimplemented unless a subsection says otherwise)

> **⚠️ Provisional — none of §15 is implemented.** Every subsection below specifies a
> mechanic (or a rule-level correction) that exists in the reference game but has no
> Humanish model yet. Values are taken directly from the reference XML
> (layered original reference, highest layer wins) and are recorded here so implementation needs no
> access to the reference install. The work plan, priorities, and the value-retune
> lists for *existing* mechanics live in `docs/planning/directreferencegaps.md`
> (with the raw comparison in `docs/planning/reference-parity-audit.md`). Companion data
> tables: `game-data.md` §29. Remove each subsection's "unimplemented" marker (and move
> it into the appropriate numbered section) as it lands.

### 15.1 Inflation

Civilization-wide expenses (unit upkeep, settlement maintenance, civic upkeep) are
multiplied by an inflation rate that grows linearly with the game turn:

```
effective_turn   = current_turn + inflation_offset          (clamped at ≥ 0)
inflation_rate % = effective_turn × inflation_percent / 100 × handicap_percent / 100
expenses_total   = base_expenses × (100 + inflation_rate) / 100      (integer math)
```

Per-pace values (reference `iInflationPercent` / `iInflationOffset`): quick 45 / −60,
normal 30 / −90, epic 20 / −135, marathon 10 / −270 (the negative offset delays onset —
inflation starts once `current_turn` passes `−offset`). Per-difficulty multiplier
(reference handicap `iInflationPercent`): settler 60, chieftain 70, warlord 80, noble 90,
prince 95, monarch–deity 100.

Implemented (2026-07-12): `TurnEngine.inflation_rate` computes the rate from the game
turn (per-pace `inflation_percent`/`inflation_offset` in `paces.json`, per-difficulty
`inflation_percent` in `difficulties.json`); `TurnEngine.gold_upkeep` applies it to the
gross expense total (unit upkeep + settlement maintenance + corporation maintenance,
after the civic upkeep modifier), so the HUD gold rate, the AI's solvency reads, and
`_update_treasury` all see the same inflated figure. The §9 Federal Reserve event's
signed `inflation_pct` modifier composes on top, unchanged.

### 15.2 Population rush ("whipping")

The reference has **two** hurry types:

| Hurry type | Conversion | Side effect | Enabled by |
|---|---|---|---|
| Gold | 3 gold per hammer of remaining cost | none | always (Humanish: implemented) |
| Population | 30 hammers per population point sacrificed | +1 anger for 10 turns per rush (stacking) | **Slavery** civic (labor) |

Reference constants: `iProductionPerPopulation` 30, `iGoldPerProduction` 3,
`HURRY_POP_ANGER` 1, `HURRY_ANGER_DIVISOR` 10 (anger duration in turns),
`NEW_HURRY_MODIFIER` 50 (+50% cost when the item was queued this turn). Production per
population scales with pace (reference hurry percent: 67/100/150/300).
Sacrificed population must respect a minimum city size of 1 and cannot exceed
what the remaining cost requires.

Implemented (2026-07-12): the `RUSH_POPULATION` command (`Commands.rush_population`,
`SimFacade._cmd_rush_population`) whips the head production item — gated on a civic
carrying the `pop_rush` flag (Slavery's headline effect in `policies.json`). Math in
`TurnEngine.rush_pop_cost`/`rush_hammers_per_pop`/`rush_remaining_cost`:
`rush_production_per_pop` 30 hammers per citizen scaled by the per-pace `hurry_scale`
(67/100/150/300 in `paces.json`), pop cost = ceiling of the remaining hammers over
that (never more than the remaining cost requires), minimum retained city size
`rush_min_population` 1. An item queued this turn (`SET_PRODUCTION` stamps each queue
entry's `queued_turn`) costs `new_hurry_modifier` +50%. Each whip stacks one timed
anger entry (−`rush_pop_anger` 1 happiness for `rush_pop_anger_turns` 10 turns) on
the settlement via the §9 timed-happiness channel; a structure with the
`halve_slavery_anger` effect (Aztec Sacrificial Altar, previously inert shipped
data) halves that duration. All constants in `data/constants.json`. The gold path is untouched and keeps its pre-existing Humanish
tuning (1 gold per hammer, Universal Suffrage gate, flat 5-turn rush anger); its
3-gold-per-hammer reference retune remains an open parity gap.

### 15.3 Pace scaling for anarchy, golden ages, victory delay, and wild timing

Four per-pace multipliers the reference applies (Humanish previously ignored the
first three and folded the fourth into the build scale):

| Pace | anarchy % | golden-age % | victory-delay % | wild % |
|---|---|---|---|---|
| quick | 67 | 80 | 67 | 67 |
| normal | 100 | 100 | 100 | 100 |
| epic | 150 | 125 | 150 | 150 |
| marathon | 200 | 200 | 300 | 400 |

Applied to: policy/state-belief transition turns (`iAnarchyPercent`, with reference
bounds `BASE_CIVIC_ANARCHY_LENGTH` 1, `BASE_RELIGION_ANARCHY_LENGTH` 1,
`MAX_ANARCHY_TURNS` 100); Golden-Age length (`GOLDEN_AGE_LENGTH` 8 ×
`iGoldenAgePercent`; `golden_age_base_turns` 8 was previously scaled by the build
percent); turn-count victory checks (the cultural legendary-culture threshold
stretched by victory-delay %); and wild-forces spawn timing (the reference's own
`iBarbPercent` column — marathon 400, not a reuse of the 300 build scale).

Implemented (2026-07-12): four per-pace columns in `paces.json` (`anarchy_scale`,
`golden_age_scale`, `victory_delay_scale`, `wild_scale`, table above; `Fixed.scale`
truncation throughout). **Anarchy** — `SimFacade._anarchy_turns` stretches both a
civic switch's `transition_turns` (`_cmd_set_policy`) and a religion switch's
`state_religion_anarchy_turns` (`_cmd_set_state_religion`), clamped to
`anarchy_min_turns` 1 / `anarchy_max_turns` 100 (`constants.json`) so quick-pace
truncation never erases a real switch cost; espionage-induced anarchy (§7.1) is
mission-priced and stays unscaled. **Golden ages** — `GreatPeople._golden_age_duration`
reads `golden_age_scale` (8 turns → 6/8/10/16), replacing its old `build_scale` read.
**Victory delay** — *superseded by D2 (2026-07-17, §15.4)*: `WinConditions._cultural`
now requires each city's `culture_total` to reach the pace's own **legendary
culture-level threshold** (`culture_level_thresholds` top entry: 25000/50000/
75000/150000 on quick/normal/epic/marathon) — the reference per-speed culture
table carries its own scaling, so no `victory_delay_scale` stretch applies. The
`victory_delay_scale` column stays shipped per-pace reference data but is
currently unread (its reference use — spaceship-arrival delay — is unmodelled).
The **Time** victory turn limit is *not* additionally scaled: `max_turns` in
`paces.json` (330/500/750/1500) already carries the reference per-pace game lengths.
**Wild timing** — `WildForces._scaled_turns` reads `wild_scale` (a 40-turn gate →
26/40/60/160), replacing its old `growth_scale` read.

### 15.4 Culture levels & culture-level city defence *(implemented — D2 + C4, 2026-07-17)*

**The border curve (D2)**: the reference geometric culture-level progression
replaces the old near-linear 10-ring `culture_ring_thresholds`. Each pace row in
`paces.json` carries its own `culture_level_thresholds` column (5 levels — the
reference table has its own per-speed scaling, quick ×½ / epic ×1.5 / marathon ×3
of normal; see game-data §29.4). A settlement's **culture level** is the number of
thresholds its `culture_total` has passed (0 = poor … 5 = legendary, via
`CultureLevels.level_for`), and its **border ring** is `level + 1` (a fresh city is
ring 1 — own tile + immediate neighbours; a legendary city reaches ring 6).
`TurnEngine._settlement_culture` recomputes the ring each turn and feeds it to
`Influence.spread`; `CultureRevolt` reads the same ring for rival-city reach, and
the city work radius stays `min(ring, 2)` (the fixed 5×5 fat cross caps it).
**Cultural victory** reads the pace's legendary threshold directly (§15.3
victory-delay note).

**The defence modifier (C4)**: a settlement's culture level grants an intrinsic
defence modifier on top of structures (`culture_level_defence` in
`constants.json`), summed in `Combat.settlement_defence`:

| Level | Culture (quick/normal/epic/marathon) | City defence % |
|---|---|---|
| fledgling | 5 / 10 / 15 / 30 | +20 |
| developing | 50 / 100 / 150 / 300 | +40 |
| refined | 250 / 500 / 750 / 1500 | +60 |
| influential | 2500 / 5000 / 7500 / 15000 | +80 |
| legendary | 25000 / 50000 / 75000 / 150000 | +100 |

**Bombardment** reduces this modifier before combat: while a hostile settlement's
culture defence still stands, a `MISSION_BOMBARD` by a unit with a `bombard_rate`
(units.json; reference `iBombardRate`/air `iBombRate` — see game-data §29.4) adds
that many points to the settlement's serialized `defence_damage`
(0..`max_city_defence_damage` 100, reference `MAX_CITY_DEFENSE_DAMAGE`); the
effective culture defence scales as `base × (100 − damage) / 100`
(`Combat.culture_defence`). Ground/naval bombardment works from an adjacent tile;
air bombardment within air range (interception applies first). Once the culture
defence is flat — or the unit has no bombard rate — the same mission falls through
to the pre-existing ranged attack on the garrison. Damage heals a flat
`city_defence_heal_rate` **5 points per owner turn** (reference
`CITY_DEFENSE_DAMAGE_HEAL_RATE`; Humanish heals unconditionally — the reference's
skip-heal-on-a-bombarded-turn refinement is not modelled) in
`TurnEngine._settlement_upkeep`.

### 15.5 Chance first strikes

Reference units have `first_strikes` (guaranteed) **plus** `chance_first_strikes`: an
extra uniform-random 0…N first strikes rolled per combat (from the shared RNG, pipeline
order). Implemented: `Combat.rolled_first_strikes` sums the unit's `first_strikes`,
its promotions' `first_strikes_bonus`es, and one uniform 0…chance roll (unit
`chance_first_strikes` + promotion `chance_first_strikes_bonus`es), drawing from the
shared RNG only when a chance stat is present so chance-free units consume no draw.
Carriers: navy seal 1+1, skirmisher 1+1. Drill promotions also grant chance first
strikes (see `game-data.md` §29.3): Drill I carries +1 and Drill III +2
`chance_first_strikes_bonus` (values adopted from the reference, 2026-07-11), so
the promotion chance field is live shipped data.

### 15.6 Per-unit siege damage caps

The reference `iCombatLimit` is a **per-unit maximum damage percentage**: a sieging
attacker cannot reduce the defender below `100 − limit` HP (catapult/trebuchet 75 →
defender floor 25; cannon 80 → floor 20; artillery/mobile artillery 85 → floor 15;
machine gun and all non-siege units 100 → can kill). Implemented: `combat_limit`
stores the per-unit defender-health floor (catapult/trebuchet/hwacha 25, cannon 20,
artillery/mobile artillery 15; 0 = no cap), replacing the old universal 1-HP floor
that made all siege drastically stronger than the reference.

### 15.7 Nuke interception & the two missing projects

- **SDI** (project; tech Laser; cost 1000; requires the Manhattan Project completed by
  anyone; one per player): gives its owner **75%** interception chance against each
  incoming nuclear strike (`iNukeInterception` 75). Intercepted nukes are consumed with
  no effect.
- **The Internet** (project; tech Computers; cost 2000; one per game): its owner
  automatically acquires any technology already known by **2** other players
  (`iTechShare` 2), checked each turn.
- Reference nuke magnitudes, retuning §5.7's placeholders: building destruction
  40% per structure, population death 30 + rand(20) + rand(20) %, unit damage
  30 + rand(50) + rand(50) (kill threshold for non-combatants 60), fallout chance 50%
  per blast tile, global-warming nuke weight 50.
- **Missiles cannot defend** (D3 companion): a `classification: "missile"` unit is
  never selected as a stack/city defender, and a missile left with no surviving
  defender on a tile taken by an enemy (captured/razed city, or ground an attacker
  advanced onto) is destroyed rather than captured.

Implemented (2026-07-17): both projects ship in `data/projects.json` as **effects
projects** — a project without `win_condition: "endgame_project"` is recorded on
`Player.projects` when completed (`TurnEngine._complete_item`) and its `effects`
dictionary is read through `Projects.effect_int` (the project analogue of
`PolicyEffects`). Instance limits (`instances: "player"|"world"`), the tech gate and
`requires_wonder_any` are enforced at the SET_PRODUCTION queue and re-checked at
completion (a world-unique project finished second grants nothing). SDI feeds
`Nuclear.try_intercept` — one rng roll per strike at the best available chance among
an in-range anti-air unit and any target-side owner's `nuke_interception` effect. The
Internet's `tech_share` runs in the PLAYER_RESEARCH phase right after normal research
(`TurnEngine._apply_tech_share`, no RNG, techs scanned in data order). The §5.7
magnitudes above are live in `Nuclear.detonate` (`data/constants.json` `nuke_*`);
missiles are excluded in `Stack.get_defender` and destroyed by
`CombatApply.destroy_stranded_missiles`.

### 15.8 War weariness — reference event weights *(implemented 2026-07-17, C8)*

War fatigue accumulates weariness per *event kind* (the old two-constant
`war_fatigue_per_loss` model is replaced) and decays it in peace. Adopted weights,
re-confirmed against the reference XML:

| Event (your side) | WW points | constants.json key |
|---|---|---|
| your unit killed while attacking | 3 | `war_weariness_unit_killed_attacking` |
| your unit killed while defending | 2 | `war_weariness_unit_killed_defending` |
| your unit captured | 2 | *(unit capture is not a Humanish mechanic — no key)* |
| you kill a unit while attacking | 2 | `war_weariness_killed_unit_attacking` |
| you kill a unit while defending | 1 | `war_weariness_killed_unit_defending` |
| you capture a unit | 1 | *(unit capture is not a Humanish mechanic — no key)* |
| your city captured | 6 | `war_weariness_city_captured` |
| hit by nuke | 3 | `war_weariness_hit_by_nuke` |
| attacked with a nuke (aggressor penalty) | 12 | `war_weariness_attacked_with_nuke` |

Multiplier `BASE_WAR_WEARINESS_MULTIPLIER` 2 (`war_weariness_multiplier` — every
accrued weight is scaled by it); decay in peace: −1/turn and then keep 99% of the
total per turn (`war_weariness_decay_rate` −1, `war_weariness_decay_peace_percent`
99 — no decay while the war is still hot); a war you were forced into accrues at
−50% (`war_weariness_forced_modifier`, tracked per-alliance in
`Alliance.forced_wars`: set when war is declared on you, when a vassal is dragged
into its overlord's war, or when a nuclear first strike opens the war; cleared at
peace).

**As built:** every event routes through the single accruer
`CombatApply.accrue_war_fatigue(gs, side_pid, enemy_pid, key)` — unit deaths from
`CombatApply.apply_unit_result` (shared by the facade and WildAI combat paths),
city loss from `SimFacade._city_falls` (kept or razed), nuke events from
`Nuclear.detonate` (each victim accrues hit-by-nuke; the aggressor accrues
attacked-with-nuke per victim alliance). Wild forces (no player/alliance) never
accrue or cause accrual, and a side in a Golden Age is frozen (§14.4). The peace
decay runs once per `TurnEngine.world_step` (`_decay_war_fatigue`). Weariness
still converts to city anger through the unchanged `war_fatigue_anger_divisor`
(4) with the Police State `war_anger_reduction` civic cut (§8).

### 15.9 Worker-speed and improvement-upgrade civic effects

Implemented (2026-07-17, B7 + C6). Worker orders and cottage-line maturation honour
percentage modifiers, and Emancipation exerts diplomatic pressure:

- **Worker speed.** Every worker order that seeds `build_turns_left` (improvement,
  road, chop/clear — the three `SimFacade` handlers) runs through the single
  `TurnEngine.worker_build_turns` site: `turns × 100 / (100 + Σmod)`, truncating,
  never below 1. Sources of Σmod (all reference-confirmed): civics carrying
  `worker_speed_modifier` in `effects` (**Serfdom** +50, now gated on its reference
  tech **Feudalism**); the player's standing structures carrying
  `worker_speed_modifier` in `effects` (**Hagia Sophia** +50, per instance); the
  unit's `work_rate` key (default 100). The reference **Fast Worker's work rate is
  100** — its edge is movement, already modelled — so `work_rate` ships as pure
  mechanism with no shipped carrier above 100. The reference has **no golden-age
  worker effect**. The reference Steam Power tech (+50, which obsoletes Hagia
  Sophia) is *not* wired: structure obsolescence is unmodelled, and adding the tech
  source without it would double up — an open gap tied to obsolescence.
- **Emancipation** (tech Democracy): `improvement_upgrade_rate_modifier: 100` —
  the cottage-line `upgrade_turns` threshold becomes `turns × 100 / (100 + mod)`,
  truncating, min 1 (twice as fast at 100; replaces the old `faster_cottage_growth`
  flag), **plus** the emancipation-pressure anger via `civic_percent_anger: 400`
  (the reference `iCivicPercentAnger`): in the contentment phase every player *not*
  running a pressure civic takes `weight × adopters × 100 / (possible × 1000)`
  anger percentage points (`civic_percent_anger_divisor` 1000 = the reference
  `PERCENT_ANGER_DIVISOR`; truncating; no RNG), where `adopters`/`possible` count
  living rivals outside the player's own alliance — e.g. all rivals adopted →
  40% of population unhappy. Adopters are exempt. Read via
  `PolicyEffects.civic_pressure_anger`.
- **Slavery** additionally gained its reference tech gate (**Bronze Working**),
  closing the gap noted at C2.

### 15.10 Per-resource corporation outputs

Reference corporation output scales with the **number of input resource instances
accessible** to the city (each counted once per copy, all values ×1/100 per resource):
see `game-data.md` §29.6 for the full seven-corporation table (e.g. Sushi: +0.5 food and
+2 culture per seafood/rice resource; Ethanol and the aluminum corp **produce a
strategic resource** — Oil / Aluminum — instead of tile yields). Maintenance likewise
scales per resource consumed (reference `iMaintenance` 100 = 1 gpt per resource
instance per franchise, before modifiers), and the HQ earns the founder a flat +4 gold
per franchise.

Implemented (2026-07-17): `EconOrgs.accessible_resource_counts` counts a player's
accessible instances — one per owned connected tile (tech/improvement gated), one per
active recurring deal supplying the resource, and one per operating corporation with
`produces_resource` the player hosts (any member city, owner not banning corporations;
the grant also satisfies the §15.12 unit resource gate and feeds other corporations'
input counts). `EconOrgs.accessible_input_instances` sums those counts over an org's
`input_resources`; every per-city channel is then `output_per_resource[channel] ×
instances / 100` (×1/100 fixed integer math, truncating). Food/production fold into
the city yield (`get_output_delta`); culture accrues in `_settlement_culture`, research
in `_apply_research`, and gold in `gold_income` (all outside the commerce split, like
specialist channels) via `EconOrgs.settlement_channel`. `maintenance_for` charges
`maintenance_per_resource × instances / 100` per member city (Free Market's
`corporation_maintenance_reduction` still applies); `hq_gold_for` pays
`hq_gold_per_franchise` (4) per member city worldwide. All rates in
`data/econ_orgs.json` (§29.6 values, confirmed against the reference XML).

### 15.11 Settler & worker discovery-site rewards *(disabled)*

The reference grants settlers and workers from goody huts on the four easiest
difficulties (see the per-difficulty roster in `game-data.md` §29.7). The Humanish
`goodies.json` records exist but carry `weight: 0` (never selected) at every
difficulty. Parity: give the settler/worker records the per-difficulty weights from
§29.7 (they already exist as data; only the weights change — no engine work beyond
per-difficulty goody weighting, which §24 already supports).

### 15.12 Compound unit prerequisites

Reference units may require **several techs (all)** and **a fixed resource plus a
list of alternatives (any one)**: knight = Guilds + Horseback Riding, Horse **and**
Iron; maceman = Civil Service + Machinery, Copper **or** Iron; bomber = Flight **and**
Radio. Implemented: `tech_required` accepts a list (AND) and `resource_required` a
`{ "all": [...], "any": [...] }` dictionary (single-string forms remain valid), read
everywhere through the canonical `UnitPrereqs.tech_ok`/`resource_ok` (the resource
side checks `EconOrgs.accessible_resources` — connected tiles plus deal imports), with
`DataDB` validation; the audit-§2 per-unit prereq sets are applied. Enforcement note:
this also introduced the game's first *resource* gates (build/draft/upgrade/AI) —
`resource_required` was previously display-only, and upgrades had no prereq gate.
The remaining per-unit stat corrections are Phase-A retunes in
`directreferencegaps.md`.
