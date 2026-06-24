# Event subsystem — planning & catalogue

**Status:** in progress. The selection **framework** and a representative **vertical
slice** of events are built and tested (branch `feat/event-subsystem-rework`). This
document is the shared memory for *filling out the rest*: it catalogues all **174
events + 18 quests** from the reference ruleset, records which engine mechanics each
needs, and lays out the roadmap. It is collaborative planning (per `CLAUDE.md`) —
edit freely.

Design intent for the framework itself lives in `docs/design/game-rules.md` §9 and
the `data/events.json` schema comment; this doc is the downstream worklist.

---

## 1. What is built (this branch)

### 1.1 Selection framework (complete)
- **Grace period**: no event fires before `event_grace_turns` (20), a flat count
  **not** scaled by game pace.
- **Per-era chance**: one roll per player per turn at `event_era_chance[era]` =
  `[1,2,4,4,6,8,10]` % (Ancient→Future) decides whether *any* event fires.
- **Per-game roster**: at setup, each event's `active`% is rolled once (in sorted id
  order, from `gs.rng`) into `GameState.active_event_ids` (serialized). Only rostered
  events can occur this game.
- **Weighted pick**: among eligible events, one is drawn weighted by `weight`.
- **Eligibility** (`Events.event_eligible`): in roster · all `prereq` hold · holds no
  `obsolete` tech · not a still-running timed instance · one_shot unfired.
- **Mandatory choices**: a human cannot End Turn while an event decision is pending
  (facade gate in `_cmd_end_turn`).
- **Deterministic outcomes**: random magnitudes (`range`) and probabilistic branches
  (`chance`) are rolled **once at fire time** in fixed order and baked into the begin
  effects / parked choice branches, so applying a resolved choice draws no RNG.

### 1.2 Prereq predicate vocabulary (built)
`tech_all` · `tech_any` · `building` · `civic` · `state_religion` · `resource_absent`
· `min_pop` · `max_pop` · `min_era` · `max_era` · `at_war` · `at_peace` · `coastal` ·
`players_tech {tech,count}` · `tile {terrain,feature,improvement,resource,route,in_city_radius}`.

### 1.3 Effect verbs (built)
`gold` (incl. `range`) · `research` · `research_pct_remaining` · `research_pct_loss` ·
`culture` · `tech` · `unit` · `building` · `capital_health` · `capital_pop` ·
`nearby_pop` · `heal_units` · `food_store` · `golden_age` · `attitude` (diplo memory)
· `grant_promotion` (by classification/domain/unit_types) · `city_happy_timed`
(scope capital/all/all_state_religion) · `place_resource` (+remove_feature/
add_improvement/add_route) · `tile_yield` · `remove_feature` · `remove_improvement` ·
`remove_route` · `spawn_wild` · `chance` (roller).

### 1.4 Supporting mechanics added to the engine
- `Tile.event_food/event_production/event_commerce` — permanent per-tile yield deltas
  folded into `TileOutput.compute` (serialized when nonzero).
- `Settlement.timed_happiness` — list of `{amount,turns_left}` ticked in
  `TurnEngine._tick_states`, folded into `_update_contentment` (positive → happy
  face, negative → flat angry citizen). Serialized.
- `GameState.active_event_ids` — per-game roster. Serialized.
- `pending_event_choices[].resolved_choices` — pre-rolled branches. Serialized.
- `GreatPeople.start_free_golden_age` — grant a free Golden Age.
- diplomacy.json `memory_kind "event"` — channel for event attitude deltas.

### 1.5 Shipped slice events (15)
`forest_fire` · `motherload` · `washed_out` · `breakthrough` · `setback` · `faux_pas`
· `bowyer` · `spicy` · `truffles` · `marathon` · `earth_day` · `gold_rush` ·
`security_tax` · `the_huns` · `dust_bowl`. Each exercises at least one framework
feature and one supporting mechanic; all covered by `tests/sim/test_events.gd`.

---

## 2. Subsystems still required (gap list)

These are the mechanics the remaining events/quests depend on that the engine does
**not** yet model. Grouped by rough size; each is a prerequisite for the events
tagged with its code in §3/§4.

