# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workflow

Every change falls into one of four **work types**. The procedure is currently the same for all four (they are kept separate so they can diverge later):

| Work type | Purpose |
|---|---|
| **bugfix** | Correct incorrect behaviour. |
| **feature** | Add new capability. |
| **refactor** | Restructure code without changing behaviour. |
| **maintenance** | Dependencies, tooling, docs, chores. |

For each of the four, follow this sequence:

1. **Ask for any clarifications** needed before starting.
2. **Create a working branch** named `<work_type>-<relevant_name>` (e.g. `bugfix-combat-rng`, `feature-trade-routes`). Use a hyphen prefix — `dev/`-style slash prefixes are blocked.
3. **Do the work** on that branch.
4. **Check whether any documents need updating** (`docs/ref/`, `docs/user/` including the in-game encyclopedia, `docs/planning/`, `CLAUDE.md`, `CHANGELOG.md`) and **request the user's permission** before updating any that are affected.
5. **Merge the branch back to `main`.**

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

# Manual AI full-game smoke run (all-AI, runs to win condition or 10-minute timeout)
godot3 --no-window -s res://tests/manual/ai_full_game_smoke.gd
godot3 --no-window -s res://tests/manual/ai_full_game_smoke.gd -- \
  --players=4 --seed=99 --map=islands --size=standard --log=/tmp/run.log
# Logs every facade signal and DebugConsole snapshot to a timestamped file under
# user:// (default) or the path given by --log. Exit 0 = win + zero errors.
```

> Heads-up: `-gdir=res://tests -ginclude_subdirs` would recurse into **all** of `tests/`, including `tests/integration`. To keep the unit run separate from the final integration gate, run them as two phases (use `./run_tests.sh`, which encodes the ordering and is mirrored by `.github/workflows/build.yml`).

The test framework is **GUT 7.4.3** (Godot 3.x). Test suites are organised by functional area, mirroring the source layout: `tests/core/`, `tests/world/`, `tests/sim/`, `tests/api/`, `tests/scenes/`, `tests/net/` — one file per module/subsystem (e.g. `combat.gd` → `tests/sim/test_combat.gd`). New tests go in the file for the subsystem they exercise; a brand-new subsystem gets a new `test_<name>.gd` under the matching layer. `tests/integration/` holds end-to-end **playthrough** suites that drive a whole game through `SimFacade` (most interaction families in one scenario); they run as the final gate **after** the unit suites, never mixed into them.

