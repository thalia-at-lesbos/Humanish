# Original-Reference Parity Audit — data values & feature gaps

Date: 2026-07-07. Compared the project against the two reference sources on this
machine: the reference-docs tree and the original-reference install (layered data
tables, highest layer wins). Add-on/mod content excluded. Method: scripted
field-by-field diff of every `data/*.json` table against the corresponding
original-reference table, plus a rules-level sweep. Scripts under the audit job's tmp dir
(throwaway); every number below was read from the actual XML.

Legend: **[value]** = numeric discrepancy in a translated value; **[schema]** = the
JSON schema cannot express the XML construct; **[missing]** = reference feature/content
absent; **[added]** = Humanish content with no reference counterpart; **[bug?]** =
looks accidental rather than a design choice.

---

## 1. Systematic model/schema differences (affect many entries at once)

1. **[schema] Single tech prereq per unit.** `units.json.tech_required` is one tech;
   the XML gives many units an AND-set (`PrereqTech` + `TechTypes`): e.g. bomber =
   Flight **and** Radio; infantry = Assembly Line **and** Rifling; cavalry needs
   Horseback Riding + Military Tradition + Rifling. Humanish keeps only one of them,
   so many units unlock earlier than in the reference.
2. **[schema] Single resource prereq per unit.** XML has `BonusType` (required) plus
   `PrereqBonuses` (any-of): knight = Horse **and** Iron; maceman = Copper **or** Iron;
   battleship = Oil or Uranium. `resource_required` keeps at most one (knight keeps
   only horse; maceman/pikeman/spearman lost their metal requirement entirely).
3. **[schema] Chance first strikes dropped.** XML `iChanceFirstStrikes` (navy seal
   1+1, skirmisher 1+1, drill promotions) has no JSON field; Humanish folds or drops it.
4. **[value/semantics] Siege combat limit flattened.** XML `iCombatLimit` is per-unit
   damage cap (catapult/trebuchet 75 → defender floor 25 HP, cannon 80 → floor 20,
   artillery/mobile artillery 85 → floor 15). Humanish `combat_limit: 1` = universal
   1-HP floor for all siege — siege is far stronger than the reference.
5. **[schema] Conditional improvement yields flattened.** XML improvements mostly
   carry `[0,0,0]` base yields — output comes from the resource worked
   (`BonusYieldChanges`), irrigation (`IrrigatedYieldChange`, farm +1F), civics and
   techs. Humanish gives improvements flat unconditional `output_delta`s (pasture
   +1F+1P, camp +1P, plantation +1C, quarry +1P…). Same end numbers in the common
   case, but resource-less improvements over/under-produce vs the reference.
   Cottage→town base commerce 1/2/3/4 matches; Humanish town adds +1F+1P **[value]**.
   Upgrade turns 10/20/40 match.
6. **[semantics] Buildings pay per-building gold upkeep** (`upkeep` on every
   structure). Reference buildings have no gold upkeep (economy drag is city
   maintenance + civic upkeep + inflation). Humanish has city maintenance and civic
   upkeep too, so its economy is double-loaded relative to the reference.
7. **[missing] Inflation is not modelled at all.** Reference: per-speed
   `iInflationPercent` (Quick 45 … Marathon 10) applied to costs over time.
8. **[value] Trait "double production speed" became "free building".**
   Reference traits double build speed of specific buildings (Aggressive:
   barracks/drydock; Protective: walls/castle; Organized: lighthouse/courthouse;
   Expansive: granary/harbor; Industrious: forge; Creative: theatre/colosseum;
   Imperialist: settler). Humanish grants those buildings **free**
   (`free_structures`) — much stronger. Also: Creative's list adds `library`
   (not in reference), Imperialistic GG rate 50 vs reference 100 **[value]**,
   Charismatic `-25% XP to level` became `xp_bonus 25` + `promotion_cost_reduction
   25` (split/approximation).
9. **[value] Movement scale.** `movement` = 60 per move point (fine), but several
   units have different move counts than the XML — see §2 table (settler/worker
   1 vs 2 is the most gameplay-visible).
