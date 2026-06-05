# Code Layout and Flow

A guide to how the codebase is structured and how the pieces connect at runtime.

---

## Directory map

```
project.godot               Godot 3.6 project file; registers all class_name globals
                            main_scene → scenes/menus/start_menu.tscn
data/                       22 JSON config tables — all numeric constants and content live here
src/
  core/                     Foundation: math, IDs, RNG, data loading
  world/                    Map geometry, tile output formula, regions, cultural influence
  sim/                      Rule modules: every §3–§11 mechanic
  api/                      Public surface: commands, save/load, facade
scenes/
  menus/                    start_menu.tscn/.gd  — entry point; title screen + nav
  setup/                    setup_screen.gd      — new-game config (players, society, world params)
  main.tscn / main.gd       Root game scene; wires all subsystems to SimFacade
  world/                    world_view.tscn, fog_layer.gd, minimap.gd
  hud/                      hud.tscn, turn_score_bar, research_bar, slider_panel,
                            selection_panel, message_log, end_turn_button
  screens/                  city_screen, tech_chooser, policy_screen,
                            diplomacy_screen, save_load_screen, pause_menu
  input/                    input_router.gd, hotkey_map.gd
  hotseat/                  hotseat_manager.gd, pass_device_screen.tscn/.gd
tests/                      GUT 7.4.3 headless suites, organised by functional area
                            (core/ world/ sim/ api/ scenes/) mirroring src/;
                            support/sim_fixture.gd holds the shared scaffolding
addons/gut/                 Test framework (vendored)
docs/                       This file, the engine-core plan, and the full game-rules spec
```

---

## Layers and the wall between them

```
┌──────────────────────────────────────────┐
│         Presentation  (scenes/)          │
│  StartMenu · SetupScreen · Main          │
│  WorldView · HUD · InputRouter           │
│  Screens · HotseatManager                │
└─────────────────┬────────────────────────┘
                  │ apply_command() / signals
                  │ init_with_facade(facade, db)
┌─────────────────▼────────────────────────┐
│            src/api/  (facade)            │  ← only entry point into the engine
│  SimFacade  ·  Commands  ·  SaveLoad     │
└─────────────────┬────────────────────────┘
                  │ reads/writes GameState
┌─────────────────▼────────────────────────┐
│  src/sim/  +  src/world/  (pure rules)   │  NO Node / Input / scene references
│  TurnEngine · settlements · combat …     │
│  WorldMap · TileOutput · Influence …     │
└─────────────────┬────────────────────────┘
                  │ reads
┌─────────────────▼────────────────────────┐
│   src/core/  +  data/*.json              │
│  GameState · DataDB · RNG · Fixed · IDs  │
└──────────────────────────────────────────┘
```

The wall is enforced by convention: `sim/` and `world/` are pure GDScript `Reference` subclasses with no editor imports, scenes, or `Node` dependencies. Tests run headless against them directly.

---

## Presentation layer (`scenes/`)

### `StartMenu` (`scenes/menus/`)
The Godot `main_scene`. A full-screen `Control` that builds its UI programmatically. On `_ready()` it loads `DataDB`; the "New Game" button instantiates `SetupScreen` and hides the menu; "Exit" calls `get_tree().quit()`. When `SetupScreen` completes, `StartMenu` instantiates `main.tscn`, calls `main.init_with_facade(facade, db)` before adding it to the tree, sets it as `current_scene`, then frees itself.

### `SetupScreen` (`scenes/setup/`)
A programmatic `Control` (no `.tscn`). Initialized via `init(db, on_start_callback)`. Presents: player count (2–4), per-player name and society picker, world size, pace, difficulty, and seed. On "Start Game" it creates a `SimFacade`, calls `facade.setup(...)` with the collected parameters, and fires `on_start_callback(facade, db)`. Society selection injects the chosen society's `leader_id`, `traits`, and `starting_gold` into the player config.

### `Main` (`scenes/main.tscn` / `main.gd`)
Root game scene. Wires `WorldView`, `HUD` sub-panels, `InputRouter`, and `HotseatManager` to the `SimFacade`. Exposes `init_with_facade(facade, db)` — call this **before** adding to the tree so `_ready()` skips the default hardcoded 2-player setup. Routes `screen_requested` signals to the appropriate full-screen nodes (`CityScreen`, `TechChooser`, `PolicyScreen`, `DiplomacyScreen`, `SaveLoadScreen`); the `OPEN_MENU` control toggles the `PauseMenu` overlay (Resume/Save/Load/New Game/Quit), whose Save/Load buttons defer to the shared `SaveLoadScreen`.

