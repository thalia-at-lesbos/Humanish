# Code Layout and Flow

A guide to how the codebase is structured and how the pieces connect at runtime.

> **Doc stream:** `docs/ref/` is the *downstream* reference tier — it is always updated to reflect the current project state and may be edited freely by Claude Code or the user. Design intent lives upstream in `docs/design/` (requires explicit user consent to change). Collaborative planning notes and TODO lists live in `docs/planning/`. End-user–facing documentation (packaged with release builds) lives in `docs/user/`.

---

## Directory map

```
project.godot               Godot 3.6 project file (v0.4.4); registers all class_name
                            globals; main_scene → scenes/menus/start_menu.tscn
data/                       25 JSON config tables — all numeric constants and content
                            live here (hotkeys.json loaded separately by HotkeyMap)
src/
  core/                     Foundation: math, IDs, RNG, data loading, debug ring buffer
  world/                    Map geometry, tile output formula, regions, cultural
                            influence, terrain-aware visibility (sight + LOS)
  sim/                      Rule modules: every §3–§11 mechanic (incl. eras, assembly,
                            culture revolt, wild-forces AI, nuclear weapons, shared
                            combat application)
  api/                      Public surface: commands, save/load, facade, AI/debug clients
  net/                      Pure remote-multiplayer wire protocol + server CLI parsing
                            (net_protocol, net_config — no sockets; see network-design.md)
scenes/
  menus/                    start_menu.tscn/.gd  — entry point; title screen + nav
  setup/                    setup_screen.gd      — new-game config (players, society, world params)
  main.tscn / main.gd       Root game scene; wires all subsystems to SimFacade
  world/                    world_view.tscn, fog_layer.gd
  hud/                      hud.tscn, menu_bar, turn_score_bar, research_bar,
                            slider_panel, selection_panel, message_log,
                            end_turn_button, minimap (overlay)
  screens/                  city_screen, tech_chooser, policy_screen,
                            diplomacy_screen, save_load_screen, pause_menu;
                            info_screen (shared read-only scaffold) + the advisor
                            screens (religion, corporation, turn_log,
                            domestic_advisor, victory_progress, options, finance,
                            military, espionage, encyclopedia)
  input/                    input_router.gd, hotkey_map.gd
  hotseat/                  hotseat_manager.gd, pass_device_screen.tscn/.gd
  net/                      Remote multiplayer runtime: net_server.gd (authoritative
                            WebSocket server + turn loop + per-turn autosave),
                            server_runner.gd (headless entry), net_client.gd,
                            multiplayer_setup.gd (client join lobby),
                            server_setup.gd (in-game host: new/load config + status)
  debug/                    debug_overlay.gd ('~' menu), terminal_console.gd
                            (debug-build-only tools; see docs/design/debug.md)
tests/                      GUT 7.4.3 headless suites, organised by functional area
                            (core/ world/ sim/ api/ scenes/ net/) mirroring src/;
                            support/sim_fixture.gd holds the shared scaffolding;
                            integration/ holds the end-to-end playthrough gate
                            (run after the unit suites — see run_tests.sh);
                            manual/ holds non-CI harnesses (e.g. the multiplayer
                            loopback smoke test)
addons/gut/                 Test framework (vendored)
docs/
  design/                   Upstream design specs (game-rules, network, UI, debug, game-data);
                            modify only with explicit user consent
  ref/                      Downstream reference (this file); always updated to current state
  planning/                 Collaborative planning memory: gaps, TODO, phase plans
  user/                     End-user documentation (quick-start.md, user-reference.md);
                            downstream — Claude Code updates freely; packaged with release builds
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
The Godot `main_scene`. A full-screen `Control` that builds its UI programmatically. On `_ready()` it loads `DataDB` and calls `randomize()` so the presentation-layer **default seed chooser** (`SetupScreen`/`main.gd` fallback `randi()`) varies per launch — purely cosmetic; `gs.rng` is always explicitly seeded in `SimFacade.setup()`, so seeded tests are unaffected. Buttons: **New Game** (instantiates `SetupScreen` and hides the menu), **Load Game** (lists `.sav` files from `user://saves/` inside a bounded, scrollable region — a fixed-height `Control` frame holds the `ScrollContainer` so the save list scrolls instead of overflowing past the Back button — builds a new facade via `init_for_load(…)` + `load_save(…)`, then hands it to `main.tscn`), **Multiplayer** (opens `multiplayer_setup.gd` for client join), **Multiplayer Server** (opens `server_setup.gd` for in-process host), **About** (instantiates `about_screen.gd`), and **Exit** (calls `get_tree().quit()`). When a game is ready (setup complete / save loaded / multiplayer connected) `StartMenu` instantiates `main.tscn`, calls `main.init_with_facade(facade, db)` before adding it to the tree, sets it as `current_scene`, then frees itself. For remote multiplayer, the live `NetClient` node is reparented into the main scene so it keeps polling.

### `SetupScreen` (`scenes/setup/`)
A programmatic `Control` (no `.tscn`). Initialized via `init(db, on_start_callback)`. Presents: player count (2–4), per-player name, society picker, and leader picker, world size, map type (populated from `data/map_types.json`), pace, difficulty, and seed. On "Start Game" it creates a `SimFacade`, calls `facade.setup(...)` with the collected parameters, and fires `on_start_callback(facade, db)`. Society selection injects the chosen society's `starting_gold` and `starting_techs` into the player config; selecting a society also populates the leader picker with that society's leaders (every leader whose `faction` matches the society id, via `DataDB.get_society_leaders`), defaulting to the society's own `leader_id`. The chosen leader supplies the player's `leader_id` and `traits` (falling back to the society default when the picker is untouched).

### `Main` (`scenes/main.tscn` / `main.gd`)
Root game scene. Wires `WorldView`, `HUD` sub-panels (`MenuBar`, `TurnScoreBar`, `ResearchBar`, `SliderPanel`, `SelectionPanel`, `MessageLog`, `EndTurnButton`), `InputRouter`, `HotseatManager`, and the `Minimap` overlay to the `SimFacade`. Exposes `init_with_facade(facade, db)` — call this **before** adding to the tree so `_ready()` skips the default hardcoded 2-player setup (the direct-run fallback also calls `randomize()` to vary the default seed per launch). It hands the `Minimap` the `WorldView` (`set_world_view`) so a minimap click recenters the main view. In solo/hotseat play it also wires a `TurnPrompts` node (start-of-turn "what now?" prompts for research and idle-city production). For remote multiplayer, `set_net_client(net_client)` attaches the client before tree entry; the `_wire_net_client` hook then connects `state_synced`/`game_over` signals to repaint the view when the server pushes new state (no local `HotseatManager` turn loop runs). Routes `screen_requested` signals to the appropriate full-screen nodes (`CityScreen`, `TechChooser`, `PolicyScreen`, `DiplomacyScreen`, `SaveLoadScreen`, `PauseMenu`); the `OPEN_MENU` control toggles the `PauseMenu` overlay (Resume/Save/Load/New Game/Controls/About/Quit), whose Save/Load buttons defer to the shared `SaveLoadScreen`. Also manages score/minimap/fog `TOGGLE_*` controls as pure presentation toggles.