10. **[semantics] Great-person data model** merges the reference's specialist GPP (3 per
    specialist, threshold 100 + growth) into 1 GPP per specialist with different
    thresholds; settled great people give far weaker, sometimes re-typed outputs
    (see §8).

---

## 2. Units — full value diff (`units.json` vs the reference unit table)

> **Resolution note (2026-07-08, A1 — ca79f8a):** every numeric diff below is now
> applied to `data/units.json` (tech/resource sets via B1, chance first strikes via
> B2, combat-limit floors via B3, withdrawal restorations + guided_missile via
> d933a61, everything else via A1). Still diverging on purpose: settler cost 100
> (reference 0 = food-box model), icbm `air_range` 999 (both mean unlimited), and
> the "?"-flagged resource entries (tactical_nuke/panzer/tank). The table below is
> the original audit snapshot, kept verbatim.

Format: `field humanish≠reference`. `tech X≠[list]` / `resource X≠[list]` = the XML AND/OR
set (schema issue §1.1/§1.2) — listed only where the JSON value isn't in the set or
the set has more members. `combat_limit(floorHP) 1≠25 (iCombatLimit 75)` per §1.4.

```
airship: strength 8≠4; cost 90≠80; air_range 6≠8
artillery: strength 16≠18; cost 120≠150; combat_limit floor 1≠15
attack_submarine: strength 40≠30; moves 6≠7; cost 250≠200; tech rocketry≠[combustion,radio,rocketry]; resource oil≠[uranium]; withdrawal 0≠50; cargo 0≠1
axeman: resource copper≠[copper OR iron]
ballista_elephant: moves 2≠1; cost 70≠60; tech guilds≠[construction,horseback_riding]; resource none≠[ivory]
battleship: resource oil≠[oil,uranium]
bear: strength 4≠3
berserker: tech civil_service≠[civil_service,machinery]; resource none≠[copper,iron]
bomber: strength 8≠16; cost 120≠140; tech flight≠[flight,radio]
bowman: strength 4≠3; cost 30≠25
camel_archer: tech guilds≠[archery,guilds,horseback_riding]; withdrawal 0≠15
cannon: resource none≠[iron]; combat_limit floor 1≠20
caravel: strength 6≠3; moves 4≠3; cost 75≠60
carrack: strength 6≠3; moves 5≠3; cost 80≠60; cargo 1≠2
carrier: strength 18≠16; moves 6≠5; cost 220≠175; tech industrialism≠[flight]; cargo 4≠3
cataphract: strength 10≠12; tech guilds≠[guilds,horseback_riding]; resource horse≠[horse,iron]
catapult: combat_limit floor 1≠25
cavalry: tech military_tradition≠[horseback_riding,military_tradition,rifling]; withdrawal 10≠30
chariot: withdrawal 0≠10
cho_ko_nu: tech machinery≠[archery,machinery]; resource none≠[iron]; withdrawal 10≠0
conquistador: strength 10≠12; cost 90≠100; tech guilds≠[gunpowder,horseback_riding,military_tradition]; resource horse≠[horse,iron]; withdrawal 0≠15
cossack: tech military_tradition≠[horseback_riding,military_tradition,rifling]; withdrawal 10≠30
crossbowman: tech machinery≠[archery,machinery]; resource none≠[iron]
cuirassier: cost 110≠100; tech military_tradition≠[gunpowder,horseback_riding,military_tradition]; resource horse≠[horse,iron]; withdrawal 0≠15
destroyer: moves 7≠8; resource none≠[oil,uranium]
dog_soldier: strength 6≠4; cost 40≠35
east_indiaman: strength 8≠6; moves 5≠4; cost 100≠80; cargo 3≠4
explorer: strength 1≠4; cost 30≠40
fast_worker: moves 2≠3; cost 30≠60
fighter: air_range 4≠6
frigate: strength 18≠8; cost 130≠90; tech chemistry≠[astronomy,chemistry]; resource none≠[iron]
galleon: strength 8≠4; cost 90≠80; cargo 2≠3
galley: cost 30≠50
gallic_warrior: strength 8≠6; cost 60≠40; resource none≠[copper,iron]
grenadier: strength 11≠12
guided_missile: strength 0≠40; cost 50≠60; tech rocketry≠[radio,rocketry]; air_range 8≠4
gunship: strength 20≠24; resource none≠[oil]; withdrawal 0≠25
holkan: strength 3≠4; cost 30≠35; tech none≠[bronze_working,hunting]
horse_archer: tech horseback_riding≠[archery,horseback_riding]; withdrawal 0≠20
hwacha: strength 6≠5; combat_limit floor 1≠25
icbm: cost 350≠500; tech rocketry≠[fission,rocketry]; air_range 999≠0 (both mean "unlimited"?)
immortal: resource none≠[horse]; withdrawal 0≠10
impi: cost 25≠35; resource none≠[copper,iron]
infantry: cost 130≠140; tech assembly_line≠[assembly_line,rifling]
ironclad: strength 22≠12; moves 4≠2; cost 150≠100; tech steam_power≠[steam_power,steel]; resource coal≠[coal,iron]
jaguar: moves 2≠1
jet_fighter: strength 22≠24; cost 180≠150; resource oil≠[aluminum,oil]; air_range 8≠10
keshik: moves 3≠2; tech horseback_riding≠[archery,horseback_riding]; first_strikes 0≠1; withdrawal 0≠20
knight: tech guilds≠[guilds,horseback_riding]; resource horse≠[horse,iron]
landsknecht: strength 8≠6; cost 50≠60; resource none≠[iron]
longbowman: cost 60≠50; tech feudalism≠[archery,feudalism]; first_strikes 2≠1
maceman: tech civil_service≠[civil_service,machinery]; resource none≠[copper OR iron]
marine: strength 18≠24; cost 140≠160; tech industrialism≠[industrialism,rifling]
mechanized_infantry: strength 28≠32; cost 170≠200; tech robotics≠[rifling,robotics]
missile_cruiser: strength 45≠40; cost 280≠260; tech satellites≠[robotics]; resource none≠[oil,uranium]; cargo 0≠4
mobile_artillery: strength 16≠26; cost 165≠200; tech laser≠[artillery,laser]; resource none≠[oil]; combat_limit floor 1≠15
mobile_sam: strength 20≠22; cost 150≠220; resource none≠[oil]
modern_armor: cost 250≠240; tech composites≠[composites,computers]; resource oil≠[aluminum,oil]; first_strikes 0≠1
musketeer: moves 1≠2
navy_seal: strength 18≠24; cost 140≠160; tech industrialism≠[industrialism,rifling]; first_strikes 2≠1+1chance
numidian_cavalry: strength 6≠5; tech horseback_riding≠[archery,horseback_riding]; withdrawal 25≠20
oromo_warrior: strength 10≠9; first_strikes 0≠1
panther: strength 3≠2
panzer: moves 3≠2; tech industrialism≠[industrialism,rifling]; resource oil≠(none? XML lists none beyond oil-or)
paratrooper: strength 16≠24; cost 120≠160; tech fascism≠[fascism,flight,rifling]
phalanx: strength 4≠5; cost 30≠35; tech hunting≠[bronze_working]; resource none≠[copper,iron]
pikeman: resource none≠[iron]
praetorian: cost 40≠45
privateer: strength 10≠6; moves 5≠4; tech chemistry≠[astronomy,chemistry]; resource none≠[copper,iron]
sam_infantry: strength 12≠18; cost 90≠150
samurai: tech civil_service≠[civil_service,machinery]; resource none≠[iron]; first_strikes 0≠2
settler: moves 1≠2; cost 100≠0 (XML settler iCost 0: reference cost is food+hammers — model difference)
ship_of_the_line: strength 24≠8; moves 4≠3; cost 160≠120; tech military_science≠[astronomy,military_science]; resource none≠[iron]
skirmisher: strength 3≠4; tech none≠[archery]; first_strikes 1≠1+1chance
spearman: strength 3≠4; cost 30≠35; resource none≠[copper OR iron]
spy: cost 60≠40; tech none≠[alphabet]
stealth_bomber: strength 24≠20; cost 250≠200; tech stealth≠[robotics,stealth]; resource oil≠[aluminum,oil]
stealth_destroyer: strength 50≠30; moves 7≠8; cost 300≠220; tech stealth≠[robotics,stealth]; resource none≠[oil,uranium]; first_strikes 0≠2
submarine: strength 32≠24; cost 180≠150; tech industrialism≠[radio]; resource oil≠[oil,uranium]; withdrawal 0≠50; cargo 0≠3 (missiles)
tactical_nuke: tech fission≠[fission,rocketry]; resource uranium≠(uranium?); air_range 12≠4
tank: tech industrialism≠[industrialism,rifling]; resource oil≠(oil?)
transport: strength 18≠16; moves 6≠5; cost 200≠125; resource none≠[oil,uranium]
trebuchet: strength 8≠4; combat_limit floor 1≠25
trireme: strength 5≠2; moves 3≠2; tech metal_casting≠[metal_casting,sailing]
vulture: resource none≠[copper,iron]
war_chariot: strength 4≠5; resource none≠[horse]; withdrawal 0≠10
wolf: strength 2≠1
work_boat: cost 15≠30
worker: moves 1≠2; cost 30≠60
```