### HUD (`scenes/hud/`)
`hud.tscn` is a `VBoxContainer` containing: `TurnScoreBar`, `ResearchBar`, `SliderPanel`, `SelectionPanel`, `MessageLog`, `EndTurnButton`. Each panel's `.gd` is initialized with `init(facade, ...)` and reads facade state or subscribes to its signals.

### World view (`scenes/world/`)
`WorldView` renders the tile map and unit positions; `FogLayer` overlays fog-of-war; `Minimap` draws the territory overview. All three are initialized with `init(facade)`.

### Full-screen overlays (`scenes/screens/`)
`CityScreen`, `TechChooser`, `PolicyScreen`, `DiplomacyScreen`, `SaveLoadScreen`, `PauseMenu` — each exposes a `show_screen()` entry point and reads state through the facade.

### Input (`scenes/input/`)
`InputRouter` translates raw `_input` events into `Commands.*()` calls via `facade.apply_command()`. `HotkeyMap` loads key bindings from `data/hotkeys.json`.

---

## Core layer (`src/core/`)

### `DataDB`
Loads 21 of the 22 JSON tables from `data/` into typed dictionaries on startup (`db.load_all()`) — every file except `hotkeys.json`, which `HotkeyMap` loads separately. Every other module receives a `DataDB` reference and reads constants through it — no magic numbers in rule code. Cross-references (e.g. `tech_required` in unit definitions pointing at a technology ID) are validated on load.

The tables and what they configure:

| File | Configures |
|---|---|
| `constants.json` | Scalar tuning values (combat scale, growth base, entrenchment cap, …) |
| `terrains.json` | Domain, landform, base output vector, movement cost, defence bonus |
| `features.json` | Surface feature output delta, movement cost add, health effects |
| `resources.json` | Bonus output per tile; tech and improvement gates |
| `improvements.json` | Tile improvement output delta, build time, tech gate |
| `transport.json` | Road/rail movement divisors, commerce bonus |
| `units.json` | Domain, strength, movement, cost, upkeep, tags, first strikes, combat limit |
| `structures.json` | Settlement building costs, upkeep, output bonuses, specialist slots |
| `technologies.json` | Research cost, prereq graph (`prereqs_all`, `prereqs_any`), unlocks |
| `policies.json` | Category, upkeep modifiers, slider constraints, anger modifier, transition turns |
| `promotions.json` | Per-promotion combat bonuses, applies-to filter |
| `beliefs.json` / `econ_orgs.json` | Founding prereqs, spread chance, economic effects |
| `ages.json` / `paces.json` / `difficulties.json` | Scaling multipliers and per-level modifiers |
| `world_sizes.json` | Map width/height, wrap axes, suggested player count |
| `win_conditions.json` | Condition type and numeric thresholds |
| `projects.json` | Endgame (spaceship-style) project stages: cost, tech/wonder gate, stage and count-needed; feeds the `endgame_project` win condition |
| `events.json` | Scripted random-event definitions (min turn, treasury/effect delta, notice text) |
| `leaders_traits.json` | `"traits"` block: per-trait combat/production/commerce bonuses. `"societies"` block: playable societies each with `leader_id`, `leader_name`, `description`, `traits[]`, and `starting_gold`. |

Typed getters follow the pattern `get_X(id) → Dictionary` for every table. Additional helpers: `get_societies() → Dictionary` (full societies map), `get_society(id) → Dictionary` (single entry).

### `RNG`
Thin wrapper around Godot's `RandomNumberGenerator` (PCG32). A single instance lives on `GameState` (`gs.rng`). Every stochastic call in the pipeline draws from it — never creating a separate generator. `get_state()` / `restore_state()` serialize the seed and state as **strings** (not ints) to avoid JSON's 53-bit double-precision truncation of 64-bit values.

### `Fixed`
All integer math helpers. Movement allowances are stored at ×100 scale (`MOVE_PRECISION = 100`, so 2 tiles = 200). Output values (food, production, commerce) are plain integers. Key functions:
- `scale(value, percent)` — integer percentage multiply
- `apply_stacked_bonus(base, bonus_sum)` — additive percentage stacking for combat modifiers
- `proportion(a, total, scale_to)` — used by `Combat` to derive per-side odds

