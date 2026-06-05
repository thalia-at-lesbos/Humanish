# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run all tests (headless) — -ginclude_subdirs recurses into tests/{core,world,sim,api,scenes}
godot3 --no-window -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

# Run a single test file
godot3 --no-window -s addons/gut/gut_cmdln.gd -gtest=res://tests/sim/test_combat.gd -gexit

# Run a single test by name within a file
godot3 --no-window -s addons/gut/gut_cmdln.gd -gtest=res://tests/sim/test_combat.gd -gunit_test_name=test_combat_same_seed_identical_outcome -gexit
```

The test framework is **GUT 7.4.3** (Godot 3.x). Test suites are organised by functional area, mirroring the source layout: `tests/core/`, `tests/world/`, `tests/sim/`, `tests/api/`, `tests/scenes/` — one file per module/subsystem (e.g. `combat.gd` → `tests/sim/test_combat.gd`). New tests go in the file for the subsystem they exercise; a brand-new subsystem gets a new `test_<name>.gd` under the matching layer.

Most suites extend the shared fixture `"res://tests/support/sim_fixture.gd"` (which itself extends GUT's `test.gd`) for the common scaffolding — `make_db()`, `make_gs(num_players, seed)`, `make_unit/make_warrior/make_settlement/make_gp`, `bare_facade(gs)`, `setup_facade(...)`, `hooks()`, `run_turns(...)`. Pure-math/data suites with no game state (e.g. `test_fixed`, `test_slider_math`) extend `"res://addons/gut/test.gd"` directly. The fixture file is **not** collected as a suite — GUT only picks up files named `test_*`. Each `test_*` method is one test case.

## Architecture

The design enforces a hard boundary: **`sim` (pure rules) ↔ `api` facade ↔ `scenes` (presentation)**. Nothing in `src/sim/` or `src/world/` may reference `Node`, scenes, or input. This keeps the engine headless and testable.

### Scene entry-point flow

```
scenes/menus/start_menu.tscn   ← project.godot main_scene
        │  "New Game" pressed
        ▼
scenes/setup/setup_screen.gd   (programmatic Control; collects players, world size, pace, difficulty, society)
        │  on_setup_complete callback(facade, db)
        ▼