Naval line stands out: nearly every ship is stronger/faster/pricier than the
reference (frigate 18 vs 8, ship of the line 24 vs 8, ironclad 22 vs 12…) —
looks like a deliberate rescale, but it is undocumented. Mounted units
systematically lost their withdrawal chances (chariot/horse archer/knight-line/
gunship) — plausibly **[bug?]** since Flanking promotions still exist.

**[missing] Units:** Machine Gun (`UNIT_MACHINE_GUN`), War Elephant
(`UNIT_WAR_ELEPHANT`), Lion (animal). **[added]:** `anti_tank` (no reference
counterpart). Missionaries/executives: reference has 7 typed each; Humanish one
generic of each (reasonable merge).

---

## 3. Technologies

- Costs: **all 90 match** except `future_tech` 8000 ≠ 10000 **[value]**.
- Eras: `calendar`, `iron_working` ancient≠classical; `genetics`, `stealth`
  modern≠future **[value]**.
- **The tree is wholesale rewired [value]:** Humanish puts everything in
  `prereqs_all` (2 techs each, `prereqs_any` always empty) while the reference
  uses mostly OR-prereqs plus a few ANDs; virtually every tech's prereq set
  differs (e.g. reference Writing ← any of animal_husbandry/pottery/priesthood;
  Humanish Writing ← pottery only. Reference Civil Service ← Mathematics AND
  (Code of Laws OR Feudalism); Humanish ← alphabet + code_of_laws). If reference
  parity of the research graph is a goal, this is the largest single divergence.
  Full diff reproducible via the audit script.