Most suites extend the shared fixture `"res://tests/support/sim_fixture.gd"` (which itself extends GUT's `test.gd`) for the common scaffolding — `make_db()`, `make_gs(num_players, seed)`, `make_unit/make_warrior/make_settlement/make_gp`, `bare_facade(gs)`, `setup_facade(...)`, `hooks()`, `run_turns(...)`. Pure-math/data suites with no game state (e.g. `test_fixed`, `test_slider_math`) extend `"res://addons/gut/test.gd"` directly. The fixture file is **not** collected as a suite — GUT only picks up files named `test_*`. Each `test_*` method is one test case.

## Documentation

The `docs/` tree has four tiers with different editorial rules:

| Tier | Path | Rule |
|---|---|---|
| **Design** (upstream) | `docs/design/` | Authoritative intent — game rules, architecture, protocol, UI vocabulary, debug spec. **Modify only with explicit user consent.** |
| **Reference** (downstream) | `docs/ref/` | Always-current description of the actual project state (`code-layout.md`). Claude Code updates this freely whenever the code changes. |
| **Planning** (collaborative) | `docs/planning/` | Shared memory of ongoing and past planning work (`designgaps.md`, `TODO`, phase plans). Updated collaboratively by Claude Code and the user. |
| **User** (downstream) | `docs/user/` | End-user–facing documentation (`quick-start.md`, `user-reference.md`). Packaged with release builds. Claude Code updates freely; content must match the actual shipped game, not design intent. |

The canonical code-layout reference is `docs/ref/code-layout.md`. Design specs (`network-design.md`, `debug.md`, `ai-design.md`, `game-data.md`, `game-rules.md`, `user-interface-design.md`) stay in `docs/design/`. End-user docs (`quick-start.md`, `user-reference.md`) live in `docs/user/`.

Each file in `docs/design/` opens with a **YAML frontmatter block** (between `---` delimiters) containing:
- `title` / `role: design` — identity and tier marker
- `summary` — 3–5 sentence orientation for agents and humans
- `audience` — who should read it and in what context
- `key_files` — annotated list of source paths the document governs
- `sections` — ordered map of section number → one-line scope, covering every `##` heading
- `editorial_rule` — consent and extension-pattern instructions
- `provisional_sections` (game-rules.md only) — list of `⚠️ Provisional` subsections with placeholder constants

Read the frontmatter before diving into a design doc — it identifies the relevant source files and tells you which sections are still unverified placeholders.

---

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

The in-game HUD (`scenes/hud/`) stacks an **advisor menu bar** (`menu_bar.gd`, a button per `OPEN_*` screen — the discoverable alternative to the F-key hotkeys), the turn/score and research bars, the economy sliders, the **selection panel** (`selection_panel.gd`: selected unit/city info, an on-tile stack list with a Select-all that orders the whole stack, a terrain readout for an inspected empty tile, foreign subjects shown read-only), the message log, and the end-turn button. `InputRouter` splits the two intents onto the two mouse buttons so targeting is never ambiguous (every tile is clickable). **Left-click = select only** (`_handle_select_click`): a tile carrying your own subject(s) selects/cycles them — units in spawn order, then the city on the tile (so a just-founded city sharing the escort's tile is reachable, and you can always switch to another unit/city); any other tile (empty or foreign-only) deselects the current unit and shows that tile's terrain readout (`SimFacade.inspect_tile`/`tile_info_text`). **Right-click = move** (`_handle_move_click`): orders the selected units to the target tile — empty (move), enemy (attack), or friendly unit/city (stack/garrison), i.e. any legal tile via `can_stack_move`; an illegal target is ignored (selection kept), and with nothing selected it is a no-op. A single selected unit moves via the per-unit `MISSION_MOVE_TO` command; a multi-unit selection moves via `MOVE_STACK` carrying the selection's `unit_ids` (so a member can peel off a stack — empty `unit_ids`, used by the AI, moves the whole tile). After an order it auto-advances to the next idle unit. `WorldView`'s `FogLayer` keeps per-player explored memory (seen tiles stay dimly revealed; live units only render in current sight). The `CityScreen` exposes manual citizen management (a work-radius grid that locks/unlocks worked tiles, an automate-citizens toggle, specialist +/-).

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
| `PolicyEffects` | §8 civic-effects reader: `sum_int`/`has_flag` aggregate a player's active policies' `effects` (both nested dicts and bare flags); plus `largest_city_ids`/`is_religious_structure`/`civic_pressure_anger` helpers. Pure static; the single reader of per-civic `effects`, called from `TurnEngine` and `SimFacade`. |
| `Projects` | §15.7 effects-projects reader (the `PolicyEffects` analogue for `data/projects.json`): SDI / The Internet are recorded on `Player.projects` at completion; `effect_int` aggregates their `effects` (`nuke_interception`, `tech_share`), `can_build`/`grantable` enforce the tech / instance-limit / wonder gates. Spaceship stages keep the separate per-alliance stage model. Pure static. |
| `TraitEffects` | §4/B4 leader-trait effects reader (the `PolicyEffects` analogue for traits): `sum_int` over a player's traits, and `production_pct` — the trait build-speed +% toward a queued item (`double_production_structures` +100%, `unit_production_modifiers` per-unit %), summed into `TurnEngine._production_percent_mods`. Pure static. |
| `Eras` | §2.1 derived per-player era system (pure static, provisional): a player's era = highest era index among researched techs, read live via `player_era()`; `Player.era` is a cache `refresh()` updates to detect advancement. Scales growth thresholds and culture-revolt power. Reads `data/ages.json` + per-tech `era` tag. |
| `CombatApply` | Pure application of a resolved `Combat.resolve()` result to `GameState` (healths, XP, promotions, deaths, attacker advance, spillover/flank, war-fatigue, Great-General accrual). Shared by `SimFacade` and `WildAI` so both combat paths write state identically; no signals. |
| `CultureRevolt` | §4.9 cultural city flipping (pure static, provisional): a `TurnEngine` player-step phase where the strongest rival that out-cultures the owner on a city's tile (and holds a settlement in range) accumulates revolt on a `gs.rng` check until the city flips. Queues flips onto `gs.pending_flips`. |
| `Assembly` | §7.2 world-government assemblies (pure static, provisional): a voting body founded by a world wonder (Apostolic Palace → United Nations). `world_tick()` opens sessions, runs resident elections and resolutions (from `data/resolutions.json`) with weighted Yea/Nay/Abstain votes. State in `gs.assembly`; outcomes onto `gs.pending_assembly_events`. |
| `WildAI` | §9 wild-forces behaviour (pure static, provisional): `WildForces` spawns raiders, `WildAI.run()` makes them act once per `world_step` (owner `-2` has no turn slot). Marches/raids and fights via `CombatApply`; surfaces fights/razes onto `gs.pending_wild_events`. |
| `StartMenu` | Entry-point scene; loads `DataDB`, routes to `SetupScreen` or quits. |
| `SetupScreen` | Collects new-game parameters (players, society, per-player human/AI toggle, world size, map type, pace, difficulty) and calls back with a ready `SimFacade`. |
| `PlayerAI` | Three-layer deterministic computer player (handicap × brain × focus); a facade *client* (like the UI) that drives a flagged player's whole turn via `apply_command`. Pure static; lives in `src/api/`. |
| `DebugConsole` | Advanced-debugging command engine (`src/api/`); a facade *client* (like `PlayerAI`) that inspects and modifies game values. Shared by the terminal reader and the `~` overlay. Debug-build-only. |
| `DebugLog` | Pure capped ring buffer of debug log lines (`src/core/`) with a stdout mirror; fed by mirrored `SimFacade` signals. Debug-build-only. |
| `NetProtocol` | Pure remote-multiplayer wire format (`src/net/`): message-type constants + `encode`/`decode` of `{v, t, d}` JSON frames. No sockets. |
| `NetConfig` | Pure parser (`src/net/`) for the headless server's command-line switches (`--server`/`--port`/`--players`/`--ai`/`--load`/…) into a config dict. |
| `net_server.gd` | Authoritative WebSocket server (`scenes/net/`, a facade *client*): the round-robin turn loop that plays AI slots, pushes state to the active remote human, and runs the end-of-turn pipeline on `submit`. |
| `net_client.gd` | Remote-multiplayer client (`scenes/net/`, a `Node` facade *client*): WebSocket transport + in-game glue; re-syncs the facade on each `state` and ships a `submit` at end of turn. |

### Computer players (`PlayerAI`)

`Player.is_ai` marks a player as computer-controlled (serialized; default `false`; set from each player config's `is_ai` in `SimFacade.setup()`, toggled per-player by the `SetupScreen` row checkboxes). `PlayerAI` (`src/api/player_ai.gd`) is **not** part of `sim/` — it is a *client* of `SimFacade`, exactly like the human UI: it only mutates state through `apply_command`, and it draws every random choice from the shared `gs.rng` (never its own generator), so an AI turn is reproducible and is captured by save/load. `PlayerAI.take_turn(facade, player_id)` runs the whole turn then ends it. Economy/research/civics/religion/assembly stay simple (cheapest researchable tech, latest-unlocked policy per civic category, solvency-aware sliders). Production and units run a **competent deterministic brain** (Phase B, see `docs/planning/advanced-ai-planning.md`): `manage_production` queues a **role-ranked** list (`_sorted_options`: needed garrison defender → economy structure → wanted settler/worker → cheapest fallback), replanned only when empty; `manage_units` is a four-pass playbook with **no RNG** — settlers walk to the best-scoring legal city site (`_best_city_site`) and found; each city's `ai_min_defenders` slots fill nearest-first from idle military (raised by one when a hostile stack is within `ai_threat_radius`); free military attacks an adjacent target it out-powers by `ai_attack_margin` (else advances on the nearest non-adjacent threat or fortifies); workers improve/relocate, recon explores. AI tuning constants (`ai_city_target`, `ai_min_defenders`, `ai_threat_radius`, `ai_attack_margin`, `ai_settle_search_radius`, `ai_site_*`) live in `data/constants.json`; `ai_bonus` per difficulty (Phase A) scales AI yields. Leader personality (Phase C) is a soft bias layered on top: `_focus_profile(player, db)` sums each trait's `ai_focus` block across `expand`/`military`/`economy`/`science` axes (integers, all-zero for a traitless leader so every site falls back to the Phase-B baseline); five decision sites read it — production order (`_sorted_options` focus term), the finance/research slider tilt (`manage_economy`), city-count target (`_city_target`), garrison floor (`_defender_target`), and attack margin (`_attack_margin`). Focus always adds above the Phase-B floor — never gates any behaviour, so a peaceful leader still defends and expands. Focus scaling constants (`ai_focus_city_per_expand`, `ai_focus_defenders_divisor`, `ai_focus_margin_per_military`, `ai_focus_finance_per_economy`, `ai_focus_finance_cap`) also live in `data/constants.json`. In the scene layer, `HotseatManager` watches `player_turn_started` and `call_deferred`s `PlayerAI.take_turn` for `is_ai` players, chaining through consecutive AI players until a human's turn opens the pass-device screen. Like any new `class_name`, `PlayerAI` is registered in `project.godot`'s `_global_script_classes`. Full reference: `docs/design/ai-design.md` (the settled three-layer design); `docs/planning/advanced-ai-planning.md` records the as-built development history.

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

### Recurring debugging gotchas

Hard-won failure modes that have bitten more than once. Each one *passes CI or looks fine* until you hit the exact condition, so they are worth recognising on sight.

- **GUT reports a suite green even when a script fails to load or a test errors mid-method.** A parse error makes `load("res://…")` return a non-null but broken `GDScript`; calling `.new()` on it (or any nonexistent method, e.g. `f.get_player()` when only `f.get_state().get_player()` exists) raises an engine-level `SCRIPT ERROR` that GUT *swallows* — it does not fail the assert, and it **aborts the rest of that test method**, so later asserts never run while the file still shows as passed (often "N/N passed" with far fewer asserts than expected). Symptom in the live game: a scene node whose script failed to parse renders nothing (this is how a blank selection panel / missing unit-city actions happened). Defences: (1) for any scene/UI script with logic, add a canary test asserting `load(path).can_instance()` is `true` — `can_instance()` reports the compile state *without throwing*, unlike `new()`; (2) run a newly written test **in isolation** (`-gunit_test_name=…`) and confirm the asserted count is what you expect — a method that errors out shows `0 of 0` or fewer asserts than written; (3) grep the run output for `SCRIPT ERROR` even when the summary is green.

- **JSON save/load returns int IDs as float keys and string dict-keys.** `JSON.parse` makes every number a float and every Dictionary key a string. GDScript treats `2` (int), `2.0` (float), and `"2"` (string) as *three distinct* Dictionary keys / `in`-membership values, so any state keyed or membership-tested by an int ID that is deserialized **without `int()` coercion** silently stops matching after a load — `dict.has(2)` misses a loaded `"2"`/`2.0`, a phantom duplicate entry accumulates, and the resumed game's `state_hash` diverges from the original. This is a **save/load determinism break** and the `tests/integration` playthrough gate (`test_playthrough_save_load_determinism_midgame`) is what catches it. It hides until the field is actually *used* in an int lookup, because `serialize()` emits identical JSON regardless of in-memory key type (Godot prints `2.0` as `2`), so the load *roundtrip* hash still matches. Rule: in every `deserialize`, coerce int-ID arrays (`int(v)` per element) and int-keyed dicts (`int(k)`) back to int — same discipline as the RNG-state-as-strings invariant. When debugging a determinism failure, **diff `f.save()` against the resumed `f2.save()` field-by-field** to pinpoint the diverging key rather than guessing.

### Adding new content

- **New unit/structure/tech/etc.**: add a JSON entry to the relevant file in `data/`. No code change required unless the entry introduces a mechanic not yet modelled.
- **New society**: add an entry to the `"societies"` block in `data/leaders_traits.json` with `id`, `name`, `leader_id`, `leader_name`, `description`, `traits` (array of trait IDs), and `starting_gold`. It will appear automatically in the `SetupScreen` society picker.
- **New map type / script**: add an entry to `data/map_types.json` with `id`, `name`, `category`, `description`, a land-mask `shape`, a `climate`, and the relevant tunables (`land_fraction`, `mountain_chance`/`hills_chance`, `forest_chance`/`jungle_chance`, plus shape params like `num_continents`, `main_size`, `plate_count`, `start_bounds`, `new_world`). It appears automatically in the `SetupScreen` map-type picker, and `MapGen` reads it directly. Reusing an existing `shape`+`climate` pair needs **no code**; a brand-new `shape` needs a builder in `MapGen._build_mask`/`_shape_bias`, and a brand-new `climate` a band in `MapGen._flat_terrain`.
- **New trait**: add an entry to the `"traits"` block in `data/leaders_traits.json`, **including an `ai_focus` block** over the four strategic axes (`expand`/`military`/`economy`/`science`, integers; `test_data_db.gd` enforces its presence) so `PlayerAI` biases that leader's play (§C, `advanced-ai-planning.md`). Wire its effects in the relevant sim module (e.g. `TurnEngine`, `Combat`, `GreatPeople`).
- **New Great Person type (§14)**: add a `unit` entry to `data/units.json` with `"classification": "great_person"`, a `generated_by` (the specialist type that produces it, or `combat_xp` for the Great General), and an `actions` array. `GreatPeople` reads these directly — `gp_unit_for_type()` maps the specialist to the unit and `perform_action()` validates against the `actions` list, so no new command is needed. A brand-new action *verb* needs a handler added to `GreatPeople.perform_action()`; `build_<structure_id>` verbs are already handled generically. Magnitudes (gold, hammers, culture, GP/Golden-Age costs) live in `data/constants.json`.
- **New civic / civic effect (§8)**: add a policy entry to `data/policies.json` (one of the five categories). The mechanical fields (`upkeep_modifier`, `slider_increment`, `slider_min_research`, `anger_modifier`, `transition_turns`) are read directly by `SimFacade`/`TurnEngine`. Headline gameplay bonuses go in the per-civic `effects` dictionary (or, for a lone flag, a bare top-level key) and are read through `PolicyEffects.sum_int`/`has_flag`; a *new* effect key needs wiring into the relevant sim site (e.g. `_update_contentment`, `_settlement_growth`, `_policy_production_delta`, `_update_treasury`, `_cmd_rush_production`). See `docs/planning/designgaps.md` §2 for the effects already wired and the few still blocked on unbuilt subsystems.
- **New assembly resolution (§7.2)**: add an entry to `data/resolutions.json` with `id`, `name`, `kind` (`election`/`resolution`), `body` (`any`/`religious`/`secular`), `effect`, optional `pass_share`, and `text` (with `{proposer}`/`{candidate}`/`{target}`/`{belief}` tokens). `Assembly` picks eligible proposals automatically; a *new* `effect` verb needs a handler in `Assembly.apply_effect()`. Provisional — see `docs/design/game-data.md` §18.
- **New random event (§9)**: add one self-contained record to `data/events.json` carrying its selection metadata inline — `active` (per-game inclusion %), `weight`, a `prereq` predicate dict, `obsolete` techs, and either begin `effects[]` or `choices[]` (each with `effects[]`); a positive `duration` + `expire_effects[]` makes it timed. There is **no** separate trigger table (it was removed). `Events` reads it directly — no code unless you introduce a *new prereq predicate* (add it to `Events.prereq_holds` and `DataDB._validate_event_prereq`) or a *new effect verb* (add a `case` to `Events._apply_effect` and the validator's `known` list in `DataDB._validate_event_effects`). For random magnitudes use `range:[min,max]`; for a probabilistic branch use `{verb:"chance",percent,then:[…]}` — both are rolled once at fire time so applying a resolved choice stays deterministic. Selection (grace `event_grace_turns`, per-era `event_era_chance`, per-game roster `Events.roll_active_events`, weighted pick, mandatory human choice) is fixed framework. The shipped catalogue is a vertical slice — the full ~174-event/18-quest roadmap and the subsystems each needs are in `docs/planning/event-subsystem-planning.md`.
- **New rule / phase override**: register via `facade.get_hooks().register(IDs.Phase.X, obj, "method")`. The method receives `(game_state, args: Dictionary)` and returns `bool`.
- **New command**: add a factory to `Commands`, add a case to `SimFacade.apply_command()`, implement a `_cmd_*` handler.
- **New advisor/info screen (§3.1 UI vocabulary)**: add a `ControlType` value to `IDs`, list it in the `screen_requested` emit group in `SimFacade._cmd_do_control`, write `scenes/screens/<name>_screen.gd` extending the read-only `info_screen.gd` scaffold (set `_title`, override `_populate(vbox)` using `_add_line`), register it in `scenes/main.gd:_init_extra_screens()` keyed by the control, and add a button for it to the HUD advisor bar (`scenes/hud/menu_bar.gd` `ENTRIES`) so it is reachable without a hotkey. (Interactive screens that need their own `.tscn` node — like `CityScreen`/`DiplomacyScreen` — are instead listed in the `main.gd` screens-init loop and routed in the `screen_requested` `match`.) A screen that issues an action routes it back through `apply_command` (see `options_screen.gd`). New `UnitCmd`/`UnitMission` verbs follow the §3.2/§3.3 pattern: enum value + `CommandType` + `Commands` factory + a case in `_cmd_unit_command`/`_cmd_mission` (stance flags live on `Unit` and are serialized). See `docs/planning/designgaps.md` §3 for what is built vs. deferred.
- **New debug console command**: add a `case` to `DebugConsole._dispatch()` and a line to `_help()` (read commands query `facade.get_state()`; write commands mutate state then call `_refresh()`), and a test in `tests/api/test_debug_console.gd`. A presentation-only helper (camera/fog) goes in `debug_overlay.gd:_run()` instead, before delegating to the shared engine. See `docs/design/debug.md` §8.

## Releasing

To cut a release:

1. **Bump the version** in `project.godot` (`config/version`). The scheme is `major.minor.bugfix`:
   - **bugfix** (`0.4.x`) for bug fixes and small docs changes.
   - **minor** (`0.x.0`) for new features or substantial rewrites.
   - **major** (`1.0.0`) for breaking API or save-format changes.
2. **Update `CHANGELOG.md`**: add a `## [VERSION] - YYYY-MM-DD` entry above the
   previous one. Group changes under `### Added`, `### Changed`, `### Fixed`.
   Read the `git log` since the last tag (`git log --oneline --no-merges <last-tag>..HEAD`)
   to find candidate entries; write human-readable bullet points.
3. **Commit** the version and changelog bump:
   ```
   git add project.godot CHANGELOG.md
   git commit -m "chore: bump to v<version>"
   ```
4. **Tag** the commit:
   ```
   git tag v<version>
   ```
   (Use `git tag -a v<version> -m "v<version>"` for an annotated tag.)
5. **Push** the commit and tag:
   ```
   git push origin main --follow-tags
   ```
   Or, if you tagged separately:
   ```
   git push origin main && git push origin v<version>
   ```