scenes/main.tscn               (wires WorldView, HUD, InputRouter, HotseatManager)
```

`StartMenu` loads `DataDB`, shows title + buttons, and instantiates `SetupScreen` on "New Game". When setup completes it calls `main.init_with_facade(facade, db)` before adding `main.tscn` to the scene tree, then frees itself. `main.gd` falls back to a default 2-player tiny game when `init_with_facade` is not called (e.g. running `main.tscn` directly).

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
| `DataDB` | Loads/validates all JSON tables; provides typed getters including `get_societies()`. |
| `Fixed` | All integer math helpers (scale, proportion, movement conversion). |
| `RNG` | Seeded PCG32 wrapper; `get_state()`/`restore_state()` for save-resume. |
| `Hooks` | FuncRef registry keyed on `IDs.Phase`; lets rules be overridden per-phase. |
| `SaveLoad` | `JSON.print(gs.serialize())` / `GameState.deserialize()`; computes `state_hash()`. |
| `Commands` | Static factories for all command Dictionaries; no logic, pure construction. |
| `PolicyEffects` | §8 civic-effects reader: `sum_int`/`has_flag` aggregate a player's active policies' `effects` (both nested dicts and bare flags); plus `largest_city_ids`/`is_religious_structure` helpers. Pure static; the single reader of per-civic `effects`, called from `TurnEngine` and `SimFacade`. |
| `StartMenu` | Entry-point scene; loads `DataDB`, routes to `SetupScreen` or quits. |
| `SetupScreen` | Collects new-game parameters (players, society, per-player human/AI toggle, world size, pace, difficulty) and calls back with a ready `SimFacade`. |
| `PlayerAI` | Simple deterministic computer player; a facade *client* (like the UI) that drives a flagged player's whole turn via `apply_command`. Pure static; lives in `src/api/`. |

### Computer players (`PlayerAI`)

`Player.is_ai` marks a player as computer-controlled (serialized; default `false`; set from each player config's `is_ai` in `SimFacade.setup()`, toggled per-player by the `SetupScreen` row checkboxes). `PlayerAI` (`src/api/player_ai.gd`) is **not** part of `sim/` — it is a *client* of `SimFacade`, exactly like the human UI: it only mutates state through `apply_command`, and it draws every random choice from the shared `gs.rng` (never its own generator), so an AI turn is reproducible and is captured by save/load. `PlayerAI.take_turn(facade, player_id)` runs the whole turn then ends it; the decision logic is deliberately simple — cheapest researchable tech, latest-unlocked policy per civic category, each city's queue refilled with every buildable unit/structure cheapest-first (replanned only when empty), and ~50% of units garrisoning their nearest city while the rest wander and pick random actions. In the scene layer, `HotseatManager` watches `player_turn_started` and `call_deferred`s `PlayerAI.take_turn` for `is_ai` players, chaining through consecutive AI players until a human's turn opens the pass-device screen. Like any new `class_name`, `PlayerAI` is registered in `project.godot`'s `_global_script_classes`.

### Godot 3 GDScript constraints to remember

- `class_name Foo` creates a global name, but **do not use `Foo.new()` inside `foo.gd`** — it triggers a cyclic-reference parse error. Use `load("res://path/foo.gd").new()` in static factory methods instead.
- Test helper functions must **omit return type annotations** (`-> MyClass`) to avoid parse-order failures with class_name globals.
- GUT 7 has no `assert_gte`/`assert_lte` — use `assert_true(a >= b, "msg")`.
- `seed` is a GDScript built-in function name; do not use it as a parameter name.
- When swapping scenes programmatically, call `init_with_facade(facade, db)` on the new scene **before** `add_child()` so `_ready()` sees the pre-built state.

### Adding new content

- **New unit/structure/tech/etc.**: add a JSON entry to the relevant file in `data/`. No code change required unless the entry introduces a mechanic not yet modelled.
- **New society**: add an entry to the `"societies"` block in `data/leaders_traits.json` with `id`, `name`, `leader_id`, `leader_name`, `description`, `traits` (array of trait IDs), and `starting_gold`. It will appear automatically in the `SetupScreen` society picker.
- **New trait**: add an entry to the `"traits"` block in `data/leaders_traits.json`. Wire its effects in the relevant sim module (e.g. `TurnEngine`, `Combat`, `GreatPeople`).
- **New Great Person type (§14)**: add a `unit` entry to `data/units.json` with `"classification": "great_person"`, a `generated_by` (the specialist type that produces it, or `combat_xp` for the Great General), and an `actions` array. `GreatPeople` reads these directly — `gp_unit_for_type()` maps the specialist to the unit and `perform_action()` validates against the `actions` list, so no new command is needed. A brand-new action *verb* needs a handler added to `GreatPeople.perform_action()`; `build_<structure_id>` verbs are already handled generically. Magnitudes (gold, hammers, culture, GP/Golden-Age costs) live in `data/constants.json`.
- **New civic / civic effect (§8)**: add a policy entry to `data/policies.json` (one of the five categories). The mechanical fields (`upkeep_modifier`, `slider_increment`, `slider_min_research`, `anger_modifier`, `transition_turns`) are read directly by `SimFacade`/`TurnEngine`. Headline gameplay bonuses go in the per-civic `effects` dictionary (or, for a lone flag, a bare top-level key) and are read through `PolicyEffects.sum_int`/`has_flag`; a *new* effect key needs wiring into the relevant sim site (e.g. `_update_contentment`, `_settlement_growth`, `_policy_production_delta`, `_update_treasury`, `_cmd_rush_production`). See `docs/planning/designgaps.md` §2 for the effects already wired and the few still blocked on unbuilt subsystems.
- **New rule / phase override**: register via `facade.get_hooks().register(IDs.Phase.X, obj, "method")`. The method receives `(game_state, args: Dictionary)` and returns `bool`.
- **New command**: add a factory to `Commands`, add a case to `SimFacade.apply_command()`, implement a `_cmd_*` handler.
