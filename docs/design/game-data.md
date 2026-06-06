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

### 11.2 Landform Modifiers

| Landform | Yield Change | Move Cost | Defense | Other |
|----------|-------------|-----------|---------|-------|
| Flat | ±0 | 1 | +0% | Default |
| Hill | −1 Food, +1 Production | +1 (total 2) | +25% | +1 sight range |
| Peak | — | Impassable | — | Cannot be entered by land units |

### 11.3 Features (Overlaid on terrain)

| Feature | Food | Production | Commerce | Move Cost | Defense | Notes |
|---------|------|------------|----------|-----------|---------|-------|
| Forest | 0 | +1 | 0 | +1 | +50% | Can be chopped for +20 prod (more with Math) |
| Jungle | −1 | 0 | 0 | +1 | +50% | Removed before most improvements; disease risk |
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
Effective Strength = Base_Strength × (1 + sum_of_all_modifiers/100) × (current_HP / max_HP)

Combat odds (attacker wins round) = Attacker_Effective_Str / (Attacker + Defender effective str)

Per-hit damage (to attacker) =
    ROUND[ max_HP × (Defender_Firepower / (Attacker_Firepower + Defender_Firepower)) ]
    minimum 1 HP

Firepower = Effective_Strength (for most units)
Max HP = 100 (all units)
```

| Constant | Value | Notes |
|----------|-------|-------|
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
Growth threshold = 18 + (2 × current_population) [× pace multiplier]
Surplus food stored = food_produced − (food_consumed = population × 2)
At threshold: population +1; stored food reset to 0 (or small carry-over)

Unhappy citizens = max(0, unhappy_count − happy_count)
Unhealthy (sick) citizens = max(0, sick_count − healthy_count)
Sick citizens reduce food surplus by 1 per sick citizen
```

| Constant | Value |
|----------|-------|
| Food consumed per citizen | 2 Food/turn |
| Base growth threshold | 18 + 2×population |
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
Research cost = base_cost × pace_multiplier × difficulty_modifier
              × (1 − trading_discount) × (1 − prerequisite_discount)

Trading discount = 0.10 per known faction that has researched this tech (up to ~50%)
Prerequisite discount = small bonus for having all prerequisites
```

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

| Level | Player Handicap | AI Bonus |
|-------|----------------|----------|
| Settler | Significant bonuses | None |
| Chieftain | Some bonuses | None |
| Warlord | Slight bonuses | Slight AI assist |
| Noble | Balanced | Balanced |
| Prince | None | Minor AI bonus |
| Monarch | None | Moderate AI bonus |
| Emperor | None | Large AI bonus |
| Immortal | None | Very large AI bonus |
| Deity | None | Maximum AI bonus |

---

## 16. Victory Conditions

| Condition | Trigger | Notes |
|-----------|---------|-------|
| Conquest | All other factions eliminated | Last faction with cities and units |
| Domination | Control ≥66% of land tiles AND ≥66% of world population | Borders + population threshold |
| Cultural | 3 cities each accumulate 50,000+ culture (Legendary level) | Only 3 cities need to reach this threshold |
| Space Race | Complete and launch the spaceship (Apollo Program + all 9 parts built) | Parts: SS Casing, Cockpit, Docking Bay, Engine, Life Support, Stasis Chamber, Thrusters + 2 more |
| Diplomatic | Win UN election with required % of votes | United Nations wonder must exist |
| Time | Highest score at turn limit (2050 AD on standard) | Score = weighted sum of population, tiles, techs, wonders |

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
