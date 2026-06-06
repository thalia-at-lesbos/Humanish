# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run everything in order: unit suites, then the integration playthrough gate.
./run_tests.sh                       # override engine with GODOT=… (default: godot3)

# Unit suites only — note tests/integration is excluded by listing the unit dirs
godot3 --no-window -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/core,res://tests/world,res://tests/sim,res://tests/api,res://tests/scenes,res://tests/net \
  -ginclude_subdirs -gexit

# Integration playthrough only (the final gate)
godot3 --no-window -s addons/gut/gut_cmdln.gd -gdir=res://tests/integration -ginclude_subdirs -gexit

# Run a single test file
godot3 --no-window -s addons/gut/gut_cmdln.gd -gtest=res://tests/sim/test_combat.gd -gexit

# Run a single test by name within a file
godot3 --no-window -s addons/gut/gut_cmdln.gd -gtest=res://tests/sim/test_combat.gd -gunit_test_name=test_combat_same_seed_identical_outcome -gexit

# Launch the headless multiplayer server (--save is REQUIRED; see network-design.md)
./run_server.sh --save=game.sav --players=3 --ai=1 --port=9080   # override engine with GODOT=…

# Manual (non-CI) end-to-end multiplayer loopback smoke test
godot3 --no-window -s res://tests/manual/loopback_smoke.gd   # prints "SMOKE: PASS"
```

> Heads-up: `-gdir=res://tests -ginclude_subdirs` would recurse into **all** of `tests/`, including `tests/integration`. To keep the unit run separate from the final integration gate, run them as two phases (use `./run_tests.sh`, which encodes the ordering and is mirrored by `.github/workflows/build.yml`).

The test framework is **GUT 7.4.3** (Godot 3.x). Test suites are organised by functional area, mirroring the source layout: `tests/core/`, `tests/world/`, `tests/sim/`, `tests/api/`, `tests/scenes/`, `tests/net/` — one file per module/subsystem (e.g. `combat.gd` → `tests/sim/test_combat.gd`). New tests go in the file for the subsystem they exercise; a brand-new subsystem gets a new `test_<name>.gd` under the matching layer. `tests/integration/` holds end-to-end **playthrough** suites that drive a whole game through `SimFacade` (most interaction families in one scenario); they run as the final gate **after** the unit suites, never mixed into them.