- **[missing/renamed]** Reference `TECH_UTOPIA` (industrial, 2800, ← Scientific
  Method + Liberalism-or) has no Humanish entry; Humanish `communism`
  (industrial, 2800, ← philosophy + scientific_method) is its evident rename with
  a swapped prereq. Buildings gated on it (`intelligence_agency`, `kremlin`)
  correctly follow `communism`.

---

## 4. Structures (buildings & wonders)

> **Resolution note (2026-07-08, A2 — 6608796):** every straight value diff below
> is now applied to `data/structures.json` (costs, tech gates, negative health,
> happiness rows, granary health). The negative-health fix also uncovered and
> retired a dead `effects.unhealthy` key (never read; the engine reads
> `health_penalty`) on factory/industrial_park/coal_plant/shale_plant/ironworks.
> Still diverging on purpose: the `science%` rows (library/seowon/academy —
> CommerceModifiers unverified, see note below), military_academy cost 300
> (reference "not city-buildable −1" is a buildability change, deferred),
> three_gorges_dam `unhealthy_global` (dead key, global semantics — needs wiring),
> Apollo/Manhattan + spaceship-part costs (A10). The table below is the original
> audit snapshot, kept verbatim.

Value diffs (`cost` in hammers; `science%` = iResearchModifier; `happy/health`):