| Code | Subsystem | Notes / size |
|------|-----------|--------------|
| **STRUCT_YIELD** | Persistent per-structure yield/culture/happy/research bonus ("+1 production for the city's forge", "+2 culture for the colosseum") | New per-settlement `structure_bonuses` map folded into the relevant output/contentment sites. Medium. Unblocks ~25 events. |
| **ESP** | Espionage-point grants/losses vs a specific player | `Player.intel_points` exists (alliance-scoped); needs a per-rival grant/drain. Small–medium. |
| **SPREAD** | Spread a religion to N own/foreign cities | Religion presence model exists (`belief_id`); needs a multi-city spread op honouring "≤1 other religion" filters. Medium. |
| **SPEC** | Grant a free specialist (artist/scientist/engineer/priest/merchant) in a city | `Settlement.specialists` exists; add an increment op. Small. |
| **SGP** | Settle a free Great Person (general/prophet/merchant/artist/scientist/spy) in a city | GP model exists (`great_people.gd`); needs a "settled GP" representation. Medium. |
| **HEALTH_TIMED** | Timed city *health* faces (wellbeing), like `city_happy_timed` but on wellbeing | Mirror of timed happiness on `wellbeing_*`. Small. |
| **REVOLT** | Put a city into N turns of revolt/disorder | `Settlement.revolt_turns` / `in_disorder` exist; add a setter verb. Small. |
| **DESTROY_BLDG** | Destroy 1..N buildings in a city (cheap/expensive split, by hammer cost) | Remove from `Settlement.structures` by cost filter. Small–medium. |
| **PILLAGE** | Pillage N tile improvements (own or a rival's near a city) | Clear `improvement_id` on N matching tiles. Small. |
| **REVEAL** | Reveal a hidden strategic resource on a tile (oil/uranium/copper), optionally with improvement+route | Extends `place_resource` with eligibility ("tile can have X", "not revealed"). Small. |
| **DRAFT** | Conscript/draft units (count scaled by city culture level) | Spawn units + draft-anger. Medium. |
| **PEACE/WAR** | Force peace (with attitude bump) / offer-or-declare war | Alliance war-state ops exist; wrap as verbs. Medium. |
| **AI_CIVIC** | Make some AI players switch a civic | AI policy model exists; add a nudge op. Small. |
| **INFLATION** | Inflation modifier (±%) | No inflation model yet. Medium (needs the economic field first). |
| **UNIT_SUPPORT** | Free unit-support / upkeep relief for N turns/units | No unit-support cost model surfaced. Medium. |
| **UNIT_STATE** | Per-unit timed states: immobile N turns, cannot-attack N turns, +XP | `Unit` flags + tick. Small. |
| **HAPPY_RES_COUNT** (prereq) | "4 or fewer happy resources" gate | Count distinct happiness resources the player controls. Small. |
| **CAN_HAVE_RES** (prereq) | "tile can have resource X" gate | Resource→terrain/feature eligibility table. Small. |
| **CIV_ID** (prereq) | "player is Aztec/Egyptian/Russian/French/American" | Map onto `society_id`/`leader_id`. Small. |
| **HOLY_CITY / SHRINE / WONDER** (prereq) | Holy-city ownership, shrine, named wonder control | Religion + wonder ownership queries. Medium. |
| **CORP** | Corporation HQ ownership, spread, resource-set coverage | `econ_orgs` exists; Quests 17/18 + Great Depression need HQ/share ops. Medium. |
| **MOVIE / EP_BONUS / SPACE** | Misc reference counters (movie bonus, espionage-from-building, spaceship-production %) | Niche; model per-event as needed. Small each. |
| **ROUTE_SPEED** | Global route-movement bonus (Interstate) | Movement-cost modifier. Medium. |
| **QUEST** | Multi-turn quest progress tracking + completion rewards | See §4. Large — its own branch. |

---

## 3. Full event catalogue (1–174)

Legend — **A/W** = Active%/Weight. **Needs**: ✓ = buildable with shipped verbs/prereqs;
otherwise the gap code(s) from §2. **slice** = shipped this branch.

> Magnitudes below are the reference's *normal/standard* values. Map-size and
> game-speed scaling (§5) is deferred — port the standard numbers as fixed data.

### Events 1–40
| # | Name | Prereq (summary) | Obsolete | A/W | Result (summary) | Needs |
|---|------|------------------|----------|-----|------------------|-------|
|1|Forest Fire|forest in city radius|—|70/100|pay 10 / pay 4 + lose forest / lose forest + angry|**slice**|
|2|City Ruins|own city-ruins feature|radio/refrig/plastics/satellites/adv-flight/ecology|90/1000|15% tech / +gold for chance of more|RPCT✓, CHANCE✓, +ruins feature|
|3|Happy Hunting|tundra forest + archery|steam/steel/sci-method/artillery|90/500|+8 food in city store|FOOD✓|
|4|Motherload|gold mine + road + early tech|—|90/200|20–40 gold|**slice**|
|5|Washed Out|road/rail|—|80/100|lose a road / pay 20|**slice**|
|6|At the Sword|1 damaged swordsman|machinery/feud/music/phil/civil/theo|100/500|+3 XP to that swordsman|UNIT_STATE(XP)|
|7|Man named Jed|scout/explorer + unrevealed oil under unit|—|75/5000|nothing / pay 10 reveal oil|REVEAL|
|8|Inspired Mission|city w/ 2 religions incl. state|—|75/200|spread state religion 4/+1/+4 own & foreign|SPREAD|
|9|Hymns & Sculptures|cathedral + 10 cathedrals globally|—|20/200|free Artist specialist|SPEC|
|10|Careless Apprentice|forge|radio/refrig/…|75/200|pay 50 / pay 10 lose forge / lose forge + angry|DESTROY_BLDG, TH✓|
|11|Famine|—|—|70/100|nothing / -50% food + attitude / pay + -100% food + attitude|FOOD✓, ATT✓|
|12|Slave Revolt|slavery + pop≥4 + early tech|—|80/500|angry + -pop + revolt + chains|REVOLT, POP✓, CHANCE✓|
|13|Blessed Sea|*(quest)*|—|—|see Quest 1|QUEST|
|14|Airliner Crash|border + other has flight|—|70/300|+att / +1000 EP / +tech% -att|ESP, ATT✓, RPCT✓|
|15|Farm Bandits|farmed wheat/rice/corn + road + unit|—|85/200|pay 10 / -5 food + unit can't attack / -5 food|FOOD✓, UNIT_STATE, CHANCE✓|
|16|Holy Mountain|*(quest)*|—|—|see Quest 2|QUEST|
|17|Horticulture|forest/jungle + calendar|—|80/200|+1 commerce tile / pay + chance / +health + scientist|TY✓, CHANCE✓, HEALTH_TIMED, SPEC|
|18|Fugitive|feudalism|—|90/200|±attitude chains|ATT✓, ESP, CHANCE✓|
|19|Pestilence 1/2|pasture/plantation tile|—|55/100,100/100|destroy tile improvement|RMI✓|
|20|Marathon|at war, enemy first-strike|—|100/800|free Golden Age|**slice** (prereq simplified to at_war)|
|21|Faux Pas|—|—|70/100|-1 attitude with an AI|**slice**|
|22|Joyous Wedding|same state religion as neighbour|—|90/200|nothing / pay + att / pay + att|ATT✓|
|23|Wedding Feud|different state religion neighbour|—|90/200|-att / pay -att +happy / pay -att +att war-offer|ATT✓, TH✓, WAR|
|24|Left at the Altar|share borders w/ AI|—|80/100|-1 attitude|ATT✓|
|25|Spicy|forest + calendar + ≤4 happy res + no spices|—|50/100|gain Spices / cultivate (plantation+road)|**slice** (happy-res prereq dropped)|
|26|Tornado|plains improvement + early tech|—|75/200|improvement destroyed|RMI✓|
|27|Baby Boom|signed a peace treaty|—|100/500|all cities +10 food store|FOOD✓ (all-city)|
|28|Bard's Tale|music|—|90/200|+100 / pay +450 / radio: pay +250 all|culture✓, STRUCT_YIELD?|
|29|Looters|angry citizen in neighbour AI city|—|70/100|pillage 1 / pay pillage 2-4 / -EP pillage + destroy bldg / -att|PILLAGE, ESP, DESTROY_BLDG, ATT✓|
|30|Brothers in Need|same religion + tradeable spare resource + AI at war|—|100/1000|gift Copper/Iron/Horse/Ivory/Oil/Uranium|resource-gift op|
|31|Hurricane|coastal + early tech + pop>2|—|75/100|destroy cheap+expensive bldg / -1 pop|DESTROY_BLDG, POP✓|
|32|Cyclone|coastal + early tech|—|70/100|destroy bldgs / -1 pop|DESTROY_BLDG, POP✓|
|33|Tsunami|coastal + medieval tech|—|0/0|destroy city if <6 pop / lose bldgs+5 pop|DESTROY_BLDG, POP✓ (disabled, A=0)|
|34|Monsoon|inland + early tech + jungle nearby|—|85/100|destroy bldgs / -1 pop|DESTROY_BLDG, POP✓|
|35|Blizzard|tundra improvement + road + early tech|—|80/100|destroy improvement+route / pay 5|RMI✓, RMR✓|
|36|Volcano|peak tile + early tech|—|70/100|destroy cottages around peak|RMI✓ (radius)|
|37|Dust Bowl|4 farmed plains + civil service|—|70/100|pay 40 lose farm / lose farm + loop|**slice**|
|38|Parrots|jungle + animal husbandry|—|85/50|+1 commerce tile|TY✓|
|39|Jade|mine + iron + road|—|85/50|+2 commerce tile|TY✓|
|40|Black Pearls|clams + fishing boat|—|70/50|+1 commerce tile|TY✓|

### Events 41–80
| # | Name | Prereq | Obsolete | A/W | Result | Needs |
|---|------|--------|----------|-----|--------|-------|
|41|Saltpeter|4 forest-hill + gunpowder|—|90/20|+1 commerce tiles|TY✓ (multi)|
|42|Clunker Coal|coal mine + road|—|90/50|-1 production tile|TY✓ (neg)|
|43|Sour Crude|oil + well/platform|—|90/50|-1 production tile|TY✓ (neg)|
|44|Truffles|grass tile|—|70/20|+1 food +1 commerce tile|**slice**|
|45|Sea Turtles|coastal + calendar|—|70/20|+1 food tile|TY✓|
|46|Tin|mined hill + bronze working|—|85/50|+2 production tile|TY✓|
|47|Prairie Dogs|plains + animal husbandry|—|70/50|+1 commerce tile|TY✓|
|48|Ice Sculpture|tundra + aesthetics|—|70/100|+100 culture / pay + settled great artist|culture✓, SGP|
|49|Appleseed|plains + civil service|—|75/50|tile gains forest + food|+add-feature verb, TY✓|
|50|Mining Accident|mine + several techs|—|90/200|pay 20 / pay 5 lose mine / lose mine + angry|RMI✓, TH✓|
|51|Breakthrough|—|—|80/50|+10% remaining tech|**slice**|
|52|Setback|—|—|65/30|-8% research|**slice**|
|53|Running Bulls|pastured cows + road + AH + feudalism|—|70/200|+100 / pay +300 culture|culture✓|
|54|Great Depression|≥1 founded corporation|—|40/100|all players -25% gold|gold✓ (all-player op)|
|55|Bermuda Triangle|naval ship on ocean + flight|—|50/100|unit destroyed|destroy-unit verb|
|56|Patron of Knowledge|library|—|85/200|+10% tech / pay + library +1 research|RPCT✓, STRUCT_YIELD|
|57|Master Smith|forge|—|70/100|+1 production for the forge|STRUCT_YIELD|
|58|Rural Farmers|grocer|—|80/100|+1 food for the grocer|STRUCT_YIELD|
|59|Money Changers|market|—|75/100|+1 gold for the market|STRUCT_YIELD|
|60|Bowyer|archery|nat/print/edu/gun/astro|35/50|all archers +Combat I|**slice**|
|61|Horseshoe|pastured horse + road|steam/steel/sci/artillery|30/50|all mounted +Flanking I|PROMO✓ (mounted)|
|62|Champion|peace + undamaged 3XP unit no Leadership|nat/print/…|30/50|unit gains Leadership|PROMO✓ (single-unit variant)|
|63|Motor Oil|oil + well/platform|—|90/200|+50 gold / pay +15 free unit support|UNIT_SUPPORT|
|64|Federal Reserve|free market + ≥1000 gold + corporation|—|90/200|-10% / pay -25% inflation|INFLATION|
|65|Electric Company|emancipation + no angry + electricity|—|90/200|+1 happy every city|TH✓ (permanent → STRUCT? use happy)|
|66|Hindenburg|airship + radio|—|85/500|nothing / pay +1 happy per airport|TH✓/STRUCT_YIELD|
|67|Comet Fragment|forest-tundra bare tile + rocketry|—|80/100|+5% spaceship +2 research/lab − forest|SPACE, STRUCT_YIELD, RMF✓|
|68|Subway|public transport + pop≥25|—|80/400×|+5 commerce to public transport|STRUCT_YIELD|
|69|Gold Rush|mine + pop≤5 + industrial era|—|90/500|+1 pop / pay +3 pop|**slice**|
|70|Influenza|pop≥10 + modern/future + no medicine|—|45/400|pay -3 pop / -3 pop + nearby -2|POP✓, nearby_pop✓ (re-add as slice-compatible)|
|71|Solo Flight|≥8 landmasses + flight|—|90/100|+1 att with all met|ATT✓ (all_met)|
|72|Antelope|bare forest + hunting + ≤4 happy res + can-have-deer|—|55/200|tile gains Deer / pay + road + camp|REVEAL/RES✓, CAN_HAVE_RES, HAPPY_RES_COUNT|
|73|Whale Of A Thing|ocean + sailing + ≤4 happy res + can-have-whale|—|50/100|tile gains Whale|RES✓, CAN_HAVE_RES|
|74|Hi Yo Silver|bare hill + mining + ≤4 happy res + can-have-silver|—|35/200|gains Silver / pay + mine + road|RES✓, CAN_HAVE_RES|
|75|Wining Monks|monastery + bare grass/plains + monarchy + no wine|—|65/100|gains Wine / pay + winery + road|RES✓|
|76|Independent Films|mass media + not own Hollywood|—|35/100|+1 Movie bonus|MOVIE|
|77|Ancient Olympics|polytheism + non-Abrahamic state religion|machinery/…|75/400|nothing / pay +att all neighbours|ATT✓|
|78|Modern Olympics|sci-method + Event77.2 occurred|—|100/500|+1 att all met|ATT✓, event-chaining flag|
|79|Interstate|universal suffrage + industrialism + emancipation|—|100/100|faster road movement|ROUTE_SPEED|
|80|Earth Day|environmentalism + industrialism/radio|—|95/100|+1 happy 10t all / pay + AIs switch Environmentalism|**slice** (AI_CIVIC branch dropped)|

### Events 81–120
| # | Name | Prereq | Obsolete | A/W | Result | Needs |
|---|------|--------|----------|-----|--------|-------|
|81|Freedom Concert|free religion + ind/radio + 3-religion city|—|95/100|+1 pop +1 happy / spread religions|POP✓, TH✓, SPREAD|
|82|Axe Haft|bronze working|nat/print/…|25/200|all axemen +Shock|PROMO✓|
|83|Tower Shield|mining|machinery/…|20/200|all melee +Cover|PROMO✓|
|84|Smokeless Powder|gunpowder|rifling/steel/sci|40/200|all musketmen +Pinch|PROMO✓|
|85|Stronger Fittings|machinery|nat/print/…|25/200|all crossbowmen +Combat I|PROMO✓|
|86|Firing Pins|military science|steam/sci/artillery|25/200|all grenadiers +Pinch|PROMO✓|
|87|Rifled Cannon|rifling + steel|radio/…|35/200|all cannons +Combat I|PROMO✓|
|88|Metal Decks|flight + industrialism|composites|35/200|all carriers +Drill III|PROMO✓|
|89|Long Range Fighters|flight|composites|20/200|all fighters +Range I|PROMO✓ (needs Range promo)|
|90|Halberd|engineering|steam/…|25/200|all pikemen +Shock|PROMO✓|
|91|Reinforced Hull|metal casting|nat/print/…|25/200|all triremes +Combat I|PROMO✓|
|92|Cigarette Smoker|drama + theater|—|80/200|-30 / -10 + destroy theater / destroy + angry|DESTROY_BLDG, TH✓|
|93|Heroic Gesture|at war and winning|—|80/350|nothing / make peace +att|PEACE|
|94|Great Mediator|at war ≥10 turns|—|85/200|nothing / make peace +att|PEACE|
|95|Forty Thieves|organized religion + horseback|nat/print/…|90/200|+2 commerce tile|TY✓|
|96|Ancient Texts|bare desert + steam/steel/sci/artillery|—|90/200|15% tech / pay +att all|RPCT✓, ATT✓|
|97|Waters of Life|oasis tile|medicine|95/200|+1 commerce tile|TY✓|
|98|Impact Crater|jungle/forest + physics + no uranium|—|20/200|nothing / pay reveal Uranium + mine|REVEAL|
|99|The Huns|player knows HBR + player knows iron working|nat/print/…|20/200|4 barb horse archers|**slice**|
|100|The Vandals|metal casting + iron working (any player)|nat/…|20/200|4 barb swordsmen|WILD✓|
|101|The Goths|mathematics + iron working|nat/…|20/200|4 barb axemen|WILD✓|
|102|The Philistines|monotheism + bronze working|nat/…|20/200|4 barb spearmen|WILD✓|
|103|The Vedic Aryans|polytheism + archery|nat/…|20/200|4 barb archers|WILD✓|
|104|Holy Ritual|temple + incense plantation + road|—|90/200|pay 20|gold✓|
|105|Security Tax|walls + early tech|nat/print/…|70/500|20–80 gold|**slice**|
|106|Literacy|all cities have library + nat/print/…|—|30/100|1 city settled great scientist|SGP|
|107|Farm Plows|forge + iron mine + road|—|90/100|30–60 gold|gold✓|
|108|Stained Glass|cathedral|—|90/100|40–70 gold|gold✓|
|109|Marble Statues|aesthetics + marble quarry + road|—|90/100|50–70 gold|gold✓|
|110|Crab Cakes|grocer + crabs + fishing boats|—|90/100|30–70 gold|gold✓|
|111|Boilers|steel + factory|—|90/100|90–140 gold|gold✓|
|112|Personal Computers|computers + factory|—|90/100|140–230 gold|gold✓|
|113|Fuel Additives|ecology + public transport|—|90/100|110–180 gold|gold✓|
|114|Hamburger Joint|radio + pastured cows + road|—|90/100|240–330 gold|gold✓|
|115|Tea|sci-method + harbor + not mercantilism|—|90/100|50–100 gold|gold✓|
|116|Fashion|radio + factory + silk plantation + road|—|90/100|180–260 gold|gold✓|
|117|Thoroughbred|stable + horse pasture + road|—|90/100|30–70 gold|gold✓|
|118|Girls Best Friend|forge + gems mine + road|—|90/100|120–180 gold|gold✓|
|119|Banana Split|refrigeration + banana plantation + road|—|90/100|160–240 gold|gold✓|
|120|Horse Whispering|*(quest)*|—|—|see Quest 3|QUEST|

### Events 121–174
| # | Name | Prereq | Obsolete | A/W | Result | Needs |
|---|------|--------|----------|-----|--------|-------|
|121–126|Harbormaster/Classic Lit/Master Blacksmith/Best Defense/Sports League/Crusade|*(quests)*|—|—|see Quests 4–9|QUEST|
|127|Miracle|walls + state religion|—|90/200|+1 commerce walls / pay + spread religion 2|STRUCT_YIELD, SPREAD|
|128|Esteemed Playwright|theater + not slavery|—|85/200|+1 commerce theater / pay +3 culture|STRUCT_YIELD|
|129|Favorite Son|colosseum|steam/…|85/200|+20 gold / pay +2 culture colosseum|gold✓, STRUCT_YIELD|
|130|Secret Knowledge|monastery + renaissance tech|—|70/200|15% religious tech / pay +4 culture monastery|RPCT✓, STRUCT_YIELD|
|131|High Warlord|castle + not emancipation|radio/…|80/200|+100 gold / 2 pikemen / settled great general|gold✓, unit✓, SGP|
|132|Spoiled Grain|granary|—|80/200|lose stored food / pay 20|FOOD✓, gold✓|
|133|Angel of Mercy|hospital|—|80/200|+2 gold hospital / pay +1 happy hospital|STRUCT_YIELD, TH✓|
|134|Chilly Flight|airport|—|80/200|+2 gold airport|STRUCT_YIELD|
|135|Industrial Fire|factory|—|80/200|destroy factory / pay 100|DESTROY_BLDG, gold✓|
|136|Laboratory|laboratory + free speech|—|80/200|15% tech|RPCT✓|
|137|Experienced Captain|drydock + 7XP naval unit|—|95/200|+2 gold drydock / pay + Military Academy|STRUCT_YIELD, building✓|
|138|Heresy|theocracy|—|85/200|angry + spread / pay +15% religious tech / nothing|TH✓, SPREAD, RPCT✓|
|139|Partisans|emancipation + a razed city|—|35/0|drafted units at site / half at capital|DRAFT (disabled, W=0)|
|140|New Dynasty|hereditary rule + capital + medieval tech|—|45/100|settled great general/merchant/priest|SGP|
|141|Crisis in the Senate|representation + nat/print/…|—|55/100|+2 EP barracks / 400-600 gold / +1 happy all|ESP/STRUCT_YIELD, gold✓, TH✓|
|142|Too Close To Call|universal suffrage + nat/…|—|60/100|+1 gold courthouses / +3 culture courthouses|STRUCT_YIELD|
|143|Charismatic|police state + nat/…|—|65/100|all gun units +March / +2 happy all|PROMO✓, TH✓|
|144|Friendly Locals|damaged unit|—|90/50|unit +1 XP|UNIT_STATE(XP)|
|145–153|Greed/War Chariots/Elite Swords/Warships/Guns Butter/Noble Knights/Overwhelm/Corporate Expansion/Hostile Takeover|*(quests)*|—|—|see Quests 10–18|QUEST|
|154|Civ Game|computers|—|80/100|+1 happy all / +3 research universities / ~320 gold|TH✓, STRUCT_YIELD, gold✓|
|155|Slave Revolt Warning|slavery + pop≥4|—|0/0|warning text only|text-only (A=0)|
|156|Immigrants|≥55 culture/turn city + net-happy + printing press|—|80/200|+1 pop|POP✓, culture-rate prereq|
|157|Healing Plant|—|feudalism/machinery/phil|70/100|timed happy / angry chains / health faces|TH✓, HEALTH_TIMED, POP✓, CHANCE✓|
|158|Great Beast|camp + hunting + polytheism + state religion|education|75/100|+1 food / pay +pop / +happy 40t state-religion cities|TY✓, POP✓, TH✓ (scope)|
|159|Controversial Philosopher|capital >35 research + theocracy + philosophy|sci-method|75/1000|+happy 15t / -happy + scientist / pay + Academy|TH✓, SPEC, building✓|
|160|Defecting Agent|≥5 intelligence agencies + contact|—|75/100|-300 EP / pay chance / -2 att|ESP, ATT✓, CHANCE✓|
|161|Jail|jail|—|80/100|-1 happy / pay 100|TH✓, gold✓|
|162|Spy Discovered|industrialism + contact + ≥4 cities + capital|robotics|60/100|+400 EP +att / pay + Great Spy / war + support + tanks|ESP, SGP, WAR, UNIT_SUPPORT|
|163|Nuclear Protests|free speech + ≥10 nukes|—|75/120|disband nukes +3 happy / -2 happy 1 city / pay 400|destroy-unit, TH✓, gold✓|
|164|Better Coal|coal mine|—|75/100|+4 production coal plants / +2 prod +1 health drydocks|STRUCT_YIELD, HEALTH_TIMED|
|165|Broken Dam|hydro plant|—|75/100|lose plant + angry -pop / pay variants|DESTROY_BLDG, TH✓, POP✓|
|166|Rabbi|Judaism + Jewish monastery + paper|mass media|0/0|convert cities / scientist / culture+gold|SPREAD, SPEC, STRUCT_YIELD (A=0)|
|167|Golden Buddha|Buddhism + forge + gold mine + road|steam power|0/0|180-200 gold / +6 culture forge / +350 culture all|gold✓, STRUCT_YIELD, culture✓ (A=0)|
|168|Preaching Researcher|Christianity + Christian monastery + university|—|0/0|+2 culture / pay +culture +research monastery|STRUCT_YIELD (A=0)|
|169|Toxcatl|Aztec + sacrificial altar + ≥1 unit|education|90/100|+2 angry / pay + unit immobile 3t|CIV_ID, TH✓, UNIT_STATE|
|170|Dissident Priest|Egyptian + non-state-religion non-capital city + 30 culture|printing press|90/100|angry + revolt / angry all / pay + libraries +research|CIV_ID, TH✓, REVOLT, STRUCT_YIELD|
|171|Pasture Built|cow/horse/sheep/pig bare tile + animal husbandry|calendar|80/100|tile gains pasture + road|place-improvement verb|
|172|Rogue Station|broadcast tower + assembly line + Russian + state property + contact|—|90/100|-EP lose tower / angry / angry + factories prod|ESP, DESTROY_BLDG, TH✓, STRUCT_YIELD, CIV_ID|
|173|Anti-Monarchists|French + hereditary rule|—|90/100|+3 happy palace / +2 gold cathedrals|CIV_ID, TH✓/STRUCT_YIELD|
|174|Impeachment|American + constitution + capital|—|90/100|+6 angry +1 happy 10t all / +2 prod courthouse + revolt|CIV_ID, TH✓, STRUCT_YIELD, REVOLT|

**3.13 changelog deltas** (apply when porting): many ancient/classical events also
obsolete with **Astronomy**; events 130/141/142/143 may also occur *after* Astronomy;
quests gain a **One City Challenge** human gate; barbarian-uprising events use a
dedicated city-attack AI. Track these as per-event `obsolete`/eligibility tweaks.

---

## 4. Quests (1–18) — deferred subsystem

Quests are **multi-turn goals**: a trigger arms the quest, the player works toward an
**aim** over many turns (without violating a constraint, e.g. "never switch state
religion"), and completing it grants a **reward** (often a choice of three). This needs
a new **Quest tracking subsystem** not present today:

- `GameState.active_quests` (serialized): `{quest_id, player_id, start_turn, progress,
  snapshot}` — `snapshot` captures the baseline for "cities that did not have it when
  triggered" style aims.
- A per-player step that (a) arms eligible quests from `data/quests.json` (same prereq
  vocabulary + `active`/`weight`), (b) re-evaluates each active quest's aim/constraint,
  (c) on success queues a reward (reusing the event effect verbs), on violation drops it.
- Aim predicates needed: build-N-of-structure, have-cities-on-N-landmasses, control-a-
  named-tile/wonder, conquer-a-resource/holy-city, spread-corp-to-N-cities, own-all-
  corp-resources, build-specific-fleet-composition.
- Rewards reuse §1.3 verbs plus PROMO/SGP/SPREAD/GA/REVEAL and "build shrine".

| Q | Name | Prereq | Aim | Reward(s) |
|---|------|--------|-----|-----------|
|1|Blessed Sea|galley+ · Eastern state religion · many landmasses · few settled|cities on ~10 landmasses, never switch religion|convert 20 cities / temple in size-5+ cities / a Great Prophet|
|2|Holy Mountain|Abrahamic state religion|build ~14 temples/monasteries (cathedral=4) to reveal peak, settle it|+1 happy all cities|
|3|Horse Whispering|animal husbandry + horse|build ~7 stables|~6 Horse Archers / mounted +Sentry / stables +1 food|
|4|Harbormaster|compass + ≥40% water map|build ~7 harbors + ~4 caravels|naval +Combat I / harbors +1 gold / naval +Navigation I|
|5|Classic Literature|writing|build ~7 libraries|+2 research a library / an ancient tech / Great Library scientist|
|6|Master Blacksmith|forge|build ~7 forges, keep trigger city|reveal Copper / swordsmen +Shock / engineer specialist|
|7|Best Defense|engineering|build ~7 castles|melee +City Garrison I / +3 att all / Great Wall EP|
|8|Sports League|construction|build ~7 colosseums|+1 happy per colosseum / +4 culture each / Statue-of-Zeus golden age|
|9|Crusade|state religion, don't hold Holy City|conquer the Holy City|~4 conscripts / build shrine / spread religion ~7 cities|
|10|Greed|bronze working + lacking a strategic resource|conquer that resource|~4 units needing it|
|11|War Chariots|the wheel + state religion|build ~8 chariots|chariots +Combat I / spread religion 5 cities|
|12|Elite Swords|iron working + state religion|build ~8 swordsmen|swords +City Raider I / melee +Drill I|
|13|Warships|sailing + metal casting + ≥55% water|build ~7 triremes|triremes +Combat I / Great Lighthouse harbors +2 commerce|
|14|Guns Butter|gunpowder|build ~8 musketmen|musket +Pinch / Vassalage:400 gold / Taj Mahal golden age|
|15|Noble Knights|guilds + horseback|build ~8 knights|knights +Flanking I / spread religion / Oracle great priest|
|16|Overwhelm|flight + industrialism + ≥55% water|build 4 destroyers/2 battleships/3 carriers/9 fighters|fleet +Combat I / harbors +5 commerce / Nuke Ban|
|17|Corporate Expansion|own a corp HQ|spread corp to ~8 new cities|+10 gold for the HQ|
|18|Hostile Takeover|own corp HQ lacking a corp resource|own all the corp's resources|+20 gold for the HQ|

---

## 5. Map-size & game-speed scaling (deferred)

All §3/§4 magnitudes are **normal/standard**. The reference scales several values:
- **Counts** ("4 barbarians", "7 stables", "default players for this size"): derive
  from world size's default player count and the quest's multiplier. Wire counts
  through `data/constants.json` (e.g. `event_huns_count`) or a per-event field, then
  compute size-scaled values in a single helper.
- **Gold/culture/food magnitudes** and **timers**: the reference multiplies by the
  game-speed growth percent. Apply one pace-scale at the roller, gated by an
  `event_pace_scaled` flag per magnitude (the grace period stays unscaled by spec).

Until then, ship the standard integers verbatim (current behaviour).

---

## 6. Roadmap

1. **Done (this branch):** framework + supporting mechanics + 15-event slice + tests +
   docs.
2. **Phase 2 — pure-verb events:** port every event whose `Needs` is already ✓ (the
   gold/TY/PROMO/RMx/FOOD/POP/ATT/RPCT/WILD set — roughly events 3,4-style,
   38–47, 60–62, 82–91, 95–97, 100–119, 144). Low risk, high count.
3. **Phase 3 — STRUCT_YIELD + SPEC + SGP + SPREAD:** the religion/structure/Great-
   Person cluster (events 9,28,56–59,127–134,140,142,158,159,166–168, etc.).
4. **Phase 4 — ESP + PEACE/WAR + DESTROY_BLDG + PILLAGE + REVOLT:** the diplomatic/
   military/destructive cluster (14,18,29,31–36,92–94,135,160–165,172).
5. **Phase 5 — niche systems:** INFLATION, MOVIE, SPACE, ROUTE_SPEED, DRAFT,
   UNIT_SUPPORT, CIV_ID, corp ops.
6. **Phase 6 — Quest subsystem** (its own branch): tracking + 18 quests.
7. **Phase 7 — scaling** (§5) once the catalogue is broad enough to balance.

Each phase adds events in `data/events.json` and tests in `tests/sim/test_events.gd`;
new verbs/prereqs extend `Events` + the `DataDB` validator; new subsystems get their
own module + tests per the normal architecture.
