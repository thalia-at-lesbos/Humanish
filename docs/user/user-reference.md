# Humanish — User Reference

Complete reference for screens, mechanics, societies, and options.  
For a shorter introduction see [Quick Start](quick-start.md).

---

## Contents

1. [Screens and navigation](#1-screens-and-navigation)
2. [Economy rates](#2-economy-rates)
3. [Cities](#3-cities)
4. [Units](#4-units)
5. [Terrain and improvements](#5-terrain-and-improvements)
6. [Combat](#6-combat)
7. [Research](#7-research)
8. [Civics and policies](#8-civics-and-policies)
9. [Diplomacy](#9-diplomacy)
10. [Beliefs and economic organisations](#10-beliefs-and-economic-organisations)
11. [Great People](#11-great-people)
12. [Eras](#12-eras)
13. [Wild forces and raiders](#13-wild-forces-and-raiders)
14. [Save and load](#14-save-and-load)
15. [Multiplayer](#15-multiplayer)
16. [Map types](#16-map-types)
17. [World sizes](#17-world-sizes)
18. [Societies](#18-societies)
19. [Victory conditions](#19-victory-conditions)
20. [Keyboard reference](#20-keyboard-reference)

---

## 1. Screens and Navigation

### Main game controls

| Control | Opens |
|---------|-------|
| Left-click tile | Select unit / city on tile, or inspect empty/foreign tile |
| Right-click tile | Move selected unit(s) to tile, or attack enemy there |
| Click / drag minimap | Recenter the main map view on that location |
| **E** / **Enter** | End Turn |
| **F1** | Encyclopedia |
| **F2** | Technology tree (Tech Chooser) |
| **F3** | Policy / Civics screen |
| **F4** | Diplomacy screen |
| **Escape** | Pause menu |

### Advisor bar

The row of buttons along the top of the HUD. Each opens a full-screen info panel:

| Screen | Shortcut | Contents |
|--------|----------|---------|
| Encyclopedia | F1 | Game rules, unit/building/tech descriptions |
| Tech Tree | F2 | Research progress, available and future technologies |
| Civics | F3 | Active policies, available civic upgrades |
| Diplomacy | F4 | Relations with other players, trade and alliance options |
| Finance | — | Treasury breakdown: income, upkeep, net per turn |
| Military | — | All your units listed with status |
| Domestic Advisor | — | City-by-city summary: growth, production, disorder warnings |
| Espionage | — | Intelligence points and missions per rival; every rival civ and its cities with your passive intel (see §9) |
| Religion | — | Founded beliefs and spread status |
| Corporation | — | Founded economic organisations |
| Turn Log | — | Chronological record of events this game |
| Victory Progress | — | Current status of every active win condition |
| Options | — | Audio, graphics, and gameplay settings |

### Pause menu

Press **Escape** to open. Buttons: **Resume**, **Save**, **Load**, **New Game**, **Quit**.

---

## 2. Economy Rates

Your empire's commerce output (trade, city production, and population) is split four ways.
You adjust **three** rates with **+/−** buttons in 10% steps; **Economy** is read-only and
always equals 100 minus the other three:

| Rate | Funds |
|------|-------|
| **Science** | Research — progress toward the current technology |
| **Culture** | Cultural output — city border expansion, cultural victory |
| **Espionage** | Espionage points accumulated against rival alliances |
| **Economy** (derived) | Gold income — treasury per turn |

Adjust from the rate panel on the HUD. A **+** that would push the three rates over 100,
or a **−** that would drop a rate below 0 (or Science below a civic-imposed research
minimum), is disabled.

Entertainment buildings (Theatre, Colosseum, Broadcast Tower and their society-unique
variants) also grant **happiness scaling with your Culture rate** — a Theatre reads
"+1 happy per 10% culture rate", a Colosseum "+1 per 20%". A city sums its
entertainment buildings' values, multiplies by the Culture rate, and rounds down once.

Your expenses (unit upkeep, city maintenance, civic upkeep) are subject to
**inflation**: from a point in the game onward — later on slower paces, and reduced on
lower difficulties — total expenses grow by a percentage that rises every turn. The
Finance advisor shows the current inflation percentage in its breakdown.

---

## 3. Cities

### Founding

Select a **Settler** unit and use **Found City** (action button in the selection panel).
Good founding criteria:

- Grassland or plains tiles nearby for food and production.
- Adjacent to a river, coast, or oasis — gives the **fresh water** growth bonus.
- Resources that your current or near-future technologies can improve.
- Not too close to another city (border overlap wastes tile output).

### City Screen

Select a city and click **Open City** in the selection panel to open its detail screen.

**Production queue** — choose what to build: units, structures, or endgame projects.
One item builds at a time; the queue advances automatically.

**Worked tiles** — the city always works its own tile for free; each remaining citizen (population minus specialists, and minus any lost to disorder) works one more tile inside the city's current cultural border ring.
Click a tile to lock or unlock it. Locked tiles are always worked first.
**Automate Citizens** lets the game choose the remaining tiles, favouring food and production; with it off, only the city centre and your locked tiles are worked.
A citizen with no tile to work and no specialist post is never idle: it automatically becomes a **Citizen specialist**, worth +1 production (shown as "Citizens (auto)" in the Specialists section). Citizens flow back onto the land as soon as tiles or slots open up.

**Specialists** — assign citizens to specialist slots in built structures (e.g. scientist, engineer, merchant, artist).
Specialists generate Great Person points toward a Great Person of that type (see §10).
Settled Great People are **free** specialists: they sit on top of your population and never take a worker slot, so assigning a specialist only ever displaces an auto-filled Citizen or a tile worker.

**Rush production** — spend gold to instantly complete the current build queue item, available under every government.
The price is 3 gold per hammer still owed; an item queued this same turn costs 50% extra.
Unlike the whip, hurrying with gold causes no unhappiness.

**Hurry with population ("whipping")** — under the **Slavery** civic the city screen's *Hurry (Pop: N)* button sacrifices N citizens to finish the current item (each citizen is worth 30 hammers at Normal pace, scaled by game pace).
The whip never takes more citizens than the remaining cost requires and always leaves the city at least 1 population; an item queued this same turn costs 50% extra.
Each whip leaves one extra angry citizen in that city for 10 turns — and repeated whips stack.

**Obsolescence** — some structures stop working once you research a certain technology (the encyclopedia lists it as "Obsoleted by").
Walls and Castles stop defending at Rifling and Economics, Monasteries stop boosting science at Scientific Method, Hagia Sophia's worker bonus hands over to Steam Power's own +50%, and so on.
An obsolete building stays in the city (buildings are never sold and give no refund) — it simply no longer contributes its bonuses.

### Growth

Each turn a city accumulates **food surplus** (food output of worked tiles minus population upkeep).
When the food store reaches the growth threshold (scales with population and era), the city gains one population point.

**Settlers and Workers are built with food.** While a Settler or Worker heads the production queue, the city's food surplus is added to production toward it (on top of the normal hammers) and **growth pauses**: the stored food is kept but frozen, and the city cannot grow until the unit finishes. A starving city still loses food — and eventually population — even while training. The city screen's Growth line shows "paused — training" while this is in effect.

**Disorder**: if a city is in disorder (discontented citizens ≥ effective workers), its effective workers drop to zero — no production or food surplus.  
**Wellbeing deficit**: pollution and overcrowding reduce effective food income.
Terrain features on **worked** tiles also count toward city health, in fractions:
each worked Forest gives +0.5 health, a Jungle −0.25, Flood Plains −0.4 (Oasis +1
and Fallout −1 stay whole points). The fractions are summed and the net rounds
toward zero — two worked forests give +1 health, but one forest (or one jungle)
alone changes nothing.

### Culture and borders

Cities produce culture each turn. As culture accumulates the city climbs through six **culture levels** — Poor, Fledgling, Developing, Refined, Influential, Legendary — and each level pushes its border ring one tile further out, claiming territory. A tile's owner is the player with the highest accumulated cultural influence on that tile.

At Normal pace the levels are reached at 10 / 100 / 500 / 5,000 / 50,000 accumulated culture (half that at Quick; half again more at Epic; triple at Marathon). The city screen shows the city's current level next to its culture total.

**Culture defends the city.** From Fledgling up, the city's culture level grants an intrinsic defence bonus to its garrison — +20 % per level, up to +100 % at Legendary — on top of walls and other defensive structures. Enemy siege engines, warships and aircraft can **bombard** these cultural defences down before an assault (see Bombardment under Units), and they recover by 5 percentage points each turn.

---

## 4. Units

### Selection

- **Left-click** a tile containing your units to select them.  
  Clicking the same tile again cycles to the next unit if multiple are stacked.
- The **selection panel** (bottom of HUD) shows the selected unit(s), health, movement, and available actions. It also displays the underlying tile's terrain readout (terrain type, feature, resource, yields) for whatever you have selected — unit, city, or an inspected empty tile.
- On a tile with both units and your own city, clicking repeatedly cycles: units first (in order), then the city.

### Movement

- **Right-click** a destination tile to move the selected unit(s) there.
- Multi-turn journeys: if the path is longer than remaining movement, the destination is remembered and the unit resumes automatically on the next turn — you issue the order once.
- **N** jumps to the next idle unit.
- **Terrain movement cost**: flat tiles (grassland, plains, desert, tundra) cost one normal move; hills cost more, and forest or jungle features add further cost. Mountains are impassable to land units, and ice tiles cannot be entered.

### Sailing the ocean

Water tiles come in two kinds: **coast** (shallow water near land) and **ocean** (deep water). Naval units can always move along the coast, but entering deep ocean is gated:

- A ship must be **ocean-capable** — Work Boats, Galleys, and Triremes are coastal-only and cannot cross open ocean. The Caravel (Optics) is the first ocean-going ship; later naval units are all ocean-capable.
- Its owner must also have researched the **ocean-travel technology (Optics)**.
- The restriction is **waived inside friendly cultural waters** — your own territory, an alliance member's, or that of a civilization you hold an open-borders agreement with — so you can always sail through friendly coastal sea even before Optics.

This is why early exploration is hemmed in by your home coastline, and why map types with wide oceans stay isolated until Optics opens them up.

### Vision and line of sight

Each unit reveals the tiles around it within its sight range. Terrain shapes what you can see:

- A unit standing on **hills** sees **one tile farther** than normal.
- **Forest**, **jungle**, **hills**, and **mountains** **block line of sight** — you cannot see the tiles *beyond* such an obstacle from where you stand. Scout from open ground or high ground to see the most.
- Explored tiles stay dimly visible in memory even after your units leave; only tiles in a current unit's sight show live activity.

### Stacks

Multiple units can share a tile. **Right-click** a friendly unit tile to merge your selection into that stack.  
The **Select all** button in the selection panel selects every unit on the current tile.

### Actions

The selection panel shows available actions for the selected unit(s):

| Action | What it does |
|--------|-------------|
| Fortify | Unit entrenches on its tile, gaining a defence bonus each turn it stays |
| Sleep | Unit rests until you wake it; removes it from the idle-unit cycle |
| Found City | (Settler only) Found a city on the current tile |
| Build Improvement | (Worker) Build a farm, mine, road, etc. on the current tile (only improvements legal for that terrain are offered) |
| Spread Belief | (Missionary) Spread your religion to the faithless city the missionary stands in — the button appears only where the spread would succeed |
| Spread Corporation | (Executive) Open a franchise in the city the executive stands in; the button shows the gold cost (e.g. "Spread Cereal Mills (50 gold)") and appears only in an eligible city you can afford |
| Great Person actions | (Great Person) One button per ability the Great Person can use right now, in a second column beside the main buttons; labels preview the cost or effect (e.g. "Golden Age (2 GP)", "Trade Mission (+2000 gold)", "Build Academy"). Buttons act immediately — a consumed Great Person is spent on the spot |
| Disband | Remove the unit permanently |

### Bombardment

Siege engines (Catapult through Mobile Artillery), bombard-capable warships (Frigate through Missile Cruiser) and strike aircraft can attack at range with the bombard order (right-click the target as usual). Against an enemy **city whose cultural defences still stand**, the bombardment instead **knocks down the city's culture-level defence bonus** — each unit type removes a fixed number of percentage points per turn (e.g. Catapult 8, Trebuchet 16, Battleship 20). Once the cultural defence is flattened (it recovers 5 points per turn, so keep the pressure up), further bombard orders hit the garrison directly. Ground and naval units bombard from an adjacent tile; aircraft within their air range (enemy interceptors may shoot them down first).

### Air interception

Every air strike or air bombardment can be **intercepted** over its target tile. A defending **Fighter or Jet Fighter on Air Patrol** (issue the Air Patrol order and leave it unmoved) covers every tile within its air range; ground and naval anti-air — **SAM Infantry** and **Mobile SAM** (adjacent tiles and their own), plus **Machine Gun, Mechanized Infantry, and Destroyer** (their own tile) — stand watch automatically. Each interceptor can engage **once per turn**.

When a strike is contested, the attacker may **evade** first — the Stealth Bomber evades half of all interceptions, the Guided Missile nearly all, and the **Ace** promotion adds +25% — otherwise the single best interceptor rolls its interception chance: Fighters intercept at 100%, Mobile SAM 50%, SAM Infantry 40%, Destroyer 30%, Machine Gun and Mechanized Infantry 20%, raised by the **Interception I/II** promotions and reduced for a damaged air interceptor. On a hit the mission is **aborted — no damage reaches the target** — and a short air battle is fought: the attacker takes damage proportional to the interceptor's chance each losing round, an intercepting fighter takes return fire in kind, and a ground or naval interceptor engages without risk. One-use weapons (the Guided Missile) are expended even when shot down. Nuclear strikes are handled by the separate anti-air/SDI interception rules instead.

### Workers

Workers build tile improvements over multiple turns. Assign them to a tile via their action buttons,
or toggle **Automate** to let the AI handle improvement assignment for you.

The improvement buttons offered depend on the tile: only improvements legal for that terrain, feature, and resource appear (for example, a **Mine** is only buildable on hills, a **Farm** only on flat land). A Worker standing on a **city tile** shows **no** build or improvement actions — the city already works that tile. See [§5 Terrain and improvements](#5-terrain-and-improvements) for the full requirements.

---

## 5. Terrain and Improvements

### Terrain types

Every land tile has a base terrain that sets its movement cost and base yields (food / production / commerce). Tiles next to a river earn extra commerce.

| Terrain | Food | Prod | Commerce | Notes |
|---------|------|------|----------|-------|
| Grassland | 2 | 0 | 0 | +1 commerce next to a river |
| Plains | 1 | 1 | 0 | +1 commerce next to a river |
| Desert | 0 | 0 | 0 | +1 commerce next to a river; improvements take 25 % longer; mostly needs water |
| Tundra | 1 | 0 | 0 | +1 commerce next to a river; improvements take 25 % longer |
| Snow | 0 | 0 | 0 | No improvements possible |
| Hills | 1 | 1 | 0 | +25 % defence, +1 sight, blocks line of sight |
| Mountain | 0 | 0 | 0 | Impassable to land units and never worked by cities; +50 % defence; blocks line of sight |
| Coast | 1 | 0 | 2 | Shallow water; +10 % defence |
| Ocean | 1 | 0 | 1 | Deep water; entry restricted until Optics (see §4) |

### Features

Features sit on top of terrain and modify it:

| Feature | Effect |
|---------|--------|
| Forest | +1 production, +0.5 health to the working city, +50 % defence, blocks line of sight; chopping it gives production to the nearest city |
| Jungle | −1 food, −0.25 health to the working city, +50 % defence, blocks line of sight; usually cleared before improving |
| Flood Plains | +3 food (desert tiles by rivers); −0.4 health to the working city |
| Oasis | +3 food, +2 commerce, +1 health (desert only); cannot be improved |
| Fallout | Heavy yield penalty and −1 health from nuclear contamination; Workers can clean it |
| Ice | Impassable; no units or improvements |

### Improvements

Workers build improvements to boost a tile's yields. Each improvement requires a particular technology and is only legal on certain terrain (and some need a matching resource or a river). Build buttons appear only for the improvements that are valid on the tile under the Worker — and **never** when the Worker stands on a city tile.

| Improvement | Yield bonus | Terrain | Tech | Notes |
|-------------|-------------|---------|------|-------|
| Farm | +1 food | Flat land | Agriculture | |
| Mine | +1 production | **Hills only** | Mining | |
| Pasture | +1 food, +1 prod | Flat | Animal Husbandry | Needs a resource |
| Camp | +1 production | Flat or hills | Hunting | Needs a resource; keeps the feature |
| Plantation | +1 commerce | Flat or hills | Calendar | Needs a resource |
| Quarry | +1 production | Hills or flat | Masonry | Needs a resource |
| Winery | +1 commerce | Flat | Monarchy | Needs a resource |
| Cottage | +1 commerce | Flat | Pottery | Grows into Hamlet (+2) → Village (+3) → Town (+4 commerce) over time |
| Workshop | −1 food, +1 prod | Flat | Metal Casting | |
| Watermill | +1 food, +1 prod | Flat | The Wheel | Riverside tiles only |
| Windmill | +1 prod, +1 commerce | Hills | Machinery | |
| Lumbermill | +1 food, +1 prod | Flat or hills | Replaceable Parts | Needs a forest; keeps it |
| Forest Preserve | +1 food | Flat or hills | Scientific Method | Needs a forest; keeps it |
| Well | +1 production | Flat | Combustion | Needs a resource (oil) |
| Fort | — | Flat or hills | Mathematics | +50 % defence |
| Road | +1 commerce | Flat or hills | — | Speeds movement |
| Railroad | +1 production | Flat or hills | Railroad | Needs a road first |
| Fishing Boats | +1 food, +1 commerce | Coast | Fishing | Needs a sea resource |
| Whaling Boats | +1 commerce | Coast or ocean | Compass | Needs a sea resource |
| Offshore Platform | +2 prod, +1 commerce | Coast or ocean | Plastics | |

(Hamlet, Village, and Town are the upgrade stages a Cottage grows into on its own — you don't build them directly.)

---

## 6. Combat

### Initiating

**Right-click** an enemy unit's tile while you have a unit selected. The attacker moves toward the enemy and combat resolves automatically. Only one combat happens per move order.

### Resolution

Combat is turn-by-turn within a single resolution. Each round:

1. Both sides' **effective strength** is calculated: base strength, modified by promotions, terrain defence, fortification, and health.
2. Odds are calculated proportionally.
3. The RNG determines which side takes a hit each round and how much damage.
4. Combat ends when one side is destroyed, retreats, or hits a combat limit.

**First strikes** (some units) attack before the defender can respond in the opening rounds.

**Spillover damage** (siege units) deals partial damage to units behind the primary target.

**Flanking** (fast units) can hit multiple units in a stack.

### Capturing civilians

**Workers and Settlers are captured, not killed**, when your attack overruns their tile on open ground: the last defender falls, your attacker advances, and you receive a **fresh Worker** on the spot — a captured **Settler demotes to a Worker**. The captured unit arrives at full health with no experience or promotions and cannot move until your next turn. No capture happens when the civilian dies defending a city tile or to an air strike, and **wild raiders never capture** — a civilian they overrun simply dies.

### Experience and promotions

Surviving units gain XP from combat. At XP thresholds you can choose a **promotion** — a permanent combat bonus (strength vs. unit class, terrain bonus, first strike, etc.).

Newly trained military units can start with XP before their first battle: from training buildings (Barracks, Stable, Drydock, Airport, and their empire-wide counterparts), from civics such as Vassalage and Theocracy, and from **settled Great Generals** in the training city (+2 each). A **drafted** unit receives half the city's total starting XP, rounded down.

Open the **Military** advisor screen to review all your units and their promotion eligibility.

### War fatigue

Prolonged war accumulates **war fatigue** on both alliances, increasing unhappiness in your cities. Every combat event adds fatigue: losing a unit hurts most while attacking, less while defending; even killing enemy units adds a little; having a civilian captured hurts like a defensive loss (capturing one adds a little); losing a city adds the most; nuclear strikes add heavy fatigue — far more for the side that launched them. A war that was declared **on** you accrues fatigue at half rate, and none accrues during a Golden Age. Once fighting stops, fatigue decays a little each turn.

---

## 7. Research

### Tech Tree

Open with **F2**. Technologies are arranged in a prerequisite graph by era: Ancient → Classical → Medieval → Renaissance → Industrial → Modern → Future.

A technology becomes researchable when you know **all** of its required prerequisites and — where it lists alternatives — **at least one** of them. The tech tree and encyclopedia show these as "Requires (all)" and "Requires (any)".

Researching a technology unlocks units, structures, improvements, and game mechanics.

### Cost

Research cost scales with:
- **Pace setting** — slower pace multiplies costs.
- **World size** — larger worlds raise research costs (Duel 100 % up to Huge 150 % of the base cost).
- **Known prerequisites** — each prereq you already own gives a 10 % discount.
- **Other players who know it** — each other known researcher gives a 5 % discount (capped at 25 %).

### Funding

The **Science** rate determines what fraction of your total commerce goes to research each turn. Progress is shown in the Research bar at the top of the screen.

### Eras

Advancing to a new era happens automatically when you research a technology tagged to that era — no separate gate. You receive a notification on the turn it happens.

---

## 8. Civics and Policies

### Overview

Open the **Civics screen** with **F3**. Policies are organised into five categories (e.g. government, economy, military, religion, society). Within each category you can adopt one policy at a time; switching costs a transition-turn period of anarchy.

### Effects

Each policy carries passive effects that apply every turn — modifiers to:
- Commerce and treasury
- Unit upkeep (free units, distance costs)
- Research and science
- Happiness and health
- Production bonuses for certain build types
- Specialist and Great Person generation rates
- Combat bonuses
- Worker build speed and cottage growth rates (e.g. **Serfdom** speeds every
  worker order by 50%; **Emancipation** doubles how fast cottages mature)

Some policies require a technology before they can be adopted (e.g. **Slavery**
needs Bronze Working, **Serfdom** needs Feudalism) — the Civics screen and the
Encyclopedia show each requirement. Beware **Emancipation** pressure: once rival
civilizations adopt Emancipation, every empire *not* running it suffers growing
unhappiness in its cities, scaling with how many rivals have adopted it.

The Civics screen shows the description and known effects of every policy.

### Transition

When you switch policies in a category, your empire enters **anarchy** for a number of turns (set by the policy and scaled by game pace — shorter at Quick, longer at Epic, always at least one turn). During anarchy no research, culture, or production accumulates. Plan switches carefully.

---

## 9. Diplomacy

Open with **F4**. You see each rival player's stance toward you and available diplomatic options:

- **Declare war / make peace** — at the alliance level; all members of an alliance are at war together.
- **Open borders** — a signable agreement that lets each side's units enter the other's cultural borders. You must have researched **Writing** to propose it. Without an open-borders agreement (and without being at war or allied), your units are blocked at a rival's borders. Either side can close their borders again, and declaring war immediately ends the agreement — at war you may invade regardless.
- **Trade** — exchange gold, resources, or technologies (trade must benefit both sides).
- **Alliance** — form a military alliance; you share research and stand together in war.
- **Subjugation** — offer or accept subordination, making one alliance a client state.

Your relationship deteriorates from aggression (war, betrayal of agreements) and improves over time with peace and shared borders.

The **Apostolic Palace** and later the **United Nations** wonders found world assemblies that hold resident elections and vote on resolutions. The **Diplomatic** victory (winning the World Leader election) is described in the Encyclopedia but is not enabled in the current version (see §19).

### Espionage

Your **Espionage** rate (and buildings such as the Jail or Intelligence Agency) accumulates **espionage points (EP)** against each rival alliance. Spend them on the **Espionage advisor** or through a **Spy** unit:

- **Active missions** — steal technology or gold, sabotage production, destroy buildings, projects, or improvements, poison water, insert culture, incite unhappiness or revolt, force a civic or religion switch, or mount counterespionage. Run them from the advisor's "Select Mission…" menu, or march a Spy onto a rival city and strike that specific city. Each mission costs EP and risks **interception** — and a Spy caught in the act is lost.
- **Passive intelligence** — costs nothing to use: while your banked EP against a rival stays above a threshold (higher for distant targets and rivals who out-spy you), the advisor shows their **demographics**, **current research**, full **city details** (Investigate City), extra **map vision** around a city (City Visibility), or **who is behind** espionage strikes against you (Detect Missions). Drop below the threshold and the intel goes dark again.
- **What you see without intel** — a rival city's readout shows only its defenses: defense bonus, HP, garrison, and defensive buildings. Population and production stay hidden until investigated.
- **Spies are invisible.** Only you see your own spies; they cross closed borders freely, can stand in any city, and cannot be attacked.

---

## 10. Beliefs and Economic Organisations

### Beliefs (religions)

The first player to research a belief's founding technology founds it; a Great Prophet's Found Religion action also works (and ignores the technology requirement).
Once founded it can **spread** to other cities — passively over time, or actively via a Missionary unit.
Adopting a **state religion** (in your Civics) gives passive bonuses; changing it triggers anarchy.

### Economic Organisations

Founded by a Great Merchant or specific Great Person action. Organisations provide per-city economic bonuses, but **unlike beliefs they never spread on their own** — they reach a new city only via an **Executive** unit (unlocked by the Corporation technology). Move the executive onto the target city and press its **Spread** button in the selection panel (it shows the gold cost): the executive is consumed and the corporation opens a franchise there.

Spreading costs gold: a **base of 50**, scaled up by your current **inflation** rate, and **doubled** when the target city belongs to another player (a vassal of yours counts as domestic). The target city must have access to at least one of the organisation's **input resources**, the organisation must not be banned for the city's owner (see the civic bans below), and a city can host only **one** organisation — an incumbent blocks any newcomer. Spreading into an eligible (empty) city always succeeds.

Two civics ban corporations. **State Property** bans them all; **Mercantilism** bans only corporations whose **headquarters city you do not own** — your own-HQ corporation keeps operating, and the ownership test is strict (an ally's or even your vassal's headquarters still counts as foreign). A banned corporation's franchises are not removed: they go **dormant** — no yields, no maintenance, no provided resource, and no headquarters gold for the founder — and resume automatically when the civic changes. An executive cannot spread a corporation into a city where it would be dormant.

Each organisation consumes a set of **input resources**: its per-city output (food, production, gold, research, or culture) scales with how many copies of those resources you can access — every connected tile and every trade-deal import counts. Some organisations also **provide a strategic resource** (Standard Ethanol supplies Oil; Aluminum Co. supplies Aluminum) to any player hosting them. Maintaining an organisation costs treasury each turn, also scaling with the resources consumed; the founder's headquarters earns gold for every member city worldwide.

---

## 11. Great People

Specialists in your cities generate **Great Person points** each turn. Each city banks its own pool of points; when a city's pool crosses the current threshold a Great Person is born there (the pool keeps any excess). The threshold is **empire-wide**: it starts at 100 points (scaled by game pace — Quick 67, Epic 150, Marathon 300) and every Great Person born anywhere in your civilization raises it by 100 for all your cities (100, 200, 300, …; the increase itself doubles from your 10th Great Person on, and births by an allied player raise your threshold by half as much). Great Generals come from a separate combat counter and do not raise this threshold.

| Type | Generated by | Notable actions |
|------|-------------|----------------|
| Great Scientist | Scientist specialists | Discover a technology instantly, build an Academy |
| Great Engineer | Engineer specialists | Hurry production, build the Ironworks |
| Great Merchant | Merchant specialists | Trade mission (instant gold), found an economic organisation |
| Great Artist | Artist specialists | Great Work (instant culture) |
| Great Prophet | Priest specialists | Found a religion, build its shrine |
| Great Spy | Spy specialists | Infiltration (a large windfall of espionage points) |
| Great General | Combat experience (all units) | Attach to a unit as a leader, build the Military Academy |

The **Military Academy** (+25% military-unit production in its city) can **only** be raised by a Great General — it never appears in a city's normal build list.

Every Great Person can also permanently **join a city** as a super-specialist, and most types can **start a Golden Age**. Use a Great Person's action from the selection panel when the unit is on a suitable tile. A settled Great Person is a **free** specialist — it does not consume a population slot, so its yields come on top of everything your citizens do. The settled **Great General** is special: it yields nothing directly but serves as a **military instructor** — every combat-capable unit trained in its city starts with **+2 experience** per settled General, stacking with barracks-style building XP.

### Golden Age

Certain Great Person actions (and accumulating a set number of them) trigger a **Golden Age** — a set number of turns (8 at Normal pace; 6 at Quick, 10 at Epic) where all worked tiles produce extra output. War weariness is frozen during a Golden Age.

---

## 12. Eras

| Era | Unlocks (examples) |
|-----|--------------------|
| Ancient | Settlers, Warriors, basic improvements |
| Classical | Swordsmen, Catapults, Libraries, Aqueducts |
| Medieval | Knights, Castles, Universities |
| Renaissance | Cannons, Caravels, Printing Press |
| Industrial | Rifles, Factories, Steam power |
| Modern | Infantry, Tanks, Flight, Computers |
| Future | Advanced units, Space Race projects |

Entering a new era produces a notification and may unlock new build options immediately.

---

## 13. Wild Forces and Raiders

Unclaimed territory spawns **raiders** — AI-controlled units (owner: Wild Forces) that wander and attack cities and units they encounter. They are not controlled by any player.

Raiders are a persistent early-game threat. Garrison your cities with at least one warrior unit and keep a mobile force nearby to respond. At higher difficulties, raiders have early free combat wins against them removed — meaning they are more dangerous in the opening turns.

The **Aggressive raiders** option at game setup lengthens raider waves and shortens the lulls between them.

---

## 14. Save and Load

| Method | How |
|--------|-----|
| Quick Save | **F5** — overwrites `quicksave.sav` immediately |
| Quick Load | **F9** — restores the last quick save immediately |
| Named save | **Escape → Save** — pick a slot or name a new one |
| Load from pause | **Escape → Load** — browse saved games |
| Load from title | Title screen → **Load Game** |

Save files are stored under your user data path (see Quick Start for platform-specific paths). The title-screen **Load Game** list scrolls, so all your saves remain reachable even when you have accumulated a long list.

---

## 15. Multiplayer

### Joining a game

1. Title screen → **Multiplayer**.
2. Enter the server's host address and port (default 9080).
3. Enter your player name and click **Connect**.

The server assigns you to the next free player slot. When it is your turn you receive the current game state, play your moves, and click **End Turn** to submit.

### Hosting in-game

1. Title screen → **Multiplayer Server**.
2. Set port, player count, AI slots, and a save-file path.
3. Choose **New Game** (runs through the normal setup) or **Load** a save.
4. Click **Start**. The screen shows connected players and the current turn; click **Stop** to close.

### Headless server

For always-on hosting without a GUI, run from a terminal:

```bash
./run_server.sh --save=game.sav --players=3 --ai=1 --port=9080
```

| Flag | Meaning |
|------|---------|
| `--save=<file>` | Save-file path (required). Autosaves every turn. |
| `--players=<n>` | Total player count including AI (default 2). |
| `--ai=<n>` | How many of those players the server plays itself (default 0). |
| `--port=<n>` | TCP port to listen on (default 9080). |
| `--name=<str>` | Server name shown to joining clients. |
| `--load=<file>` | Resume from a saved game instead of starting new. |
| `--new` | Start a fresh game (the default when `--load` is absent). |
| `--world=<size>` | World size ID (duel/tiny/small/standard/large/huge; default tiny). |
| `--map=<type>` | Map type ID (continents/pangaea/etc.; default continents). |
| `--pace=<id>` | Pace ID (quick/normal/epic/marathon; default normal). |
| `--difficulty=<id>` | Difficulty ID (default warlord). |
| `--seed=<n>` | RNG seed (random when omitted). |

The server autosaves after every turn (human or AI). If interrupted it can be resumed with `--load`.

---

## 16. Map Types

The map type sets the overall shape of the world. Each new game generates a fresh map at random, so even the same map type and settings produce a different layout every time you start a game.

| Map | Description |
|-----|-------------|
| **Continents** | Two major continents with a chance of a smaller third; a blend of land war and naval logistics. Recommended for new players. |
| **Pangaea** | One massive interconnected landmass; every civilization shares the same continent, emphasising early land warfare. |
| **Archipelago** | A world of small islands; exploration and tech crawl until naval units arrive. |
| **Terra** | Every player begins on an isolated Old World; a massive, raider-infested New World waits across the ocean. |
| **Hemispheres** | The map splits into two large, roughly equal landmasses. |
| **Big and Small** | One large main continent with scattered smaller islands. |
| **Medium and Small** | A smaller primary landmass surrounded by islands, favouring naval empires. |
| **Fractal** | Unpredictable, highly varied landmasses with no rigid continent structure. |
| **Tectonics** | Simulated plate tectonics — natural mountain ranges along plate boundaries, dynamic coastlines. |
| **Great Plains** | Predominantly flat, resource-rich land that encourages rapid expansion. |
| **Highlands** | Densely mountainous; empires form around bottlenecks and chokepoints. |
| **Ice Age** | Massive polar caps leave only a narrow, tundra-heavy band for colonisation. |
| **Inland Sea** | A ring of land surrounds a massive central sea; most empires share tight borders. |
| **Lakes** | A landmass fractured by many small lakes; abundant fresh water, limited naval play. |
| **Oasis** | A fertile, forest-heavy rim around a central desert dotted with resource-rich oases. |
| **Tilted Axis** | World axis is tilted — climate bands run vertically instead of horizontally. |
| **Shuffle** | Secretly picks one of Archipelago, Continents, Fractal, or Pangaea at random. |

---

## 17. World Sizes

| Size | Tiles | Research cost | Notes |
|------|-------|---------------|-------|
| Duel | 40 × 24 | 100 % | 2 players suggested; fast games |
| Tiny | 52 × 32 | 110 % | 3 players suggested |
| Small | 64 × 40 | 120 % | 5 players suggested |
| Standard | 84 × 52 | 130 % | 7 players suggested; default |
| Large | 104 × 64 | 140 % | 9 players suggested; longer games |
| Huge | 128 × 80 | 150 % | 11 players suggested; very long games |

The player-count spinner at setup follows the chosen world size's suggestion but can be set to anything from 2 to 16.

---

## 18. Societies

Each society's leader carries traits that provide passive combat, growth, or economic bonuses. Traits stack with civics and other bonuses. Societies with more than one historical leader let you pick one at setup (the first listed is the default); the chosen leader determines the traits.

| Society | Leader(s) | Character |
|---------|-----------|-----------|
| American | Washington, Roosevelt, Lincoln | Young expansive republic of pioneers and industry |
| Arabian | Saladin | Desert faithful with camel riders and scholars |
| Aztec | Montezuma | Sun-worshipping warriors who feed the gods with conquest |
| Babylonian | Hammurabi | Lawgivers of Mesopotamia whose armies march in strict order |
| Byzantine | Justinian I | Heirs of Rome whose cataphracts guard a holy empire |
| Carthaginian | Hannibal | Sea-trading financiers who muster mercenary cavalry |
| Celtic | Brennus, Boudica | Forest tribes whose guerrilla warriors need no iron |
| Chinese | Qin Shi Huang, Mao Zedong | Industrious dynasty of wonder-builders and crossbowmen |
| Dutch | Willem van Oranje | Merchant seafarers who reclaim land from the waves |
| Egyptian | Hatshepsut, Ramesses II | Builders of the Nile whose chariots need no horse |
| English | Elizabeth, Victoria, Churchill | Financial island power of redcoats and exchanges |
| Ethiopian | Zara Yaqob | Highland defenders whose drilled musketeers hold the passes |
| French | Louis XIV, Napoleon, De Gaulle | Creative artisans whose salons and musketeers shine |
| German | Bismarck, Frederick | Industrial engineers whose panzers race across the field |
| Greek | Alexander, Pericles | Philosopher-warriors whose phalanx anchors the line |
| Holy Roman | Charlemagne | Pious imperium of landsknechts and free cities |
| Incan | Huayna Capac | Mountain financiers whose quechua scouts the high passes |
| Indian | Gandhi, Asoka | Spiritual civilization of fast workers and great souls |
| Japanese | Tokugawa | Disciplined samurai who fight on at any wound |
| Khmer | Suryavarman II | Temple-builders whose ballista elephants storm cities |
| Korean | Wang Kon | Scholarly defenders whose hwacha rain fire on attackers |
| Malinese | Mansa Musa | Gold-rich traders whose skirmishers need no bow training |
| Mayan | Pacal II | Astronomer-kings whose holkan guard the jungle cities |
| Mongolian | Genghis Khan, Kublai Khan | Horse-lords whose keshiks ride faster than any foe |
| Native American | Sitting Bull | Plains nations whose dog soldiers need neither copper nor iron |
| Ottoman | Mehmed II, Suleiman | Gunpowder empire whose janissaries heal from every kill |
| Persian | Cyrus, Darius I | Imperial heartland whose immortals never falter |
| Portuguese | Joao II | Explorers whose carracks chart trade routes across oceans |
| Roman | Julius Caesar, Augustus Caesar | Disciplined legions whose praetorians outmatch any sword |
| Russian | Catherine, Peter, Stalin | Vast creative empire whose cossacks charge at full strength |
| Spanish | Isabella | Zealous conquistadors who found cities far from home |
| Sumerian | Gilgamesh | First cities, whose vultures and ziggurats herald civilization |
| Viking | Ragnar | Raiders whose berserkers storm ashore and strike twice |
| Zulu | Shaka | Fast-mustering impis who flank and overrun the enemy |

See the **Encyclopedia** (F1) for each society's specific trait bonuses.

---

## 19. Victory Conditions

Every game is played with the same **five active conditions**: Conquest, Domination, Cultural, Score, and Time. A game ends immediately when any alliance achieves one of them. Track progress in the **Victory Progress** screen.

### Conquest

Eliminate every other alliance — no enemy settlements or units may remain on the map.

### Domination

Hold at least **66 %** of all land tiles *and* **66 %** of total population simultaneously.

### Cultural

Bring **three** of your cities to **Legendary culture** (**50,000** culture points accumulated in each city at Normal pace — the requirement scales with game pace: 25,000 at Quick, 75,000 at Epic, 150,000 at Marathon). The three cities can be any combination; they do not need to reach Legendary simultaneously.

### Score

The first alliance whose summed score reaches **400** wins immediately.

Score is a weighted sum: your share of land tiles (as a percentage), plus your share of total population (as a percentage), plus 2 points per technology researched and 5 points per wonder built.

### Time

When the turn limit is reached (330 / 500 / 750 turns at Quick / Normal / Epic pace), the alliance with the **highest score** wins.

### Not currently enabled

Two further conditions are described in the Encyclopedia but are not enabled at game setup in the current version:

- **Space Race** — after building the **Apollo Program** wonder, construct the spaceship's parts: 5 SS Casings, 5 SS Thrusters, 2 SS Engines, and one each of SS Cockpit, SS Life Support, SS Stasis Chamber, and SS Docking Bay (building extras of a finished part type is wasted). One of **every** part type launches the ship; it then travels for 10 turns (scaled by game pace, longer if optional engines/thrusters are missing) and arrives safely if you built enough casings (−20% success per missing casing — a failed arrival loses the launch, but the parts survive for a relaunch). Losing your capital destroys a spaceship in flight.
- **Diplomatic** — win the World Leader election in a world assembly (United Nations: 60 % of the weighted vote; Apostolic Palace: 75 %).

---

## 20. Keyboard Reference

| Key | Action |
|-----|--------|
| **E** / **Enter** | End Turn |
| **N** | Next idle unit |
| **B** | Next idle worker |
| **C** | Centre camera on selection |
| **F1** | Encyclopedia |
| **F2** | Technology tree |
| **F3** | Policy / Civics screen |
| **F4** | Diplomacy screen |
| **F5** | Quick Save |
| **F9** | Quick Load |
| **Escape** | Pause menu (Resume / Save / Load / New Game / Quit) |