```
academy: science% 50≠0 (reference academy modifier lives elsewhere: +50% research is the reference's published value — the table here has 0)
airport/assembly_plant/drydock/factory/forge/mint/laboratory/research_institute/industrial_park: humanish drops the reference's negative health (0 ≠ -1/-2)
ball_court: happy 2≠3        barracks: cost 60≠50
buddhist/christian/confucian/hindu/taoist cathedrals: happy 2≠0 (reference cathedrals give happiness via culture%/music resource, not flat)
cothon: cost 80≠100          dun: cost 60≠50, tech none≠masonry
forum: cost 100≠150, happy 1≠0
ger: cost 50≠60              granary: health 1≠0
hagia_sophia: cost 550≠500, tech engineering≠theology
hippodrome: happy 0≠1        library: science% 25≠0 (see note below)
madrassa: cost 80≠90         market: happy 1≠0
military_academy: cost 300 (reference: not city-buildable, -1)
odeon: happy 1≠2             sacrificial_altar: cost 120≠90
seowon: science% 35≠0        space_elevator: tech satellites≠robotics
walls: tech none≠masonry     ziggurat: cost 120≠90
scotland_yard: cost 0≠-1 (GP-built in both; fine)
```

Note on `science% 25≠0`: this reference XML stores library/university/observatory
research bonuses as `CommerceModifiers` lists, not `iResearchModifier` — treat
those rows as *unverified* rather than wrong. The cost/happy/health/tech rows
above are solid.

Name mappings that hide equivalences (no action needed, documented here):
`monument`↔`BUILDING_OBELISK`, `obelisk`↔`BUILDING_EGYPTIAN_OBELISK`,
`forbidden_palace`↔`BUILDING_GREAT_PALACE` (cost 200 matches),
`three_gorges_dam`↔`BUILDING_GREAT_DAM` (1750 matches), `ironworks`↔
`BUILDING_IRON_WORKS` (700 matches), `synagogue/mosque/stupa`↔ the jewish/
islamic/buddhist cathedrals, `temple_of_artemis`↔`BUILDING_ARTEMIS`,
`customs_house`↔`BUILDING_CUSTOM_HOUSE`, `rock_n_roll`↔`BUILDING_ROCKNROLL`,
`university_of_sankore`↔`BUILDING_SANKORE`, `totem_pole`↔
`BUILDING_NATIVE_AMERICA_TOTEM`, `security_bureau`↔`BUILDING_NATIONAL_SECURITY`,
`pavilion`↔`BUILDING_CHINESE_PAVILLION`, `garden`↔`BUILDING_BABYLON_GARDEN`.

- **Merged**: 7 per-religion monasteries → one generic `monastery`; 7 holy
  shrines → one generic `shrine`; plus generic `temple`/`cathedral` alongside the
  per-religion ones (reference has only per-religion).
- **Moved**: Apollo Program (1000 ≠ project 1600 **[value]**) and Manhattan
  Project (1250 ≠ 1500 **[value]**) are buildings here, projects in the reference.
- **[missing] Projects: The Internet, SDI** — no Humanish counterpart anywhere.
- Spaceship parts (see §12 of game-data): Humanish costs 250–600 vs reference
  1000–2000 **[value]**; counts casing×3/thrusters×2/engine×1 vs reference
  casing×5/thrusters×5/engine×2 **[value]**; docking bay tech satellites ≠
  reference TECH_SATELLITES ✓ (matches), cockpit fiber_optics ✓.

---

## 5. Difficulties (`difficulties.json` vs the reference handicap table)