### `IDs`
Enums only. The sim/world core uses `Domain`, `Landform`, `Output`, `UnitClass`, `CommandType`, `WinType`, and `Phase` (`Phase` lists every named hook point in the §3 pipeline). The remaining enums back the UI-design spec's §2–§6 vocabulary: `DirtyRegion`, `WidgetType`, `InterfaceMode`, `PopupType`, `ControlType`, `UnitCmd`, and `UnitMission`.

---

## World layer (`src/world/`)

### `WorldMap` + `Tile`
The map is a flat array `_tiles[y * width + x]`. `WorldMap` provides wrap-aware access: `get_tile(x, y)` applies modular arithmetic on wrapped axes before indexing. Distance is Chebyshev (8-directional). Key methods: `neighbours4`, `neighbours8`, `tiles_in_range(cx, cy, r)`, `ring_at_distance(cx, cy, r)`.

Each `Tile` holds:
- Terrain/feature/resource/improvement/transport IDs (strings pointing into DataDB tables)
- `influence: Dictionary` — `player_id (int) → accumulated influence (int)`
- `owner_player_id` — derived from influence each turn
- `pollution: int`

### `TileOutput`
Pure static computation: `compute(tile, db, known_techs) → [food, production, commerce]`. Applies the §1.3 formula in order: terrain base → feature delta → resource bonus (gated by tech + improvement) → improvement delta (gated by tech) → transport commerce bonus. All outputs clamped ≥ 0 at the end.

### `Influence`
Manages cultural spread and border ownership. `spread()` adds culture to rings around a settlement each turn, decaying by a configurable divisor per ring. `resolve_ownership()` scans every tile and awards it to the player with the highest accumulated influence. `found_claim()` does an immediate influence injection when a settlement is first founded.

### `Regions`
Flood-fill utilities. `compute_regions()` labels every tile with a region ID based on domain connectivity (land tiles form land regions, sea tiles form sea regions). `compute_supply_groups()` does the same but restricted to same-owner transport-linked tiles.

---

## Sim layer (`src/sim/`)

### `GameState`
The single source of truth. Everything serializable lives here:

```
gs.db              DataDB reference (not serialized)
gs.rng             RNG instance
gs.map             WorldMap
gs.players[]       Player instances
gs.settlements[]   Settlement instances
gs.units[]         Unit instances
gs.alliances[]     Alliance instances
gs.turn_number
gs.current_player_id
gs.winning_alliance_id
gs.founded_beliefs / gs.founded_econ_orgs / gs.endgame_project_stages
```

ID counters (`_next_unit_id` etc.) are also serialized so IDs remain stable across save/load.

### `TurnEngine`
Implements §3 as three static functions called in sequence. Every phase first consults `hooks.run(IDs.Phase.X, gs)` — if a hook returns `true` the built-in is skipped entirely.