Most suites extend the shared fixture `"res://tests/support/sim_fixture.gd"` (which itself extends GUT's `test.gd`) for the common scaffolding — `make_db()`, `make_gs(num_players, seed)`, `make_unit/make_warrior/make_settlement/make_gp`, `bare_facade(gs)`, `setup_facade(...)`, `hooks()`, `run_turns(...)`. Pure-math/data suites with no game state (e.g. `test_fixed`, `test_slider_math`) extend `"res://addons/gut/test.gd"` directly. The fixture file is **not** collected as a suite — GUT only picks up files named `test_*`. Each `test_*` method is one test case.

## Architecture

The design enforces a hard boundary: **`sim` (pure rules) ↔ `api` facade ↔ `scenes` (presentation)**. Nothing in `src/sim/` or `src/world/` may reference `Node`, scenes, or input. This keeps the engine headless and testable.

### Scene entry-point flow

```
scenes/menus/start_menu.tscn   ← project.godot main_scene
        │  "New Game" pressed
        ▼
scenes/setup/setup_screen.gd   (programmatic Control; collects players, world size, map type, pace, difficulty, society)
        │  on_setup_complete callback(facade, db)
        ▼
scenes/main.tscn               (wires WorldView, HUD, InputRouter, HotseatManager)
```

`StartMenu` loads `DataDB`, shows title + buttons (New Game / Load Game / About / Exit), and instantiates `SetupScreen` on "New Game". When setup completes it calls `main.init_with_facade(facade, db)` before adding `main.tscn` to the scene tree, then frees itself. `main.gd` falls back to a default 2-player tiny game when `init_with_facade` is not called (e.g. running `main.tscn` directly).

The in-game HUD (`scenes/hud/`) stacks an **advisor menu bar** (`menu_bar.gd`, a button per `OPEN_*` screen — the discoverable alternative to the F-key hotkeys), the turn/score and research bars, the economy sliders, the **selection panel** (`selection_panel.gd`: selected unit/city info, an on-tile stack list with a Select-all that orders the whole stack, foreign subjects shown read-only), the message log, and the end-turn button. `InputRouter` left-click priority: a selected unit treats a click on any *other* tile as a move/attack destination (friendly cities/stacks included); clicking its own tile cycles the stack; with nothing selected a click selects the unit then city on the tile. After an order it auto-advances to the next idle unit. `WorldView`'s `FogLayer` keeps per-player explored memory (seen tiles stay dimly revealed; live units only render in current sight). The `CityScreen` exposes manual citizen management (a work-radius grid that locks/unlocks worked tiles, an automate-citizens toggle, specialist +/-).

### Data flow

1. `DataDB` is created and `db.load_all()` parses all JSON tables from `data/`.
2. `SimFacade.setup(db, seed, ...)` initializes `GameState`.
3. Each player action is a plain Dictionary built by `Commands.*()` helpers and submitted via `facade.apply_command(cmd)`. No other path mutates state.
4. Observers read `facade.get_state()` or subscribe to facade signals (`turn_advanced`, `combat_resolved`, etc.).
5. Save/load: `facade.save()` → JSON string → `facade.load_save(json)`. State hash via `facade.state_hash()` is the determinism gate. The in-game UI lives in `scenes/screens/save_load_screen.gd` (the `Screens/SaveLoadScreen` node in `main.tscn`), reading/writing `.sav` files under `user://saves/`. It is reached via the `screen_requested` signal from `SimFacade._cmd_control`, which `main.gd` routes: `OPEN_SAVE_LOAD` opens the file-list screen, while `QUICK_SAVE`/`QUICK_LOAD` (bound to F5/F9 in `data/hotkeys.json`) call the screen's `quick_save()`/`quick_load()` directly against the fixed `quicksave.sav` slot without showing it. After a load the screen calls `facade.get_dirty().mark_all()` so the presentation layer fully repaints. The `StartMenu` also offers "Load Game": it lists `user://saves/*.sav`, builds a fresh `SimFacade`, calls `facade.init_for_load(db)` (scaffolds `_db`/`_hooks`/UI state without running `setup()`), then `facade.load_save(json)` and hands the facade to `main.tscn` via the same `init_with_facade` path as a new game. In-game, **Escape** (bound to `OPEN_MENU` = 24 in `data/hotkeys.json`) toggles the pause menu (`scenes/screens/pause_menu.gd`, the `Screens/PauseMenu` node) — a Resume/Save/Load/New Game/Quit overlay whose Save and Load buttons defer to the shared `SaveLoadScreen` (handed to it via `set_save_load_screen` in `main.gd`), whose New Game `change_scene`s back to `start_menu.tscn`, and whose Quit calls `get_tree().quit()`.

### Non-negotiable engine invariants

1. **Integer math only** — no floats in `sim/` or `world/`. `Fixed` (100-unit scale) handles movement precision. Percentages are integer 0–100. Use ternaries instead of `max()`/`min()` in `-> int` typed functions (Godot 3's `max()`/`min()` returns float).
2. **One shared RNG** — every stochastic call goes through `gs.rng` in pipeline order. Never create a separate `RandomNumberGenerator`. The RNG seed/state is serialized as **strings** (not ints) to avoid JSON double-precision truncation of 64-bit values.
3. **Data-driven** — all numeric constants live in `data/*.json`, loaded by `DataDB`. No magic numbers in rule code.
4. **Pipeline order is a rule** — `TurnEngine.world_step()` and `player_step()` execute phases in strict §3 order. Each phase first calls `hooks.run(IDs.Phase.X, gs)` and skips the built-in if it returns `true`.

### Key class responsibilities

| Class | Role |
|---|---|
| `GameState` | Root aggregate; the single source of truth. All sim state lives here. |
| `TurnEngine` | Implements §3 pipeline as static methods; calls into every other sim module. |
| `GreatPeople` | §14 Great Person subsystem: type-aware birth, Golden Ages, the Great General from combat, and GP action dispatch (`perform_action`). Pure static; reads types/actions from `data/units.json`. |
| `SimFacade` | Public API; validates commands, routes to `TurnEngine`, emits signals. |
| `DataDB` | Loads/validates all JSON tables; provides typed getters including `get_societies()` and `get_map_type()`. |
| `MapGen` | Procedural map generator (`src/world/`, pure static): per-script land-mask `shape` + climate `paint`, driven by `data/map_types.json`. `generate(map, db, rng, map_type_id)` fills a blank `WorldMap`; `find_start_positions(...)` lays out spread-out starts (honouring per-script `start_bounds`). |
| `Fixed` | All integer math helpers (scale, proportion, movement conversion). |
| `RNG` | Seeded PCG32 wrapper; `get_state()`/`restore_state()` for save-resume. |
| `Hooks` | FuncRef registry keyed on `IDs.Phase`; lets rules be overridden per-phase. |
| `SaveLoad` | `JSON.print(gs.serialize())` / `GameState.deserialize()`; computes `state_hash()`. |
| `Commands` | Static factories for all command Dictionaries; no logic, pure construction. |
| `PolicyEffects` | §8 civic-effects reader: `sum_int`/`has_flag` aggregate a player's active policies' `effects` (both nested dicts and bare flags); plus `largest_city_ids`/`is_religious_structure` helpers. Pure static; the single reader of per-civic `effects`, called from `TurnEngine` and `SimFacade`. |
| `StartMenu` | Entry-point scene; loads `DataDB`, routes to `SetupScreen` or quits. |
| `SetupScreen` | Collects new-game parameters (players, society, per-player human/AI toggle, world size, map type, pace, difficulty) and calls back with a ready `SimFacade`. |
| `PlayerAI` | Simple deterministic computer player; a facade *client* (like the UI) that drives a flagged player's whole turn via `apply_command`. Pure static; lives in `src/api/`. |
| `DebugConsole` | Advanced-debugging command engine (`src/api/`); a facade *client* (like `PlayerAI`) that inspects and modifies game values. Shared by the terminal reader and the `~` overlay. Debug-build-only. |
| `DebugLog` | Pure capped ring buffer of debug log lines (`src/core/`) with a stdout mirror; fed by mirrored `SimFacade` signals. Debug-build-only. |
| `NetProtocol` | Pure remote-multiplayer wire format (`src/net/`): message-type constants + `encode`/`decode` of `{v, t, d}` JSON frames. No sockets. |
| `NetConfig` | Pure parser (`src/net/`) for the headless server's command-line switches (`--server`/`--port`/`--players`/`--ai`/`--load`/…) into a config dict. |
| `net_server.gd` | Authoritative WebSocket server (`scenes/net/`, a facade *client*): the round-robin turn loop that plays AI slots, pushes state to the active remote human, and runs the end-of-turn pipeline on `submit`. |
| `net_client.gd` | Remote-multiplayer client (`scenes/net/`, a `Node` facade *client*): WebSocket transport + in-game glue; re-syncs the facade on each `state` and ships a `submit` at end of turn. |

### Computer players (`PlayerAI`)

`Player.is_ai` marks a player as computer-controlled (serialized; default `false`; set from each player config's `is_ai` in `SimFacade.setup()`, toggled per-player by the `SetupScreen` row checkboxes). `PlayerAI` (`src/api/player_ai.gd`) is **not** part of `sim/` — it is a *client* of `SimFacade`, exactly like the human UI: it only mutates state through `apply_command`, and it draws every random choice from the shared `gs.rng` (never its own generator), so an AI turn is reproducible and is captured by save/load. `PlayerAI.take_turn(facade, player_id)` runs the whole turn then ends it; the decision logic is deliberately simple — cheapest researchable tech, latest-unlocked policy per civic category, each city's queue refilled with every buildable unit/structure cheapest-first (replanned only when empty), and ~50% of units garrisoning their nearest city while the rest wander and pick random actions. In the scene layer, `HotseatManager` watches `player_turn_started` and `call_deferred`s `PlayerAI.take_turn` for `is_ai` players, chaining through consecutive AI players until a human's turn opens the pass-device screen. Like any new `class_name`, `PlayerAI` is registered in `project.godot`'s `_global_script_classes`.

### Remote multiplayer (`src/net/`, `scenes/net/`)

A simple asynchronous **client–server** layer for playing over the internet — **full-state handoff, round robin** (simultaneous turns are planned, not built). Like `PlayerAI` and the UI, every networking object is a *client* of `SimFacade`: it only reads `get_state()` or mutates through `apply_command()`/`load_save()`/`save()`, so **nothing in `sim/`/`world/` references it** and the wall holds. Transport is Godot 3's built-in **WebSocket** (`WebSocketServer`/`WebSocketClient`) — TCP on one port, chosen because it is transparent across the internet (clients connect outbound; no NAT/UDP/firewall setup beyond the server's one reachable port). Frame buffers are widened (`set_buffers`) because a whole serialized `GameState` exceeds the WebSocket default.

The authoritative game lives on the **server** (the engine run windowless): it holds the one `SimFacade`, plays any AI slots itself, and relays turns. At the start of a remote player's turn the server pushes the whole serialized state (`state` message); the client plays its moves locally, then on End Turn pushes its post-move snapshot back (`submit`); the server adopts it (`load_save`) and runs the authoritative end-of-turn pipeline (`apply_command(end_turn)` → `player_step`/`world_step`/AI turns). The round-robin `_drive()` loop in `net_server.gd` is the single place turn *policy* lives — the documented seam for future simultaneous turns.

* **The server autosaves every turn.** `net_server.gd` connects to the facade's `player_turn_started` (fires on every turn transition, human or AI) and writes `facade.save()` to its configured file — so a completed turn is never lost and a game can be resumed with `--load`. A bare save name lands under `user://saves/`; a name with a `/` is a full path. A default save file is therefore **mandatory** (`NetConfig.server_config_error` enforces it).
* **Server mode, headless (command line):** `./run_server.sh --save=<file> [flags]` wraps `godot3 --no-window -s res://scenes/net/server_runner.gd -- --server …`. `server_runner.gd` (`extends SceneTree`) builds `DataDB`+`SimFacade` from `NetConfig`, stands up `net_server.gd`, and polls the socket each `idle_frame` (no scene/menu loaded). Flags (`--save` required, plus `--port`, `--players`, `--ai`, `--load`, `--world`, `--map`, …) are parsed by `NetConfig`.
* **Server mode, in-game host:** the start menu's **"Multiplayer Server"** button opens `scenes/net/server_setup.gd`, which runs an authoritative `NetServer` *in this process* (polled each `_process` frame). The host sets port/name/save-file, then either configures a **New Game** (reusing the normal `SetupScreen`) or **loads** a saved state; the screen then becomes a live status panel (connected players, current turn) with a Stop button. The server holds/relays state only — no game board on the host.
* **Client mode is the "Multiplayer" button on the start menu** → `scenes/net/multiplayer_setup.gd` (host/port/name → Connect). On the first `state` snapshot the `NetClient` builds a facade, installs itself as the facade's remote-submit handler, and hands the facade to `main.tscn` via the same `init_with_facade` path as New Game / Load (the live `NetClient` Node is reparented into the main scene so it keeps polling). The server sends every joiner a bootstrap `state` on `hello` **regardless of whose turn it is** (inactive when it is not their turn), so a client joining on another player's turn still enters the game in the "waiting" state instead of stalling in the lobby — `_drive()` only pushes to the active player, so this bootstrap is what off-turn joiners rely on.
* **The only engine seam** is on `SimFacade`: `set_remote_submit_handler(funcref)` marks the facade a remote client and intercepts End Turn (the `END_TURN` command and the `DO_CONTROL` END_TURN/FORCE_END_TURN hotkey path) — instead of running the local pipeline it ships the snapshot and parks the turn via `set_remote_waiting(true)` (the End Turn button then reads "Waiting…"). The seam is presentation-only wiring and **not serialized**.
* **Adding a network message**: add a type constant to `NetProtocol`, a `case` to the server's `_handle_frame` and/or the client's `_handle_frame`, and a test to `tests/net/test_net_protocol.gd`. CI covers the pure layers (`NetProtocol`, `NetConfig`), the facade seam (`tests/api/test_sim_facade_remote.gd`), **and the live socket path** — `tests/net/test_multiplayer_loopback.gd` opens real loopback WebSocket connections (server↔client(s)), pumping frames via GUT yields + a poller Node, and asserts the turn cycle, autosave, and the off-turn-join bootstrap. `tests/manual/loopback_smoke.gd` is a by-hand probe of the same path. Like any `class_name`, `NetProtocol`/`NetConfig` are registered in `project.godot`. Full reference: `docs/design/network-design.md`.

### Advanced debugging (debug-build-only)

A developer debugging subsystem, **gated to interactive debug builds** — it is inert under release exports and under the headless/GUT runner (detected in `scenes/main.gd:_debug_active()` and `terminal_console.gd:_is_interactive_debug()` via `OS.is_debug_build()` plus a `--no-window`/`gut_cmdln` cmdline check), so it never affects shipped play or CI. Two pure classes do the work: `DebugLog` (`src/core/`, a capped ring buffer with a stdout mirror) and `DebugConsole` (`src/api/`, the command engine and a facade *client* like `PlayerAI` — read commands query `facade.get_state()`, write commands mutate `GameState` directly then `get_dirty().mark_all()`). Two thin scene nodes (`scenes/debug/`) surface it: `terminal_console.gd` reads stdin on a worker thread and `call_deferred`s each line to the engine on the main thread, and `debug_overlay.gd` is the `~`-toggled (Escape-to-close) in-game menu with a live info pane + an embedded console running the same engine plus GUI-only `reveal`/`fog` view helpers. `scenes/main.gd:_wire_debug()` builds one shared `DebugLog`+`DebugConsole`, hands them to both surfaces, and mirrors `SimFacade` signals into the log as the "extra logging". `sim/`/`world/` never reference any of it. Full reference: `docs/design/debug.md`.

### Godot 3 GDScript constraints to remember

- `class_name Foo` creates a global name, but **do not use `Foo.new()` inside `foo.gd`** — it triggers a cyclic-reference parse error. Use `load("res://path/foo.gd").new()` in static factory methods instead.
- Test helper functions must **omit return type annotations** (`-> MyClass`) to avoid parse-order failures with class_name globals.
- GUT 7 has no `assert_gte`/`assert_lte` — use `assert_true(a >= b, "msg")`.
- `seed` is a GDScript built-in function name; do not use it as a parameter name.
- When swapping scenes programmatically, call `init_with_facade(facade, db)` on the new scene **before** `add_child()` so `_ready()` sees the pre-built state.

### Adding new content

- **New unit/structure/tech/etc.**: add a JSON entry to the relevant file in `data/`. No code change required unless the entry introduces a mechanic not yet modelled.
- **New society**: add an entry to the `"societies"` block in `data/leaders_traits.json` with `id`, `name`, `leader_id`, `leader_name`, `description`, `traits` (array of trait IDs), and `starting_gold`. It will appear automatically in the `SetupScreen` society picker.
- **New map type / script**: add an entry to `data/map_types.json` with `id`, `name`, `category`, `description`, a land-mask `shape`, a `climate`, and the relevant tunables (`land_fraction`, `mountain_chance`/`hills_chance`, `forest_chance`/`jungle_chance`, plus shape params like `num_continents`, `main_size`, `plate_count`, `start_bounds`, `new_world`). It appears automatically in the `SetupScreen` map-type picker, and `MapGen` reads it directly. Reusing an existing `shape`+`climate` pair needs **no code**; a brand-new `shape` needs a builder in `MapGen._build_mask`/`_shape_bias`, and a brand-new `climate` a band in `MapGen._flat_terrain`.
- **New trait**: add an entry to the `"traits"` block in `data/leaders_traits.json`. Wire its effects in the relevant sim module (e.g. `TurnEngine`, `Combat`, `GreatPeople`).
- **New Great Person type (§14)**: add a `unit` entry to `data/units.json` with `"classification": "great_person"`, a `generated_by` (the specialist type that produces it, or `combat_xp` for the Great General), and an `actions` array. `GreatPeople` reads these directly — `gp_unit_for_type()` maps the specialist to the unit and `perform_action()` validates against the `actions` list, so no new command is needed. A brand-new action *verb* needs a handler added to `GreatPeople.perform_action()`; `build_<structure_id>` verbs are already handled generically. Magnitudes (gold, hammers, culture, GP/Golden-Age costs) live in `data/constants.json`.
- **New civic / civic effect (§8)**: add a policy entry to `data/policies.json` (one of the five categories). The mechanical fields (`upkeep_modifier`, `slider_increment`, `slider_min_research`, `anger_modifier`, `transition_turns`) are read directly by `SimFacade`/`TurnEngine`. Headline gameplay bonuses go in the per-civic `effects` dictionary (or, for a lone flag, a bare top-level key) and are read through `PolicyEffects.sum_int`/`has_flag`; a *new* effect key needs wiring into the relevant sim site (e.g. `_update_contentment`, `_settlement_growth`, `_policy_production_delta`, `_update_treasury`, `_cmd_rush_production`). See `docs/planning/designgaps.md` §2 for the effects already wired and the few still blocked on unbuilt subsystems.
- **New rule / phase override**: register via `facade.get_hooks().register(IDs.Phase.X, obj, "method")`. The method receives `(game_state, args: Dictionary)` and returns `bool`.
- **New command**: add a factory to `Commands`, add a case to `SimFacade.apply_command()`, implement a `_cmd_*` handler.
- **New advisor/info screen (§3.1 UI vocabulary)**: add a `ControlType` value to `IDs`, list it in the `screen_requested` emit group in `SimFacade._cmd_do_control`, write `scenes/screens/<name>_screen.gd` extending the read-only `info_screen.gd` scaffold (set `_title`, override `_populate(vbox)` using `_add_line`), register it in `scenes/main.gd:_init_extra_screens()` keyed by the control, and add a button for it to the HUD advisor bar (`scenes/hud/menu_bar.gd` `ENTRIES`) so it is reachable without a hotkey. (Interactive screens that need their own `.tscn` node — like `CityScreen`/`DiplomacyScreen` — are instead listed in the `main.gd` screens-init loop and routed in the `screen_requested` `match`.) A screen that issues an action routes it back through `apply_command` (see `options_screen.gd`). New `UnitCmd`/`UnitMission` verbs follow the §3.2/§3.3 pattern: enum value + `CommandType` + `Commands` factory + a case in `_cmd_unit_command`/`_cmd_mission` (stance flags live on `Unit` and are serialized). See `docs/planning/designgaps.md` §3 for what is built vs. deferred.
- **New debug console command**: add a `case` to `DebugConsole._dispatch()` and a line to `_help()` (read commands query `facade.get_state()`; write commands mutate state then call `_refresh()`), and a test in `tests/api/test_debug_console.gd`. A presentation-only helper (camera/fog) goes in `debug_overlay.gd:_run()` instead, before delegating to the shared engine. See `docs/design/debug.md` §8.