> **Resolution note (2026-07-08, A3 — a3d1078):** every diff below is now applied
> to `data/difficulties.json` (research %, free early wins, health/happiness
> reference floors — never negative for the human). `ai_research_per_era` carries
> the reference sign (0/0/0/0/−1…−5) with the `Research._effective_cost` read
> flipped to match (negative = AI techs cheaper). Water-raider density undid the
> ×4 (750…250; `wild_water_per_unit` constant fallback 2000→500). The dead
> `combat_bonus_vs_wild` field was replaced by `wild_combat_modifier` with
> reference semantics — a percent modifier on the *wild* side's strength vs a
> human opponent, newly wired in `Combat.resolve`, value 0 at every level. The
> table below is the original audit snapshot, kept verbatim.

Docs claim these were ported from the reference handicap table and not yet retuned, but
several columns differ from the file:

- `handicap_research_percent`: 60/72/85/100/**100**/110/118/124/135 vs XML
  60/75/90/100/**110**/115/120/125/135 (prince ≠).
- `ai_research_per_era`: **sign/semantics flipped** — Humanish −8…+9
  (settler→deity), XML 0/0/0/0/−1/−2/−3/−4/−5.
- `free_early_wins`: 5/3/1/0/0/0… vs XML 5/4/3/2/1/0… .
- `health_bonus`/`happiness_bonus`: Humanish 2/1/0/0/0/0/−1/−1/−2 and same for
  happiness; XML health 4/3/2/2/2/2/2/2/2, happiness 6/5/4/4/4/4/4/4/4 —
  Humanish shifted down and goes negative at high difficulty (reference never
  penalizes the human).
- `combat_bonus_vs_wild`: Humanish 30/15/0…−15 vs XML `iBarbarianCombatModifier`
  0 at every level (the reference's barb discount is on the *barbarian's* side
  via `iAIBarbarianCombatModifier` etc.) — semantics differ.
- `unowned_water_tiles_per_wild_unit`: exactly **4×** the XML at every level
  (3000/2400/…/1000 vs 750/600/…/250). Land tiles-per-unit and tiles-per-city
  match the XML. (Deliberate naval-raider damping? Undocumented.)

## 6. World sizes

> **Resolution note (2026-07-08, A4 — a3d1078):** all three columns below are now
> at reference values in `data/world_sizes.json` (grids, research % 100–150,
> players_suggested 2/3/5/7/9/11). The table below is the original audit
> snapshot, kept verbatim.

- Grids: only duel (40×24) matches. tiny 56×36≠52×32, small 72×44≠64×40,
  standard 96×60≠84×52, large 128×80≠104×64, huge 160×100≠128×80 — Humanish maps
  run larger.
- `research_percent`: 75/85/95/100/110/120 vs XML 100/110/120/130/140/150 —
  reference makes research *more* expensive as maps grow from a 100 floor;
  Humanish recentred on standard=100 (same relative spacing, different absolute
  costs at every size).
- `players_suggested`: 2/3/4/6/8/10 vs XML 2/3/5/7/9/11.

## 7. Paces

`growth/research/build 67/100/150/300` and total game turns **330/500/750/1500
all match** the XML. Missing per-speed knobs: `iAnarchyPercent`,
`iGoldenAgePercent` (golden-age length doesn't scale with pace; reference quick
80 … marathon 200), `iInflationPercent` (no inflation at all), victory-delay
percent, and the reference's separate `iBarbPercent` (marathon 400 ≠ reuse of
build scale).

## 8. Terrain / features / specialists / GP

> **Resolution note (2026-07-08, A5 — 221871c): the terrain/feature rows below are
> now applied** — grassland 2F/0P, hills net 1F/1P, mountain 0-yield + unworkable
> (new `unworkable` flag, `TileOutput.workable()`), river +1C extended to
> desert/tundra (the previously dead `river_commerce_bonus` key is now wired via a
> `has_river` param on `TileOutput.compute`), flood-plains defence −33 → 0.
> Still open: the fractional feature health percentages (forest +0.5 / jungle −0.25 /
> flood-plains −0.4 — needs a fractional-health model, not a value edit). The
> **specialists / GPP / settled-GP / XP-curve rows are untouched — they are work
> item A7.** The text below is the original audit snapshot, kept verbatim.