### HUD (`scenes/hud/`)
`hud.tscn` is a `VBoxContainer` containing: `MenuBar` (advisor button row — Science/Civics/Diplomacy/Finance/Military/Espionage/Religion/Corp/Domestic/Victory/Log/Pedia/Options, each sending `DO_CONTROL(OPEN_*)`), `TurnScoreBar`, `ResearchBar`, `SliderPanel`, `SelectionPanel`, `MessageLog`, `EndTurnButton`. Each panel's `.gd` is initialized with `init(facade, ...)` and reads facade state or subscribes to its signals. `SelectionPanel`'s per-unit action buttons come from `SimFacade.get_flyout_menu`, which offers Skip Turn, Fortify, and **Sleep** (`IDs.UnitCmd.SLEEP` → `Commands.unit_sleep`, available to any unit not already asleep) — Sleep sets the serialized `Unit.is_sleeping` flag, ending the turn and removing the unit from the idle-unit cycle (`cycle_idle_units`) and the end-turn idle prompt (`get_end_turn_state`) until it is woken (`UNIT_WAKE`) or given another order; unlike Fortify it carries no defence/heal intent. `SelectionPanel` also appends a tile terrain readout (`_append_tile_terrain`, via `SimFacade.tile_info_text`) below a selected unit or city — so the panel always shows the underlying tile's terrain, not only for an inspected empty tile. The readout's **Yields** line shows the *full computed* tile output (`TileOutput.compute` from the current player's `technologies`), so a built improvement's bonus and the resource yields it unlocks appear there — not just the raw `terrain.base_output` (which it previously, wrongly, displayed, so improvements never appeared to change a tile's yields). `SelectionPanel` also suppresses worker improvement/chop buttons on a settlement tile (`_add_worker_buttons` early-returns when a settlement occupies the tile; `SimFacade._cmd_build_improvement` enforces the same rejection as defense-in-depth). A resource-bound improvement (e.g. the **Fishing Boats** sea improvement the work boat builds on a fish/clam/crab tile) is offered only when the tile's resource is *visible* (`_tile_offers_resource_improvement`); a resource whose reveal `tech_required` is JSON `null` (fish/clam/crab/corn/rice/wheat) is visible from the start — the reader coerces that null to `""` rather than the literal `"Null"`, so those resources are improvable without a tech (a bug that previously made the work boat unable to build Fishing Boats). The `Minimap` is a separate `Control` overlay (`HUD/Minimap`) drawn in the lower-right corner; clicking or dragging on it recenters the main `WorldView` (`_gui_input` → `pixel_to_tile` → `WorldView.pan_to_tile`, wired via `set_world_view` from `main.gd`). The `TurnPrompts` node (start-of-turn research/idle-city chain) is a child of `main.gd`, not inside `hud.tscn`; it is only wired in solo/hotseat play.

### World view (`scenes/world/`)
`WorldView` renders the tile map and unit positions; `FogLayer` overlays fog-of-war (rebuilds per-player, dims explored-but-not-visible tiles). Both are initialized with `init(facade)`. Cultural territory is a per-tile diagonal hatch in `_player_color(owner)`; the wild owner `-2` (Raider Camp tiles) maps to a dedicated charcoal `WILD_COLOR`, so wild borders render distinctly while only a truly unowned tile (`-1`) draws no hatch. `FogLayer._add_visible_range` computes each source's visible set through the shared `Visibility.visible_tiles` helper, so the rendered fog matches contact detection and the wild-spawn darkness mask (terrain sight bonus + line-of-sight blocking). The `Minimap` HUD overlay (`scenes/hud/minimap.gd`) and the thumbnail `scenes/world/minimap.gd` both read facade state + `FogLayer` to draw an always-visible overview, and both share the same `WILD_COLOR` so the camp's tiles/dot read as wild there too.

### Full-screen overlays (`scenes/screens/`)
`CityScreen`, `TechChooser`, `PolicyScreen`, `DiplomacyScreen`, `SaveLoadScreen`, `PauseMenu` — each exposes a `show_screen()` entry point and reads state through the facade. The `CityScreen`'s manual-citizen panel renders the **full** `(2·culture_ring+1)²` work-radius square: an unavailable tile (off-map or owned by another player, per `_tile_workable`) is a **blank** non-Button cell so the grid stays rectangular, and a **worked** tile carries a `•` dot (the city centre also shows `⌂` and is always worked) — see the pure `_tile_grid_marker(is_center, is_worked, is_locked)` helper. Its "Add to production" chooser greys out only **one-per-city** items (every `"structure"` — buildings/wonders) once they are already built or queued, via the pure `_can_queue_more(kind, id, structures, queue)` / `_is_one_per_city(kind)` helpers; **units stay addable while queued**, so the same unit can be queued multiple times. The `PauseMenu` includes Resume, Save, Load, New Game, Controls, About, and Quit buttons; Save/Load defer to the shared `SaveLoadScreen`. **Controls** (`controls_screen.gd`) and **About** (`about_screen.gd`) are simple read-only overlays built lazily from the pause menu. In the start menu, `about_screen.gd` is also opened by the About button (no game state needed). The **Espionage mission popup** (`espionage_menu.gd`) is a full-screen popup opened by the `EspionageScreen` when the player clicks "Select Mission…".

The **Encyclopedia** (`encyclopedia_screen.gd`, `OPEN_ENCYCLOPEDIA`) is a tabbed reference built live from `DataDB` (Technologies/Units/Buildings/Terrain/Improvements/Resources/Civics/Promotions/…); the **Terrain** and **Improvements** tabs surface terrain/feature data (including vision and movement effects) and improvement terrain/tech gating, and the Units detail flags `ocean_capable` ("ocean-going") hulls — matching the new sight and deep-water-crossing rules.

The simple read-only advisor/info screens (`OPEN_RELIGION`, `OPEN_CORPORATION`, `OPEN_TURN_LOG`, `OPEN_DOMESTIC_ADVISOR`, `OPEN_VICTORY_PROGRESS`, `OPEN_OPTIONS`, plus `OPEN_FINANCE`/`OPEN_MILITARY`/`OPEN_ESPIONAGE`/`OPEN_ENCYCLOPEDIA`) share a `info_screen.gd` scaffold — opaque backdrop, scrolled text labels, Close — and override `_populate(vbox)`. They carry no `.tscn` node; `main.gd:_init_extra_screens()` instantiates each programmatically under the `Screens` node, keyed by the `ControlType` that opens it (via the facade's `screen_requested` signal). The §3.1 control vocabulary that opens them is documented in `docs/planning/designgaps.md` §3.

### Input (`scenes/input/`)
`InputRouter` translates raw `_input` events into `Commands.*()` calls via `facade.apply_command()`. **Left-click selects only** (`_handle_select_click`: cycle a tile's units then its city, else inspect the terrain); **right-click moves/attacks** (`_handle_move_click`: a single selection moves via `MISSION_MOVE_TO`, a multi-selection via `MOVE_STACK`). Right-click never opens a context menu — the selection panel's action buttons are simply the *currently selected* subject's actions. Because the left-click cycle now includes civilians (workers/settlers), the active selection can land on a civilian sharing a warrior's tile; so when the current selection cannot make the move **and** the target is hostile (`SimFacade.is_hostile_tile`) **and** the whole owned stack on the head's tile *can* attack it (`can_stack_move` with empty `unit_ids`), `_handle_move_click` escalates the order to the whole stack — the move command then picks the combat-capable unit as the attacker, so a right-click on a wild Raider Camp attacks with the escort instead of silently no-op'ing. Keyboard events run through `_handle_keyboard` on `_unhandled_input`, so a focused UI control (LineEdit/Button), an open advisor/info screen, the pause menu, or the debug overlay all consume the key first and the main-view binding never fires while a modal is up. `HotkeyMap` loads key bindings from `data/hotkeys.json`; **Enter / Numpad-Enter (`KEY_ENTER`/`KEY_KP_ENTER`) are bound to the `END_TURN` control**, the same `DO_CONTROL` path the HUD End Turn button uses (so the remote-submit seam still intercepts it).

### Remote multiplayer (`src/net/`, `scenes/net/`)
A simple asynchronous **client–server** layer, **full-state handoff, round robin**. Like the UI and `PlayerAI`, every networking object is a *client* of `SimFacade` — it only reads `get_state()` or mutates through `apply_command()`/`load_save()`/`save()`; nothing in `sim/`/`world/` references it. Transport is Godot 3's built-in **WebSocket** (TCP, one port) — the simplest stack that is transparent across the internet (clients make outbound connections; no NAT/firewall config beyond the server's one reachable port).

* **`src/net/net_protocol.gd`** (`NetProtocol`, pure) — the wire format: message-type constants and `encode`/`decode` of `{v, t, d}` JSON frames. Snapshots are `SimFacade.save()` strings carried inside frames.
* **`src/net/net_config.gd`** (`NetConfig`, pure) — parses the headless server's command-line switches (`--server`, `--port`, `--players`, `--ai`, `--load`, …) into a config dict.
* **`scenes/net/net_server.gd`** — the authoritative server (a `Reference`): a `WebSocketServer` plus the round-robin `_drive()` loop that plays AI slots itself, pushes `state` to the active remote human, and on `submit` adopts the snapshot and runs the authoritative end-of-turn pipeline. On `hello` it also sends every joiner a bootstrap `state` (inactive when it is not their turn) so off-turn joiners still enter the game. **Autosaves every turn** (`set_save_path`, hooked to the facade's `player_turn_started`). Polled by whatever owns it.
* **`scenes/net/server_runner.gd`** — headless entry point (`extends SceneTree`, the `-s` target): builds `DataDB` + `SimFacade` from `NetConfig`, stands up the server, polls the socket each `idle_frame`. No scene/menu is loaded. `--save` is required. Launched via `run_server.sh`.
* **`scenes/net/net_client.gd`** — the client (`Node`, so it polls each frame): a `WebSocketClient`; on the first `state` it builds a facade and installs itself as the facade's remote-submit handler, then re-syncs on each `state` and ships a `submit` when the player ends their turn.
* **`scenes/net/multiplayer_setup.gd`** — the client join `Control` opened by the start menu's **Multiplayer** button (host/port/name → Connect), which hands the server-built facade to `main.tscn` like the New Game / Load flows.
* **`scenes/net/server_setup.gd`** — the in-game host `Control` opened by the start menu's **Multiplayer Server** button: sets port/name/save-file, then configures a **New Game** (reusing `SetupScreen`) or **loads** a save, runs a `NetServer` in-process (polled each `_process` frame), and shows a running-server status panel with a Stop button.

The only engine seam is on `SimFacade` (`set_remote_submit_handler` / `set_remote_waiting`): for a remote client, ending the turn is intercepted and handed to the network instead of running the local pipeline. It is presentation-only wiring (a `FuncRef`) and is not serialized. Full design — protocol table, sequence diagram, launch flags, future simultaneous-turn plan — in **`docs/design/network-design.md`**.

---

## Core layer (`src/core/`)

### `DataDB`
Loads 25 of the 26 JSON tables from `data/` into typed dictionaries on startup (`db.load_all()`) — every file except `hotkeys.json`, which `HotkeyMap` loads separately. Every other module receives a `DataDB` reference and reads constants through it — no magic numbers in rule code. Cross-references (e.g. `tech_required` in unit definitions pointing at a technology ID) are validated on load.

The tables and what they configure:

| File | Configures |
|---|---|
| `constants.json` | Scalar tuning values (combat scale, growth base, entrenchment cap, …) |
| `terrains.json` | Domain, landform, base output vector, movement cost, defence bonus, `sight_bonus` (extends a source's sight radius), `blocks_sight` (line-of-sight occlusion) |
| `features.json` | Surface feature output delta, movement cost add, health effects, `blocks_sight` (forest/jungle occlude line of sight) |
| `resources.json` | Bonus output per tile; tech and improvement gates |
| `improvements.json` | Tile improvement output delta, build time, tech gate, `allowed_landforms` (e.g. mine is hills-only) |
| `transport.json` | Road/rail movement divisors, commerce bonus |
| `units.json` | Domain, strength, movement, cost, upkeep, tags, first strikes, combat limit, `ocean_capable` (sea hulls cleared for deep-water crossing) |
| `structures.json` | Settlement building costs, upkeep, output bonuses, specialist slots |
| `technologies.json` | Research cost, prereq graph (`prereqs_all`, `prereqs_any`), unlocks |
| `policies.json` | Category, upkeep modifiers, slider constraints, anger modifier, transition turns, and a per-civic `effects` block of gameplay bonuses (read by `PolicyEffects`) |
| `promotions.json` | Per-promotion combat bonuses, applies-to filter |
| `beliefs.json` / `econ_orgs.json` | Founding prereqs, spread chance, economic effects |
| `specialists.json` | The 14 specialist types (7 working + 7 great-person): per-head `output` vector (food/production/commerce/science/culture/espionage), `gp_points`/`gp_type`, `great_person_unit`, and `default_slots` slot rules (read by `Specialists`) |
| `ages.json` / `paces.json` / `difficulties.json` | Scaling multipliers and per-level modifiers |
| `world_sizes.json` | Map width/height, wrap axes, suggested player count |
| `map_types.json` | Map-script definitions: land-mask `shape`, `climate`, target `land_fraction`, landform/feature chances, and shape params (read by `MapGen`) |
| `win_conditions.json` | Condition type and numeric thresholds |
| `projects.json` | Endgame (spaceship-style) project stages: cost, tech/wonder gate, stage and count-needed; feeds the `endgame_project` win condition |
| `events.json` | §9 random-event definitions: name/text, optional `choices`, begin `effects`, and `duration`/`expire_effects` for timed events. Effect verbs (gold/research/culture/tech/unit/building/capital_health/heal_units) are read by `Events`; magnitudes are fixed ints |
| `event_triggers.json` | §9 trigger predicates that gate when an event fires: `event_id`, pace-scaled `min_turn`/`max_turn`, `tech_required`/`building_required`/`terrain_required`, `at_war`/`at_peace`, `probability`, `weight`, `one_shot` (read by `Events.trigger_holds`) |
| `goodies.json` | §9 goody-hut / discovery-site reward table: weighted `type` (treasury/map/experience/heal/unit/tech/ambush) with per-reward magnitudes (read by `Events.exploration_reward`; per-difficulty weight overrides live in `difficulties.json` `goody_weights`) |
| `resolutions.json` | §7.2 world-assembly resolutions: category, vote threshold, effect payload, eligibility gates (read by `Assembly`) |
| `espionage_missions.json` | §7.1 espionage mission catalogue: per-mission `effect` verb (steal_tech/sabotage/incite_unrest/steal_gold/poison_water), `cost_multiplier` (× the base EP-advantage cost curve), `interception_modifier`, and per-verb magnitudes (read by `SimFacade._cmd_espionage_mission`; each verb's target gate lives in `_mission_target_valid`) |
| `diplomacy.json` | §7 AI attitude & memory: `attitude_levels`/`attitude_thresholds`/`attitude_base`, live `factors` weights, `memory_kinds` (value + decay per remembered act), and the `deal_accept_min_attitude`/`war_min_attitude`/`memory_cap` gates (read by the `Diplomacy` module) |
| `leaders_traits.json` | `"traits"` block: per-trait combat/production/commerce bonuses. `"societies"` block: playable societies each with `leader_id`, `leader_name`, `description`, `traits[]`, and `starting_gold`. |

Typed getters follow the pattern `get_X(id) → Dictionary` for every table. Scalar constants come through `get_constant(key, default) → int` (the common case, coerced to int) or `get_constant_str(key, default) → String` for string-valued constants (e.g. `ocean_travel_tech`, the deep-water gating tech). Additional helpers: `get_societies() → Dictionary` (full societies map), `get_society(id) → Dictionary` (single entry), `get_leaders() → Dictionary` (full leaders map), `get_leader(id) → Dictionary` (single entry), `get_society_leaders(society_id) → Array` (leader ids whose `faction` matches the society), `get_map_types() → Dictionary` (full map-script map), `get_map_type(id) → Dictionary` (single entry, falling back to `continents`).

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

### `MapGen`
Pure static procedural generator that fills a blank `WorldMap` with the chosen **map script**. `generate(map, db, rng, map_type_id)` reads the script's spec from `data/map_types.json` and runs two orthogonal stages:

* **shape** builds the land/water *mask* (where the continents lie). Most shapes share one height-field pipeline — random noise → box-blur into blobs → a **contrast stretch** about the integer mean (`_stretch_contrast` / `HEIGHT_CONTRAST_PCT`, widening the blurred field so the per-seed noise competes with the bias and maps vary visibly seed-to-seed) → a per-shape height *bias* → percentile *threshold* to the spec's `land_fraction`. The bias is what makes each script distinct: a central blob (`pangaea`), vertical land bands with ocean channels (`continents`), two horizontal bands (`hemispheres`), a radial main blob plus scattered islands (`islands_plus_main` → Big/Medium-and-Small), a downward push for fragmentation (`archipelago`), a rim-vs-centre inversion (`inland_sea`), an upward push that leaves low pockets as lakes (`lakes`), pure noise (`fractal`), or twin Old/New-World blobs with a carved mid-ocean channel (`terra`). `tectonics` instead scatters plate seeds, assigns tiles by nearest seed (Voronoi), and raises mountain ranges along plate boundaries. `shuffle` resolves once, secretly, to one of the core scripts.
* **climate** *paints* each land tile: a landform roll (mountain/hills from the spec's chances) overlays a flat-terrain band picked by `latitude` (poles top/bottom), `tilted` (poles on the sides), `ice_age` (wide snow/tundra, narrow temperate equator), `plains` (mostly grassland/plains), or `oasis` (desert heart, fertile rim). A feature pass then sprinkles forest/jungle/oasis per the spec's chances. `_add_coasts()` turns land-adjacent ocean into coast.

Everything is drawn from the shared `gs.rng` in a fixed order, so a script is fully deterministic for its seed and captured by save/load (tiles serialize in full). All ids are data-driven (`terrains.json`/`features.json`); per-script tunables live in `map_types.json`, while the structural shape-amplitude constants stay in `map_gen.gd`.

`find_start_positions(map, db, count, map_type_id)` returns spread-out passable land tiles (greedily maximising the minimum inter-start distance). When a script defines `start_bounds` (e.g. Terra confines players to the Old World) candidates are clipped to that percentage-bounded region, falling back to the whole map if it cannot host everyone.

Two start-dependent post-passes run after `find_start_positions` (wired by `SimFacade.setup`, both drawing from the shared map RNG in fixed order so the stream stays deterministic): `normalize_starts(map, db, rng, starts, map_type_id)` is the reference `normalize*` fairness pass — per start, in order, it removes adjacent peaks (→ hills), strips jungle, upgrades poor terrain near the city, guarantees fresh water (carving a short river when none is adjacent), and tops up the inner ring to `start_normalize_min_food_bonuses` food resources; a final global pass equalises strategic-resource access so no start sits more than `start_normalize_resource_tolerance` below the richest within `start_normalize_balance_radius`. `place_goody_huts(map, db, rng, starts)` scatters goody huts (the generalised discovery site, `Tile.has_discovery`) across passable land — one per `goody_hut_land_per_hut` land tiles — kept `goody_hut_min_distance_from_start` clear of every start. Tunables live in `constants.json`; a per-script `normalize` block in `map_types.json` may override the normalize parameters.

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
Manages cultural spread and border ownership. `spread()` adds culture to rings around a settlement each turn, decaying by a configurable divisor per ring. `resolve_ownership()` scans every tile and awards it to the owner (player **or** the wild owner `-2`) with the highest accumulated influence — only a tile with *no* influence at all stays unowned (`-1`), so a wild Raider Camp shows cultural borders like any civ city. `found_claim()` does an immediate influence injection when a settlement is first founded (used both for civ cities and, with owner `-2`, for the raider-camp's `wild_camp_claim_radius`/`wild_camp_claim_influence` ring — its whole border, since wild forces have no turn slot and never run the per-player culture spread).

### `Regions`
Flood-fill utilities. `compute_regions()` labels every tile with a region ID based on domain connectivity (land tiles form land regions, sea tiles form sea regions). `compute_supply_groups()` does the same but restricted to same-owner transport-linked tiles.

### `Visibility`
Pure static terrain-aware sight helper — the single source of truth for "what can a sight source at `(cx, cy)` see". `visible_tiles(wmap, db, cx, cy, base_radius) → Dictionary` of map-normalized `"x,y"` keys applies two data-driven rules: (1) **sight bonus** — the source tile's terrain `sight_bonus` extends the effective radius (hills grant +1, so a unit on high ground sees one ring farther); (2) **line of sight** — an integer Bresenham trace in local offset space (wrap-safe) treats a tile flagged `blocks_sight` on its terrain or feature (hills/mountain, forest/jungle) as occluding everything strictly beyond it; the source and its eight neighbours are always visible, and a blocker is itself visible. Integer math only, no hardcoded terrain/feature ids. Shared by `TurnEngine._scan_sight_contact` (diplomatic first contact), `WildForces._mark_sight` (the wild-spawn darkness mask), and `scenes/world/fog_layer.gd` (fog-of-war), so all three agree exactly.

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
gs.assembly                      §7.2 world-assembly state (body, resident, open session, tallies)
gs.pending_assembly_events
gs.deals                         §7 persistent diplomatic deals (recurring per-turn items, cancellable)
gs.open_borders                  §7 bilateral open-borders agreements ({a,b} player-id pairs; Writing-gated)
gs.pending_deal_events
gs.pending_flips / gs.pending_era_advances / gs.pending_wild_events
gs.pending_first_contacts        §7 newly-met player pairs (per-direction)
gs.pending_tech_completions / gs.pending_great_people
gs.pending_productions / gs.pending_growth / gs.pending_improvements
```

Per-player diplomatic state also lives on each `Player`: `intel_points` (§7.1 EP per rival alliance) and `diplo_memory` (§7 decaying memory of rivals' acts, feeding the AI's attitude — see `Diplomacy`).

The `pending_*` arrays are an outbox: pipeline phases push records onto them, and `SimFacade` drains each into the matching signal (`assembly_event`, `city_flipped`, `era_advanced`, `technology_completed`, `unit_created`/`settlement_founded`, `settlement_production`, `settlement_grown`, `first_contact`) at the next opportunity. **First contact (§7):** `TurnEngine._ensure_mutual_contact` detects the not-met → met transition (a fresh append to `Alliance.contacts`) during the world-step sight sweep and pushes a per-direction record onto `gs.pending_first_contacts`; `SimFacade._drain_first_contacts` (called in the world-step block) turns each into a `first_contact` signal and a "You have made contact with <name>." notification (read by the HUD message log), naming the rival via `Player.name`. The queue is transient — drained the same step, so it is not serialized (no JSON int-key coercion needed). ID counters (`_next_unit_id` etc.) are also serialized so IDs remain stable across save/load.

### `TurnEngine`
Implements §3 as three static functions called in sequence. Every phase first consults `hooks.run(IDs.Phase.X, gs)` — if a hook returns `true` the built-in is skipped entirely.

**`world_step(gs, hooks)`** — runs once after all players end their turn:
1. Resolve/expire trade offers, then deliver every active persistent deal's recurring per-turn items (`_execute_deals`, §7: gold-per-turn transfers; a deal lapses if a party is gone or the two alliances are at war). Diplomatic memory also decays one step here (`Diplomacy.decay`)
2. Advance shared alliance research stores. Tributaries pay tribute to overlords (`_collect_tribute`), then vassalage maintenance runs (`Vassalage.world_tick`, §7: shared war/peace re-sync + liberation of recovered vassals)
3. Per-tile upkeep (`_tile_upkeep` — charges each owned, improved tile's improvement maintenance)
4. Spawn wild/raider forces (`WildForces`), then let them act (`WildAI.run` — §9 scouts, camp alerts, mustered raid waves; pushes fights/razes onto `gs.pending_wild_events`)
5. Environmental degradation (`Pollution`)
6. Assign special sites (stub)
7. Assembly/voting (`Assembly.world_tick` runs the §7.2 world-assembly lifecycle: sessions, resident elections, resolutions; gated on a built Apostolic Palace / United Nations. Diplomatic victory is delivered here via the UN election — `Assembly.apply_effect "diplomatic_victory"` — not by a standalone population poll)
8. Increment `turn_number`
9. Advance `current_player_id`
10. Check win conditions (`WinConditions`)

**`player_step(gs, player_id, hooks)`** — runs when a player ends their turn:
1. Pre-turn bookkeeping
2. Auto-assign workers to tiles (`_auto_assign_workers`): the **city centre tile is always worked for free** (it does not consume a population worker slot), then `effective_workers()` population citizens work the highest-scoring locked/owned tiles in the culture ring. Without the free centre a fresh size-1 city worked a single off-centre tile and ran a zero food surplus, so it never grew (the §4.2 food box never filled)
3. Treasury: income (finance slice of settlement commerce) − unit upkeep (civics waive free units / drop distance maintenance); insolvency handling
4. Research: accumulate research slice of commerce (+ civic science effects) against current tech cost
5. Intelligence accumulation (`_apply_intelligence` — §7.1 espionage points per rival, from the intel slice + structure `espionage` output scaled by `espionage_output`)
6. Settlement steps (iterates `settlement_step` for all owned settlements), then §4.9 cultural revolt / city flipping (`CultureRevolt.process_player`, queued onto `gs.pending_flips`)
7. Tick down timed states (transition, rush anger, celebration, Golden Age, state-religion/civic anarchy)
8. Validate policies; update war fatigue
9. Random events (`Events.process_player_events`, §9 lifecycle): tick timed `gs.active_events` to expiry, then scan `event_triggers.json` predicates (`trigger_holds`) and fire at most one — applying begin `effects`, auto-resolving an AI's branch, or parking a human's choice on `gs.pending_event_choices`; fired/expired records queue on `gs.pending_events` for the facade's `_drain_events`. A trigger whose event has a positive `duration` does not hold while an instance is already active for that player (`trigger_holds`'s `_timed_event_active` guard), so a non-one_shot timed event (e.g. the plague) cannot re-arm and stack overlapping instances each turn — it becomes eligible again only after it expires
10. Reset unit movement/action flags — a stationary worker mid-build advances here (`_advance_worker_build`); on completion the improvement is placed and, unless it `preserves_feature` (camp/lumbermill/forest_preserve/fort) or requires that feature, a removable forest/jungle on the tile is cleared via the shared `_chop_tile`. A worker running a **standalone chop order** (`MISSION_CLEAR_FEATURE`, sets `Unit.clearing_feature`) advances in the same loop (`_advance_worker_chop`) and fells the feature with no improvement placed. A felled forest delivers its `chop_yield` as production to the nearest owned city — raised by `chop_yield_tech_bonus_pct` once the `chop_yield_tech` (Mathematics) is researched, and scaled to `chop_outside_borders_pct` when the chopped tile sits outside the player's borders (full inside). Jungle clears for nothing. Then recompute the player's derived era (`Eras.refresh`, queuing `gs.pending_era_advances`)

**`settlement_step(gs, settlement, player, hooks)`** — runs per settlement:
- Growth: sum tile outputs + structure bonuses + econ org delta (+ civic tile/capital/free-specialist bonuses via `PolicyEffects`) → surplus food → food store → population threshold check
- Wellbeing: positive (structures, features, empire-health civics) vs negative (population, polluting structures) → deficit reduces effective food
- Contentment: positive sentiment (incl. civic happiness effects) vs anger-driven negative (war anger trimmed by civics) → `discontented` citizens → `in_disorder` flag
- Production: accumulate construction capacity (adjusted by `_policy_production_delta` for the queued item) → complete queue items (units, structures, projects)
- Culture: accumulate total culture → ring expansion → `Influence.spread()`
- Beliefs: `Beliefs.spread_all()` on each turn
- Specialist progress: at a city's threshold a Great Person unit of the dominant specialist type is born (`GreatPeople.birth_from_settlement`); with no typed specialists the legacy abstract bonus (instant tech / seeded org / gold) applies
- Structure upkeep charged to treasury

### `Player`
Per-player economic and research state. The four allocation sliders (`slider_finance`, `slider_research`, `slider_culture`, `slider_intel`) sum to 100. `split_commerce(total)` partitions a settlement's commerce output into `[finance, research, culture, intel]` according to the sliders. Also holds: `state_religion` (§8.1 — the player's adopted belief, switching it triggers anarchy via the shared anarchy counter); `era` (§2.1 — a *cache* of the derived current era, recomputed by `Eras.refresh`; every rule reads it live through `Eras.player_era`); `intel_points` (§7.1 — espionage points accumulated per rival alliance, spent on missions); Golden Age state (`golden_age_turns` / `golden_age_count` / `pending_golden_age_gp`); and Great General accumulation (`great_general_points` / `great_general_threshold` / `great_generals_produced`). All serialized.

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

### `CombatApply`
Pure application of a resolved `Combat.resolve()` result back to `GameState`: healths, XP, auto-promotions, removing the dead, advancing a victorious attacker onto the tile, spillover/flanking damage, war-fatigue, and Great-General accrual. No signals or `Node` references — so both `SimFacade` (the human/AI command path) and `WildAI` (the world-step raider path) share one source of truth. Each caller emits its own signals afterwards from the returned `result`.

### `Pathfinding`
Dijkstra over `WorldMap.neighbours4`. Movement cost per tile = terrain base + feature add, reduced if a road improvement is present. Domain legality (land/sea/air) is checked per tile. Tiles occupied by enemies block passage. `find_path(...)` takes an optional trailing `game_state` so legality can be world-aware: **deep-water (ocean) entry is gated (§5)** — a sea unit may enter a `deep_water` tile only if it is `ocean_capable` (a per-hull data flag, set on every ocean-going ship in `units.json`) **and** its owner has researched the `ocean_travel_tech` constant, with a waiver for tiles in the mover's own or an alliance-mate's territory (the open-borders proxy). The check lives in `can_enter_deep_water(tile, db, ocean_ctx)`; when no `game_state` is threaded in the gate is skipped (domain-only callers are unaffected), and ownerless/wild units skip the tech check. `SimFacade._cmd_move_stack` and `_explore_step` (the shared explore mover) both pass `_gs` so the gate is enforced on real moves. **Cultural border blocking (§7)** is enforced in the same Dijkstra loop by `border_passage_allowed(tile, mover_id, gs)`: a tile owned by another player may be ENTERED only when the mover **owns** it, is **at war** with the owner (war = invasion rights), is an **alliance-mate**, or holds an **open-borders** agreement with the owner — unowned/wild land (`owner < 0`) and own land pass freely, and the gate is skipped for domain-only callers and ownerless/wild movers. The deep-water waiver's `_tile_in_friendly_territory` now likewise honours a real open-borders agreement (via `Diplomacy.has_open_borders`) in addition to alliance membership, so land and ocean passage rules stay consistent. The explore-candidate filter applies the same predicate so a scout never steers into a foreign border it cannot enter. A **sea unit may also dock on a LAND tile** when that tile holds the mover's own (or an alliance-mate's) settlement — a coastal city acts as a harbour, so e.g. a work boat can pull into port (`_tile_has_friendly_settlement`, world-context only); any other land tile stays impassable to a sea unit.

**Explore targeting.** The `MISSION_EXPLORE` mission (used by both the human "Explore" order and the AI recon pass — `PlayerAI` issues `Commands.mission_explore` for idle recon units, so both converge on one mover) steers each step toward *unrevealed* map rather than wandering at random. `SimFacade._explore_choose_step` scores the unit's legal neighbour tiles by how many currently-unseen tiles each would newly reveal (`Visibility.visible_tiles` footprint vs the player's current sight set `_player_visible_tiles`), and the exploring unit keeps a serialized heading (`Unit.explore_dx/dy`) it commits to while the straight-ahead step still opens new fog — only re-aiming toward the max-reveal neighbour when the heading goes stale. `_explore_target` runs a deterministic BFS over legal terrain to confirm any reachable unseen tile still exists; when none does the scout idles (clears `is_exploring`) instead of thrashing. The "revealed" notion is *sim-derived current per-player visibility* (the same terrain-aware `Visibility` model the fog renderer, first-contact scan and wild-spawn mask use) — never the scene fog layer's accumulated ever-seen memory, which is presentation-only. No RNG is drawn, so an explore turn is reproducible and survives save/load.

### `Research`
`can_research(tech_id, player, db)` checks `prereqs_all` (all required) and `prereqs_any` (at least one). `_effective_cost()` applies pace scaling, a discount per known prereq (10% each), and a discount for each other player who already knows the tech (5% each, capped at 25%).

### `Alliance`
Tracks war state (`at_war_with`), contacts, subordination, shared research store, war fatigue, and pending trade offers. War and peace are declared at the alliance level, not the player level. Accepted trades carrying recurring items promote to persistent deals on `gs.deals` (§7, see `TurnEngine._execute_deals` / `SimFacade._cmd_cancel_deal`).

### `Diplomacy`
§7 AI diplomatic attitude & memory (pure static, provisional). Computes a deterministic 0..100 attitude one player holds toward another — a neutral base + live relational factors (at-war, shared war, permanent ally, an active deal, shared/clashing state religion) + a decaying memory total — bucketed into five levels (furious → friendly). Memory lives on `Player.diplo_memory` (`rival_id -> {kind: signed points}`): `record` accrues a kind's data value when a rival acts (declared war, broke a deal, razed a city, traded, made peace), `decay` (once per world step) shrinks every entry toward zero. No RNG. All magnitudes in `data/diplomacy.json`. The AI (`PlayerAI.manage_diplomacy`) and `Assembly.ai_vote` read it to gate deal acceptance, war declaration, and assembly votes. `deal_resources_for(gs, player_id)` returns the resources a player gains through active recurring deals — unioned into `EconOrgs._player_accessible_resources`, so a traded resource counts as an accessible corporation input.

**Open borders (§7).** `has_open_borders(gs, a, b)` is the canonical passage predicate — true when two players share a signed agreement (`gs.open_borders`) **or** are alliance-mates (same-alliance counts as implicit open borders). `open_borders_tech(db)` reads the gating tech from `data/constants.json` (`open_borders_tech`, default `"writing"`), and `can_open_borders(gs, db, player_id)` checks the player holds it. An agreement is a bilateral, signable, ongoing deal stored as `{a,b}` player-id pairs on `gs.open_borders` (serialized; deserialize coerces a/b to int). It is **proposed** as a trade carrying an `open_borders` flag (`Commands.propose_open_borders` / `propose_trade(..., open_borders=true)`), Writing-gated at proposal time in `SimFacade._cmd_propose_trade`, **accepted** by the other side through the normal trade-accept path (the AI's `_answer_trade_offers` accepts a value-neutral offer from a non-loathed rival by attitude), and **recorded** in `_execute_trade` (re-checking both sides hold the tech). It is **revoked** by either party (`CANCEL_OPEN_BORDERS` / `Commands.cancel_open_borders` → `_cmd_cancel_open_borders`), and **torn up by war** — `SimFacade._cmd_declare_war` purges every cross-alliance member pair (at war you invade regardless). `GameState.has_open_borders`/`add_open_borders`/`remove_open_borders` are the order-independent storage helpers. The HUD's `DiplomacyScreen` offers an "Open Borders"/"Close Borders" button per met rival, shown only when the player holds Writing (or an agreement already stands).

### `Vassalage`
§7 team/vassalage parity (pure static, provisional; Phase 8). The war-driven half of the subordination model, layered on the existing scaffolding (`Alliance.is_subordinate_to`/`tributaries`, the voluntary `SET_SUBORDINATION` command, `TurnEngine._collect_tribute`). `alliance_power(gs, alliance)` is the canonical military-strength proxy (summed `effective_strength × health` of land combat units; `PlayerAI._alliance_military_power` delegates to it). `is_crushed_by(gs, db, sub, overlord)` is the **capitulation** gate (at war **and** sub power ≤ `vassal_capitulation_power_pct`% of the overlord's), `crushing_overlord` finds the strongest such conqueror; `can_liberate` is the **liberation** gate (sub power recovered to ≥ `vassal_liberation_power_pct`% of the overlord's — the 40/70 dead band gives hysteresis). `world_tick(gs, db)` runs each world step (after tribute, no RNG): `sync_vassal_wars` drags vassals into the overlord's wars and out of wars it has left (shared war & peace), then liberates any recovered vassal and queues a `vassal_liberated` notice onto `gs.pending_deal_events`. Capitulation reuses `SET_SUBORDINATION` (the AI's `PlayerAI._maybe_capitulate` submits its alliance's lowest-id leader when crushed); the overlord's `FREE_VASSAL` command (`SimFacade._cmd_free_vassal`) releases a tributary. Thresholds in `data/constants.json`; **no new serialized state**

### Other sim modules
- **`Eras`** — §2.1 ages/eras (pure static reader, provisional): a player's era is *derived* — the highest era index among the techs they have researched (`Ancient`/0 with none), read live through `player_era()`; `Player.era` is only a cache that `refresh()` updates to detect advancement (queued onto `gs.pending_era_advances`). Eras scale growth thresholds and the §4.9 culture-revolt power term; unit/structure availability is already era-gated transitively through tech prereqs. Reads `data/ages.json` and the per-tech `era` tag
- **`CultureRevolt`** — §4.9 cultural city flipping (pure static, provisional): a TurnEngine phase in the owner's player step that tests each of the owner's settlements; the strongest rival that both out-cultures the owner on the city's tile and holds a settlement within cultural radius accumulates revolt on a passed `gs.rng` check, and the city flips once enough accumulate. Mutates ownership/occupation directly and returns flip records onto `gs.pending_flips`
- **`Assembly`** — §7.2 world-government assemblies, elections & resolutions (pure static, provisional): a voting body founded by a world wonder (the religious Apostolic Palace, superseded by the secular United Nations). `world_tick()` drives the lifecycle once per world step — a session opens on a cadence recording one proposal (a resident election while there is no resident, else a random eligible resolution from `data/resolutions.json`), members cast weighted Yea/Nay/Abstain over their player-turns (humans via `SimFacade.cast_assembly_vote` / the `CHOOSE_ELECTION` popup, AI automatically), and the proposal resolves. State lives in `gs.assembly`; outcomes push onto `gs.pending_assembly_events`
- **`WildAI`** — §9 wild-forces *behaviour* (pure static, provisional). `WildForces` spawns raiders; `WildAI.run()` makes them act once per world step (owner `-2` has no round-robin slot, so it runs inside `world_step`, not as a facade client): refresh wild movement, march each unit toward its raid goal or wander, and fight via the shared `CombatApply`. **Camp garrison** (`_camp_garrison_ids`, run before `_act_units`): a raider camp is never marched fully empty — for each camp tile (a `-2` settlement) holding more than `wild_camp_min_garrison` (default 1) land raiders, that many of the strongest occupants (tie-broken by ascending id, deterministic, no RNG) are held back to defend the camp and its claimed cultural border; the rest sortie normally. A camp with only enough units to meet the floor (e.g. a single freshly-mustered unit) still sends them all out, so holding the last unit never starves raiding. **Animals** (§9.3, `is_animal`) branch to `_act_animal`: hunt the nearest weak/unfortified non-garrisoned unit within range, never assaulting cities and (mostly) never entering borders. **Naval raiders** (§9.4, sea-domain) branch to `_act_naval`: a random water patrol that attacks any player unit it sails into. Surfacing (a fight, a razed city) goes onto `gs.pending_wild_events`
- **`GreatPeople`** — §14 subsystem (pure static): maps specialists → great-person units (via the `Specialists` table, falling back to a unit `generated_by` scan for the General's `combat_xp`), type-aware birth, Golden Ages (worked-tile bonus in `_settlement_growth`, war-weariness freeze, tick-down in `_tick_states`), the Great General accrued from combat, and the `GP_ACTION` action dispatch (`perform_action`) validated against each unit's data `actions` list. Types/actions are defined entirely in `data/units.json`; magnitudes in `data/constants.json`
- **`Specialists`** — §6.5/§14.5 specialists reader (pure static): the single consumer of `data/specialists.json`. `settlement_output`/`settlement_channel` sum each assigned specialist's per-head output vector across the six yield channels; `settlement_gp_points` weights GPP accumulation by each type's `gp_points`; `great_person_unit` maps a type to the GP unit it births (used by `GreatPeople.gp_unit_for_type`); `slots_for` resolves the per-type slot ceiling (`default_slots` + per-structure `specialist_slots`, −1 for unlimited / Caste System); `assignable_types` is the city-screen roster. `TurnEngine` routes the channels into city output / research / culture / intelligence; `SimFacade._cmd_assign_specialist` enforces `slots_for`
- **`PolicyEffects`** — §8 civic-effects reader (pure static): `sum_int`/`has_flag` aggregate a player's active policies' `effects` (both nested `effects` dicts and bare top-level flags); `largest_city_ids`/`is_religious_structure` are supporting helpers. The single reader of per-civic `effects`, called from `TurnEngine` (happiness/health, tile + capital output, production via `_policy_production_delta`, research/intel, treasury, Great-Person rate, new-unit XP) and `SimFacade` (rush gating, Serfdom worker speed). The mechanical policy fields stay in `SimFacade`/`TurnEngine`. See `docs/planning/designgaps.md` §2 for the wired-vs-inert breakdown
- **`Beliefs`** — founding (first-eligible random draw), passive spread within range each turn
- **`EconOrgs`** — §14.6 corporations: founded by a special person/Great Merchant (`found` erects the corporation's `hq_structure` in the founding city), organically `spread_all` like beliefs (costs treasury) or deliberately via an executive unit (`SimFacade._cmd_spread_corporation`, the `spread_corporation`-tagged unit, charged `corporation_executive_spread_cost`). Per-city output (`get_output_delta`) is the flat `output_delta` plus `output_per_input_resource × accessible-input-count` (distinct input resources the city owner has connected); `maintenance_for` charges per member city (Free Market `corporation_maintenance_reduction` halves it) and `hq_gold_for` pays the founder per unit of input consumed worldwide — both wired into `TurnEngine._update_treasury`. Mercantilism/State Property set the `corporations_disabled` civic flag, under which a player's corporations produce nothing, cost no maintenance, and cannot be spread into. Keyed off `data/econ_orgs.json` (HQ/executive/maintenance/HQ-gold per corp); HQ structures carry a `corporation_hq` flag so they are granted by founding, never offered as a normal build
- **`WildForces`** — BtS-derived spawn model (§9.2/§9.3 provisional): turn/era/city gates, then a per-area unowned-tile density top-up (`((unowned/divisor) − existing)/4 + 1`) for units, and a gated/probabilistic/distance-checked raider-camp spawn (a freshly spawned camp immediately `Influence.found_claim`s a small owner-`-2` ring so it has visible cultural borders). Also `spawn_animals` (§9.3): quiet-phase wildlife on dark/unowned tiles up to a per-difficulty density, thinned once raiders take over; and `spawn_naval` (§9.4): the same per-area density model over water areas, using the strongest sea unit any player has unlocked. Reads per-difficulty tables from `data/difficulties.json`
- **`Pollution`** — per-settlement accumulation each turn; per-tile RNG degradation chain
- **`WinConditions`** — stateless evaluation against `gs`; returns winning `alliance_id` or −1
- **`Scoring`** — weighted sum of (land tiles, population, technology count) per alliance
- **`Nuclear`** — §5.7 nuclear weapons & radioactive fallout (pure static, provisional): `is_nuke(db, unit)` checks the `nuke` tag; `strike(gs, x, y, strength, radius)` detonates over a target tile — area damage to all units/settlements in the blast radius, ground stripping (forest/jungle/improvement removal), and Fallout feature contamination. The meltdown/`contain()` world-tick runs inside `TurnEngine.world_step`. All the integer-math chances and magnitudes live in `data/constants.json`; every stochastic step draws from the shared `gs.rng`
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
    ["last_standing", "dominance", "time"],
    "continents")   # map_type_id (optional; defaults to "continents")

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

### Facade *clients* (`src/api/`)
These are not part of the engine — each is a *client* of `SimFacade`, exactly like the UI: they read `get_state()` and mutate only through `apply_command()` (or, for debug write commands, mutate `GameState` then `get_dirty().mark_all()`), drawing any randomness from the shared `gs.rng`, so their actions are reproducible and captured by save/load.

- **`PlayerAI`** — the three-layer deterministic computer player (`take_turn(facade, player_id)`). **(A) Handicap** — `ai_bonus` from `data/difficulties.json` scales AI production and research yields at prince and above (0 at noble → 70 at deity). **(B) Brain** — a competent role-ranked playbook: `manage_production` refills each city's queue only when empty using `_sorted_options` (defender floor → economy structures → settlers/workers → cheapest fallback); `manage_units` is a four-pass playbook (settlers → garrison fill → free military offense/advance → workers/recon), wholly deterministic with no separate RNG. **(C) Focus** — `_focus_profile(player, db)` sums each trait's `ai_focus` block (`expand`/`military`/`economy`/`science`) and soft-biases production order, economy sliders, city-count target, garrison floor, and attack margin above their Phase-B baselines, never gating any behaviour. All decisions are reproducible and captured by save/load. Marked by `Player.is_ai`; driven in-scene by `HotseatManager` and on the server by `net_server.gd`.
- **`DebugConsole`** + **`DebugLog`** (the latter in `src/core/`) — the debug-build-only debugging subsystem: a command engine and a capped stdout-mirrored ring buffer, surfaced by the `~` overlay and a stdin terminal reader. Inert under release exports and the headless/GUT runner. Full reference: `docs/design/debug.md`.

### Presentation-only helpers (`src/api/`)
UI concerns that deliberately live outside `GameState` (they have no effect on simulation outcomes and are not serialized):

- **`DirtyFlags`** — per-region invalidation bit set (one bool per `IDs.DirtyRegion`). `SimFacade` sets flags on state change; the presentation host clears them after repainting each affected region. `get_dirty().mark_all()` forces a full repaint (used after a load).
- **`SelectionState`** — the active subject (selected unit IDs or selected city) tracked for the HUD/input layer.
- **`SliderMath`** — keeps the four economic-allocation sliders summing to exactly 100 by spreading a change across the other three in a fixed round-robin order, in whole `step` increments (predictable, no value jumping).
- **`TextGen`** — centralized tooltip/breakdown text (§9 of ui-design): every human-readable explanation of game state lives here, reached via `SimFacade.widget_help()`, so displayed text always matches the actual computation.

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
             ├─ resolve/expire trades        → alliance.pending_trades
             ├─ alliance research stores
             ├─ tile upkeep                  → player.treasury
             ├─ WildForces + WildAI.run      → gs.units (appended), gs.pending_wild_events
             ├─ Pollution + Nuclear.meltdown → tile.pollution, tile.terrain_id, fallout
             ├─ Assembly.world_tick          → gs.pending_assembly_events
             ├─ gs.turn_number += 1
             ├─ advance current_player_id
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
