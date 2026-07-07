---
title: "Game Data"
role: design
summary: >
  Content tables for all data-driven game entities: technologies, factions, leaders,
  units, buildings, wonders, civics, religions, resources, terrain, improvements,
  promotions, Great People, and global constants. Also documents the JSON field
  schemas for units.json, structures.json, improvements.json, and promotions.json
  (§19), and the serialized state fields for the Player, Settlement, and Unit engine
  entities (§19.5). The JSON files in data/ are authoritative for numeric values;
  this document describes their intended design-level content.
audience:
  - Coding agents reading or modifying data/*.json
  - Contributors adding new units, buildings, technologies, civics, or promotions
  - Reviewers checking data tables against the design intent
key_files:
  - data/units.json              # unit definitions (§5; field schema §19.1)
  - data/structures.json         # buildings and wonders (§6–§7; field schema §19.2)
  - data/technologies.json       # tech tree (§2)
  - data/policies.json           # civics / policies (§8)
  - data/leaders_traits.json     # factions, leaders, traits (§3–§4)
  - data/promotions.json         # promotion definitions (§13; field schema §19.4)
  - data/improvements.json       # tile improvements (§12; field schema §19.3)
  - data/terrains.json           # terrain types (§11)
  - data/resources.json          # strategic, luxury, and bonus resources (§10)
  - data/constants.json          # global numeric constants (§15)
  - data/beliefs.json            # religion belief types
  - data/econ_orgs.json          # corporation definitions (§14.6)
  - data/resolutions.json        # assembly resolution catalogue (§18.3)
  - data/win_conditions.json     # win condition definitions (§16)
  - data/ages.json               # era definitions and growth scale (§1, §2.1)
  - data/paces.json              # game pace multipliers (§15.6)
  - data/world_sizes.json        # map size presets (§15.8)
  - data/difficulties.json       # difficulty level modifiers (§15.9)
  - data/map_types.json          # map generation type configurations
  - data/hotkeys.json            # rebindable key→ControlType bindings
  - data/events.json             # scripted/random event definitions (§9)
  - src/core/data_db.gd          # loads, validates, and exposes all tables
sections:
  "§1   Eras":                   "Era index table (Ancient–Future) and growth-scale constants"
  "§2   Technologies":           "Full tech tree by era with costs and prerequisites"
  "§3   Factions":               "All 34 playable societies with leaders and starting techs"
  "§4   Leaders & Traits":       "11 traits and 52 leaders; trait mechanical effects"
  "§5   Units":                  "Non-combat, land, naval, and air units; faction-unique units"
  "§6   Buildings":              "Standard, religion-specific, Great Person, and faction-unique buildings"
  "§7   Wonders":                "World wonders and national wonders with costs and effects"
  "§8   Civics":                 "Five civic categories, 26 policies, mechanical effects per civic"
  "§9   Religions":              "Seven belief types and their founding/spread rules"
  "§10  Resources":              "Strategic, luxury, and bonus resources with yields"
  "§11  Terrain & Features":     "Base terrain types, landform modifiers, and overlaid features"
  "§12  Improvements":           "Tile improvements, build times, yields, and maturation chain"
  "§13  Promotions":             "All promotion lines with prerequisites and effects"
  "§14  Great People":           "GP types, thresholds, Golden Ages, specialist slots, corporations"
  "§15  Global Constants":       "Combat formulas, growth formulas, healing rates, difficulty scales"
  "§16  Victory Conditions":     "Seven win condition types (incl. Score) and their trigger criteria"
  "§17  Spaceship Parts":        "Space Race component list"
  "§18  Assembly & Resolutions": "World-government assembly mechanics and resolution catalogue (provisional)"
  "§19  Data field reference":   "JSON field schemas (§19.1–§19.4) and serialized entity fields (§19.5) — provisional"
  "§21  Random events":          "events.json record schema, selection framework, prereq/effect vocabulary, and the full event (1–174) + quest (1–18) catalogue"
  "§22  Specialists":            "specialists.json: 14 specialist types with output vectors, GP-point sources, and slot rules"
  "§23  Corporations":           "econ_orgs.json: corporation definitions with HQ, executive unit, input resources, maintenance, and spread"
  "§24  Goody huts":             "goodies.json: complete 12-record weighted discovery-site reward catalogue with per-difficulty weight overrides and map placement (complete)"
  "§25  Espionage missions":     "espionage_missions.json: intel mission catalogue — 13 active missions run from the alliance screen and by spy units on city tiles; 5 passive intelligence missions as standing EP thresholds (§25.6) with the information-fog rules they lift"
  "§26  Diplomacy attitude & memory": "diplomacy.json: AI attitude levels, live factors, decaying memory kinds, deal gates (incomplete — no denial-reason layer)"
  "§27  Score victory":          "win_conditions.json score condition: absolute-threshold immediate win and its scoring formula"
  "§28  Map start-fairness":     "MapGen normalize pass and constants for capital-surroundings fairness (complete — all 9 reference steps + BonusBalancer)"
editorial_rule: >
  Modify only with explicit user consent. The JSON tables in data/ are the
  authoritative numeric values; this document describes design intent. When adding
  a new data entry, add the corresponding row here. When adding a new JSON field,
  add it to the relevant §19 field-reference subsection.
---

# Game Data Reference

> Technology prerequisites are approximate and should be verified against authoritative data files
> before finalising an implementation. All other values (costs, strengths, effects) are as designed.

---

## 1. Eras

| # | Era Name | Notes |
|---|----------|-------|
| 0 | Ancient | Starting era; most factions begin here |
| 1 | Classical | Iron working, philosophy, construction |
| 2 | Medieval | Feudalism, theology, engineering |
| 3 | Renaissance | Gunpowder, printing, astronomy |
| 4 | Industrial | Steam, assembly, electricity |
| 5 | Modern | Flight, computers, nuclear |
| 6 | Future | Robotics, genetics, fusion |

---

## 2. Technologies

Costs are in research points (beakers).

### 2.1 Ancient Era — no-prerequisite pool

These six techs have **no prerequisites** and form the starting tech pool — each faction begins with two of them:

| Tech | Cost | Unlocks |
|------|------|---------|
| Agriculture | 60 | Farm improvement |
| Fishing | 40 | Work Boat unit |
| Hunting | 40 | Scout, Spearman; Camp improvement |
| Mining | 50 | Mine improvement |
| Mysticism | 50 | Monument, Stonehenge wonder |
| The Wheel | 60 | Chariot unit, Road improvement |

### 2.2 Ancient Era — require above

| Tech | Cost | Prerequisites | Unlocks |
|------|------|---------------|---------|
| Animal Husbandry | 100 | The Wheel | Pasture; reveals Horse resource |
| Archery | 60 | Hunting | Archer; upgrades to Crossbowman/Longbowman path |
| Bronze Working | 120 | Mining | Axeman; Slavery civic; forest chopping |
| Calendar | 350 | Mysticism + Sailing | Plantation improvement; centers world map; obsoletes Stonehenge/Obelisk |
| Iron Working | 200 | Bronze Working | Swordsman; reveals Iron; jungle clearing |
| Masonry | 80 | Mining | Walls, Quarry; enables Pyramids, Great Wall, Stonehenge |
| Meditation | 80 | Mysticism | Monastery; founds Buddhism |
| Monotheism | 120 | Polytheism + Meditation | Organized Religion civic; founds Judaism |
| Polytheism | 100 | Mysticism + Hunting | Parthenon; founds Hinduism |
| Pottery | 80 | Agriculture | Granary, Cottage improvement |
| Priesthood | 60 | Mysticism | Temple, Oracle wonder |
| Sailing | 100 | Fishing | Galley, Lighthouse; coastal trade |
| Writing | 120 | Pottery | Library; enables Open Borders |

### 2.3 Classical Era

| Tech | Cost | Prerequisites | Unlocks |
|------|------|---------------|---------|
| Aesthetics | 300 | Literature + Polytheism | Parthenon, Statue of Zeus, Shwedagon Paya |
| Alphabet | 300 | Writing | Technology trading between factions |
| Code of Laws | 350 | Alphabet | Courthouse, Chichen Itza; Caste System civic; founds Confucianism |
| Compass | 400 | Masonry + Sailing | Explorer unit, Harbor |
| Construction | 350 | Masonry + Mathematics | War Elephant, Catapult, Colosseum; bridge crossing |
| Currency | 400 | Metal Casting + Mathematics | Market, Grocer; +1 trade route; gold trading |
| Drama | 300 | Aesthetics | Theatre, Globe Theatre national wonder; culture slider |
| Horseback Riding | 250 | Animal Husbandry + The Wheel | Horse Archer, enables Knight/Cavalry line |
| Literature | 200 | Alphabet | Heroic Epic, National Epic, Great Library |
| Mathematics | 250 | Alphabet | Aqueduct, Hanging Gardens, Fort; +50% forest chopping |
| Metal Casting | 450 | Bronze Working | Trireme, Forge, Colossus, Workshop improvement |
| Monarchy | 300 | Code of Laws + Metal Casting | Winery improvement; Hereditary Rule civic |

### 2.4 Medieval Era

| Tech | Cost | Prerequisites | Unlocks |
|------|------|---------------|---------|
| Banking | 700 | Currency + Guilds | Bank; Mercantilism civic |
| Civil Service | 800 | Alphabet + Code of Laws | Maceman; Bureaucracy civic; farms spread irrigation without rivers |
| Divine Right | 1200 | Theology + Monotheism | Versailles, Spiral Minaret; founds Islam |
| Engineering | 1000 | Construction + Iron Working | Pikeman, Trebuchet, Castle, Hagia Sophia; +1 road movement |
| Feudalism | 700 | Monarchy | Longbowman; Vassalage, Serfdom civics |
| Guilds | 1000 | Feudalism + Currency | Knight (with Horseback Riding) |
| Machinery | 700 | Engineering + Metal Casting | Crossbowman, Maceman, Windmill, Watermill improvements |
| Music | 600 | Drama + Calendar | Cathedral, Sistine Chapel; building culture; grants Great Artist |
| Optics | 600 | Compass + Mathematics | Caravel; +1 water visibility |
| Paper | 600 | Alphabet | Map trading |
| Philosophy | 800 | Literature + Meditation | Angkor Wat, Pacifism civic; founds Taoism |
| Theology | 500 | Priesthood + Monotheism | Hagia Sophia, Apostolic Palace; Theocracy civic; founds Christianity |

### 2.5 Renaissance Era

| Tech | Cost | Prerequisites | Unlocks |
|------|------|---------------|---------|
| Astronomy | 2000 | Optics + Mathematics | Galleon, Frigate, Observatory; ocean trade; obsoletes Colossus |
| Chemistry | 1800 | Gunpowder + Metal Casting | Privateer, Frigate; +1 Workshop yield |
| Constitution | 2000 | Printing Press + Liberalism | Jail; Representation civic |
| Corporation | 1600 | Economics + Metal Casting | Wall Street national wonder; +1 trade route; enables Corporations; obsoletes Great Lighthouse |
| Democracy | 2800 | Printing Press + Nationalism | Security Bureau; Statue of Liberty; Universal Suffrage, Emancipation civics |
| Economics | 1400 | Guilds + Banking | Customs House; Free Market civic; grants Great Merchant; obsoletes Castle |
| Education | 1800 | Philosophy + Paper | University, Oxford University national wonder |
| Gunpowder | 1200 | Iron Working + Metal Casting | Musketman |
| Liberalism | 1400 | Education + Philosophy | Free Speech, Free Religion civics; grants 1 free technology |
| Military Science | 2000 | Engineering + Gunpowder | Grenadier, Ship of the Line, Military Academy national wonder |
| Military Tradition | 2000 | Horseback Riding + Feudalism | Cuirassier, Cavalry; West Point national wonder; defensive pacts |
| Nationalism | 1800 | Gunpowder + Education | Hermitage national wonder, Taj Mahal; Nationhood civic |
| Printing Press | 1600 | Machinery + Paper | +1 Commerce from Villages/Towns |
| Replaceable Parts | 1800 | Engineering + Machinery | Lumbermill improvement; +1 yield from mills |
| Rifling | 2400 | Gunpowder + Chemistry | Rifleman; obsoletes Chichen Itza, Walls |

### 2.6 Industrial Era

| Tech | Cost | Prerequisites | Unlocks |
|------|------|---------------|---------|
| Artillery | 4000 | Rifling + Engineering | Artillery, Anti-Tank, Mobile Artillery units |
| Assembly Line | 5000 | Industrialism + Electricity | Infantry, Factory, Coal Plant, Pentagon wonder |
| Biology | 3600 | Scientific Method | Farm without irrigation; +1 Food from farms |
| Combustion | 3600 | Steam Power + Physics | Transport, Destroyer, Submarine, Well improvement; obsoletes Whale |
| Communism | 2800 | Philosophy + Scientific Method | Scotland Yard national wonder, Kremlin; State Property civic; permanent alliances |
| Electricity | 4500 | Steam Power + Scientific Method | Bunker, Bomb Shelter, Broadway wonder; +1 Commerce from windmills, +2 from watermills |
| Fascism | 2400 | Nationalism + Military Science | Paratrooper, Mt. Rushmore national wonder; Police State civic; grants Great General |
| Fission | 5500 | Electricity + Physics | ICBM, Tactical Nuke, Nuclear Plant, Manhattan Project national wonder |
| Industrialism | 6500 | Electricity + Assembly Line | Marine, Tank, Battleship, Carrier, Industrial Park; reveals Aluminum; obsoletes Ivory |
| Medicine | 4500 | Biology + Scientific Method | Hospital, Red Cross national wonder; Environmentalism civic |
| Physics | 4000 | Astronomy + Education | Airship; reveals Uranium; grants Great Scientist |
| Railroad | 4500 | Steam Power + Industrialism | Railroad improvement (3× movement); Machine Gun unit |
| Scientific Method | 2400 | Paper + Astronomy | Forest Preserve improvement; reveals Oil; obsoletes Great Library, Monastery |
| Steam Power | 3200 | Engineering + Physics | Ironclad, Levee improvement; reveals Coal; +50% faster improvement building; obsoletes Hagia Sophia |
| Steel | 2800 | Iron Working + Industrialism | Cannon, Ironclad, Drydock, Ironworks national wonder |

### 2.7 Modern Era

| Tech | Cost | Prerequisites | Unlocks |
|------|------|---------------|---------|
| Advanced Flight | 5000 | Flight + Rocketry | Gunship; obsoletes Stable |
| Composites | 7500 | Computers + Plastics | Modern Armor, Jet Fighter, SS Casing |
| Computers | 6500 | Electricity + Scientific Method | Modern Armor, Laboratory, The Internet project; obsoletes Angkor Wat, Spiral Minaret, University of Sankore |
| Ecology | 5500 | Biology + Combustion | Recycling Center, SS Life Support; Environmentalism civic; fallout cleanup |
| Fiber Optics | 7500 | Computers + Satellites | The Internet, SS Cockpit; obsoletes Kremlin |
| Flight | 5000 | Combustion + Physics | Fighter, Bomber, Airport |
| Genetics | 7000 | Medicine + Computers | SS Stasis Chamber; +1 Health in all cities |
| Laser | 7000 | Composites + Plastics | Mobile Artillery, Mobile SAM, SDI |
| Mass Media | 3600 | Radio + Electricity | Broadcast Tower, Hollywood wonder, United Nations wonder |
| Plastics | 7000 | Chemistry + Combustion | Hydro Plant, Three Gorges Dam wonder, Offshore Platform; obsoletes Fur |
| Radio | 6000 | Electricity + Mass Media | Submarine, Bomber, Eiffel Tower wonder, Rock 'n' Roll wonder |
| Refrigeration | 4000 | Medicine + Combustion | Supermarket; +1 movement for naval units |
| Robotics | 8000 | Computers + Laser | Mechanized Infantry, Stealth Bomber, Stealth Destroyer, Space Elevator wonder, SS Docking Bay |
| Rocketry | 5000 | Flight + Physics | SAM Infantry, Gunship, Guided Missile, Tactical Nuke, ICBM, Apollo Program national wonder, SS Casing |
| Satellites | 6000 | Rocketry + Computers | SS Docking Bay, Space Elevator wonder; reveals entire world map |
| Stealth | 8000 | Computers + Fiber Optics | Stealth Bomber, Stealth Destroyer |
| Superconductors | 6500 | Physics + Robotics | Laboratory, SS Thrusters |

### 2.8 Future Era

| Tech | Cost | Prerequisites | Unlocks |
|------|------|---------------|---------|
| Fusion | 8000 | Robotics + Superconductors | SS Engine; grants Great Engineer |
| Future Tech | 8000 | Fusion + Genetics | +1 Health and +1 Happiness in all cities (repeatable) |
| Genetics | 7000 | Medicine + Computers | SS Stasis Chamber; +1 Health in all cities |
| Stealth | 8000 | Computers + Fiber Optics | Stealth Bomber, Stealth Destroyer |

---

## 3. Factions

34 factions total: 18 in the core release, 6 added in the first expansion, 10 added in the second expansion.

Each faction begins with two technologies from the starting pool and has one unique unit and one unique building.

**Starting units.** Every faction opens with exactly two units: one **Settler** plus a single escort unit determined by its starting techs — a **Scout** if either starting tech is **Hunting** (which unlocks the Scout), otherwise a **Warrior** by default. (Mechanically this is a small data-driven rule: `starting_units_base` + `starting_unit_by_tech` + `starting_unit_default` in `data/constants.json`, evaluated against each society's `starting_techs`; see `DataDB.starting_units_for_techs`.) Thus the Hunting factions below (Aztec, German, Greek, Persian, Mongolian, Russian, Celtic, Viking, Zulu, Ethiopian, Holy Roman, Khmer) begin with a Scout, and all others with a Warrior.

**Starting building (capital Palace).** A faction's **first city is its capital and is founded with a [Palace](#palace) already built** (see §Buildings). The Palace is the national wonder that *defines* the capital, granting the capital's bonuses (reduced maintenance, +1 Happiness, +4 Espionage, +8 Commerce) from turn one. Seeding it is applied in `SimFacade._cmd_found_settlement`: the first settlement a player founds gets `"palace"` appended to its `structures`, provided the data tables define a `palace` entry.

The capital is **wherever the Palace is** (`TurnEngine._find_capital` returns the city holding the Palace, falling back to the earliest-founded surviving city only in the gap before relocation). The Palace can move:

* **Relocation on loss.** If a player loses the city that holds the Palace, `TurnEngine._ensure_capital_palace` (run at the top of every `player_step`, before maintenance/bureaucracy read the capital) rebuilds the Palace **for free** in the player's new capital — the earliest-founded surviving city — so a player who still has cities is never left capital-less.
* **Relocation by choice.** A player may **build a new Palace in another city** (queue the `palace` structure there); on completion `TurnEngine._complete_item` strips the Palace from the player's other cities, so the newly built city becomes the capital. There is therefore always exactly one Palace (hence one capital) per player.

| # | Faction | Release | Starting Tech 1 | Starting Tech 2 | Unique Unit | Unique Building |
|---|---------|---------|-----------------|-----------------|-------------|-----------------|
| 1 | American | Core | Fishing | Agriculture | Navy SEAL | Mall |
| 2 | Arabian | Core | Mysticism | The Wheel | Camel Archer | Madrassa |
| 3 | Aztec | Core | Hunting | Mysticism | Jaguar | Sacrificial Altar |
| 4 | Chinese | Core | Agriculture | Mining | Cho-Ko-Nu | Pavilion |
| 5 | Egyptian | Core | Agriculture | The Wheel | War Chariot | Obelisk |
| 6 | English | Core | Fishing | Mining | Redcoat | Stock Exchange |
| 7 | French | Core | Agriculture | The Wheel | Musketeer | Salon |
| 8 | German | Core | Hunting | Mining | Panzer | Assembly Plant |
| 9 | Greek | Core | Fishing | Hunting | Phalanx | Odeon |
| 10 | Incan | Core | Agriculture | Mysticism | Quechua | Terrace |
| 11 | Indian | Core | Mysticism | Mining | Fast Worker | Mausoleum |
| 12 | Japanese | Core | Fishing | The Wheel | Samurai | Shale Plant |
| 13 | Malinese | Core | Mining | The Wheel | Skirmisher | Mint |
| 14 | Mongolian | Core | Hunting | The Wheel | Keshik | Ger |
| 15 | Native American | Core | Fishing | Agriculture | Dog Soldier | Totem Pole |
| 16 | Persian | Core | Agriculture | Hunting | Immortal | Apothecary |
| 17 | Roman | Core | Fishing | Mining | Praetorian | Forum |
| 18 | Russian | Core | Hunting | Mining | Cossack | Research Institute |
| 19 | Carthaginian | Exp. 1 | Fishing | Mining | Numidian Cavalry | Cothon |
| 20 | Celtic | Exp. 1 | Hunting | Mysticism | Gallic Warrior | Dun |
| 21 | Korean | Exp. 1 | Mysticism | Mining | Hwacha | Seowon |
| 22 | Ottoman | Exp. 1 | Agriculture | The Wheel | Janissary | Hammam |
| 23 | Viking | Exp. 1 | Fishing | Hunting | Berserker | Trading Post |
| 24 | Zulu | Exp. 1 | Agriculture | Hunting | Impi | Ikhanda |
| 25 | Babylonian | Exp. 2 | Agriculture | The Wheel | Bowman | Garden |
| 26 | Byzantine | Exp. 2 | The Wheel | Mysticism | Cataphract | Hippodrome |
| 27 | Dutch | Exp. 2 | Fishing | Agriculture | East Indiaman | Dike |
| 28 | Ethiopian | Exp. 2 | Hunting | Mining | Oromo Warrior | Stele |
| 29 | Holy Roman | Exp. 2 | Hunting | Mysticism | Landsknecht | Rathaus |
| 30 | Khmer | Exp. 2 | Hunting | Mining | Ballista Elephant | Baray |
| 31 | Mayan | Exp. 2 | Mysticism | Mining | Holkan | Ball Court |
| 32 | Portuguese | Exp. 2 | Fishing | Mining | Carrack | Feitoria |
| 33 | Sumerian | Exp. 2 | Agriculture | The Wheel | Vulture | Ziggurat |
| 34 | Spanish | Core | Fishing | Mysticism | Conquistador | Citadel |

---

## 4. Leaders & Traits

### 4.1 Traits (11 total)

| Trait | Free Structures (−50% cost) | Unit Effect | City/Economy Effect |
|-------|----------------------------|-------------|---------------------|
| Aggressive | Barracks, Drydock | Free Combat I for all units | — |
| Charismatic | — | +25% XP from combat; units need 25% less XP per promotion | +1 Happiness per city |
| Creative | Library, Theatre, Colosseum | — | +2 Culture per city per turn |
| Expansive | Granary, Harbor | — | +2 Health in all cities |
| Financial | — | — | +1 Commerce on any tile producing 2+ Commerce |
| Imperialistic | Settler (50% cheaper) | +50% Great General emergence | — |
| Industrious | Forge | — | +50% Wonder production speed |
| Organized | Courthouse, Lighthouse | — | Civic upkeep reduced 50% |
| Philosophical | — | — | +100% Great Person birth rate in all cities |
| Protective | Walls, Castle | Free Drill I + City Garrison I for all units | — |
| Spiritual | — | — | No anarchy when switching civics or state religion |

### 4.2 Leaders

#### Core Leaders (26)

| Leader | Faction | Trait 1 | Trait 2 | Favorite Civic |
|--------|---------|---------|---------|----------------|
| Alexander | Greek | Aggressive | Philosophical | Police State |
| Asoka | Indian | Organized | Spiritual | Universal Suffrage |
| Bismarck | German | Expansive | Industrious | Nationalism |
| Catherine | Russian | Creative | Imperialistic | Police State |
| Cyrus | Persian | Imperialistic | Charismatic | Hereditary Rule |
| Elizabeth | English | Financial | Philosophical | Free Speech |
| Frederick | German | Organized | Philosophical | Free Speech |
| Gandhi | Indian | Philosophical | Spiritual | Democracy |
| Genghis Khan | Mongolian | Aggressive | Imperialistic | Hereditary Rule |
| Hatshepsut | Egyptian | Creative | Spiritual | Theocracy |
| Huayna Capac | Incan | Financial | Industrious | Representation |
| Isabella | Spanish | Expansive | Spiritual | Theocracy |
| Julius Caesar | Roman | Organized | Imperialistic | Bureaucracy |
| Kublai Khan | Mongolian | Aggressive | Creative | Hereditary Rule |
| Louis XIV | French | Creative | Industrious | Police State |
| Mansa Musa | Malinese | Financial | Spiritual | Free Religion |
| Mao Zedong | Chinese | Expansive | Protective | Police State |
| Montezuma | Aztec | Aggressive | Spiritual | Theocracy |
| Napoleon | French | Organized | Charismatic | Nationhood |
| Peter | Russian | Expansive | Philosophical | Representation |
| Qin Shi Huang | Chinese | Industrious | Protective | Bureaucracy |
| Roosevelt | American | Industrious | Organized | Representation |
| Saladin | Arabian | Spiritual | Protective | Theocracy |
| Tokugawa | Japanese | Aggressive | Protective | Hereditary Rule |
| Victoria | English | Financial | Imperialistic | Free Market |
| Washington | American | Expansive | Charismatic | Democracy |

#### First Expansion Leaders (10 added)

| Leader | Faction | Trait 1 | Trait 2 | Notes |
|--------|---------|---------|---------|-------|
| Augustus Caesar | Roman | Organized | Imperialistic | Alternate Roman leader |
| Brennus | Celtic | Creative | Spiritual | Primary Celtic leader |
| Churchill | English | Charismatic | Protective | Third English leader |
| Hannibal | Carthaginian | Financial | Charismatic | Primary Carthaginian leader |
| Mehmed II | Ottoman | Imperialistic | Organized | Primary Ottoman leader |
| Ragnar | Viking | Aggressive | Financial | Primary Viking leader |
| Ramesses II | Egyptian | Creative | Spiritual | Alternate Egyptian leader |
| Shaka | Zulu | Aggressive | Expansive | Primary Zulu leader |
| Stalin | Russian | Industrious | Aggressive | Third Russian leader |
| Wang Kon | Korean | Financial | Protective | Primary Korean leader |

#### Second Expansion Leaders (16 added)

| Leader | Faction | Trait 1 | Trait 2 | Notes |
|--------|---------|---------|---------|-------|
| Boudica | Celtic | Aggressive | Charismatic | Alternate Celtic leader |
| Charlemagne | Holy Roman | Protective | Imperialistic | Primary Holy Roman leader |
| Darius I | Persian | Financial | Organized | Alternate Persian leader |
| De Gaulle | French | Charismatic | Industrious | Third French leader |
| Gilgamesh | Sumerian | Aggressive | Creative | Primary Sumerian leader |
| Hammurabi | Babylonian | Organized | Protective | Primary Babylonian leader |
| Joao II | Portuguese | Imperialistic | Expansive | Primary Portuguese leader |
| Justinian I | Byzantine | Spiritual | Imperialistic | Primary Byzantine leader |
| Lincoln | American | Financial | Philosophical | Third American leader |
| Pacal II | Mayan | Financial | Philosophical | Primary Mayan leader |
| Pericles | Greek | Creative | Philosophical | Alternate Greek leader |
| Sitting Bull | Native American | Philosophical | Protective | Primary Native American leader |
| Suleiman | Ottoman | Philosophical | Imperialistic | Alternate Ottoman leader |
| Suryavarman II | Khmer | Creative | Expansive | Primary Khmer leader |
| Willem van Oranje | Dutch | Creative | Financial | Primary Dutch leader |
| Zara Yaqob | Ethiopian | Organized | Creative | Primary Ethiopian leader |

---

## 5. Units

### 5.1 Non-Combat Units

| Unit | Move | Cost | Tech Req | Function |
|------|------|------|----------|----------|
| Settler | 1 | 100 | — | Founds new cities; consumed on use |
| Worker | 1 | 30 | — | Builds tile improvements; 4 turns base per improvement |
| Work Boat | 2 | 15 | Fishing | Builds Fishing Boats, Whaling Boats; consumed on use |
| Missionary (×7) | 2 | 60 | Religion founded | Spreads state religion to cities |
| Executive (×9) | 2 | 80 | Corporation founded | Spreads corporations to cities |
| Spy | 1 | 60 | — | Espionage missions in foreign cities |
| Great Person (×7) | 2 | — | Specialist points | See Section 14 |

### 5.2 Land Combat Units

Strength is base combat strength. All land units start with 0 promotions unless otherwise noted. Upgrade costs = 20 gold × era gap.

#### Melee / Infantry Line

| Unit | Str | Move | Cost | Tech | Resource | Special | Upgrades From | Upgrades To |
|------|-----|------|------|------|----------|---------|---------------|-------------|
| Warrior | 2 | 1 | 15 | — | — | — | — | Axeman, Swordsman, Spearman |
| Axeman | 5 | 1 | 35 | Bronze Working | Copper | — | Warrior | Maceman |
| Swordsman | 6 | 1 | 40 | Iron Working | Iron | — | Warrior | Maceman |
| Pikeman | 6 | 1 | 60 | Engineering | — | +100% vs Mounted | Spearman | Musketman, Rifleman |
| Maceman | 8 | 1 | 70 | Machinery + Civil Service | — | — | Axeman/Swordsman | Rifleman, Grenadier |
| Grenadier | 11 | 1 | 100 | Military Science | Gunpowder | +50% vs cities | Maceman | Rifleman |
| Musketman | 9 | 1 | 80 | Gunpowder | — | — | Pikeman/Crossbowman | Rifleman |
| Rifleman | 14 | 1 | 110 | Rifling | — | — | Musketman/Grenadier | Infantry |
| Infantry | 20 | 1 | 130 | Assembly Line | — | — | Rifleman | Mechanized Infantry |
| Paratrooper | 16 | 1 | 120 | Fascism | — | Can paradrop 5 tiles | Infantry | Mechanized Infantry |
| Marine | 18 | 1 | 140 | Industrialism | — | Amphibious (no penalty) | Infantry | Mechanized Infantry |
| Mechanized Infantry | 28 | 2 | 170 | Robotics | — | — | Infantry | — |

#### Spear / Anti-Mounted Line

| Unit | Str | Move | Cost | Tech | Resource | Special | Upgrades To |
|------|-----|------|------|------|----------|---------|-------------|
| Spearman | 3 | 1 | 30 | Hunting | — | +100% vs Mounted | Pikeman, Maceman |

#### Archery Line

| Unit | Str | Move | Cost | Tech | Resource | Special | Upgrades To |
|------|-----|------|------|------|----------|---------|-------------|
| Archer | 3 | 1 | 25 | Archery | — | 1 First Strike | Crossbowman, Longbowman |
| Longbowman | 6 | 1 | 60 | Feudalism | — | 2 First Strikes | Rifleman |
| Crossbowman | 6 | 1 | 60 | Machinery + Archery | — | 1 First Strike | Musketman, Rifleman |

#### Mounted Line

| Unit | Str | Move | Cost | Tech | Resource | Special | Upgrades To |
|------|-----|------|------|------|----------|---------|-------------|
| Chariot | 4 | 2 | 30 | The Wheel | Horse | First Strike Immunity | Knight |
| Horse Archer | 6 | 2 | 50 | Horseback Riding | Horse | — | Cavalry |
| Knight | 10 | 2 | 90 | Guilds + Horseback Riding | Horse + Iron | — | Cavalry, Cuirassier |
| Cuirassier | 12 | 2 | 110 | Military Tradition + Rifling | Horse | — | Cavalry |
| Cavalry | 15 | 2 | 120 | Military Tradition | Horse | +10% withdrawal | Gunship, Tank |
| Gunship | 20 | 4 | 160 | Advanced Flight | — | Air unit; anti-armor | — |

#### Siege Units

| Unit | Str | Move | Cost | Tech | Special | Upgrades To |
|------|-----|------|------|------|---------|-------------|
| Catapult | 5 | 1 | 50 | Construction | Splash; cannot kill (leaves 1 HP); +200% vs cities | Trebuchet |
| Trebuchet | 8 | 1 | 80 | Engineering | Splash; cannot kill; +200% vs cities | Cannon |
| Cannon | 12 | 1 | 100 | Steel | Splash; cannot kill; +200% vs cities | Artillery |
| Artillery | 16 | 1 | 120 | Artillery tech | Splash; cannot kill; +200% vs cities | Mobile Artillery |
| Mobile Artillery | 16 | 2 | 165 | Laser | Splash; cannot kill; +200% vs cities | — |
| Anti-Tank | 12 | 1 | 90 | Artillery tech | +100% vs Armored | Mobile SAM |
| Mobile SAM | 20 | 2 | 150 | Laser | +100% vs Air units | — |

#### Modern Ground

| Unit | Str | Move | Cost | Tech | Resource | Special | Upgrades To |
|------|-----|------|------|------|----------|---------|-------------|
| Tank | 28 | 2 | 180 | Rifling + Industrialism | Oil | — | Modern Armor |
| Modern Armor | 40 | 2 | 250 | Robotics + Composites | Oil | — | — |
| SAM Infantry | 12 | 1 | 90 | Rocketry | — | +100% vs Air | — |

#### Explorers

| Unit | Str | Move | Cost | Tech | Special |
|------|-----|------|------|------|---------|
| Scout | 1 | 2 | 15 | Hunting | +50% hills defense bonus |
| Explorer | 1 | 2 | 30 | Compass | Can move through all terrain |

### 5.3 Naval Units

| Unit | Str | Move | Cost | Tech | Cargo | Special | Upgrades To |
|------|-----|------|------|------|-------|---------|-------------|
| Galley | 2 | 2 | 30 | Sailing | 1 | Coastal only | Trireme, Caravel |
| Trireme | 5 | 3 | 50 | Metal Casting | — | — | Caravel |
| Caravel | 6 | 4 | 75 | Optics | — | Can cross ocean | Galleon, Frigate |
| Galleon | 8 | 4 | 90 | Astronomy | 2 units | — | Transport |
| Frigate | 18 | 4 | 130 | Chemistry | — | — | Destroyer |
| Privateer | 10 | 5 | 80 | Chemistry | — | Can plunder trade | Destroyer |
| Ship of the Line | 24 | 4 | 160 | Military Science | — | — | Destroyer |
| Ironclad | 22 | 4 | 150 | Steam Power | — | Requires Coal | Destroyer |
| Transport | 18 | 6 | 200 | Combustion | 4 units | — | — |
| Destroyer | 30 | 7 | 200 | Combustion | — | — | Stealth Destroyer |
| Submarine | 32 | 6 | 180 | Industrialism | — | Invisible to most units | Attack Submarine |
| Battleship | 40 | 6 | 225 | Industrialism | — | Can bombard coast | — |
| Carrier | 18 | 6 | 220 | Industrialism | 4 air units | — | — |
| Attack Submarine | 40 | 6 | 250 | Rocketry | — | Invisible | — |
| Stealth Destroyer | 50 | 7 | 300 | Stealth | — | — | — |
| Missile Cruiser | 45 | 7 | 280 | Satellites | — | +100% vs Air | — |

### 5.4 Air Units

Air units are based in cities or carriers; they fly missions without moving permanently.

| Unit | Str | Cost | Tech | Resource | Intercept Str | Special | Upgrades To |
|------|-----|------|------|----------|---------------|---------|-------------|
| Fighter | 12 | 100 | Flight | Oil | 35 | Intercepts enemy air | Jet Fighter |
| Jet Fighter | 22 | 180 | Advanced Flight | Oil | 60 | — | — |
| Bomber | 8 | 120 | Flight | Oil | — | Area bomb; 8 tiles range | Stealth Bomber |
| Stealth Bomber | 24 | 250 | Stealth | Oil | — | Evades interception | — |
| Guided Missile | — | 50 | Rocketry | — | — | 1-use; collateral damage | — |
| Tactical Nuke | — | 250 | Fission | Uranium | — | 1-use; massive AoE | — |
| ICBM | — | 350 | Rocketry + Fission | Uranium | — | 1-use; global range | — |

### 5.5 Faction-Unique Units

Each faction's unique unit replaces a standard unit and is only available to that faction.

| Faction | Unique Unit | Replaces | Str | Move | Cost | Special Advantages |
|---------|-------------|----------|-----|------|------|--------------------|
| American | Navy SEAL | Marine | 18 | 1 | 140 | Starts with March; 1–2 First Strikes; Amphibious |
| Arabian | Camel Archer | Knight | 10 | 2 | 90 | No Horse required; First Strike Immunity; +50% vs Melee; desert movement |
| Aztec | Jaguar | Swordsman | 5 | 2 | 35 | No Iron required; heals +10 HP after kills; forest/jungle move at normal cost |
| Babylonian | Bowman | Archer | 4 | 1 | 30 | Starts with Drill I + City Garrison I |
| Byzantine | Cataphract | Knight | 10 | 2 | 90 | Starts with Shock I; +25% vs Melee |
| Carthaginian | Numidian Cavalry | Horse Archer | 6 | 2 | 50 | Starts with Flanking I; +25% withdrawal |
| Celtic | Gallic Warrior | Swordsman | 8 | 1 | 60 | No Iron required; starts with Guerrilla I |
| Chinese | Cho-Ko-Nu | Crossbowman | 6 | 1 | 60 | 2 First Strikes; 1 withdrawal chance |
| Dutch | East Indiaman | Galleon | 8 | 5 | 100 | Carries 3 units; +1 trade route; +1 Food on sea tiles |
| Egyptian | War Chariot | Chariot | 4 | 2 | 30 | No Horse required; First Strike Immunity |
| English | Redcoat | Rifleman | 14 | 1 | 110 | +25% vs units from other continents (amphibious attackers) |
| Ethiopian | Oromo Warrior | Musketman | 10 | 1 | 80 | First Strike Immunity; starts with Drill I + Drill II |
| French | Musketeer | Musketman | 9 | 1 | 80 | Starts with Woodsman I; +25% forest defense |
| German | Panzer | Tank | 28 | 3 | 180 | 3 movement vs 2 for Tank; same strength |
| Greek | Phalanx | Spearman | 4 | 1 | 30 | +25% vs Mounted (stacks with base +100%) |
| Holy Roman | Landsknecht | Pikeman | 8 | 1 | 50 | Cheaper (50 vs 60 production); +100% vs Melee AND +100% vs Mounted |
| Incan | Quechua | Warrior | 2 | 1 | 15 | +100% vs Archery units |
| Indian | Fast Worker | Worker | 0 | 2 | 30 | 2 movement; builds improvements 50% faster |
| Japanese | Samurai | Maceman | 8 | 1 | 70 | Bushido: fights at full strength regardless of current HP |
| Khmer | Ballista Elephant | War Elephant | 8 | 2 | 70 | Can attack without moving the unit; can bombard city defenses |
| Korean | Hwacha | Catapult | 6 | 1 | 50 | Starts with Cover I; stronger base |
| Malinese | Skirmisher | Archer | 3 | 1 | 25 | No Archery tech required; +25% vs Mounted |
| Mayan | Holkan | Spearman | 3 | 1 | 30 | First Strike Immunity; no Hunting required |
| Mongolian | Keshik | Horse Archer | 6 | 3 | 50 | 3 movement; starts with Flanking I |
| Native American | Dog Soldier | Axeman | 6 | 1 | 40 | +50% vs Mounted; no Copper or Iron required |
| Ottoman | Janissary | Musketman | 9 | 1 | 80 | Starts with Shock I + Cover; heals 10 HP after kills |
| Persian | Immortal | Chariot | 4 | 2 | 30 | No Horse required; starts with Combat I; can cross rivers normally |
| Portuguese | Carrack | Caravel | 6 | 5 | 80 | Can carry 1 unit; +1 trade route |
| Roman | Praetorian | Swordsman | 8 | 1 | 40 | 8 Str vs 6 for Swordsman; same cost |
| Russian | Cossack | Cavalry | 15 | 2 | 120 | Starts with Flanking I + II; attacks at full strength |
| Spanish | Conquistador | Knight | 10 | 2 | 90 | Can found cities; treats all terrain as road for movement |
| Sumerian | Vulture | Axeman | 6 | 1 | 35 | +100% vs Melee; starts with Shock I; no Copper required |
| Viking | Berserker | Maceman | 8 | 1 | 70 | Amphibious (no attack penalty from sea); can attack twice per turn |
| Zulu | Impi | Spearman | 4 | 2 | 25 | 2 movement; +25% vs Mounted; cheaper (25 vs 30); flanking damage on victory |

---

## 6. Buildings

### 6.1 Standard Buildings

| Building | Era | Tech Req | Resource Req | Cost | Effects |
|----------|-----|----------|--------------|------|---------|
| Monument | Ancient | Mysticism | — | 30 | +1 Culture/turn |
| Barracks | Ancient | — | — | 60 | +3 XP to new land units |
| Granary | Ancient | Pottery | — | 60 | Stores 50% Food after city growth |
| Library | Ancient | Writing | — | 90 | +25% Science output; +2 Culture |
| Lighthouse | Ancient | Sailing | — | 60 | +1 Food on water tiles (coastal cities only) |
| Monastery | Ancient | Meditation | — | 60 | +10% Science; +2 Culture; trains Missionaries |
| Temple | Ancient | Priesthood | — | 80 | +1 Culture; +1 Happiness |
| Walls | Ancient | Masonry | — | 50 | +50% Defense bonus (vs pre-gunpowder) |
| Aqueduct | Classical | Mathematics | — | 100 | +2 Health |
| Colosseum | Classical | Construction | — | 80 | +1 Happiness; +1 Happiness per 20% Culture rate (capped) |
| Courthouse | Classical | Code of Laws | — | 120 | +2 Espionage; −50% City Maintenance |
| Forge | Classical | Metal Casting | — | 120 | +25% Production output; +1 Unhealthiness |
| Harbor | Classical | Compass | — | 80 | +50% Trade route yield (coastal only) |
| Market | Classical | Currency | — | 150 | +25% Commerce output |
| Stable | Classical | Horseback Riding | — | 60 | +2 XP for Mounted units |
| Theatre | Classical | Drama | — | 50 | +3 Culture |
| Bank | Medieval | Banking | — | 200 | +50% Commerce output (stacks with Market) |
| Castle | Medieval | Engineering | — | 100 | +1 Culture; +25% Espionage; +50% Defense bonus |
| Cathedral | Medieval | Music | — | 300 | +50% Culture; +2 Happiness (requires state religion) |
| Grocer | Medieval | Guilds + Currency | — | 150 | +25% Commerce; +1 Health per luxury resource |
| Observatory | Renaissance | Astronomy | — | 150 | +25% Science (stacks with Library/University) |
| University | Renaissance | Education | — | 200 | +25% Science; +3 Culture |
| Jail | Renaissance | Constitution | — | 120 | +4 Espionage; +50% Espionage defense |
| Customs House | Renaissance | Economics | — | 180 | +100% Commerce from intercontinental trade routes (coastal only) |
| Security Bureau | Modern | Democracy | — | 220 | +8 Espionage; +50% Espionage defense |
| Coal Plant | Industrial | Assembly Line | Coal | 150 | Provides Power (+25% Production when powered) |
| Factory | Industrial | Assembly Line | — | 250 | +25% Production; +50% with Power |
| Hospital | Industrial | Medicine | — | 200 | +3 Health |
| Industrial Park | Industrial | Industrialism | — | 200 | +2 Unhealthiness; +1 free Engineer specialist |
| Intelligence Agency | Industrial | Communism | — | 180 | +8 Espionage; +50% Espionage output |
| Levee | Industrial | Steam Power | — | 180 | +1 Production on river tiles |
| Nuclear Plant | Industrial | Fission | Uranium | 250 | Provides clean Power |
| Bomb Shelter | Industrial | Electricity | — | 100 | −50% Nuclear weapon damage |
| Bunker | Industrial | Electricity | — | 100 | −50% Air unit damage |
| Drydock | Industrial | Steel | — | 120 | +50% Naval unit production; +4 XP for Naval units |
| Public Transportation | Industrial | Combustion | — | 150 | +1 Health |
| Airport | Modern | Flight | — | 250 | Airlift 1 unit/turn; +3 XP for air units |
| Broadcast Tower | Modern | Mass Media | — | 175 | +50% Culture |
| Hydro Plant | Modern | Plastics | — | 200 | Provides clean Power |
| Laboratory | Modern | Superconductors | — | 250 | +25% Science; +50% Spaceship part production |
| Recycling Center | Modern | Ecology | — | 300 | Removes all building-caused Unhealthiness |
| Supermarket | Modern | Refrigeration | — | 150 | +1 Food |

### 6.2 Religion-Specific Buildings

Each of the 7 religions has three tiers of buildings. Building names differ by religion; effects are identical:

| Tier | Generic Name | Tech Req | Cost | Effects |
|------|-------------|----------|------|---------|
| 1 | Temple | Priesthood | 80 | +1 Culture; +1 Happiness |
| 2 | Monastery | Meditation | 60 | +10% Science; +2 Culture; trains Missionaries |
| 3 | Cathedral | Music | 300 | +50% Culture; +2 Happiness (with state religion) |

Building names by religion:
- **Buddhism**: Stupa (Temple), Monastery, Buddhist Cathedral
- **Christianity**: Christian Temple, Monastery, Christian Cathedral
- **Confucianism**: Confucian Temple, Monastery, Confucian Cathedral
- **Hinduism**: Hindu Temple, Monastery, Hindu Cathedral
- **Islam**: Islamic Temple, Monastery, Mosque
- **Judaism**: Jewish Temple, Monastery, Synagogue
- **Taoism**: Taoist Temple, Monastery, Taoist Cathedral

### 6.3 Great Person Buildings

| Building | Built By | Effects |
|----------|----------|---------|
| Academy | Great Scientist | +4 Culture; +50% Science in city |
| Military Academy | Great General | +25% Military unit production in city |
| Scotland Yard | Great Spy | +100% Espionage output in city |
| Shrine (per religion) | Great Prophet | Finance income = number of cities worldwide with that religion |

### 6.4 Faction-Unique Buildings

| Faction | Unique Building | Replaces | Effects |
|---------|-----------------|----------|---------|
| American | Mall | Supermarket | +1 Food; +20% Commerce |
| Arabian | Madrassa | Library | +25% Science; allows 2 Priest specialist slots |
| Aztec | Sacrificial Altar | Courthouse | −50% City Maintenance; halves the anger duration when using Slavery civic to rush production |
| Babylonian | Garden | Colosseum | +2 Health (instead of +1 Happiness) |
| Byzantine | Hippodrome | Theatre | +1 Happiness when city has access to Horse resource |
| Carthaginian | Cothon | Harbor | +1 additional Trade Route; same other effects |
| Celtic | Dun | Walls | Grants Guerrilla I to Recon, Archery, and Gunpowder units built here |
| Chinese | Pavilion | Theatre | +25% Culture |
| Dutch | Dike | Levee | Can be built in coastal cities (not just river cities) |
| Egyptian | Obelisk | Monument | +1 Culture; allows 2 Priest specialist slots |
| English | Stock Exchange | Bank | +15% Commerce above Bank base |
| Ethiopian | Stele | Monument | +1 Culture; +25% Culture bonus |
| French | Salon | Observatory | +25% Science; free Artist specialist slot |
| German | Assembly Plant | Factory | Allows 4 Engineer specialist slots |
| Greek | Odeon | Colosseum | +3 Culture; allows 2 Artist specialist slots |
| Holy Roman | Rathaus | Courthouse | −75% City Maintenance |
| Incan | Terrace | Granary | Stores 50% Food; +2 Culture |
| Indian | Mausoleum | Jail | +4 Espionage; +2 Happiness |
| Japanese | Shale Plant | Coal Plant | Provides Power without requiring Coal resource |
| Khmer | Baray | Aqueduct | +2 Health; +1 Food |
| Korean | Seowon | University | +35% Science (vs +25%) |
| Malinese | Mint | Forge | +10% Commerce (instead of +25% Production) |
| Mayan | Ball Court | Colosseum | +2 Happiness (instead of +1) |
| Mongolian | Ger | Stable | +2 XP for Mounted units (same as Stable but cheaper) |
| Native American | Totem Pole | Monument | +1 Culture; +3 XP to Archery units produced here |
| Ottoman | Hammam | Aqueduct | +2 Health; +2 Happiness |
| Persian | Apothecary | Grocer | +2 Health; +25% Commerce |
| Portuguese | Feitoria | Customs House | +1 Commerce on all worked water tiles |
| Roman | Forum | Market | +25% Great Person birth rate |
| Russian | Research Institute | Laboratory | +25% Science; 2 free Scientist specialist slots |
| Spanish | Citadel | Castle | +5 XP to Siege units produced here |
| Sumerian | Ziggurat | Courthouse | Requires Priesthood instead of Code of Laws |
| Viking | Trading Post | Lighthouse | Free Navigation I promotion for naval units built here |
| Zulu | Ikhanda | Barracks | −20% City Maintenance; every military unit trained here receives a free promotion |

---

## 7. Wonders

### 7.1 World Wonders

One copy exists globally; only the first faction to complete it keeps it.

| Wonder | Era | Tech Req | Resource | Cost | Effects | Obsoleted By |
|--------|-----|----------|----------|------|---------|--------------|
| Stonehenge | Ancient | Mysticism | Stone | 120 | Free Monument in every city; centers world map | Astronomy |
| Oracle | Ancient | Priesthood | Marble | 150 | Grants free technology when built | — |
| Pyramids | Ancient | Masonry | Stone | 500 | Enables all Government civics immediately | — |
| Temple of Artemis | Ancient | Polytheism | Marble | 350 | Free Priest; +100% trade route yield | Scientific Method |
| Great Wall | Ancient | Masonry | Stone | 150 | Prevents Barbarians entering your borders; +100% Great General emergence rate | — |
| Great Lighthouse | Ancient | Sailing + Masonry | — | 200 | +2 Trade Routes in all coastal cities | Corporation |
| Chichen Itza | Classical | Code of Laws | Stone | 500 | +25% Defense in all cities | Rifling |
| Colossus | Classical | Metal Casting + Forge | Copper | 250 | +1 Commerce on all worked water tiles | Astronomy |
| Great Library | Classical | Literature + Library | Marble | 350 | +2 free Scientist specialists | Scientific Method |
| Hanging Gardens | Classical | Mathematics + Aqueduct | Stone | 300 | +1 Health in all cities; +1 Population in all cities | — |
| Mausoleum of Maussollos | Classical | Calendar | Marble | 450 | +50% Golden Age length | — |
| Parthenon | Classical | Aesthetics + Polytheism | Marble | 400 | +50% Great Person birth rate in all cities | Scientific Method |
| Shwedagon Paya | Classical | Aesthetics + Meditation | Gold | 450 | Enables all Religion civics immediately | — |
| Statue of Zeus | Classical | Aesthetics + Monument | Ivory | 300 | +100% enemy war weariness in all your cities | — |
| Angkor Wat | Medieval | Philosophy | Stone | 500 | +1 Production from Priest specialists; allows 3 Priest specialists | Computers |
| Apostolic Palace | Medieval | Theology | — | 400 | Acts as religious assembly; allows elections; +2 Production for religious buildings | Mass Media |
| Hagia Sophia | Medieval | Engineering + Theology | Marble | 550 | Workers build improvements 50% faster | Steam Power |
| Notre Dame | Medieval | Engineering | Stone | 550 | +2 Happiness in all continental cities | — |
| Sistine Chapel | Medieval | Music | Marble | 600 | +2 Culture per specialist in all cities; +5 Culture from state religion buildings | — |
| Spiral Minaret | Medieval | Divine Right | Stone | 550 | +2 Gold from all state religion buildings | Computers |
| University of Sankore | Medieval | Paper | Stone | 550 | +2 Beakers from all state religion buildings | Computers |
| Versailles | Medieval | Divine Right | Marble | 800 | Reduces city maintenance costs empire-wide | — |
| Statue of Liberty | Renaissance | Democracy + Forge | Copper | 1500 | +1 free specialist in all cities on the same continent | — |
| Taj Mahal | Renaissance | Nationalism | Marble | 700 | Triggers a Golden Age immediately | — |
| Broadway | Industrial | Electricity | — | 800 | +50% Culture; produces Hit Musicals wonder resource | — |
| Kremlin | Industrial | Communism | Stone | 800 | −33% hurry production cost with Slavery/Universal Suffrage; 2 Spy specialist slots | Fiber Optics |
| Pentagon | Industrial | Assembly Line | — | 1250 | +2 XP for units in all cities | — |
| Cristo Redentor | Modern | Radio | — | 1000 | No anarchy when switching civics or religion | — |
| Eiffel Tower | Modern | Radio + Forge | Iron | 1250 | Free Broadcast Tower in every city | — |
| Hollywood | Modern | Mass Media | — | 1000 | +50% Culture; produces Hit Movies wonder resource | — |
| Rock 'n' Roll | Modern | Radio | — | 800 | +50% Culture; produces Hit Singles wonder resource | — |
| Three Gorges Dam | Modern | Plastics | — | 1750 | Provides clean Power for all cities on same continent (+2 Unhealthiness globally) | — |
| United Nations | Modern | Mass Media | — | 1000 | Triggers UN elections; guarantees voting eligibility | — |
| Space Elevator | Modern | Satellites + Robotics | Aluminum | 2000 | +50% Spaceship part production in all cities | — |

### 7.2 National Wonders

Can only be built once per faction and typically require a number of prerequisite buildings first.

| Wonder | Tech Req | Building Req | Resource | Cost | Effects |
|--------|----------|--------------|----------|------|---------|
| Palace | — | 6 cities | — | 160 | Capital city; reduces maintenance; +1 Happiness; +4 Espionage; +8 Commerce |
| Moai Statues | Sailing | — | Stone | 250 | +1 Production on all water tiles in this city |
| Forbidden Palace | Code of Laws | 6 Courthouses | — | 200 | Reduces maintenance costs in nearby cities |
| Globe Theatre | Drama | 6 Theatres | — | 300 | No Unhappiness in this city; allows 3 Artist specialists |
| Heroic Epic | Literature | Barracks | Marble | 200 | +100% military unit production in this city |
| National Epic | Literature | Library | Marble | 250 | +100% Great Person birth rate in this city |
| Hermitage | Nationalism | — | Marble | 300 | +100% Culture in this city |
| Oxford University | Education | 6 Universities | Stone | 400 | +100% Science in this city; allows 3 Scientist specialists |
| Wall Street | Corporation | 6 Banks | — | 600 | +100% Commerce in this city; allows 3 Merchant specialists |
| West Point | Military Tradition | 1 level-6 unit | Stone | 800 | +4 XP to all military units produced in this city |
| Ironworks | Steel | 6 Forges | — | 700 | +50% Production with Iron or Coal; allows 3 Engineer specialists; +2 Unhealthiness |
| Mt. Rushmore | Fascism | — | Stone | 500 | −25% War Anger in all cities |
| National Park | Biology | — | — | 300 | +1 specialist per Forest Preserve; removes Population Unhealthiness |
| Red Cross | Medicine | 6 Hospitals | — | 600 | Free Medic I promotion for units built here |
| Apollo Program | Rocketry | — | — | 1000 | Allows Spaceship part construction |
| Manhattan Project | Fission | — | Uranium | 1250 | Allows Tactical Nuke and ICBM construction globally |
| Military Academy | Military Science | Great General | — | 300 | +25% military unit production in this city |

---

## 8. Civics

Five categories; each faction chooses one civic per category at any time. Switching causes anarchy (turns = number of changes) unless the Spiritual trait or Cristo Redentor wonder is active.

### Government

| Civic | Tech | Upkeep | Effects |
|-------|------|--------|---------|
| Despotism | — | Low | Default; no effects |
| Hereditary Rule | Monarchy | Low | +1 Happiness per military unit garrisoned in city |
| Republic | Code of Laws | Medium | No war weariness from unit deaths; −1 Happiness per city at war |
| Universal Suffrage | Democracy | Medium | +1 Production from Town improvements; can spend gold to rush production |
| Representation | Constitution | Medium | +3 Science from Scientist specialists; +1 Happiness in 5 largest cities |
| Police State | Fascism | High | +25% military unit production; −50% War Anger |

### Legal

| Civic | Tech | Upkeep | Effects |
|-------|------|--------|---------|
| Barbarism | — | Low | Default; no effects |
| Vassalage | Feudalism | High | +2 XP for new units; 2 free units per city |
| Bureaucracy | Civil Service | High | +50% Commerce and Production in capital city |
| Nationhood | Nationalism | None | +1 Happiness from Barracks; can draft citizens into soldiers; +4 Espionage |
| Free Speech | Liberalism | Low | +1 Commerce from Town tiles; +100% Culture in all cities |

### Labor

| Civic | Tech | Upkeep | Effects |
|-------|------|--------|---------|
| Tribalism | — | Low | Default; no effects |
| Slavery | Bronze Working | Medium | Can sacrifice population to rush production (1 citizen = 30 production) |
| Serfdom | Feudalism | Low | Workers build improvements 50% faster |
| Caste System | Code of Laws | Medium | Unlimited specialist slots; +1 Production from Workshop improvements |
| Emancipation | Democracy | Low | Cottages grow to Hamlet/Village/Town faster; other factions without Emancipation gain unhappiness |

### Economy

| Civic | Tech | Upkeep | Effects |
|-------|------|--------|---------|
| Decentralization | — | Low | Default; no effects |
| Mercantilism | Banking | Medium | +1 free specialist per city; no foreign trade routes; corporations have no effect |
| Free Market | Economics | Medium | +1 Trade Route per city; −50% Corporation maintenance |
| State Property | Communism | Low | No distance maintenance penalty; +1 Production from Watermill/Farm; corporations have no effect |
| Environmentalism | Medicine | Medium | +6 Health empire-wide; +1 Happiness per Forest/Jungle tile; +1 Commerce from Windmills |

### Religion

| Civic | Tech | Upkeep | Effects |
|-------|------|--------|---------|
| Paganism | — | Low | Default; no effects |
| Organized Religion | Monotheism | High | +1 Production for religious buildings; can build Missionaries without Monastery |
| Theocracy | Theology | Medium | +2 XP for units trained with state religion; prevents spread of non-state religions |
| Pacifism | Philosophy | None | +100% Great Person birth rate; −1 Production per military unit |
| Free Religion | Liberalism | Low | +1 Happiness per religion present in city; +10% Science output |

---

## 9. Religions

The first faction to research the founding technology founds that religion in one of its cities (chosen randomly if tied). That city becomes the Holy City, earning +5 Culture/turn from the shrine built there by a Great Prophet. All religions have identical mechanical effects; they differ only in founding technology and building aesthetics.

| Religion | Founding Tech | Temple | Monastery | Cathedral | Shrine Name |
|----------|--------------|--------|-----------|-----------|-------------|
| Buddhism | Meditation | Buddhist Temple | Buddhist Monastery | Buddhist Cathedral | Mahabodhi |
| Christianity | Theology | Christian Temple | Christian Monastery | Christian Cathedral | Church of the Nativity |
| Confucianism | Code of Laws | Confucian Temple | Confucian Monastery | Confucian Cathedral | Kong Miao |
| Hinduism | Polytheism | Hindu Temple | Hindu Monastery | Hindu Cathedral | Kashi Vishwanath |
| Islam | Divine Right | Islamic Temple | Islamic Monastery | Islamic Cathedral | Masjid al-Haram |
| Judaism | Monotheism | Jewish Temple | Jewish Monastery | Jewish Cathedral | Temple of Solomon |
| Taoism | Philosophy | Taoist Temple | Taoist Monastery | Taoist Cathedral | Dai Miao |

**Holy City effect:** +5 Culture/turn baseline; shrine built by Great Prophet yields +1 Gold per city worldwide that has adopted the religion.

---

## 10. Resources

### 10.1 Strategic Resources

Must be connected to road network. Enable certain units and buildings.

| Resource | Improvement | Tech to Reveal | Tech to Improve | Yield Bonus | Enables |
|----------|-------------|----------------|-----------------|-------------|---------|
| Coal | Mine | Mining | Assembly Line | +1 Production | Factory/Coal Plant power, Ironclad |
| Copper | Mine | Mining | Bronze Working | +1 Production | Axeman; substitute for Iron in some units |
| Horse | Pasture | Animal Husbandry | Animal Husbandry | +2 Production +1 Commerce | Chariot, Horse Archer, Knight, Cavalry, Cuirassier |
| Iron | Mine | Mining | Iron Working | +1 Production | Swordsman, Knight, Cannon, Frigate |
| Marble | Quarry | Masonry | Masonry | +1 Production +2 Commerce | Wonder production bonus |
| Oil | Well/Platform | Combustion | Combustion/Plastics | +2 Production +1 Commerce | Tank, Destroyer, Submarine, Battleship, Carrier, Fighter, Bomber |
| Aluminum | Mine | Mining | Industrialism | +1 Production +1 Commerce | Modern Armor, Jet Fighter, Space Elevator |
| Stone | Quarry | Masonry | Masonry | +2 Production | Wonder production bonus |
| Uranium | Mine | Fission | Fission | +3 Commerce | Tactical Nuke, ICBM, Nuclear Plant |

### 10.2 Luxury Resources

Each luxury connected to a city's trade network provides +1 Happiness city-wide.

| Resource | Improvement | Tech to Reveal | Tech to Improve | Terrain |
|----------|-------------|----------------|-----------------|---------|
| Dye | Plantation | — | Calendar | Forest tiles |
| Fur | Camp | Hunting | Hunting | Forest/Tundra |
| Gems | Mine | Mining | Mining | Hill tiles |
| Gold | Mine | Mining | Mining | Hill tiles |
| Incense | Plantation | — | Calendar | Desert/Plains |
| Ivory | Camp | Hunting | Hunting | Plains/Grassland; obsoleted by Industrialism |
| Silk | Plantation | — | Calendar | Forest tiles |
| Silver | Mine | Mining | Mining | Hill tiles |
| Spices | Plantation | — | Calendar | Jungle tiles |
| Sugar | Plantation | — | Calendar | Flood Plains/Jungle |
| Whale | Whaling Boats | Sailing | Compass | Ocean/Coast; obsoleted by Combustion |
| Wine | Winery | Pottery | Monarchy | Grassland/Plains |

**Wonder-produced luxuries (provide happiness without tile connection):**
- Hit Movies (Hollywood wonder): +1 Happiness
- Hit Musicals (Broadway wonder): +1 Happiness
- Hit Singles (Rock 'n' Roll wonder): +1 Happiness

### 10.3 Bonus Resources (Food)

Provide +1 Health city-wide when connected. All also provide additional Food yield.

| Resource | Improvement | Terrain | Base Yield Bonus |
|----------|-------------|---------|-----------------|
| Banana | Plantation | Jungle | +2 Food |
| Clam | Fishing Boats | Coast | +1 Food +1 Commerce |
| Corn | Farm | Plains/Grassland | +2 Food |
| Cow | Pasture | Plains/Grassland | +1 Food +1 Production |
| Crab | Fishing Boats | Coast | +1 Food +1 Production |
| Deer | Camp | Forest/Tundra | +1 Food +1 Production |
| Fish | Fishing Boats | Ocean/Coast | +2 Food |
| Pig | Pasture | Plains/Grassland | +1 Food +1 Production |
| Rice | Farm | Plains/Flood Plains | +2 Food |
| Sheep | Pasture | Plains/Grassland/Hills | +1 Food +1 Commerce |
| Wheat | Farm | Plains/Flood Plains | +2 Food |

---

## 11. Terrain & Features

### 11.1 Base Terrain

| Terrain | Food | Production | Commerce | Notes |
|---------|------|------------|----------|-------|
| Grassland | 2 | 0 | 0 | +1 Commerce adjacent to river |
| Plains | 1 | 1 | 0 | +1 Commerce adjacent to river |
| Desert | 0 | 0 | 0 | Improvements take 25% longer; requires water for most |
| Tundra | 1 | 0 | 0 | Improvements take 25% longer |
| Snow | 0 | 0 | 0 | No improvements possible |
| Coast | 1 | 0 | 2 | Water; +10% defense |
| Ocean | 1 | 0 | 1 | Water; deep-water; restricted early access |

**Global-warming erosion (`degrades_to`).** Each land terrain declares the terrain a
global-warming strike erodes it into (game-rules §11). The chains converge on the barren base
terrain (`gw_base_terrain`, desert): `grassland → plains → desert`, `tundra → snow → desert`,
`hills → plains → desert`, `mountain → hills → plains → desert`. Desert has no successor (it is
the terminal); water terrains are never targeted.

### 11.2 Landform Modifiers

| Landform | Yield Change | Move Cost | Defense | Other |
|----------|-------------|-----------|---------|-------|
| Flat | ±0 | 1 | +0% | Default |
| Hill | −1 Food, +1 Production | +1 (total 2) | +25% | +1 sight range |
| Peak | — | Impassable | — | Cannot be entered by land units |

### 11.3 Features (Overlaid on terrain)

| Feature | Food | Production | Commerce | Move Cost | Defense | Notes |
|---------|------|------------|----------|-----------|---------|-------|
| Forest | 0 | +1 | 0 | +1 | +50% | Can be chopped for +20 prod (more with Math); `growth_probability` > 0 → counts as forest cover that defends against global warming (§11 game-rules) |
| Jungle | −1 | 0 | 0 | +1 | +50% | Removed before most improvements; disease risk; `growth_probability` > 0 → defends against global warming (§11 game-rules) |
| Flood Plains | +3 | 0 | 0 | 0 | −33% | Only on Desert tiles adjacent to rivers |
| Oasis | +3 | 0 | +2 | 0 | 0 | Only in Desert; cannot be improved |
| Fallout | −3 | −3 | −3 | +1 | 0 | Nuclear contamination; can be cleaned by Workers |
| Ice | — | — | — | Impassable | — | No units or improvements |

**River:** Not a feature on a tile itself, but borders between tiles. Provides +1 Commerce to adjacent tiles; provides freshwater for irrigation without requiring adjacency to other farms (after Civil Service tech); river-crossing costs 1 extra movement and imposes −25% attack penalty (without Amphibious promotion).

---

## 12. Improvements

Build times are base turns for a standard Worker. Workers with the Industrious faction bonus build 50% faster; Serfdom civic grants an additional 50% speed.

| Improvement | Tech Req | Valid Terrain | Base Build Time | Yield Effect | Notes |
|-------------|----------|---------------|-----------------|--------------|-------|
| Farm | Agriculture | Grassland, Plains, Desert (w/ water), Flood Plains | 4 | +1 Food | +1 more Food with Civil Service (river adj); +1 more with Biology |
| Mine | Mining | Hills, Resources (Coal, Copper, Iron, Gold, Gems, Silver, Aluminum, Uranium) | 5 | +1 Production (hills); varies by resource | Required to access strategic resources |
| Pasture | Animal Husbandry | Plains/Grassland (Horse, Cow, Sheep resources) | 4 | Enables resource; +1 Production or Food | |
| Camp | Hunting | Forest/Tundra (Fur, Ivory, Deer resources) | 4 | Enables resource; +1 Production | |
| Plantation | Calendar | Various (Dye, Silk, Spice, Incense, Sugar, Banana) | 5 | Enables luxury resource | Often requires removing Jungle first |
| Quarry | Masonry | Stone, Marble resources | 5 | Enables resource; +1 Production | |
| Winery | Monarchy | Grassland/Plains (Wine resource) | 4 | Enables Wine luxury | |
| Fishing Boats | Fishing | Coast/Ocean (Fish, Clam, Crab resources) | 3 | Enables food resource; +1–2 Food | Work Boat unit; consumed on placement |
| Whaling Boats | Compass | Ocean/Coast (Whale resource) | 3 | Enables Whale luxury | Work Boat unit |
| Well | Combustion | Plains/Desert (Oil resource on land) | 5 | Enables Oil | |
| Offshore Platform | Plastics | Coast/Ocean (Oil at sea) | 6 | Enables Oil; +2 Production +1 Commerce | |
| Cottage | Pottery | Grassland, Plains, Desert, Tundra (non-resource) | 5 | +1 Commerce | Grows over time to Hamlet/Village/Town |
| Hamlet | Printing Press | Same as Cottage | — | +2 Commerce | Upgraded from Cottage automatically with turns |
| Village | — | — | — | +3 Commerce +1 Food | Upgraded from Hamlet |
| Town | Nationalism | — | — | +4 Commerce +1 Food +1 Production | Upgraded from Village; cannot be pillaged back easily |
| Workshop | Metal Casting | Grassland, Plains, Desert, Tundra | 4 | +1 Production | +1 more Production with Caste System; +1 more with Chemistry |
| Watermill | The Wheel | Flat tiles adjacent to rivers | 5 | +1 Production +1 Food | +1 more Production with Electricity |
| Windmill | Machinery | Hills (without other improvements) | 5 | +1 Production +1 Commerce | +1 more Commerce with Electricity |
| Lumbermill | Replaceable Parts | Forest tiles | 4 | +1 Production +1 Food | Does not remove forest |
| Fort | Mathematics | Most land tiles | 4 | +50% Defense for garrisoned units | Air units can use forts as bases |
| Forest Preserve | Scientific Method | Forest tiles | 3 | Prevents forest removal; +1 Food | Counts toward National Park wonder |
| Road | The Wheel | Most land tiles | 2 | Reduces movement cost to 1/3 | Required for resource connections |
| Railroad | Steam Power | Most land tiles | 3 | Movement cost = 0 (unlimited movement in own territory) | Requires Road first |

---

## 13. Promotions

### 13.1 General Land Unit Promotions

Available to most land combat units. Each promotion costs experience equal to: 5 × (2^current_level) XP.
Thresholds: first promotion at 5 XP, second at 10, third at 20, etc.

**Combat Line** (available to all land units):

| Promotion | Prerequisite | Effect |
|-----------|-------------|--------|
| Combat I | — | +10% Strength |
| Combat II | Combat I | +10% Strength |
| Combat III | Combat II | +10% Strength |
| Combat IV | Combat III | +10% Strength |
| Combat V | Combat IV | +10% Strength |
| Combat VI | Combat V | +10% Strength |

**City Raider Line** (melee and gunpowder units):

| Promotion | Prerequisite | Effect |
|-----------|-------------|--------|
| City Raider I | Combat I | +20% attacking cities |
| City Raider II | City Raider I | +20% attacking cities |
| City Raider III | City Raider II | +20% attacking cities; can reduce city defenses by bombardment |

**City Garrison Line** (melee and archery units):

| Promotion | Prerequisite | Effect |
|-----------|-------------|--------|
| City Garrison I | Combat I | +25% defending in cities |
| City Garrison II | City Garrison I | +25% defending in cities |
| City Garrison III | City Garrison II | +25% defending in cities |

**Drill Line** (increases first strikes; available to most foot soldiers):

| Promotion | Prerequisite | Effect |
|-----------|-------------|--------|
| Drill I | Combat I | +1 First Strike |
| Drill II | Drill I | +1 First Strike |
| Drill III | Drill II | +1 First Strike |
| Drill IV | Drill III | +1 First Strike; −50% damage taken per hit |

**Guerrilla Line** (archery, rifle, and similar units):

| Promotion | Prerequisite | Effect |
|-----------|-------------|--------|
| Guerrilla I | Combat I | +20% defending on hills |
| Guerrilla II | Guerrilla I | +20% defending on hills |
| Guerrilla III | Guerrilla II | +20% defending on hills; normal movement through all terrain |

**Woodsman Line** (forest and jungle specialists):

| Promotion | Prerequisite | Effect |
|-----------|-------------|--------|
| Woodsman I | Combat I | +20% in forests/jungles |
| Woodsman II | Woodsman I | +1 Movement in forests/jungles; extra healing in forests |
| Woodsman III | Woodsman II | +20% in forests/jungles |

**Medic Line** (healing support):

| Promotion | Prerequisite | Effect |
|-----------|-------------|--------|
| Medic I | Combat I | Adjacent friendly units heal +10 HP/turn extra |
| Medic II | Medic I | Adjacent units also heal in enemy territory |

**Flanking Line** (mounted units only):

| Promotion | Prerequisite | Effect |
|-----------|-------------|--------|
| Flanking I | Combat I | +10% withdrawal chance |
| Flanking II | Flanking I | +10% withdrawal chance |

**Accuracy Line** (bombers and air units):

| Promotion | Prerequisite | Effect |
|-----------|-------------|--------|
| Accuracy I | — | +25% vs cities |
| Accuracy II | Accuracy I | +25% vs cities |

**Barrage Line** (siege weapons):

| Promotion | Prerequisite | Effect |
|-----------|-------------|--------|
| Barrage I | Combat I | +25% vs fortified units |
| Barrage II | Barrage I | +25% vs fortified units |
| Barrage III | Barrage II | +25% vs fortified units |

**Individual Promotions:**

| Promotion | Prerequisite | Unit Types | Effect |
|-----------|-------------|------------|--------|
| Shock | Combat I | Melee | +25% vs Melee units |
| Pinch | Combat I | Melee | +25% vs Gunpowder units |
| Formation | Combat I | Melee/Spear | +25% vs Mounted units |
| Cover | Combat I | Archery | −50% damage from Siege unit bombardment |
| Amphibious | Combat I | Land | No attack penalty when attacking from sea |
| Sentry | Combat I | Any | +1 Vision range |
| March | Medic I | Any land | Heals every turn even when moving or attacking |
| Morale | Combat III | Any land | +1 Movement |
| Blitz | Combat V | Mounted | Can attack multiple times per turn |
| Commando | Combat V | Any land | Can move after attacking |
| Leadership | Great General | Any | Adjacent friendly units gain +100% XP |
| Withdrawal | Combat I | Mounted | Can attempt to withdraw from combat (loses fight but survives) |

**Naval Promotions:**

| Promotion | Prerequisite | Effect |
|-----------|-------------|--------|
| Navigation I | — | +1 Movement |
| Navigation II | Navigation I | +1 Movement |
| Boarding I | — | +25% attacking ships |
| Boarding II | Boarding I | +25% attacking ships |
| Escort | — | Accompanying unit takes −50% damage |

**Air Unit Promotions:**

| Promotion | Prerequisite | Effect |
|-----------|-------------|--------|
| Interception I | — | +33% Interception strength |
| Interception II | Interception I | +33% Interception strength |
| Dogfighting I | — | +25% vs fighters |
| Dogfighting II | Dogfighting I | +25% vs fighters |
| Air Supremacy | Interception I | +33% Interception; reduces enemy intercept by 20% |
| Evasion | — | 50% chance to evade interception |

---

## 14. Great People

Great People are produced by accumulating Great Person Points (GPP) in cities via specialists and certain buildings/wonders. Each type is generated by its corresponding specialist type. Threshold for each successive GP rises.

### 14.1 Types, Specialist Sources, and Actions

| Great Person | Generated By | Per-Specialist Output | Actions |
|-------------|-------------|----------------------|---------|
| Great Artist | Artist specialist | +3 Culture/turn | **Great Work** — instantly adds 4000 Culture to the city (can flip nearby cultural borders). **Join City** — adds a permanent +3 Culture/turn super-specialist. **Start Golden Age** — consumes this unit to contribute to a Golden Age (see §14.4). |
| Great Engineer | Engineer specialist | +2 Production/turn | **Hurry Production** — instantly contributes 500+ Hammers to the current build queue item. **Build Ironworks** — constructs the Ironworks national wonder. **Join City** — adds a permanent +2 Production/turn super-specialist. **Start Golden Age**. |
| Great Merchant | Merchant specialist | +3 Commerce/turn | **Trade Mission** — visit a distant foreign city to gain 2000+ Gold. **Found Corporation** — establishes a corporation in a city (see §14.6). **Join City** — adds a permanent +3 Commerce/turn super-specialist. **Start Golden Age**. |
| Great Prophet | Priest specialist | +2 Culture/turn | **Found Religion** — founds a religion if any remain unfounded. **Build Shrine** — constructs the religion's shrine as a national wonder in the holy city; shrine yields +1 Gold per city worldwide that follows that religion. **Join City** — adds a permanent +2 Culture/turn super-specialist. **Start Golden Age**. |
| Great Scientist | Scientist specialist | +3 Science/turn | **Discover Technology** — instantly researches a currently available technology. **Build Academy** — constructs an Academy building (+50% Science in that city). **Join City** — adds a permanent +3 Science/turn super-specialist. **Start Golden Age**. |
| Great Spy | Spy specialist | +3 Espionage/turn | **Infiltration** — visit a foreign city to gain +3000 Espionage Points against that faction. **Join City** — adds a permanent +3 Espionage/turn super-specialist. *(Cannot start a Golden Age.)* |
| Great General | Combat XP accumulation | +2 Production/turn (if settled) | **Attach to Unit** — the General follows one military unit; all friendly units in the same tile gain the Leadership promotion. **Build Military Academy** — constructs the Military Academy national wonder. **Join City** — adds a permanent +2 Production/turn super-specialist. *(Cannot start a Golden Age.)* |

### 14.2 Great General — Special Generation Rules

The Great General is not produced by specialists. Instead, it accumulates from **combat experience**:
- Each combat victory contributes a fractional amount of points toward a Great General.
- The Imperialistic trait grants **+50% Great General emergence rate**.
- The Great Wall wonder grants **+100% Great General emergence rate**.
- The first Great General costs 30 points; subsequent ones cost progressively more.
- Great Generals are produced directly in the field (at the location of the victorious unit), not in a city.
- Multiple Great Generals do not stack the Leadership effect; only one can be attached to a given unit.

### 14.3 Great Person Point (GPP) Thresholds

Each city maintains a separate **GP pool** per type, based on which specialists are assigned there. When total accumulated GPP in a city reaches the threshold, a Great Person of the dominant type is born there.

```
Threshold for Nth Great Person = 100 × N × (1 + 0.15 × (N − 1))   [approximate formula]
  (e.g., 1st GP ≈ 100 pts; 2nd ≈ 230 pts; 3rd ≈ 390 pts; ...)

Type born = whichever specialist type has contributed the most accumulated GPP in that city.
If multiple types are tied, one is chosen at random.
```

Modifiers to GPP accumulation:
- **Philosophical trait**: ×2 to all GPP in all cities
- **National Epic** national wonder: ×2 to all GPP in that city
- **Parthenon** world wonder: +50% GPP in all cities
- **Pacifism** civic: +100% GPP in cities with a state religion
- **Caste System** civic: allows unlimited specialist slots (increases GPP rate)
- **Representation** civic: +3 Science per Scientist specialist

### 14.4 Golden Ages

A Golden Age lasts **8 turns** (base, scaled by pace). During a Golden Age:
- All worked tiles produce +1 Food, +1 Production, and +1 Commerce.
- War Weariness does not increase.

**How to start a Golden Age:**
- Use **2 Great Persons** of any type (not Great General or Great Spy) together in one action — both units are consumed.
- If already in a Golden Age, only **1 Great Person** is needed to extend it.
- Certain wonders can also trigger them directly (e.g., Taj Mahal grants an immediate Golden Age).

**Golden Age duration modifiers:**
- **Mausoleum of Maussollos** world wonder: +50% duration (12 turns base instead of 8).
- Each subsequent Golden Age triggered by Great Persons costs one more GP than the last.

### 14.5 Specialist Slots and Sources

Cities have limited specialist slots by default. Extra slots come from buildings, the Caste System civic (unlimited), and certain national wonders.

| Specialist | Default Slots | Buildings that Add Slots |
|-----------|--------------|--------------------------|
| Artist | 1 | Theatre (+1), Globe Theatre (+3), Hermitage (+1) |
| Engineer | 1 | Forge (+1), Factory (+1), Ironworks (+3), Industrial Park (+1), Assembly Plant (+4) |
| Merchant | 1 | Market (+1), Bank (+1), Wall Street (+3) |
| Priest | 1 | Temple (+1), Angkor Wat (+3), Madrassa (+2), Obelisk (+2) |
| Scientist | 1 | Library (+1), University (+1), Oxford University (+3), Laboratory (+1), Research Institute (+2) |
| Spy | 1 | Intelligence Agency (+1) |
| Citizen | Unlimited | — (assigned to work no tile) |

### 14.6 Corporations

Each corporation is founded by a Great Merchant and spreads like a religion, but consumes input resources to produce output. Competing corporations cannot coexist in the same city.

**Full corporation model (reference parity).** Each corporation should carry, in a
`data/corporations.json`-style table: a **headquarters structure** built once in the founding
city (earning the founder gold per unit of input consumed worldwide), an **executive unit**
that spreads the corporation to a new city for a treasury cost (the corporate missionary), the
**input-resource set** whose access **count** scales the per-city output, a **per-city
maintenance** cost, and civic interactions (e.g. a state-property economy bans corporations).
The output scales with the **number of distinct/total input resources** the owner can access,
not a flat amount. *(The current `econ_orgs` model omits the HQ-gold share, the executive-unit
spread cost, the resource-count scaling, and per-city maintenance — close these for parity.)*

| Corporation | Input Resources | Output per City |
|-------------|-----------------|-----------------|
| Cereal Mills | Wheat, Rice, Corn | +1 Food per resource type |
| Creative Constructions | Marble, Stone | +2 Production |
| Aluminum Co. | Aluminum | +3 Production |
| Mining Inc. | Iron, Copper, Coal | +2 Production per type |
| Sid's Sushi | Crab, Clam, Fish | +2 Food |
| Civilized Jewelers | Gems, Gold, Silver | +4 Commerce |
| Standard Ethanol | Sugar, Corn, Wheat | +1 Food, +1 Commerce |
| Overseas Trading Co. | Silk, Dye, Spice | +4 Commerce |
| Nationalist Mutual | Oil, Coal | +3 Commerce |

---

## 15. Global Constants & Formulas

### 15.1 Combat

```
Effective Strength = Base_Strength × (100 + sum_of_all_modifiers)/100 × (current_HP / max_HP)

Combat odds (per round, in thousandths) =
    theirOdds = COMBAT_DIE_SIDES × theirStr / (ourStr + theirStr)
    COMBAT_DIE_SIDES = 1000 ; clamped so neither side is below 10% (100) or above 90% (900)

Per-hit damage (the canonical reference model) =
    strengthFactor = (ourFirepower + theirFirepower + 1) / 2
    ourDamage      = max(1, COMBAT_DAMAGE × (theirFirepower + strengthFactor)
                                         / (ourFirepower   + strengthFactor))
    COMBAT_DAMAGE = 20  →  ≈20 HP/hit vs an even opponent, ≈5 hits to a kill

Firepower = Effective_Strength (for most units; siege/special carry a distinct firepower)
Max HP = 100 (all units)
```

> **Supersede note.** The earlier `max_HP × Def_FP/(Atk_FP+Def_FP)` damage formula gave ≈50
> HP/hit (≈2 hits to kill); the reference's `COMBAT_DAMAGE = 20` blended-firepower model above
> is canonical (≈5 hits). Constants live in `data/constants.json` (`combat_scale = 1000`,
> `combat_damage = 20`, `max_hp = 100`).

| Constant | Value | Notes |
|----------|-------|-------|
| Combat die sides (`combat_scale`) | 1000 | Odds expressed in thousandths; per-round draw in [0,999] |
| Odds clamp | 10% / 90% | Neither side ever below 100 or above 900 of the die |
| Base combat damage (`combat_damage`) | 20 | Damage coefficient in the per-hit formula |
| Max HP | 100 | All units |
| Min damage per hit | 1 HP | Floor on hit damage |
| First-strike advantage | 1 round per strike | Defender cannot deal damage during attacker's first strikes |
| Withdrawal base chance | 0% | Added by promotions or unit type |
| Max XP from barbarians | 10 XP per fight | Capped to prevent farming |
| XP from kill | 4–7 XP | Based on relative strength ratio |
| Flanking damage | 20% of stack (capped) | Mounted units hitting adjacent stacked units |
| Collateral/spillover cap | 35 HP | Siege units cannot reduce any target below 35 HP |
| Entrenchment bonus | +20% per turn | Capped at +40% (2 turns stationary) |
| River-crossing penalty | −25% attack strength | Waived by Amphibious promotion |
| Amphibious attack penalty | −50% attack strength | Waived by Amphibious promotion |

### 15.2 Cities & Growth

```
Surplus food stored = food_produced − food_consumed
food_consumed = (population − angryPop) × FOOD_CONSUMPTION_PER_POPULATION − healthRate
              # angry/discontented citizens do NOT eat; net unhealthiness drains consumption
FOOD_CONSUMPTION_PER_POPULATION = 2

Growth threshold = base × f(current_population) × speed_multiplier × era_scale [× difficulty growth_bonus]
              # rises with population AND game speed (reference growthThreshold curve),
              # not strictly linear; carry-over capped at threshold × max_food_kept_percent/100
At threshold: population +1; keep granary carry-over, spill the rest. If store < 0: starve
              (a size-1 city is floored so it does not starve to zero)
```

> **Supersede note.** Consumption excludes **angry** citizens and folds net unhealthiness in
> as a food drain (not a separate after-the-fact `wellbeing_deficit`); the growth threshold
> follows the reference's pop-and-speed curve rather than the flat `18 + 2×pop`.

| Constant | Value |
|----------|-------|
| Food consumed per (non-angry) citizen | 2 Food/turn |
| Base growth threshold | reference `growthThreshold(pop, speed)` curve (pop- and speed-scaled) |
| City maintenance formula | (distance_to_capital + 0.5×num_cities) × size_factor |
| Minimum city spacing | 2 tiles (cities cannot be adjacent) |
| Cultural border flip threshold | 2× opponent's accumulated culture on a tile |

### 15.3 Culture Levels

| Level | Name | Accumulated Culture | Border Radius |
|-------|------|--------------------|----|
| 0 | Fledgling | 0 | 1 (just city tile and ring 1) |
| 1 | Developing | 10 | 2 |
| 2 | Refined | 100 | 3 |
| 3 | Influential | 500 | — |
| 4 | Legendary | 5,000 | — |
| 5 | Divine | 50,000 | Cultural Victory level |

*Note: For Cultural Victory, 3 cities must each reach the Legendary (50,000 culture) level.*

### 15.4 Research

```
# Canonical reference percent chain (integer, floored at 1):
Research cost = base_cost
              × handicap_research_percent / 100   # difficulty: Settler 60 … Noble 100 … Deity 130
              × world_research_percent    / 100   # map size
              × speed_research_percent    / 100   # Quick 67 / Normal 100 / Epic 150 / Marathon 300
              × era_research_percent       / 100   # advanced-start era
              × max(0, TECH_COST_EXTRA_TEAM_MEMBER_MODIFIER × (teamMembers−1) + 100) / 100

# Humanish discounts applied AFTER the chain (intentional extensions, not in the reference):
Trading discount     = 5% per other faction that already knows this tech (capped ~25%)
Prerequisite discount = 10% per held prerequisite of this tech
```

> **Supersede note.** The authoritative cost is the percent chain above. The engine currently
> applies only the speed scalar and folds difficulty into an AI beaker bonus; add the
> handicap/world/era/team factors. The two discounts remain as this game's extensions.

### 15.5 Espionage

```
Mission cost = base_cost × (1 + target_EP_advantage / 100)
Base EP accumulation = espionage_slider_output per turn against a specific faction
```

### 15.6 Game Paces (turn/cost multipliers)

| Pace | Research | Growth | Production | Era Turns |
|------|----------|--------|------------|-----------|
| Marathon | 300% | 300% | 300% | Longest |
| Epic | 150% | 150% | 150% | Long |
| Normal | 100% | 100% | 100% | Standard |
| Quick | 67% | 67% | 67% | Short |

### 15.7 Healing Rates

| Location | HP healed per turn |
|----------|--------------------|
| Inside friendly city | 20 HP |
| In own territory (non-city) | 15 HP |
| In neutral territory | 10 HP |
| In enemy territory | 5 HP |

A unit does not heal on any turn it moves or fights.

### 15.8 World Sizes

| Map Size | Dimensions (approx.) | Recommended Players |
|----------|-----------------------|---------------------|
| Duel | 40×24 | 2 |
| Tiny | 56×36 | 3 |
| Small | 72×44 | 4 |
| Standard | 96×60 | 6 |
| Large | 128×80 | 8 |
| Huge | 160×100 | 10+ |

### 15.9 Difficulty Levels

The two **canonical** knobs (reference-grounded) are the **player research %**
(`handicap_research_percent`, scaling the player's own tech cost, §15.4) and the **AI per-era
research modifier** (`ai_research_per_era`, making AI techs cheaper as the game advances).
`noble` is the balanced baseline (research 100, every bonus 0). The `ai_bonus` (flat AI yield
handicap) and the human-only city aids (`growth_bonus`/`health_bonus`/`happiness_bonus`) are
this game's additional levers. All apply to human players only except the AI knobs.

| Level | Player research % | AI per-era modifier | AI yield bonus | City aids (human only) |
|-------|:----------------:|:-------------------:|----------------|------------------------|
| Settler | 60 | 0 | None | Large (+growth/health/happiness) |
| Chieftain | ~70 | 0 | None | Some |
| Warlord | ~85 | 0 | Slight | Slight |
| Noble (baseline) | 100 | 0 | Balanced | None |
| Prince | ~110 | 0 | Minor | None |
| Monarch | ~115 | −1 | Moderate | None |
| Emperor | ~120 | −2 | Large | None |
| Immortal | ~125 | −3 | Very large | None |
| Deity | 130 | −5 | Maximum | None |

*(Settler/Noble/Deity research % and the Deity per-era −5 are the reference anchors; the
intermediate rows are interpolated targets to balance.)*

### 15.10 Wild-forces spawn tables (provisional)

> **⚠️ Provisional.** Per-difficulty wild-spawn fields on each `data/difficulties.json` entry,
> governing the §9.2 spawning model. Values are ported from Civilization IV: Beyond the Sword
> (`CIV4HandicapInfo.xml`) and **not yet retuned** for this engine. See game-rules §9.2 for the
> formulas that consume them.

| Field | Settler | Chieftain | Warlord | Noble | Prince | Monarch | Emperor | Immortal | Deity |
|-------|--------:|----------:|--------:|------:|-------:|--------:|--------:|---------:|------:|
| `unowned_tiles_per_wild_unit` | 150 | 100 | 80 | 60 | 50 | 40 | 35 | 30 | 25 |
| `unowned_water_tiles_per_wild_unit` (§9.4) | 3000 | 2400 | 2200 | 2000 | 1800 | 1600 | 1400 | 1200 | 1000 |
| `unowned_tiles_per_wild_city` | 160 | 150 | 140 | 130 | 120 | 110 | 100 | 90 | 80 |
| `wild_creation_turns_elapsed` ‡ | 50 | 45 | 40 | 35 | 30 | 25 | 20 | 15 | 10 |
| `wild_city_creation_turns_elapsed` ‡ | 55 | 50 | 45 | 40 | 35 | 30 | 25 | 20 | 15 |
| `wild_city_creation_prob` (%) | 4 | 5 | 5 | 6 | 6 | 7 | 7 | 8 | 8 |
| `unowned_tiles_per_animal` (§9.3) | 100 | 80 | 60 | 50 | 40 | 35 | 30 | 25 | 20 |
| `animals_enter_borders` (§9.3) | no | no | no | no | no | no | yes | yes | yes |

‡ Turn gates are **scaled by game pace** (`paces.json` `growth_scale`): Quick ×0.67, Normal ×1.0,
Epic ×1.5, Marathon ×3.0.

Animal globals (`data/constants.json`, §9.3): `animal_land_per_unit` (60, density fallback),
`animal_detect_radius` (2, hunt range), `animal_spawn_per_turn` (2), `animal_xp_lifetime_cap` (10,
max XP a unit ever banks from animals), and `unit_sight` (2) / `city_sight` (3) — the fog radii the
spawner reuses to keep animals in the dark. Animal unit types are `data/units.json` entries with
`"classification": "animal"` (Wolf, Panther, Bear).

Supporting global constants (`data/constants.json`): `wild_city_min_distance` (6, min tiles from
civ culture), `wild_spawn_min_distance` (2, min tiles a unit spawns from civ units/cities),
`wild_city_ratio_num` / `wild_city_ratio_den` (3 / 2, the cities-per-civ gate), and the
`wild_land_per_unit` / `raider_land_per_camp` / `wild_creation_turns_elapsed` /
`wild_city_creation_turns_elapsed` / `wild_city_creation_prob` fallbacks used when a difficulty
omits its per-level value. The Ancient era's `no_wild_units` flag (`data/ages.json`) gates the
era check (BtS `bNoBarbUnits`).

### 15.11 Global warming (§11)

Constants in `data/constants.json` driving the global-warming degradation pass (game-rules §11):

| Constant | Value | Meaning |
|----------|------:|---------|
| `gw_base_terrain` | `desert` | The terrain that strikes degrade tiles toward (the terminal of the degrade chain). |
| `gw_chance` | 20 | Base per-strike landing chance (integer percent) before forest defence. |
| `gw_forest_ratio` | 50 | Weight of forest/jungle cover in `GW_DEFENSE = #FOREST/#LAND × gw_forest_ratio` (percent subtracted from the landing chance). |
| `gw_global_unhealth_ratio` | 20 | Weight of building unhealthiness in `GW_VALUE` (strikes per turn). |
| `gw_nuclear_ratio` | 50 | Per-nuke contribution to `GW_VALUE`: each detonation adds `gw_nuclear_ratio/100` strike attempts. |

A tile counts as forest cover (`#FOREST`) when its feature carries a positive `growth_probability`
(§11.3) — Forest and Jungle by default. `#BAD_HEALTH` is the summed structure `health_penalty`
across all cities; `#NUKES_EXPLODED` is `GameState.nukes_exploded`, the cumulative count of ICBM /
tactical-nuke / Nuclear-Plant-meltdown explosions.

---

## 16. Victory Conditions

| Condition | Trigger | Notes |
|-----------|---------|-------|
| Conquest | All other factions eliminated | Last faction with cities and units |
| Domination | Control ≥66% of land tiles AND ≥66% of world population | Borders + population threshold |
| Cultural | 3 cities each accumulate 50,000+ culture (Legendary level) | Only 3 cities need to reach this threshold |
| Space Race | Complete and launch the spaceship (Apollo Program + all 9 parts built) | Parts: SS Casing, Cockpit, Docking Bay, Engine, Life Support, Stasis Chamber, Thrusters + 2 more |
| Diplomatic | Win UN election with required % of votes | United Nations wonder must exist |
| Score | Reach a configured absolute score threshold first | The reference's 7th condition; expose as its own selectable win (currently folded into Time) |
| Time | Highest score at turn limit (2050 AD on standard) | Score = weighted sum of population, tiles, techs, wonders |

> **Seven canonical conditions** (reference): Conquest, Domination, Cultural, Space Race,
> Diplomatic, **Score**, and Time. This game previously shipped six — add **Score** as its own
> selectable condition (`data/win_conditions.json`).

---

## 17. Spaceship Parts (Space Race Victory)

All parts require Apollo Program national wonder. Parts must be built in cities and transported to the capital.

| Part | Tech Req | Resource | Production Cost | Count Needed |
|------|----------|----------|-----------------|--------------|
| SS Casing | Composites + Rocketry | — | 250 | 3 |
| SS Cockpit | Fiber Optics | — | 400 | 1 |
| SS Docking Bay | Satellites + Robotics | — | 250 | 1 |
| SS Engine | Fusion | — | 600 | 1 |
| SS Life Support | Ecology | — | 400 | 1 |
| SS Stasis Chamber | Genetics | — | 300 | 1 |
| SS Thrusters | Superconductors | — | 250 | 2 |

---

## 18. Diplomatic Assemblies & Resolutions (provisional)

> **⚠️ Provisional — newly implemented, not verified.** This section is the data companion to
> `game-rules.md` §7.2 (world assemblies, elections & resolutions), now wired through the
> `Assembly` module (`src/sim/assembly.gd`) and the catalogue in **`data/resolutions.json`**.
> The founding wonders, offices, vote-weight rules, resolution catalogue (including its **flavour
> text**), and constants below are **unverified placeholders** to be checked against the
> reference game and balance-tested. Effects are **partly wired, partly recorded-only** (the
> "Effect" column notes which). All values are integer math.

### 18.1 Founding Wonders

Each assembly is founded by a world wonder; `Assembly.active_body` returns the secular body when
any city holds the United Nations, else the religious body when any city holds the Apostolic
Palace, else **none** (razing the wonder dissolves the assembly).

| Wonder | Era | Tech Req | Cost | Assembly | Effect flag (in `structures.json`) | Office title |
|--------|-----|----------|------|----------|-------------------------------------|--------------|
| Apostolic Palace | Medieval | Theology | 400 | Religious | `religious_assembly` | Pope (resident) |
| United Nations | Modern | Mass Media | 1000 | Secular | `un_elections` | Secretary-General (resident) |

* The **religious assembly** organises around the belief of the city holding the Apostolic
  Palace (§9); the secular **United Nations** organises around all players and **supersedes** it.
* The United Nations **guarantees voting eligibility** so every non-eliminated player is a secular
  member.

### 18.2 Vote Weight

| Assembly | Per-member vote weight | Eligibility |
|----------|------------------------|-------------|
| Religious | population of the member's cities **holding the assembly's belief** | any player with ≥1 such city |
| Secular | total governed population | every non-eliminated player |

*The legacy `_resolve_assembly` population poll (raw total population per alliance → the §16
Diplomatic standing) still runs alongside, unchanged. Met-contact filtering of secular membership
(§7) is **not yet** applied — provisional.*

### 18.3 Resolution Catalogue

`data/resolutions.json` holds the catalogue. Each entry has `id`, `name`, `kind`
(`election`/`resolution`), `body` (`any`/`religious`/`secular` — which assembly may put it
forward), `effect` (dispatched by `Assembly.apply_effect`), an optional `pass_share` override,
and **`text`** — the proposal flavour read out at the session, with `{candidate}` `{proposer}`
`{target}` `{belief}` tokens substituted at runtime. A session presents **one** proposal, voted
**Yea / Nay / Abstain** by weight; it passes when the Yea share of the chamber's total weight
reaches `pass_share` (or the constant `resolution_pass_share`).

| Resolution | Kind | Body | Effect | Status |
|------------|------|------|--------|--------|
| Election of the Resident | election | any | Seat the presiding resident (front-runner candidate). | **wired** |
| Resolution of Supreme Leadership | election | any | Candidate's alliance **wins** (§16) — needs `pass_share` 67 and the Diplomatic win enabled. | **wired** |
| Resolution for Universal Peace | resolution | any | Global cease-fire: clears all wars and war-fatigue. | **wired** |
| Resolution of Economic Sanction | resolution | any | Embargo the target alliance (blocked from proposing/receiving trades, §7). | wired (trade block) |
| Resolution on Common Governance | resolution | any | Members adopt the resident's government civic where tech allows (§8). | **wired** |
| Resolution on the One Faith | resolution | religious | Members harbouring the belief adopt it as **state religion** (§8.1), no anarchy. | **wired** |
| Resolution of Open Worship | resolution | religious | Suspend state-religion spread blocks among members. | recorded only |
| Resolution on Non-Proliferation | resolution | secular | Forbid building/keeping nuclear units. | recorded only |
| Resolution of Tribute to the Resident | resolution | any | Grant the resident `resident_aid_gold`. | **wired** |

*"Recorded only" effects are stored on `gs.assembly.standing` but their full enforcement awaits
the relevant subsystems (free belief spread; nuclear units). The §4.5 "defiance of assembly
rulings" anger is not yet wired to the contentment model.*

### 18.4 Constants (in `data/constants.json`)

| Key | Value | Meaning |
|-----|-------|---------|
| `assembly_session_interval` | 12 | Turns between assembly sessions. |
| `resolution_pass_share` | 50 | Default Yea share of total chamber weight needed to pass (percent). |
| `resident_aid_gold` | 100 | Gold granted to the resident by the tribute resolution. |
| `assembly_defiance_anger` | 1 | Anger per turn for defying a ruling (constant present; **not yet** read). |
| `vote_share_required` | 67 | Share for the Supreme-Leadership election and the legacy Diplomatic standing (in `data/win_conditions.json`; mirrored as the resolution's `pass_share`). |

### 18.5 Engine touchpoints

`gs.assembly` (serialized) holds `{kind, belief_id, resident_player_id, last_session_turn,
standing, pending:{resolution_id, candidate_player_id, target_alliance_id, belief_id, pass_share,
text, votes}}`; `gs.pending_assembly_events` is the transient queue drained by the facade.
`Assembly.world_tick` (called from `TurnEngine.world_step` §3.7) opens/resolves sessions; the
`CAST_VOTE` command (`Commands.cast_vote` → `SimFacade._cmd_cast_vote` → `Assembly.cast_vote`)
records a vote; humans are prompted via the `CHOOSE_ELECTION` popup; computer players vote in
`PlayerAI.manage_assembly` (`Assembly.ai_vote`); and `assembly_event` is the facade signal.

---

## 19. Data field reference (provisional)

> **⚠️ Provisional — implemented, not verified.** This section documents JSON data fields
> and engine entity fields that exist in the code but were not enumerated in the sections
> above. All are implemented and serialized; values and names are subject to tuning.

### 19.1 Unit data fields (`data/units.json`)

The tables in §5 list the design-level unit properties. The following additional fields
appear in `units.json` and are read by the engine:

| Field | Type | Meaning |
|-------|------|---------|
| `can_found` | bool | Unit can found a settlement (`FOUND_SETTLEMENT` mission) |
| `can_build` | bool | Unit can build tile improvements (worker behaviour) |
| `draftable` | bool | Unit type can be conscripted via the draft (§6.6); only the most advanced draftable type is raised |
| `cargo_capacity` | int | Number of units this unit can carry as cargo (transport ships, carriers) |
| `transport_capacity` | int | Alternative capacity field used by some transport types (may alias `cargo_capacity`) |
| `consumed_on_use` | bool | Unit is removed from the map when it performs its primary action (Work Boat, Tactical Nuke, ICBM, Missile) |
| `blast_radius` | int | Chebyshev radius of area effect on detonation; used by nuclear weapons (§5.7) |
| `global_range` | bool | Unit can target any tile on the map regardless of `air_range` (ICBM tag) |
| `one_use` | bool | Equivalent to `consumed_on_use`; marks single-use weapons |
| `generated_by` | String | Specialist type that generates this Great Person unit, or `"combat_xp"` for the Great General (§14.1) |
| `per_specialist_output` | Dict | Per-specialist commerce/science/culture output the GP unit provides while garrisoned (specialist mode) |
| `classification` | String | Unit class: `"civilian"`, `"great_person"`, `"land"`, `"naval"`, `"air"` — used for combat class matching (§5.3) and garrison checks |
| `first_strikes` | int | Number of first-strike rounds the unit fires before normal combat |
| `intercept_strength` | int | Effectiveness as an air interceptor (fighter units) |
| `withdrawal_chance` | int | Percent chance (0–100) the unit retreats instead of dying |
| `combat_limit` | int | Maximum damage this unit can deal to a defending unit per combat (siege collateral cap) |
| `free_promotions` | Array | Promotion IDs granted when the unit is built or drafted |
| `replaces` | String | The standard unit ID this faction-unique unit replaces |
| `unique_to` | String | Society/faction ID; restricts availability to that faction |
| `upgrades_to` | Array | Unit IDs this type can upgrade into (requires gold + tech) |
| `upkeep` | int | Gold per turn maintenance cost |
| `air_range` | int | Maximum tiles an air unit can fly per mission |

### 19.2 Structure / building data fields (`data/structures.json`)

Fields beyond the headline effects table in §6:

| Field | Type | Meaning |
|-------|------|---------|
| `cultural_defence_bonus` | int | Additional culture-based defence rating added to the city's `Combat._settlement_defence` sum (§4.9, §5.3) |
| `espionage_output` | int | Flat EP added to the city's espionage output each turn (§7.1) |
| `requires_state_religion` | bool | Building can only be built when the city's owner has the matching state religion |
| `espionage_defense` | int | Flat EP modifier reducing enemy EP accumulated against this city |
| `heals_units` | bool | All units garrisoned in this city heal each turn regardless of stance (§5.6) |
| `free_promotion` | String | Promotion granted to every new unit built in this city |
| `free_promotion_all` | String | Promotion granted empire-wide to all new units |
| `land_xp` / `mounted_xp` / `naval_xp` / `archery_xp` / `siege_xp` / `air_xp` | int | XP bonus applied to new units of the named domain/class built in this city (§5.5) |
| `military_xp_city` | int | XP bonus applied to all military units built in this city |
| `unit_xp_all_cities` | int | Empire-wide XP bonus applied to all military units built anywhere |
| `is_wonder` | bool | Identifies this as a world wonder (only one may exist globally); counted in scoring (§10) |
| `is_national_wonder` | bool | Only one copy per player (not globally unique) |
| `wonder_type` | String | `"world"` or `"national"` — alternative to the boolean flags |
| `coastal_only` | bool | Can only be built in coastal cities |
| `coastal_allowed` | bool | Can be built in coastal cities (some buildings are land-only by default) |
| `building_req` | String | Building ID that must already exist in the city before this can be built |
| `obsoleted_by` | String | Tech ID after which this building no longer provides effects |
| `tier` | int | Build order tier (used for auto-build priority) |
| `built_by` | String | Great Person classification that can build this structure as an action |
| `era` | String | Era tag (used for availability gating alongside `tech_required`) |
| `replaces` | String | Standard building ID this faction-unique structure replaces |
| `unique_to` | String | Society/faction ID |
| `upkeep` | int | Gold per turn maintenance |
| `output_delta` | Dict | Per-field output modifiers (food/production/commerce) added to the city each turn |
| `effects` | Dict | Civic-style effect dictionary (read via `PolicyEffects` — same keys as §8 civic effects) |

### 19.3 Improvement data fields (`data/improvements.json`)

Fields beyond the headline table in §12:

| Field | Type | Meaning |
|-------|------|---------|
| `requires_river` | bool | Improvement can only be built on tiles adjacent to a river (Watermill) |
| `requires_feature` | String | Feature ID that must be present on the tile (Lumbermill: `"forest"`, Forest Preserve: `"forest"`) |
| `requires_improvement` | String | Improvement ID that must already exist on the tile (Railroad requires `"road"`) |
| `upgrade_only` | bool | This improvement is never built directly; it is only reached by upgrading from a lower tier (Hamlet, Village, Town) |
| `upgrade_turns` | int | Turns a worked tile must accumulate before auto-advancing to the next maturation stage (§4.10) |
| `upgrades_to` | String | Improvement ID of the next maturation stage |
| `movement_cost_override` | int | Fixed movement cost (in Fixed units) for tiles with this improvement, replacing the terrain default; Road = 34 (≈ 1/3 tile), Railroad = 0 |
| `allowed_landforms` | Array | Terrain IDs this improvement may be placed on |
| `output_delta` | Dict | Food/production/commerce yield changes added to the tile |
| `defence_bonus` | int | Percent defence bonus for units garrisoned on this tile |
| `pillage_value` | int | Gold awarded to the pillaging unit when this improvement is destroyed |
| `upkeep` | int | Gold per turn deducted from the owning player's treasury |

### 19.4 Promotion bonus keys (`data/promotions.json`)

Promotion entries support the following bonus-key fields read by `Unit.effective_strength`
and related combat code (§5.3):

| Key | Meaning |
|-----|---------|
| `combat_strength_bonus` | General percent strength modifier (stacks with Combat line) |
| `vs_melee` | Bonus percent strength when fighting melee-class opponents |
| `vs_mounted` | Bonus percent strength when fighting mounted-class opponents |
| `vs_gunpowder` | Bonus percent strength when fighting gunpowder-class opponents |
| `vs_ships` | Bonus percent strength when fighting naval units |
| `vs_fighters` | Bonus percent strength when fighting air units (interceptors) |
| `vs_fortified` | Bonus percent strength when the opponent has any entrenchment |
| `attack_vs_settlement` | Bonus percent strength when attacking a tile with an enemy settlement |
| `defense_in_settlement` | Bonus percent strength when defending inside a settlement |
| `defense_on_hills` | Bonus percent strength when defending on hills terrain (Guerrilla line) |
| `combat_in_forest` | Bonus percent strength when fighting in or from a forest tile |
| `first_strikes_bonus` | Additional first-strike rounds beyond the unit's base |
| `withdrawal_chance_bonus` | Additional percent added to the unit's withdrawal roll |
| `healing_bonus` | Extra HP healed per turn (§5.6) |
| `adjacent_heal_bonus` | HP healed per turn granted to adjacent friendly units |
| `adjacent_heal_in_enemy_territory` | HP healed to adjacent allies even in enemy territory |
| `movement_bonus` | Additional movement points |
| `forest_movement_bonus` | Ignore terrain movement penalty in forests/jungles |
| `ignore_terrain_cost` | All terrain costs 1 movement point |
| `vision_bonus` | Extra sight range tiles |
| `intercept_bonus` | Bonus when intercepting enemy air attacks |
| `evade_interception_chance` | Percent chance to avoid an interception roll |
| `reduce_enemy_intercept` | Reduces the enemy's interception chance |
| `hit_damage_reduction` | Percent damage reduction per hit received |
| `siege_bombard_damage_reduction` | Specific reduction against siege splash damage |
| `escort_damage_reduction` | Absorbs a share of damage directed at a carried unit |
| `extra_attacks` | Number of additional attacks per turn (e.g. Blitz) |
| `move_after_attack` | Unit retains remaining movement after attacking |
| `heal_while_active` | Unit heals even while moving (March) |
| `adjacent_xp_bonus` | XP bonus granted to adjacent friendly units after combat |
| `applies_to` | Array of unit classifications this promotion is valid for |
| `prereqs` | Array of promotion IDs that must be held first |
| `can_bombard` | Unit may use the `BOMBARD` mission |
| `no_amphibious_penalty` | Waives the amphibious attack strength penalty (§5.2) |
| `airlift` | City with this promotion can airlift one unit per turn |
| `sentry` | Grants the Sentry stance (auto-wakes when enemies approach) |
| `commando` | Unit can move through enemy ZOC without stopping |
| `formation` | Formation promotion effect (blocking mounted attacks) |

### 19.5 Serialized entity fields (provisional)

> **⚠️ Provisional.** These are the GDScript fields serialized to JSON by `SaveLoad` and
> restored on load. They represent the engine's in-memory state, not user-facing data.

#### Player (`src/sim/player.gd`)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | int | 0 | Player index |
| `name` | String | "" | Display name |
| `leader_id` | String | "" | Leader ID from `leaders_traits.json` |
| `treasury` | int | 0 | Current gold balance |
| `slider_finance/research/culture/intel` | int | 0/100/0/0 | Economic split percentages, sum = 100 |
| `state_religion` | String | "" | Active state religion belief ID (§8.1) |
| `current_research_id` | String | "" | Tech being researched (§6.3) |
| `era` | int | 0 | Cached era index; recomputed from techs each turn (§2.1) |
| `alliance_id` | int | -1 | Alliance the player belongs to |
| `free_early_wins` | int | 0 | Free tech wins from alliance shared research bonus |
| `transition_turns` | int | 0 | Remaining turns of anarchy (civic or state-religion switch) |
| `score` | int | 0 | Current score |
| `is_eliminated` | bool | false | Player has no units or settlements remaining |
| `is_ai` | bool | false | Controlled by `PlayerAI` |
| `celebration_turns` | int | 0 | Remaining turns of a We Love the King celebration |
| `events_fired` | Array | [] | IDs of one-shot events already triggered (§9) |
| `insolvent_turns` | int | 0 | Consecutive turns in the red; triggers structure/unit sales at the grace-period cap |
| `golden_age_turns` | int | 0 | Remaining turns of an active Golden Age (§14.4) |
| `golden_age_count` | int | 0 | Number of Golden Ages the player has had (used to escalate GP cost) |
| `pending_golden_age_gp` | int | 0 | GP points accumulated toward triggering the next Golden Age |
| `great_general_points` | int | 0 | Combat XP toward the next Great General (§14.2) |
| `great_general_threshold` | int | 0 | Threshold for the next Great General (escalates each time) |
| `great_generals_produced` | int | 0 | Total Great Generals born to this player |

#### Settlement (`src/sim/settlement.gd`)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | int | 0 | Settlement index |
| `name` | String | "" | City name |
| `owner_player_id` | int | -1 | Owning player |
| `x, y` | int | 0 | Map coordinates |
| `population` | int | 1 | Current city size |
| `output_food/production/commerce` | int | 0 | Cached per-turn outputs (updated each turn) |
| `production_queue` | Array | [] | Ordered list of items being built |
| `positive_sentiment` | int | 0 | Happiness points from all sources (§4.5) |
| `in_disorder` | bool | false | City is in disorder (unhappy citizens ≥ happy) |
| `wellbeing_positive/negative` | int | 0 | Health surplus/deficit (§4.6) |
| `worked_tiles` | Array | [] | Tile coordinates the city currently works |
| `manage_citizens_auto` | bool | true | City auto-assigns free workers; false = only lock-overrides |
| `belief_id` | String | "" | Religion present/dominant in this city (§8) |
| `econ_org_id` | String | "" | Corporation active in this city (§14.6) |
| `special_person_points` | int | 0 | GP points accumulated this city (§6.5) |
| `special_person_threshold` | int | 100 | Points needed for the next GP birth (escalates) |
| `special_persons_produced` | int | 0 | Total GPs born from this city |
| `rush_anger_turns` | int | 0 | Remaining turns of unhappiness from a production rush/draft |
| `garrison_turns` | int | 0 | Turns a military unit has been continuously garrisoned here |
| `defence_value` | int | 0 | Current city wall/fortification HP |
| `peak_population` | int | 1 | Highest population ever reached (used in cultural revolt formula §4.9) |
| `revolt_turns` | int | 0 | Remaining occupation revolt turns after capture (§4.8) |
| `revolt_progress` | int | 0 | Accumulated successful cultural revolts toward a flip (§4.9) |
| `alert_turns` | int | 0 | Turns this wild camp has been mustering raiders (§9.1) |
| `alert_target_x/y` | int | -1 | Map coordinates the mustered raiders march toward |
| `alert_cooldown` | int | 0 | Turns remaining before this camp can be roused again |

#### Unit (`src/sim/unit.gd`)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | int | 0 | Unit index |
| `unit_type_id` | String | "" | Key into `data/units.json` |
| `owner_player_id` | int | -1 | Owning player (-2 = wild faction) |
| `x, y` | int | 0 | Map tile coordinates |
| `base_strength` | int | 0 | Combat strength from data |
| `health` | int | 100 | Current HP (0–100) |
| `experience` | int | 0 | Accumulated XP |
| `experience_level` | int | 0 | Number of promotions taken |
| `promotions` | Array | [] | Promotion IDs currently held |
| `movement_total` | int | 200 | Full movement allowance in Fixed units (200 = 2 tiles) |
| `movement_left` | int | 200 | Remaining movement this turn |
| `entrenchment` | int | 0 | Current entrenchment bonus (percent, capped by data) |
| `stationary_turns` | int | 0 | Consecutive turns without moving or attacking |
| `cargo` | Array | [] | IDs of units carried as cargo |
| `transported_by` | int | -1 | ID of the transport carrying this unit (-1 = free) |
| `build_turns_left` | int | 0 | Turns remaining on current improvement build |
| `building_improvement` | String | "" | Improvement ID being built by this worker |
| `goto_x / goto_y` | int | -1 | Persistent go-to destination; -1 = no standing order |
| `has_moved` | bool | false | Unit has used movement this turn |
| `has_attacked` | bool | false | Unit has attacked this turn |
| `is_fortified` | bool | false | Fortify stance active (accumulates entrenchment) |
| `is_wild` | bool | false | Wild/barbarian unit (owner -2) |
| `is_animal` | bool | false | Wild **animal** (§9.3) — a wild unit with animal spawning/behaviour/combat limits |
| `xp_from_animals` | int | 0 | Lifetime XP this unit has banked from killing animals (capped, §9.3) |
| `is_sentry` | bool | false | Sentry stance — auto-wakes when enemies enter sight |
| `is_patrolling` | bool | false | Air/sea patrol stance |
| `is_healing` | bool | false | Heal-in-place stance |
| `is_sleeping` | bool | false | Sleep stance (stays idle until manually woken) |

---

## 21. Random events

The random-event system (`data/events.json`, rules in `game-rules.md` §9) is a
first-class, data-driven domain. Every event is **one self-contained record** — there
is no separate trigger table. A representative **vertical slice** of events ships
today (marked ✅ below); the remaining records and the 18 quests are catalogued here as
the authoritative data spec, with the engineering roadmap and per-event subsystem
requirements in `docs/planning/event-subsystem-planning.md`.

> Magnitudes are the reference's **normal/standard** values. Map-size and game-speed
> scaling of counts/magnitudes is deferred (planning doc §5); ship the standard
> integers verbatim.

### 21.1 Selection framework

| Stage | Rule |
|-------|------|
| **Grace** | No event fires before `event_grace_turns` (20) — a flat count, **not** pace-scaled. |
| **Per-era chance** | One roll per player per turn at `event_era_chance[era]` = `[1,2,4,4,6,8,10]`% (Ancient→Future) decides whether *any* event fires. |
| **Per-game roster** | At setup each event's `active`% is rolled once into `GameState.active_event_ids` (serialized); only rostered events can occur this game. |
| **Weighted pick** | Among eligible events, one is drawn weighted by `weight`. |
| **Eligibility** | In roster · all `prereq` hold · holds no `obsolete` tech · not a still-running timed instance · (if `one_shot`) unfired. |
| **Mandatory choice** | A human cannot End Turn while an event decision is unresolved. |
| **Determinism** | `range` magnitudes and `chance` branches are rolled once at fire time (fixed order) and baked into the resolved branches, so applying a choice draws no RNG. |

### 21.2 Record schema

```jsonc
"forest_fire": {
  "name": "...", "text": "...",
  "active": 70, "weight": 100,          // inclusion % and selection weight
  "prereq": { ... },                     // predicate dict (table below)
  "obsolete": ["nationalism", ...],      // any held tech disqualifies
  "choices": [ {"id","text","effects":[...]} ],  // OR a bare begin "effects":[...]
  "duration": 5, "expire_effects": [...] // optional timed event
}
```

**Prereq predicates** (all ANDed; absent keys impose no constraint):

| Key | Holds when |
|-----|-----------|
| `tech_all` / `tech_any` | player holds all / any of the listed techs |
| `building` | player owns the structure in some city |
| `civic` | the policy is active in some category |
| `state_religion` | player has adopted a state religion |
| `resource_absent` | player owns no tile with the resource |
| `min_pop` / `max_pop` | some owned city is ≥ / ≤ the size |
| `min_era` / `max_era` | player's era is within bounds (0–6) |
| `at_war` / `at_peace` | player's war state |
| `coastal` | some owned city is adjacent to sea |
| `players_tech {tech,count}` | ≥ count players hold the tech |
| `tile {terrain,feature,improvement,resource,route,in_city_radius}` | an owned tile matches every key given |

**Effect verbs** (begin / choice / expire / nested `chance.then`):

| Verb | Effect |
|------|--------|
| `gold` | treasury delta (`amount`, or `range:[min,max]` rolled at fire) |
| `research` / `research_pct_remaining` / `research_pct_loss` | beaker delta, or ± a percent of the current tech's remaining/full cost |
| `culture` | capital culture delta |
| `tech` | grant a named tech, or the cheapest researchable |
| `unit` / `spawn_wild` | spawn `count` of `unit_type` at the capital / as wild raiders nearby |
| `building` | grant a free structure in the capital |
| `capital_health` / `capital_pop` / `nearby_pop` | capital health / population, or nearby-city population (floored at 1) |
| `food_store` | capital food-store delta (`amount` or `pct`) |
| `heal_units` | restore all owned units |
| `golden_age` | start/extend a free Golden Age |
| `attitude {target,amount}` | diplo-memory delta toward a rival / all met players |
| `grant_promotion {promotion,classification?/domain?/unit_types?}` | gift a promotion to matching units |
| `city_happy_timed {amount,turns,scope}` | timed happy (+) / angry (−) face on capital / all / state-religion cities |
| `place_resource {resource,match,remove_feature?,add_improvement?,add_route?}` | seed a resource on a matching owned tile |
| `tile_yield {food?,production?,commerce?,match}` | permanent per-tile yield delta |
| `remove_feature` / `remove_improvement` / `remove_route` | clear a matching owned tile's feature / improvement / route |
| `chance {percent,then:[...]}` | fire-time roller: on success splice in `then` (supports the reference's "chance of option N" / loop) |

### 21.3 Event catalogue (1–174)

**Status:** ✅ shipped · ◻ planned (see planning doc for the subsystem each needs).
Magnitudes are normal/standard.

#### Events 1–40
| # | Name | Prereq | Obsolete | A/W | Result | Status |
|---|------|--------|----------|-----|--------|:--:|
|1|Forest Fire|forest in city radius|—|70/100|pay 10 / pay 4 + lose forest / lose forest + angry|✅|
|2|City Ruins|own city-ruins feature|radio/refrig/plastics/satellites/adv-flight/ecology|90/1000|15% tech / +gold for chance of more|◻|
|3|Happy Hunting|tundra forest + archery|steam/steel/sci-method/artillery|90/500|+8 food in city store|◻|
|4|Motherload|gold mine + road + early tech|—|90/200|20–40 gold|✅|
|5|Washed Out|road/rail|—|80/100|lose a road / pay 20|✅|
|6|At the Sword|1 damaged swordsman|machinery/feud/music/phil/civil/theo|100/500|+3 XP to that swordsman|◻|
|7|Man named Jed|scout/explorer + unrevealed oil under unit|—|75/5000|nothing / pay 10 reveal oil|◻|
|8|Inspired Mission|city w/ 2 religions incl. state|—|75/200|spread state religion 4/+1/+4 own & foreign|◻|
|9|Hymns & Sculptures|cathedral + 10 cathedrals globally|—|20/200|free Artist specialist|◻|
|10|Careless Apprentice|forge|radio/refrig/…|75/200|pay 50 / pay 10 lose forge / lose forge + angry|◻|
|11|Famine|—|—|70/100|nothing / -50% food + attitude / pay + -100% food + attitude|◻|
|12|Slave Revolt|slavery + pop≥4 + early tech|—|80/500|angry + -pop + revolt + chains|◻|
|13|Blessed Sea|*(Quest 1)*|—|—|see §21.4|◻|
|14|Airliner Crash|border + other has flight|—|70/300|+att / +1000 EP / +tech% -att|◻|
|15|Farm Bandits|farmed wheat/rice/corn + road + unit|—|85/200|pay 10 / -5 food + unit can't attack / -5 food|◻|
|16|Holy Mountain|*(Quest 2)*|—|—|see §21.4|◻|
|17|Horticulture|forest/jungle + calendar|—|80/200|+1 commerce tile / pay + chance / +health + scientist|◻|
|18|Fugitive|feudalism|—|90/200|±attitude chains|◻|
|19|Pestilence 1/2|pasture/plantation tile|—|55/100, 100/100|destroy tile improvement|◻|
|20|Marathon|at war, enemy first-strike|—|100/800|free Golden Age|✅ *(prereq simplified to at_war)*|
|21|Faux Pas|—|—|70/100|-1 attitude with an AI|✅|
|22|Joyous Wedding|same state religion as neighbour|—|90/200|nothing / pay + att / pay + att|◻|
|23|Wedding Feud|different state religion neighbour|—|90/200|-att / pay -att +happy / pay -att +att war-offer|◻|
|24|Left at the Altar|share borders w/ AI|—|80/100|-1 attitude|◻|
|25|Spicy|forest + calendar + ≤4 happy res + no spices|—|50/100|gain Spices / cultivate (plantation+road)|✅ *(happy-res prereq dropped)*|
|26|Tornado|plains improvement + early tech|—|75/200|improvement destroyed|◻|
|27|Baby Boom|signed a peace treaty|—|100/500|all cities +10 food store|◻|
|28|Bard's Tale|music|—|90/200|+100 / pay +450 / radio: pay +250 all|◻|
|29|Looters|angry citizen in neighbour AI city|—|70/100|pillage 1 / pay pillage 2-4 / -EP pillage + destroy bldg / -att|◻|
|30|Brothers in Need|same religion + tradeable spare resource + AI at war|—|100/1000|gift Copper/Iron/Horse/Ivory/Oil/Uranium|◻|
|31|Hurricane|coastal + early tech + pop>2|—|75/100|destroy cheap+expensive bldg / -1 pop|◻|
|32|Cyclone|coastal + early tech|—|70/100|destroy bldgs / -1 pop|◻|
|33|Tsunami|coastal + medieval tech|—|0/0|destroy city if <6 pop / lose bldgs+5 pop|◻ *(disabled, A=0)*|
|34|Monsoon|inland + early tech + jungle nearby|—|85/100|destroy bldgs / -1 pop|◻|
|35|Blizzard|tundra improvement + road + early tech|—|80/100|destroy improvement+route / pay 5|◻|
|36|Volcano|peak tile + early tech|—|70/100|destroy cottages around peak|◻|
|37|Dust Bowl|4 farmed plains + civil service|—|70/100|pay 40 lose farm / lose farm + loop|✅|
|38|Parrots|jungle + animal husbandry|—|85/50|+1 commerce tile|◻|
|39|Jade|mine + iron + road|—|85/50|+2 commerce tile|◻|
|40|Black Pearls|clams + fishing boat|—|70/50|+1 commerce tile|◻|

#### Events 41–80
| # | Name | Prereq | Obsolete | A/W | Result | Status |
|---|------|--------|----------|-----|--------|:--:|
|41|Saltpeter|4 forest-hill + gunpowder|—|90/20|+1 commerce tiles|◻|
|42|Clunker Coal|coal mine + road|—|90/50|-1 production tile|◻|
|43|Sour Crude|oil + well/platform|—|90/50|-1 production tile|◻|
|44|Truffles|grass tile|—|70/20|+1 food +1 commerce tile|✅|
|45|Sea Turtles|coastal + calendar|—|70/20|+1 food tile|◻|
|46|Tin|mined hill + bronze working|—|85/50|+2 production tile|◻|
|47|Prairie Dogs|plains + animal husbandry|—|70/50|+1 commerce tile|◻|
|48|Ice Sculpture|tundra + aesthetics|—|70/100|+100 culture / pay + settled great artist|◻|
|49|Appleseed|plains + civil service|—|75/50|tile gains forest + food|◻|
|50|Mining Accident|mine + several techs|—|90/200|pay 20 / pay 5 lose mine / lose mine + angry|◻|
|51|Breakthrough|—|—|80/50|+10% remaining tech|✅|
|52|Setback|—|—|65/30|-8% research|✅|
|53|Running Bulls|pastured cows + road + AH + feudalism|—|70/200|+100 / pay +300 culture|◻|
|54|Great Depression|≥1 founded corporation|—|40/100|all players -25% gold|◻|
|55|Bermuda Triangle|naval ship on ocean + flight|—|50/100|unit destroyed|◻|
|56|Patron of Knowledge|library|—|85/200|+10% tech / pay + library +1 research|◻|
|57|Master Smith|forge|—|70/100|+1 production for the forge|◻|
|58|Rural Farmers|grocer|—|80/100|+1 food for the grocer|◻|
|59|Money Changers|market|—|75/100|+1 gold for the market|◻|
|60|Bowyer|archery|nat/print/edu/gun/astro|35/50|all archers +Combat I|✅|
|61|Horseshoe|pastured horse + road|steam/steel/sci/artillery|30/50|all mounted +Flanking I|◻|
|62|Champion|peace + undamaged 3XP unit no Leadership|nat/print/…|30/50|unit gains Leadership|◻|
|63|Motor Oil|oil + well/platform|—|90/200|+50 gold / pay +15 free unit support|◻|
|64|Federal Reserve|free market + ≥1000 gold + corporation|—|90/200|-10% / pay -25% inflation|◻|
|65|Electric Company|emancipation + no angry + electricity|—|90/200|+1 happy every city|◻|
|66|Hindenburg|airship + radio|—|85/500|nothing / pay +1 happy per airport|◻|
|67|Comet Fragment|forest-tundra bare tile + rocketry|—|80/100|+5% spaceship +2 research/lab − forest|◻|
|68|Subway|public transport + pop≥25|—|80/400×|+5 commerce to public transport|◻|
|69|Gold Rush|mine + pop≤5 + industrial era|—|90/500|+1 pop / pay +3 pop|✅|
|70|Influenza|pop≥10 + modern/future + no medicine|—|45/400|pay -3 pop / -3 pop + nearby -2|◻|
|71|Solo Flight|≥8 landmasses + flight|—|90/100|+1 att with all met|◻|
|72|Antelope|bare forest + hunting + ≤4 happy res + can-have-deer|—|55/200|tile gains Deer / pay + road + camp|◻|
|73|Whale Of A Thing|ocean + sailing + ≤4 happy res + can-have-whale|—|50/100|tile gains Whale|◻|
|74|Hi Yo Silver|bare hill + mining + ≤4 happy res + can-have-silver|—|35/200|gains Silver / pay + mine + road|◻|
|75|Wining Monks|monastery + bare grass/plains + monarchy + no wine|—|65/100|gains Wine / pay + winery + road|◻|
|76|Independent Films|mass media + not own Hollywood|—|35/100|+1 Movie bonus|◻|
|77|Ancient Olympics|polytheism + non-Abrahamic state religion|machinery/…|75/400|nothing / pay +att all neighbours|◻|
|78|Modern Olympics|sci-method + Event 77.2 occurred|—|100/500|+1 att all met|◻|
|79|Interstate|universal suffrage + industrialism + emancipation|—|100/100|faster road movement|◻|
|80|Earth Day|environmentalism + industrialism/radio|—|95/100|+1 happy 10t all / pay + AIs switch Environmentalism|✅ *(AI-civic branch dropped)*|

#### Events 81–120
| # | Name | Prereq | Obsolete | A/W | Result | Status |
|---|------|--------|----------|-----|--------|:--:|
|81|Freedom Concert|free religion + ind/radio + 3-religion city|—|95/100|+1 pop +1 happy / spread religions|◻|
|82|Axe Haft|bronze working|nat/print/…|25/200|all axemen +Shock|◻|
|83|Tower Shield|mining|machinery/…|20/200|all melee +Cover|◻|
|84|Smokeless Powder|gunpowder|rifling/steel/sci|40/200|all musketmen +Pinch|◻|
|85|Stronger Fittings|machinery|nat/print/…|25/200|all crossbowmen +Combat I|◻|
|86|Firing Pins|military science|steam/sci/artillery|25/200|all grenadiers +Pinch|◻|
|87|Rifled Cannon|rifling + steel|radio/…|35/200|all cannons +Combat I|◻|
|88|Metal Decks|flight + industrialism|composites|35/200|all carriers +Drill III|◻|
|89|Long Range Fighters|flight|composites|20/200|all fighters +Range I|◻|
|90|Halberd|engineering|steam/…|25/200|all pikemen +Shock|◻|
|91|Reinforced Hull|metal casting|nat/print/…|25/200|all triremes +Combat I|◻|
|92|Cigarette Smoker|drama + theater|—|80/200|-30 / -10 + destroy theater / destroy + angry|◻|
|93|Heroic Gesture|at war and winning|—|80/350|nothing / make peace +att|◻|
|94|Great Mediator|at war ≥10 turns|—|85/200|nothing / make peace +att|◻|
|95|Forty Thieves|organized religion + horseback|nat/print/…|90/200|+2 commerce tile|◻|
|96|Ancient Texts|bare desert + steam/steel/sci/artillery|—|90/200|15% tech / pay +att all|◻|
|97|Waters of Life|oasis tile|medicine|95/200|+1 commerce tile|◻|
|98|Impact Crater|jungle/forest + physics + no uranium|—|20/200|nothing / pay reveal Uranium + mine|◻|
|99|The Huns|player knows HBR + player knows iron working|nat/print/…|20/200|4 barb horse archers|✅|
|100|The Vandals|metal casting + iron working (any player)|nat/…|20/200|4 barb swordsmen|◻|
|101|The Goths|mathematics + iron working|nat/…|20/200|4 barb axemen|◻|
|102|The Philistines|monotheism + bronze working|nat/…|20/200|4 barb spearmen|◻|
|103|The Vedic Aryans|polytheism + archery|nat/…|20/200|4 barb archers|◻|
|104|Holy Ritual|temple + incense plantation + road|—|90/200|pay 20|◻|
|105|Security Tax|walls + early tech|nat/print/…|70/500|20–80 gold|✅|
|106|Literacy|all cities have library + nat/print/…|—|30/100|1 city settled great scientist|◻|
|107|Farm Plows|forge + iron mine + road|—|90/100|30–60 gold|◻|
|108|Stained Glass|cathedral|—|90/100|40–70 gold|◻|
|109|Marble Statues|aesthetics + marble quarry + road|—|90/100|50–70 gold|◻|
|110|Crab Cakes|grocer + crabs + fishing boats|—|90/100|30–70 gold|◻|
|111|Boilers|steel + factory|—|90/100|90–140 gold|◻|
|112|Personal Computers|computers + factory|—|90/100|140–230 gold|◻|
|113|Fuel Additives|ecology + public transport|—|90/100|110–180 gold|◻|
|114|Hamburger Joint|radio + pastured cows + road|—|90/100|240–330 gold|◻|
|115|Tea|sci-method + harbor + not mercantilism|—|90/100|50–100 gold|◻|
|116|Fashion|radio + factory + silk plantation + road|—|90/100|180–260 gold|◻|
|117|Thoroughbred|stable + horse pasture + road|—|90/100|30–70 gold|◻|
|118|Girls Best Friend|forge + gems mine + road|—|90/100|120–180 gold|◻|
|119|Banana Split|refrigeration + banana plantation + road|—|90/100|160–240 gold|◻|
|120|Horse Whispering|*(Quest 3)*|—|—|see §21.4|◻|

#### Events 121–174
| # | Name | Prereq | Obsolete | A/W | Result | Status |
|---|------|--------|----------|-----|--------|:--:|
|121–126|Harbormaster / Classic Lit / Master Blacksmith / Best Defense / Sports League / Crusade|*(Quests 4–9)*|—|—|see §21.4|◻|
|127|Miracle|walls + state religion|—|90/200|+1 commerce walls / pay + spread religion 2|◻|
|128|Esteemed Playwright|theater + not slavery|—|85/200|+1 commerce theater / pay +3 culture|◻|
|129|Favorite Son|colosseum|steam/…|85/200|+20 gold / pay +2 culture colosseum|◻|
|130|Secret Knowledge|monastery + renaissance tech|—|70/200|15% religious tech / pay +4 culture monastery|◻|
|131|High Warlord|castle + not emancipation|radio/…|80/200|+100 gold / 2 pikemen / settled great general|◻|
|132|Spoiled Grain|granary|—|80/200|lose stored food / pay 20|◻|
|133|Angel of Mercy|hospital|—|80/200|+2 gold hospital / pay +1 happy hospital|◻|
|134|Chilly Flight|airport|—|80/200|+2 gold airport|◻|
|135|Industrial Fire|factory|—|80/200|destroy factory / pay 100|◻|
|136|Laboratory|laboratory + free speech|—|80/200|15% tech|◻|
|137|Experienced Captain|drydock + 7XP naval unit|—|95/200|+2 gold drydock / pay + Military Academy|◻|
|138|Heresy|theocracy|—|85/200|angry + spread / pay +15% religious tech / nothing|◻|
|139|Partisans|emancipation + a razed city|—|35/0|drafted units at site / half at capital|◻ *(disabled, W=0)*|
|140|New Dynasty|hereditary rule + capital + medieval tech|—|45/100|settled great general/merchant/priest|◻|
|141|Crisis in the Senate|representation + nat/print/…|—|55/100|+2 EP barracks / 400-600 gold / +1 happy all|◻|
|142|Too Close To Call|universal suffrage + nat/…|—|60/100|+1 gold courthouses / +3 culture courthouses|◻|
|143|Charismatic|police state + nat/…|—|65/100|all gun units +March / +2 happy all|◻|
|144|Friendly Locals|damaged unit|—|90/50|unit +1 XP|◻|
|145–153|Greed / War Chariots / Elite Swords / Warships / Guns Butter / Noble Knights / Overwhelm / Corporate Expansion / Hostile Takeover|*(Quests 10–18)*|—|—|see §21.4|◻|
|154|Civ Game|computers|—|80/100|+1 happy all / +3 research universities / ~320 gold|◻|
|155|Slave Revolt Warning|slavery + pop≥4|—|0/0|warning text only|◻ *(A=0)*|
|156|Immigrants|≥55 culture/turn city + net-happy + printing press|—|80/200|+1 pop|◻|
|157|Healing Plant|—|feudalism/machinery/phil|70/100|timed happy / angry chains / health faces|◻|
|158|Great Beast|camp + hunting + polytheism + state religion|education|75/100|+1 food / pay +pop / +happy 40t state-religion cities|◻|
|159|Controversial Philosopher|capital >35 research + theocracy + philosophy|sci-method|75/1000|+happy 15t / -happy + scientist / pay + Academy|◻|
|160|Defecting Agent|≥5 intelligence agencies + contact|—|75/100|-300 EP / pay chance / -2 att|◻|
|161|Jail|jail|—|80/100|-1 happy / pay 100|◻|
|162|Spy Discovered|industrialism + contact + ≥4 cities + capital|robotics|60/100|+400 EP +att / pay + Great Spy / war + support + tanks|◻|
|163|Nuclear Protests|free speech + ≥10 nukes|—|75/120|disband nukes +3 happy / -2 happy 1 city / pay 400|◻|
|164|Better Coal|coal mine|—|75/100|+4 production coal plants / +2 prod +1 health drydocks|◻|
|165|Broken Dam|hydro plant|—|75/100|lose plant + angry -pop / pay variants|◻|
|166|Rabbi|Judaism + Jewish monastery + paper|mass media|0/0|convert cities / scientist / culture+gold|◻ *(A=0)*|
|167|Golden Buddha|Buddhism + forge + gold mine + road|steam power|0/0|180-200 gold / +6 culture forge / +350 culture all|◻ *(A=0)*|
|168|Preaching Researcher|Christianity + Christian monastery + university|—|0/0|+2 culture / pay +culture +research monastery|◻ *(A=0)*|
|169|Toxcatl|Aztec + sacrificial altar + ≥1 unit|education|90/100|+2 angry / pay + unit immobile 3t|◻|
|170|Dissident Priest|Egyptian + non-state-religion non-capital city + 30 culture|printing press|90/100|angry + revolt / angry all / pay + libraries +research|◻|
|171|Pasture Built|cow/horse/sheep/pig bare tile + animal husbandry|calendar|80/100|tile gains pasture + road|◻|
|172|Rogue Station|broadcast tower + assembly line + Russian + state property + contact|—|90/100|-EP lose tower / angry / angry + factories prod|◻|
|173|Anti-Monarchists|French + hereditary rule|—|90/100|+3 happy palace / +2 gold cathedrals|◻|
|174|Impeachment|American + constitution + capital|—|90/100|+6 angry +1 happy 10t all / +2 prod courthouse + revolt|◻|

**3.13 changelog deltas** (apply when porting): many ancient/classical events also
obsolete with **Astronomy**; events 130/141/142/143 may also occur *after* Astronomy;
the quests gain a **One City Challenge** human gate; barbarian-uprising events use a
dedicated city-attack AI.

### 21.4 Quest catalogue (1–18) — deferred subsystem

Quests are **multi-turn goals**: a trigger arms the quest, the player pursues an
**aim** over many turns (often under a constraint), and completing it grants a
**reward** (frequently a choice of three). This needs a Quest-tracking subsystem
(`GameState.active_quests`, a per-player progress step, aim/constraint predicates) not
yet built — design in `docs/planning/event-subsystem-planning.md` §4. Counts shown are
standard-size; the reference scales them by world size's default player count.

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

## 22. Specialists

`data/specialists.json`. **14 first-class specialist types** — 7 working specialists a
city may assign citizens to, plus their 7 great-person counterparts (settled
super-specialists). Each carries a per-head `output` vector over the six yield channels
(food / production / commerce / science / culture / espionage), the great-person points
it banks per turn (`gp_points`) and of which type (`gp_type`), the great-person unit a
dominant pool births (`great_person_unit`), and slot rules. This is the data-side
companion to §14.5 (specialist slots and sources).

### 22.1 Working specialists

| Type | Output | GP type | GPP/turn | Births | Default slots |
|------|--------|---------|:--------:|--------|:-------------:|
| `citizen` | — | — | 0 | — | unlimited (`-1`) |
| `priest` | +1 production, +1 commerce | priest | 1 | `great_prophet` | 1 |
| `artist` | +3 culture | artist | 1 | `great_artist` | 1 |
| `scientist` | +3 science | scientist | 1 | `great_scientist` | 1 |
| `merchant` | +3 commerce | merchant | 1 | `great_merchant` | 1 |
| `engineer` | +2 production | engineer | 1 | `great_engineer` | 1 |
| `spy` | +3 espionage | spy | 1 | `great_spy` | 1 |

### 22.2 Settled Great People (super-specialists)

`is_great: true`; `default_slots: 0` and `gp_points: 0` (they occupy no city slot and
bank no further GPP — they are the settled reward form).

| Type | Output | GP type |
|------|--------|---------|
| `great_priest` (Settled Great Prophet) | +2 culture | priest |
| `great_artist` | +3 culture | artist |
| `great_scientist` | +3 science | scientist |
| `great_merchant` | +3 commerce | merchant |
| `great_engineer` | +2 production | engineer |
| `great_general` | +2 production | engineer |
| `great_spy` | +3 espionage | spy |

> The engine currently collapses settled Great People into their working specialist type;
> the `great_*` records are kept for parity/validation and city-screen display.

**Slots** = `default_slots` (available without buildings; `-1` = unlimited, for `citizen`)
+ per-structure `specialist_slots` + the Caste System civic's `unlimited_specialists`.

**Reference parity:** the reference's `GameSpecialistInfos.xml` lists exactly these 14
types (`CITIZEN … GREAT_SPY`). ✅ **Complete.**

---

## 23. Corporations

`data/econ_orgs.json`. Player-foundable economic organisations that spread between cities
via an executive unit, consuming input resources for a per-city yield. This is the
data-side companion to §14.6. The project ships **10** corporations (the reference defines
7); each carries the full reference model — HQ building, executive spreader, input set,
per-city maintenance, and an HQ gold share.

| Corp | Input resources | Per-city output | HQ structure |
|------|-----------------|-----------------|--------------|
| `merchant_guild` | gold | +4 commerce | `merchant_guild_hq` |
| `cereal_mills` | wheat, rice, corn | +1 food per distinct input present | `cereal_mills_hq` |
| `creative_constructions` | marble, stone | +2 production | `creative_constructions_hq` |
| `aluminum_co` | aluminum | +3 production | `aluminum_co_hq` |
| `mining_inc` | iron, copper, coal | +2 production per distinct input present | `mining_inc_hq` |
| `sids_sushi` | crab, clam, fish | +2 food | `sids_sushi_hq` |
| `civilized_jewelers` | gems, gold, silver | +4 commerce | `civilized_jewelers_hq` |
| `standard_ethanol` | sugar, corn, wheat | +1 food, +1 commerce | `standard_ethanol_hq` |
| `overseas_trading_co` | silk, dye, spices | +4 commerce | `overseas_trading_co_hq` |
| `nationalist_mutual` | oil, coal | +3 commerce | `nationalist_mutual_hq` |

Output is either a flat `output_delta` per city, or an `output_per_input_resource` scaled
by the count of distinct input resources reachable by that city (`cereal_mills`,
`mining_inc`). Shared fields on every corporation:

| Field | Value | Meaning |
|-------|:-----:|---------|
| `executive_unit` | `executive` | The spreader unit that establishes the corp in a new city. |
| `maintenance` | 3 | Gold/turn per city the corp operates in. |
| `hq_gold_per_input` | 2 | Gold to the HQ city per input resource the corp consumes. |
| `spread_cost` | 200 | Production/gold cost for an executive to spread the corp. |
| `spread_chance_base` | 15 | Base % chance an AI/auto spread succeeds. |

**Reference parity:** the reference's `GameCorporationInfo.xml` defines 7 corporations,
each paired with a `BUILDING_CORPORATION_n` HQ and an `EXECUTIVE_n` unit. The project ships
10 with the full HQ/executive/maintenance model. ✅ **Complete** (exceeds the reference
count).

---

## 24. Goody huts

> **Status: complete** — all **12** goody records are specified below and shipped:
> placement, consumption, every record, the parameter refinements listed after the
> table, and the full per-difficulty weight tables all match `data/goodies.json` /
> `data/difficulties.json` and `Events.exploration_reward` exactly.

`data/goodies.json` + `MapGen.place_goody_huts`. Map-placed discovery sites; the first land
unit to enter a hut consumes it and rolls one reward weighted by `weight`.

**Placement:** one hut per `goody_hut_land_per_hut` (28) passable land tiles, kept at least
`goody_hut_min_distance_from_start` (4) tiles from any start.

**Reward table** (consumed by `Events.exploration_reward`; weights are relative, and a
weight of 0 means the record is rolled only where a difficulty overrides it upward):

| id | type | weight | Effect | Status |
|----|------|:------:|--------|:------:|
| `gold` | treasury | 30 | 20–80 gold | shipped |
| `gold_large` | treasury | 12 | 40–120 gold — the premium treasury tier | shipped |
| `map` | map | 18 | reveal radius 4 (signal-only, no sim state) | shipped |
| `experience` | experience | 16 | 5–15 XP to the unit | shipped |
| `heal` | heal | 10 | unit restored to full health | shipped |
| `unit` | unit | 11 | spawn a `warrior` for the discoverer | shipped |
| `settler` | unit | 0 | spawn a `settler` — easy difficulties only (enabled via `goody_weights`) | shipped |
| `worker` | unit | 0 | spawn a `worker` — easy difficulties only (enabled via `goody_weights`) | shipped |
| `scout` | unit | 5 | spawn a `scout` | shipped |
| `tech` | tech | 8 | grant one free researchable tech | shipped |
| `ambush` | ambush | 7 | discoverer takes 50% damage (`damage: 50`) | shipped |
| `ambush_strong` | ambush | 4 | wild-raider ambush: each tile adjacent to the site has a 40% chance to spawn a wild `warrior` (owner −2), minimum 2 spawned (`spawn_chance: 40`, `min_spawn: 2`, `spawn_unit: "warrior"`) | shipped |

**Parameter refinements** (shipped — JSON fields on the records above):

- `map` — centre the reveal on the least-explored point within 4 tiles of the site
  (`offset: 4`) and reveal each tile inside the radius with 80% probability
  (`reveal_chance: 80`).
- `heal` — eligibility gate `damage_prereq: 60`: the reward can only be rolled when the
  discoverer has lost at least 60% of its maximum health (otherwise re-roll).
- `ambush` — in addition to the 50% damage, spawn wild raiders around the site: each
  adjacent tile has a 20% chance to spawn a wild `warrior`, minimum 1
  (`spawn_chance: 20`, `min_spawn: 1`, `spawn_unit: "warrior"`).
- Both ambush tiers carry `bad: true`. A `bad` reward is re-rolled when it cannot apply —
  no raider can be placed (no legal adjacent tile, or wild forces are disabled for the
  game) — and a discoverer whose unit classification is recon (the `scout` line) never
  receives a `bad` reward at all (re-roll).

**Per-difficulty availability** — a difficulty may override any goody's weight via
`difficulties.json` `goody_weights` (id → weight). Every difficulty ships the full
override table below (each difficulty column is a full weight set normalised to sum
100; 0 = never rolled at that difficulty):

| id | settler | chieftain | warlord | noble | prince | monarch | emperor | immortal | deity |
|----|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| `gold` | 10 | 10 | 15 | 20 | 20 | 20 | 25 | 25 | 25 |
| `gold_large` | 20 | 20 | 15 | 15 | 10 | 5 | 5 | 0 | 0 |
| `map` | 5 | 5 | 10 | 10 | 10 | 10 | 10 | 10 | 5 |
| `experience` | 5 | 5 | 5 | 10 | 10 | 10 | 5 | 5 | 5 |
| `heal` | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| `unit` | 10 | 10 | 10 | 10 | 10 | 10 | 5 | 5 | 5 |
| `settler` | 10 | 10 | 5 | 0 | 0 | 0 | 0 | 0 | 0 |
| `worker` | 10 | 10 | 5 | 0 | 0 | 0 | 0 | 0 | 0 |
| `scout` | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 | 5 |
| `tech` | 20 | 15 | 15 | 10 | 10 | 10 | 10 | 10 | 10 |
| `ambush` | 0 | 5 | 5 | 10 | 15 | 15 | 15 | 15 | 10 |
| `ambush_strong` | 0 | 0 | 5 | 5 | 5 | 10 | 15 | 20 | 30 |

The pattern: free `settler`/`worker` rewards exist only at the three easiest levels; the
premium gold tier fades out and disappears at the two hardest; weak ambushes are absent at
the easiest level and strong ambushes at the two easiest, then together they climb to 40%
of all rolls at the hardest; `heal` and `scout` stay flat at 5 everywhere; `tech` is twice
as common at the easiest level as at normal-and-above. (§28's start-fairness pass has an
extras step that can scatter additional discovery sites near below-par starts.)

---

## 25. Espionage missions

> **Status: complete (18 mission types)** — the thirteen active, state-changing
> missions run from two paths: the alliance-scope espionage screen and a spy unit
> standing on a foreign city tile (§25.5). The five passive, information-gathering
> missions are **standing EP thresholds** (§25.6): they never run and spend
> nothing — their intel stays revealed while the attacker's banked EP against the
> target meets a distance-scaled threshold. What they reveal is defined by the
> **information-fog rules** (§25.6): a rival city shows only its defensive
> posture, foreign spies are invisible, and rival demographics/research are
> hidden until the matching passive threshold is met.

### 25.1 How a mission runs

`data/espionage_missions.json` holds the catalogue. Each turn a player's espionage output
accrues as **intel points (EP)** ledgered *per target alliance* (§7, §15.5). EP is the
currency these missions spend. The flow in `SimFacade._cmd_espionage_mission` is:

1. **Resolve** the named mission record (rejected if absent from the table).
2. **Gate** — the mission's per-verb *target gate* must hold *before any EP is spent*
   (`_mission_target_valid`): e.g. `steal_tech` needs a tech the target knows and the
   attacker lacks; `destroy_building` needs a target city holding a razeable structure.
   A gate-failed mission spends nothing.
3. **Pay** — the attacker must hold at least the mission's cost in EP against that
   alliance; the cost is deducted whether or not the mission then succeeds.
4. **Interception** — a `gs.rng` roll against the mission's interception chance. On a hit
   the EP is still spent but the effect is suppressed ("mission intercepted").
5. **Apply** — `_espionage_apply` dispatches the `effect` verb, mutating game state
   deterministically. Every city-targeting verb acts on the **most populous valid target
   city** (lowest settlement id breaking a tie), so outcomes are reproducible.

### 25.2 Cost and interception

**Cost** = `intel_mission_cost` (100) × `cost_multiplier`/100 × (1 + EP-advantage/100),
where the EP-advantage is how much more EP the *target* holds against the attacker than the
attacker holds against the target (a well-defended rival costs more to strike), capped by
`intel_cost_advantage_max` (200). When the attacker is ahead the surcharge is zero and the
cost floors at the scaled base.

**Interception** = `intel_interception_chance` (25%) base
+ the strongest `espionage_defense` structure across the target's cities
+ the mission's own `interception_modifier`
+ `intel_counterespionage_bonus` (25) if any target member holds **active
counterespionage cover** against the attacker's alliance,
capped at `intel_interception_max` (90%).

All five constants live in `constants.json` and the arithmetic is computed in `SimFacade`.

### 25.3 The catalogue

Magnitudes (`amount`, `duration`) live in the mission record — the table is the single
source of mission tuning. Each `effect` verb has a matching handler in
`SimFacade._espionage_apply` and a target gate in `_mission_target_valid`.

| id | name | effect | `cost_multiplier` | `intercept` | magnitude fields | What it does |
|----|------|--------|:-:|:-:|---|---|
| `steal_tech` | Steal Technology | `steal_tech` | 100 | 0 | — | Copies one technology a target member knows that the attacker lacks. |
| `sabotage` | Sabotage Production | `sabotage` | 80 | 0 | — | Halves a target city's stored production. |
| `destroy_building` | Destroy Building | `destroy_building` | 100 | +5 | — | Razes the **costliest non-Palace** structure in the largest target city. |
| `destroy_project` | Destroy Project | `destroy_project` | 150 | +5 | — | Cancels an in-progress **endgame project** and wipes its stored production. |
| `destroy_improvement` | Destroy Improvement | `destroy_improvement` | 75 | 0 | — | Clears the improvement on a tile worked by a target city. |
| `steal_gold` | Steal Treasury | `steal_gold` | 300 | 0 | `amount` 100 | Transfers up to `amount` gold from the richest target member to the attacker. |
| `poison_water` | Poison Water | `poison_water` | 120 | +20 | — | Removes 1 population from the largest target city (population ≥ 2). |
| `insert_culture` | Spread Culture | `insert_culture` | 120 | +5 | `amount` 100 | Adds `amount` of the **attacker's** cultural influence to the largest target city's tile, feeding §4.9 revolt pressure. |
| `incite_unhappiness` | Foment Unrest | `incite_unhappiness` | 120 | +10 | `amount` 3, `duration` 5 | Adds a timed angry-citizen modifier of `amount` faces for `duration` turns to the largest target city. |
| `incite_revolt` | Incite Revolt | `incite_revolt` | 650 | +20 | `duration` 3 | Tips the largest target city into disorder and starts a `duration`-turn revolt during which it produces nothing. |
| `switch_civic` | Foment Anarchy | `switch_civic` | 200 | +10 | `duration` 2 | Throws the largest target city's owner into `duration` turns of governmental anarchy. |
| `switch_religion` | Incite Schism | `switch_religion` | 180 | +10 | `duration` 2 | Strips the state religion from a target member that has one and forces `duration` turns of anarchy. |
| `counterespionage` | Counterespionage | `counterespionage` | 100 | 0 | `duration` 5 | The attacker holds **+`intel_counterespionage_bonus`% interception** of the target alliance's missions for `duration` turns. |

### 25.4 State touched

Most verbs read and write existing aggregates, so they compose with the rest of the
engine rather than carrying bespoke state:

- **`destroy_building`** removes from `Settlement.structures` (and clears any matching
  `structure_bonuses`); the Palace is never targetable.
- **`destroy_project`** dequeues the project at the head of `production_queue` and zeroes
  `production_store`.
- **`destroy_improvement`** clears `Tile.improvement_id` / `improvement_turns_left` /
  `improvement_age` on a worked tile.
- **`insert_culture`** adds to `Tile.influence[attacker]`, which the §4.9 cultural-revolt
  subsystem reads directly when judging whether a city flips.
- **`incite_unhappiness`** appends a `{amount, turns_left}` entry to
  `Settlement.timed_happiness` — the same timed-anger channel random events use, which
  decays one turn at a time.
- **`incite_revolt`** sets `in_disorder`, fills `discontented`, and raises `revolt_turns`.
- **`switch_civic` / `switch_religion`** set the victim player's `transition_turns`
  (anarchy), and the religion variant also clears `state_religion`.
- **`counterespionage`** writes the attacker's `Player.counter_espionage` ledger
  (rival alliance id → turns), ticked down each turn in `TurnEngine._tick_states` and
  read back by the interception calculation. Both this ledger and `intel_points` are
  int-keyed and coerced back to int on load (the recurring JSON key-type discipline).

### 25.5 Spy units on tiles

Besides the alliance-scope espionage screen, the same thirteen missions can be run by a
**spy unit** physically standing in a target city — a unit carrying the `espionage` tag
in `data/units.json` (the Spy). Three rules govern a spy's behaviour, all enforced in
`SimFacade` so the UI never offers an order the rules would reject:

- **Spies can stand on any city tile, friendly or foreign.** A spy *infiltrates*: in
  `Pathfinding.find_path` an espionage unit ignores civilian borders (it may cross and
  traverse foreign territory), and `_cmd_move_stack` / `can_stack_move` route an all-spy
  stack onto a city tile as a **peaceful relocation** — never combat — even into a
  garrisoned city or one its owner is at war with. (A spy still cannot tunnel *through* an
  enemy field stack; it just needs a path to the city.) Non-spy civilians are unaffected
  and still cannot enter foreign territory at peace.
- **Spies cannot be attacked.** `Stack.get_defender` skips espionage units, so a tile
  holding only spies has no defender and is not a hostile/attackable target. A spy stacked
  under a real defender is never chosen as the victim; the military unit takes the blow.
- **Spies are invisible to everyone but their owner.** The world view draws (and
  stack-badges) a foreign espionage unit for no one, the tile readout omits it, and
  `Pathfinding._has_enemy` ignores it — a hidden spy neither blocks a rival's path
  nor leaks its position by making its tile read as occupied. A unit moving onto a
  tile held only by a hidden enemy spy simply shares it (no combat is possible).
- **A spy acts only from a foreign city tile, and only at full movement.** The action gate
  (`_spy_target_city`) requires the unit to be an espionage unit with its **whole movement
  allowance unspent**, standing on a settlement owned by a *different alliance*. The
  mission then strikes **that specific city** (and its owner), not the alliance's largest —
  the per-effect handlers and gates take an optional target city for exactly this. Running
  a mission consumes the spy's entire turn (`movement_left → 0`). A spy on its own/allied
  city, on open ground, or with spent movement is offered nothing.

The command is `Commands.spy_mission(player, unit, mission_id)` →
`SimFacade._cmd_spy_mission`, which derives the target alliance from the city's owner and
shares the validate → pay → interception → apply pipeline (`_run_espionage_mission`) with
the screen path. The HUD lists a spy's available missions via
`SimFacade.spy_mission_options(unit_id)`, which returns **only valid (gate holds) and
usable (affordable)** rows — empty whenever the spy cannot act, which is the signal for the
selection panel to show no espionage buttons.

**An intercepted tile mission captures the spy.** `_run_espionage_mission` reports its
outcome (`MissionRun.REJECTED` / `EXECUTED` / `INTERCEPTED`); on interception the
spy-on-tile path destroys the spy unit (the EP is already spent, and the command still
counts as an attempted mission) with a "spy captured" notification to the owner. The
alliance-scope screen path involves no unit, so interception there only wastes the EP,
as before. The computer player runs spies through `PlayerAI._manage_spy` (§B7,
`ai-design.md`): it builds up to `ai_spy_count` spies once a rival is met, marches them
to the nearest rival city, and on station runs the highest-priority affordable mission
(steal_tech → steal_gold → sabotage → destroy_building → poison_water →
incite_unhappiness), deterministically.

### 25.6 Passive intelligence and information fog

The five passive records complete the 18-type reference catalogue. They are **not
runnable** (`_run_espionage_mission`, `espionage_mission_options`, and
`spy_mission_options` all exclude `kind: "passive"`) and spend no EP. Instead each is a
**standing threshold**: its intel is revealed *while*

```
EP(attacker → target alliance)  ≥  intel_mission_cost × threshold_multiplier/100
                                   × (1 + capped EP-advantage/100)     ← §25.2 curve
                                   × (1 + intel_passive_distance_percent/100 × d/D)
```

where `d` is the Chebyshev distance from the viewer's capital to the target city
(city-scope) or the target's nearest city (alliance-scope), and `D` is half the sum of
the map's dimensions. Knowledge is therefore a **pure function of current EP** — nothing
new is serialized, save/load is untouched, and dropping below a threshold re-hides the
intel. The arithmetic lives in `SimFacade._passive_intel_threshold` /
`_passive_intel_active`, with current-player wrappers `passive_intel_threshold` /
`passive_intel_active` feeding the espionage advisor (which shows locked rows as
"have/need EP" progress).

| id | scope | `threshold_multiplier` | What it reveals while held |
|----|-------|:-:|---|
| `see_demographics` | alliance | 50 | Each member's empire statistics (population, cities, land tiles, production, GNP, unit count/power — `SimFacade.player_demographics`) on the espionage advisor. |
| `investigate_city` | city | 80 | The full civilian readout of that city — population, current production, complete structure list — in the tile readout and the advisor (`city_intel_lines`). |
| `see_research` | alliance | 120 | Each member's current research target and progress (`SimFacade.player_research_info`). |
| `city_visibility` | city | 160 | Live sight over the city and its surroundings within `intel_city_visibility_radius` (2), merged into `player_visible_tiles` so the fog lifts; derived live, never committed to fog memory. |
| `detect_missions` | alliance | 200 | Attribution: an espionage mission the target runs against you (executed *or* intercepted) is reported with the perpetrator's name instead of anonymously (`_intel_detects`). |

**The information fog these lift** (the baseline a player sees without intel):

- **A rival city shows only its defensive posture** — defence bonus percent
  (`Combat.settlement_defence`), siege HP out of `TurnEngine.city_max_health`, its
  defensive structures (positive `defence_bonus`/`cultural_defence_bonus`), and a
  garrison summary. Population, production, religion, and the full building list are
  hidden until `investigate_city` is met. Alliance-mates stay fully readable.
- **Foreign spies are invisible** everywhere (§25.5).
- Rival demographics and research appear nowhere in the UI until the matching
  passive threshold is met.

Constants: `intel_passive_distance_percent` (100) and `intel_city_visibility_radius`
(2) in `constants.json`, beside the §25.2 five. Validation: a passive record must carry
a positive `threshold_multiplier`, a `scope` of `alliance`/`city`, and a known passive
effect verb (`DataDB._validate_espionage_mission_refs`).

---

## 26. Diplomacy attitude & memory

> **Status: incomplete** — attitude levels, live factors, decaying memory, and deal gates
> are modelled; the reference's **denial-reason** layer (structured codes for why an AI
> refuses a deal) is not.

`data/diplomacy.json`. `attitude_base` is the neutral starting score; live factors and the
running memory total are summed onto it, clamped to 0–100, then mapped to an attitude
level. All integer math (provisional, not balance-tested).

**Attitude levels** (`attitude_base` = 50; `attitude_thresholds` = [20, 40, 60, 80]):

| Level | Name | Score range |
|:-----:|------|-------------|
| 0 | furious | 0–19 |
| 1 | annoyed | 20–39 |
| 2 | cautious | 40–59 |
| 3 | pleased | 60–79 |
| 4 | friendly | 80–100 |

**Live factors** (recomputed each turn from current relations):

| Factor | Δ |
|--------|:--:|
| `at_war` | −45 |
| `shared_war` | +12 |
| `shared_religion` | +12 |
| `different_religion` | −8 |
| `permanent_ally` | +25 |
| `active_deal` | +8 |

**Memory kinds** (accrue when a rival acts via `Diplomacy.record`; decay toward zero by
`decay`/turn via `Diplomacy.decay`; the running total is capped at `memory_cap` = 120):

| Kind | Value | Decay/turn |
|------|:-----:|:----------:|
| `declared_war` | −30 | 1 |
| `broke_deal` | −25 | 1 |
| `razed_city` | −40 | 1 |
| `fair_trade` | +8 | 1 |
| `traded_tech` | +6 | 1 |
| `made_peace` | +8 | 1 |
| `gave_gift` | +10 | 1 |
| `event` | 0 | 1 |

**Gates:** `deal_accept_min_attitude` = 1 (an AI must be at least *annoyed* to accept a
deal); `war_min_attitude` = 2 (attitude gate on war behaviour).

**Deals:** `gs.deals` holds standing deal objects — one-off deals resolve immediately;
**recurring** deals carry a `recurring` block whose `give.resources` flow proposer→accepter
each turn while the deal stands (`Diplomacy.deal_resources_for`).

**Gap to reference:** persistent deal objects (one-off + per-turn) ✅, AI attitude (5 levels)
✅, decaying memory of acts ✅ — but **denial reasons** (the structured "why we refuse"
codes the reference surfaces in trade UI and AI logic) are **not** modelled. Cross-ref §7 of
`game-rules.md`.

---

## 27. Score victory

`data/win_conditions.json` `score`. The reference's **7th victory condition** (`SCORE`):
the first alliance whose summed score reaches an absolute threshold wins **immediately** —
distinct from Time, which only awards the highest score at the turn limit.

| Field | Value |
|-------|:-----:|
| `score_threshold` | 400 (provisional/tunable) |

**Scoring formula** (`Scoring.compute_all`, per player, then summed per alliance):

| Component | Formula |
|-----------|---------|
| Land | `land_tiles × 100 / total_land` (share %) |
| Population | `population × 100 / total_pop` (share %) |
| Technology | `techs_researched × 2` |
| Wonders | `wonders × score_weight_wonder` (5) |

Player score = land + population + technology + wonders; alliance score = sum of members.

**Reference parity:** `GameVictoryInfo.xml` lists 7 conditions including `SCORE`; the project
now ships all 7 (`last_standing`/Conquest, `dominance`/Domination, `endgame_project`/Space
Race, `cultural`, `diplomatic`, `score`, `time`). ✅ **Complete.** Cross-ref §16.

---

## 28. Map start-fairness (`normalize*`)

> **Status: complete** — all 9 of the reference's `normalize*` steps are implemented
> (plus `BonusBalancer`): start repositioning is score-driven, and
> `addGoodTerrain` / `addExtras` run as steps 8 and 9.

`MapGen.normalize_starts` runs after `find_start_positions` to tidy each capital's
surroundings so no player is crippled by a hostile spawn. Every random choice draws from the
shared map RNG in a fixed order, so the result is deterministic for the seed. A per-map
`normalize` block in `data/map_types.json` may override the constants.

**Step coverage** (mapped to the reference's 9-step `normalize*` sequence + `BonusBalancer`):

| # | Reference step | Code | Behaviour |
|:-:|----------------|:----:|-----------|
| 1 | `normalizeStartingPlotLocations` | ✅ | `find_start_positions` maximises spacing; `_normalize_reposition_starts` then shifts weak starts to a better-scoring nearby plot (yield/fresh-water/resource score), keeping the layout's minimum spacing and any `start_bounds` |
| 2 | `normalizeAddRiver` | ✅ | `_normalize_add_fresh_water` carves river borders when no fresh water is near |
| 3 | `normalizeRemovePeaks` | ✅ | `_normalize_remove_peaks`: peaks on start tile/inner ring → hills |
| 4 | `normalizeAddLakes` | ✅ | folded into `_normalize_add_fresh_water` (fresh-water guarantee) |
| 5 | `normalizeRemoveBadFeatures` | ✅ | `_normalize_strip_bad_features`: strip jungle from start tile/ring |
| 6 | `normalizeRemoveBadTerrain` | ✅ | `_normalize_fix_bad_terrain`: snow/desert city tile → grassland; ring snow→tundra, desert→plains |
| 7 | `normalizeAddFoodBonuses` | ✅ | `_normalize_add_food_bonuses`: top up to `min_food` food resources in the inner ring |
| 8 | `normalizeAddGoodTerrain` | ✅ | `_normalize_add_good_terrain`: upgrade up to a quota of poor tiles in the wider radius one step toward grass/plains (snow→tundra, tundra→grassland, desert→plains) |
| 9 | `normalizeAddExtras` | ✅ | `_normalize_add_extras`: starts scoring below par get extra food/luxury resources, then extra discovery sites if still short |
| — | `BonusBalancer` | ✅ | `_balance_start_resources`: no start sits more than `resource_tolerance` strategic resources below the richest within `balance_radius` |

**Constants** (`data/constants.json`; a per-map `normalize` block may override
`min_food_bonuses` / `balance_radius` / `resource_tolerance`):

| Constant | Value |
|----------|:-----:|
| `start_normalize_min_food_bonuses` | 1 |
| `start_normalize_balance_radius` | 2 |
| `start_normalize_resource_tolerance` | 1 |
| `start_normalize_reposition_radius` | 3 |
| `start_normalize_reposition_min_gain` | 4 |
| `start_normalize_score_radius` | 2 |
| `start_normalize_score_food_weight` | 2 |
| `start_normalize_score_resource` | 3 |
| `start_normalize_score_fresh_water` | 8 |
| `start_normalize_good_terrain_radius` | 2 |
| `start_normalize_good_terrain_quota` | 3 |
| `start_normalize_extras_radius` | 2 |
| `start_normalize_extras_tolerance` | 6 |
| `start_normalize_extras_huts` | 1 |
| `start_normalize_extras_hut_radius` | 6 |
| `goody_hut_land_per_hut` | 28 |
| `goody_hut_min_distance_from_start` | 4 |

The plot score behind steps 1 and 9 (`_start_plot_score`) sums the terrain base yields in
the `score_radius` neighbourhood (food weighted by `score_food_weight`), adds
`score_resource` per resource in reach and `score_fresh_water` when the plot has fresh
water. Step 1 is purely score-driven (no RNG draw); steps 8 and 9 draw their tile picks
from the shared map RNG in fixed start order, keeping generation deterministic.