- **[value] Grassland 2F/1P ≠ reference 2F/0P** — every grassland tile produces
  a free hammer; biggest single yield deviation in the game.
- Hills: Humanish flat 1F/2P/0C terrain vs reference hills = plot modifier
  (grass-hill 1F/1P). Net +1P per hill **[value]**. Mountain: workable 0F/1P and
  (per `movement_cost: 0`) impassable? — reference peaks yield nothing and are
  impassable; the +1P is an extension.
- River commerce: reference gives +1C to grass/plains/desert/tundra river tiles;
  Humanish only grass/plains **[value]**.
- Features: forest +1P ✓, jungle −1F ✓, oasis 3F/2C ✓, flood plains 3F ✓ (+1C
  river adjacency dropped), fallout −3/−3/−3 ✓. Feature health percentages
  dropped/rounded: forest +0.5 → +1, jungle −0.25 → 0, flood plains −0.4 → 0
  **[value]**; flood-plains defence −33 is a Humanish addition (reference 0).
- Specialists **[value]**: citizen 0 output ≠ reference +1 hammer; artist 3
  culture ≠ 4 culture +1 research; spy 3 esp ≠ 4 esp +1 research; priest ✓,
  scientist ✓, merchant ✓, engineer ✓. GPP 1/specialist vs reference 3 (with
  reference threshold 100+; scaled model — verify thresholds scale by ⅓ too).
  Settled great people are far weaker and partly re-typed: great_priest
  2 culture ≠ +2P/+5 gold; great_artist 3 culture ≠ +3 gold/+12 culture;
  great_scientist 3 science ≠ +1P/+6 research; great_merchant 3 commerce ≠
  +1F/+6 gold; great_engineer 2P ≠ +3P/+3 research; great_spy 3 esp ≠
  +3 research/+12 esp; great_general +2P has no reference settled yield (it's
  a military instructor: +XP to units built) **[value/semantics]**.
- Great General threshold 30 + 50%/each ✓ matches XML. XP-per-level thresholds
  [0,10,30,60,100,150,210] don't follow the reference's level curve (2,5,10,17,
  26,…) **[value]**. XP caps: `experience_vs_wild_cap 20` ≠ reference barbarian
  cap 10; `animal_xp_lifetime_cap 10` ≠ reference `ANIMAL_MAX_XP_VALUE` **5**
  (game-rules §9.3 cites the reference for 10 — the reference file says 5) **[value, doc wrong]**.
  Max XP per combat 10 (reference) has no Humanish equivalent (`experience_per_
  kill_max 100`).

## 9. Promotions

- **[added]** accuracy1/2, boarding1/2, dogfighting1/2, air_supremacy, escort,
  evasion, withdrawal (reference versions don't exist; reference `accuracy` is
  single-tier).
- **[missing]** ace, ambush, charge, leader, medic3, mobility, range1/2, tactics.
- **[value]** combat6 +10 ≠ +25; flanking2 +10 ≠ +20; interception1/2 +33/+33 ≠
  +10/+20; guerrilla3 lost +50 withdrawal; drill line lost collateral-damage
  protection and the 1/1/2 first-strike/chance split (flat +1/tier); woodsman3
  lost +2 first strikes/heal; morale/navigation "+1 move" ✓ equivalent.
- Combat5's +10% enemy-territory heal and medic tile semantics differ mildly.

## 10. Traits & leaders

See §1.8 for the free-vs-double-speed issue and value diffs. Pairings: 34
societies (= 34 reference civs ✓, one primary leader each; reference has 52
leaders total — the alternates are deliberately out of scope). Three leaders'
trait pairs differ from the reference leader table **[value]**:
- Hammurabi: organized+protective ≠ reference aggressive+organized
- Brennus: creative+spiritual ≠ reference charismatic+spiritual
- Gilgamesh: aggressive+creative ≠ reference creative+protective