**`world_step(gs, hooks)`** — runs once after all players end their turn:
1. Resolve/expire trades
2. Advance shared alliance research stores
3. Per-tile upkeep (`_tile_upkeep` — charges each owned, improved tile's improvement maintenance)
4. Spawn wild/raider forces (`WildForces`)
5. Environmental degradation (`Pollution`)
6. Assign special sites (stub)
7. Assembly/voting (`_resolve_assembly` — tallies population-weighted `gs.diplomatic_votes` per alliance)
8. Increment `turn_number`
9. Advance `current_player_id`
10. Check win conditions (`WinConditions`)

**`player_step(gs, player_id, hooks)`** — runs when a player ends their turn:
1. Pre-turn bookkeeping
2. Auto-assign workers to tiles
3. Treasury: income (finance slice of settlement commerce) − unit upkeep; insolvency handling
4. Research: accumulate research slice of commerce against current tech cost
5. Intelligence accumulation
6. Settlement steps (iterates `settlement_step` for all owned settlements)
7. Tick down timed states (transition, rush anger, celebration, Golden Age)
8. Validate policies; update war fatigue
9. Random events (`Events`)
10. Reset unit movement/action flags

**`settlement_step(gs, settlement, player, hooks)`** — runs per settlement:
- Growth: sum tile outputs + structure bonuses + econ org delta → surplus food → food store → population threshold check
- Wellbeing: positive (structures, features) vs negative (population, polluting structures) → deficit reduces effective food
- Contentment: positive sentiment vs anger-driven negative → `discontented` citizens → `in_disorder` flag
- Production: accumulate construction capacity → complete queue items (units, structures, projects)
- Culture: accumulate total culture → ring expansion → `Influence.spread()`
- Beliefs: `Beliefs.spread_all()` on each turn
- Specialist progress: at a city's threshold a Great Person unit of the dominant specialist type is born (`GreatPeople.birth_from_settlement`); with no typed specialists the legacy abstract bonus (instant tech / seeded org / gold) applies
- Structure upkeep charged to treasury

### `Player`
Per-player economic and research state. The four allocation sliders (`slider_finance`, `slider_research`, `slider_culture`, `slider_intel`) sum to 100. `split_commerce(total)` partitions a settlement's commerce output into `[finance, research, culture, intel]` according to the sliders. Also holds Golden Age state (`golden_age_turns` / `golden_age_count` / `pending_golden_age_gp`) and Great General accumulation (`great_general_points` / `great_general_threshold` / `great_generals_produced`) — all serialized.

### `Settlement`
Holds all per-city state: population, food store, production queue and store, culture total and border ring, contentment/wellbeing breakdowns, specialist assignments, and a list of built structure IDs. `effective_workers()` = `population − discontented`.

### `Unit`
Per-unit state: position, `base_strength`, `health` (0–100), experience, promotions, movement allowance (fixed-point), entrenchment, and worker state. `effective_strength(db, is_attacker, terrain, feature, versus_class)` computes the final integer strength factoring in all stacked percentage modifiers from promotions, terrain defence, and entrenchment, then scales by `health / 100`.

### `Stack`
Stateless helpers that query `gs.units` by tile position. `at(units, x, y, player_id)` lists units at a tile. `get_defender(...)` returns the highest-strength enemy unit at a tile.

### `Combat`
`resolve(attacker, defender, gs, rng)` runs the per-round loop:
1. Compute effective strengths → odds (`Fixed.proportion(a_str, total, 1000)`)
2. Compute per-hit damage (proportional to opponent's firepower vs self)
3. Apply free early-win odds clamp against wild units (from difficulty setting)
4. Loop: consume first-strikes, then draw from RNG each round → attacker or defender takes a hit → check withdrawal, combat limit, death
5. Compute XP gains, spillover (siege), and flanking (fast unit) damage
Returns a result Dictionary — it does not mutate the unit objects directly.

### `Pathfinding`
Dijkstra over `WorldMap.neighbours4`. Movement cost per tile = terrain base + feature add, reduced if a road improvement is present. Domain legality (land/sea/air) is checked per tile. Tiles occupied by enemies block passage.

### `Research`
`can_research(tech_id, player, db)` checks `prereqs_all` (all required) and `prereqs_any` (at least one). `_effective_cost()` applies pace scaling, a discount per known prereq (10% each), and a discount for each other player who already knows the tech (5% each, capped at 25%).

### `Alliance`
Tracks war state (`at_war_with`), contacts, subordination, shared research store, war fatigue, and pending trades. War and peace are declared at the alliance level, not the player level.

### Other sim modules
- **`GreatPeople`** — §14 subsystem (pure static): maps specialists → great-person units, type-aware birth, Golden Ages (worked-tile bonus in `_settlement_growth`, war-weariness freeze, tick-down in `_tick_states`), the Great General accrued from combat, and the `GP_ACTION` action dispatch (`perform_action`) validated against each unit's data `actions` list. Types/actions are defined entirely in `data/units.json`; magnitudes in `data/constants.json`
- **`Beliefs`** — founding (first-eligible random draw), passive spread within range each turn
- **`EconOrgs`** — founded by special person or a Great Merchant; spread like beliefs but costs treasury
- **`WildForces`** — per-tile RNG spawn on unclaimed land tiles; raider settlements
- **`Pollution`** — per-settlement accumulation each turn; per-tile RNG degradation chain
- **`WinConditions`** — stateless evaluation against `gs`; returns winning `alliance_id` or −1
- **`Scoring`** — weighted sum of (land tiles, population, technology count) per alliance
- **`Hooks`** — `register(IDs.Phase.X, obj, "method_name")` stores a FuncRef; `run(phase, gs, args)` fires each registered handler in order, returning true if any handles it

---

## API layer (`src/api/`)

### `Commands`
Pure static factories that build command Dictionaries. No validation or logic — just construct `{"type": IDs.CommandType.X, ...}` objects that `SimFacade.apply_command()` consumes.

### `SimFacade`
The only object a caller needs to hold. Lifecycle:

```gdscript
var db = DataDB.new()
db.load_all()

var facade = SimFacade.new()
facade.setup(db, seed_val, "standard", "normal", "prince",
    [{"name": "Alice", ...}, {"name": "Bob", ...}],
    ["last_standing", "dominance", "time"])

# Each player action:
facade.apply_command(Commands.move_stack(player_id, fx, fy, tx, ty))
facade.apply_command(Commands.end_turn(player_id))

# Observe results:
var gs: GameState = facade.get_state()
facade.connect("combat_resolved", self, "_on_combat")
facade.connect("turn_advanced", self, "_on_turn")

# Persistence:
var json: String = facade.save()
facade.load_save(json)
var hash: int = facade.state_hash()   # determinism gate
```

`apply_command()` rejects commands from the wrong player (not `current_player_id`). On `END_TURN` it calls `TurnEngine.player_step()`; when the last player ends their turn it also calls `TurnEngine.world_step()`. `_cmd_move_stack()` calls `Pathfinding.find_path()` and then `Combat.resolve()` for any tile entered that contains an enemy.

### `SaveLoad`
`save_to_string(gs)` calls `gs.serialize()` → `JSON.print()`. `load_from_string(json, db)` calls `JSON.parse()` → `GameState.deserialize()`. Every sim object has symmetric `serialize() → Dictionary` and `static deserialize(d) → Object` methods. Integer-keyed dictionaries (e.g. `tile.influence`) convert keys back to `int` on deserialize to restore exact types. `state_hash()` returns `String.hash()` of the JSON output — used by integration tests as the determinism gate.

---

## Data flow through one turn

```
Player calls: facade.apply_command(Commands.end_turn(player_id))
  └─ SimFacade._cmd_end_turn(player_id)
       ├─ TurnEngine.player_step(gs, player_id, hooks)
       │    ├─ _auto_assign_workers        → gs.settlements[*].worked_tiles
       │    ├─ _update_treasury            → player.treasury
       │    ├─ _apply_research             → player.research_store, player.technologies
       │    ├─ settlement_step × N
       │    │    ├─ _settlement_growth     → s.food_store, s.population
       │    │    ├─ _update_wellbeing      → s.wellbeing_deficit
       │    │    ├─ _update_contentment    → s.discontented, s.in_disorder
       │    │    ├─ _settlement_production → gs.units (new), s.structures (new)
       │    │    └─ _settlement_culture    → s.culture_total, s.culture_ring
       │    │         └─ Influence.spread  → tile.influence[*]
       │    │              └─ Influence.resolve_ownership → tile.owner_player_id
       │    └─ resets unit movement flags
       │
       └─ (if last player) TurnEngine.world_step(gs, hooks)
            ├─ WildForces.spawn_turn         → gs.units (appended)
            ├─ Pollution.accumulate/degrade  → tile.pollution, tile.terrain_id
            ├─ gs.turn_number += 1
            └─ WinConditions.check_all       → gs.winning_alliance_id
```

When `apply_command(Commands.move_stack(...))` triggers combat:

```
SimFacade._cmd_move_stack
  └─ Pathfinding.find_path(map, from, to, unit, db, all_units) → path[]
       └─ per step: check domain, impassable, enemy presence
  └─ per step entered:
       └─ Stack.get_defender(units, sx, sy, player_id, gs)
            └─ unit.effective_strength(db, false, terrain, feature, "")
       └─ Combat.resolve(attacker, defender, gs, gs.rng) → result{}
            ├─ unit.effective_strength (both sides, with/without terrain bonuses)
            ├─ Fixed.proportion(a_str, total, 1000) → odds
            └─ rng.randi_range(0, 999) × rounds → health deltas, XP, spillover
       └─ SimFacade._apply_combat_result    → unit.health, removes dead units
            └─ GreatPeople.award_combat_points → Great General points/birth (§14.2)
       └─ emit_signal("combat_resolved", result)
```