## 11. Beliefs, econ orgs, espionage, goodies, civics

- Religions: the 7 reference religions' founding techs all match ✓.
  **[added]** `sun_faith`, `earth_covenant` — and their `holy_site_structure`s
  (`temple_of_sun`, `grove_sanctuary`) **do not exist in structures.json**
  (dangling references), and both have `founding_tech: null` — unfoundable dead
  data **[bug?]**.
- Econ orgs: the 7 reference corporations map over with **changed input sets**
  (sushi drops rice; ethanol swaps rice→wheat; mining drops gold/silver;
  creative-constructions drops the metals; nationalist/coal adds oil)
  **[value]**; outputs are flat per-org rather than per-resource-consumed
  **[semantics]**; maintenance model differs (3 vs reference 100-scale per-city
  formula). **[added]** merchant_guild, overseas_trading_co, nationalist_mutual
  (10 vs 7).
- Espionage: 18/18 missions covered ✓ (already tracked as closed in
  designgaps §5.1).
- Goody huts: all 12 reference outcomes present, but `settler` and `worker`
  rewards have **weight 0** (disabled; reference grants them on low
  difficulties) **[value/missing]**.
- Civics: all 25 reference civics present in `policies.json` ✓, but `tribalism`,
  `slavery`, `serfdom` carry **no effects** — in particular **population
  rush ("whipping") is missing** (reference `HURRY_POP_ANGER`/slavery hurry);
  Humanish rush is gold/GP only. Serfdom's +50% worker speed likewise unmodelled
  (worker-speed effects don't exist).
- Culture: ring thresholds [10,30,60,…,550] vs reference culture levels
  10/100/500/5000/50000 (normal speed) — different curve, no per-speed scaling,
  and the reference's per-culture-level **city defence 20–100%** has no
  Humanish analogue **[value/missing]**.
- Healing rates: settlement 30/friendly 20/allied 15/neutral 5/hostile 0 vs
  reference city 20/friendly 15/neutral 10/enemy 5 **[value]**.
- Growth threshold: 12 + 8·pop vs reference `BASE_CITY_GROWTH_THRESHOLD 20` +
  `CITY_GROWTH_MULTIPLIER 2`·pop **[value]**. Min city distance 3 ≠ reference
  `MIN_CITY_RANGE 2` **[value]**. Combat dice/damage 1000/20 ✓; fortify 5%×5 ✓;
  upgrade cost 20+3/prod ✓ (documented extensions aside); food/citizen 2 ✓.

## 12. Events & quests

`events.json` 143 + `quests.json` 18 = 161 implemented vs the reference's ~177
unique events (197 triggers incl. `_1/_2` variants); game-data §21 tracks the
per-event status — the remaining ◻ rows are the gap. All names map to base
reference triggers (verified separately; no mod content).

## 13. Feature-level gaps not (or only partly) in the data tables

Already tracked in `missing-engine-features.md` / `designgaps.md` are the
engine-side stubs; the following are *reference* mechanics with no Humanish
model at all, collected here for completeness:

1. **Inflation** (per-speed + handicap) — no model.
2. **Population rush / whipping** under Slavery; **serfdom worker speed**.
3. **Golden-age length pace scaling** (`iGoldenAgePercent`).
4. **Culture-level city defence** (20–100%).
5. **The Internet & SDI projects** (and nuke interception %).
6. **Machine Gun / War Elephant / Lion** units.
7. **Chance first strikes** as a stat anywhere in the model.
8. **AND-tech / AND+OR-resource unit prereqs** (schema).
9. **Per-resource corporation output scaling**.
10. **Settler/worker goody outcomes** (present but weight 0).
11. **anarchy pace scaling** (`iAnarchyPercent`).

---

*Generated by a scripted audit; re-run by diffing `data/*.json` against the
layered original-reference tables (highest layer wins). When retuning any table toward reference
parity, prefer citing the reference value in the commit message.*
