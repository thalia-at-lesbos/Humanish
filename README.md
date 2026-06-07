# Humanish

A turn-based, empire-building **4X strategy game** at roughly *Civilization IV* scale —
a tiled world, settlements with growth/production/culture, units with detailed combat,
research, policies, alliances and diplomacy, beliefs, economic organizations, Great
People, and multiple victory conditions.

Built in **Godot 3.6 / GDScript** (version **0.4.2**). The repository ships a fully
headless, deterministic rules engine plus a flat-color prototype UI for playing it.

---

## Design

The codebase enforces a hard boundary:

```
sim (pure rules)  ↔  api facade  ↔  scenes (presentation)
```

Nothing in `src/sim/` or `src/world/` references `Node`, scenes, or input, which keeps
the engine headless and testable. All presentation goes through `SimFacade`, and the
only way to mutate game state is to submit a command dictionary via
`facade.apply_command(cmd)`.

### Engine invariants

- **Integer math only** — no floats in the simulation. A `Fixed` type (100-unit scale)
  handles movement precision; percentages are integer 0–100.
- **One shared RNG** — every stochastic call goes through `gs.rng` in pipeline order, so
  a given seed always reproduces the same game. RNG state is serialized as strings to
  avoid JSON double-precision truncation.
- **Data-driven** — all numeric constants and content live in `data/*.json`, loaded by
  `DataDB`. Adding most new units/structures/techs/societies needs no code change.
- **Pipeline order is a rule** — `TurnEngine` runs turn phases in a strict, documented
  order, each overridable via the `Hooks` registry.

Determinism is the central guarantee: `facade.state_hash()` is the gate, and save/load
round-trips reproduce an identical hash.

---

## Repository layout

| Path | Contents |
|---|---|
| `src/sim/` | Pure rules: `GameState`, `TurnEngine`, combat, settlements, research, Great People, alliances, wild forces… |
| `src/world/` | World map, tile output, regions, cultural influence. |
| `src/api/` | Public surface: `SimFacade`, `Commands`, `SaveLoad`, dirty-flag tracking, `PlayerAI`, `DebugConsole`. |
| `src/core/` | `DataDB`, `IDs`, `Fixed`, `RNG`, `DebugLog`, shared primitives. |
| `src/net/` | Pure remote-multiplayer wire format (`NetProtocol`) and server CLI parsing (`NetConfig`). |
| `data/` | 24 JSON tables — all game content and tuning. |
| `scenes/` | Godot scenes/scripts: menus, setup, world view, HUD, input router, hotseat manager, advisor screens, remote multiplayer runtime, debug overlay/console. |
| `tests/` | GUT 7.4.3 test suites (core/world/sim/api/scenes/net + integration + manual). |
| `docs/design/` | Upstream design specs — game rules, network protocol, UI design, debug spec, data reference. |
| `docs/ref/` | Downstream reference — always-current code layout doc. |
| `docs/planning/` | Collaborative planning memory (gaps, TODO, phase plans). |
| `docs/user/` | End-user documentation (quick-start, user-reference). |
| `CLAUDE.md` | Working notes and conventions for contributors (and Claude Code). |

---

## Running the game

Open the project in the Godot 3.6 editor and run it, or launch from the CLI. The main
scene is `scenes/menus/start_menu.tscn` (New Game / Load Game / Multiplayer).

```bash
godot3 scenes/menus/start_menu.tscn
```

### Headless multiplayer server

```bash
./run_server.sh --save=game.sav --players=3 --ai=1 --port=9080
```

Runs an authoritative WebSocket server (windowless). Connect via the **Multiplayer**
button on the title screen.

### In-game controls

- **Left-click** — select subject (unit/city); empty/foreign tiles show terrain readout.
- **Right-click** — move/attack/garrison selected subjects.
- **F5 / F9** — quick-save / quick-load.
- **Escape** — pause menu: Resume / Save / Load / New Game / Quit.
- **`~`** (debug builds) — debug overlay with live info pane and console.

Saves are written to `user://saves/*.sav`. Load from the title screen's **Load Game**
picker or the in-game pause / save-load screen.

---

## Tests

The engine is covered by **643** tests using **GUT 7.4.3**, organised by functional
area under `tests/{core,world,sim,api,scenes,net}/` to mirror the source layout, plus
`tests/integration/` (end-to-end playthrough gate) and `tests/manual/`.

```bash
# Run everything in order (unit suites then integration gate)
./run_tests.sh

# Unit suites only
godot3 --no-window -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/core,res://tests/world,res://tests/sim,res://tests/api,res://tests/scenes,res://tests/net \
  -ginclude_subdirs -gexit

# Integration playthrough only
godot3 --no-window -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration -ginclude_subdirs -gexit

# Run a single test file
godot3 --no-window -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/sim/test_combat.gd -gexit

# Run a single test by name
godot3 --no-window -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/sim/test_combat.gd \
  -gunit_test_name=test_combat_same_seed_identical_outcome -gexit
```

> Heads-up: `-gdir=res://tests -ginclude_subdirs` would recurse into **all** of
> `tests/`, including `tests/integration`. Use `./run_tests.sh` for the correct
> two-phase ordering.

---

## Remote multiplayer

The game supports internet play with a simple **authoritative server, round-robin**
model. Transport is Godot 3's built-in **WebSocket** (TCP, one port).

- The **headless server** (`./run_server.sh`) holds the one `SimFacade`, plays AI
  slots, and relays turns. It autosaves every turn.
- **Clients** connect via the **Multiplayer** button on the start menu, receive a
  full state snapshot, play their turn locally, then submit their moves.
- An **in-game host** option (Multiplayer Server) runs the server in-process with a
  status panel and Stop button.

---

## Extending content

Most additions are data-only. See `CLAUDE.md` and `docs/design/` for the full recipes:

- **New unit / structure / tech / improvement** — add a JSON entry under `data/`.
- **New society** — add to `data/leaders_traits.json`; appears in the setup screen.
- **New map type / script** — add to `data/map_types.json`; needs code only for a
  novel `shape` or `climate`.
- **New civic / civic effect** — add to `data/policies.json`; wire new effect keys in
  `TurnEngine` / `SimFacade` via `PolicyEffects`.
- **New debug console command** — add a case to `DebugConsole._dispatch()` and a test
  in `tests/api/test_debug_console.gd`.
- **New advisor/info screen** — add a `ControlType` to `IDs`, write a screen extending
  `info_screen.gd`, register in `main.gd`, add a button to the HUD menu bar.
- **New rule / phase override** — register a hook:
  `facade.get_hooks().register(IDs.Phase.X, obj, "method")`.
- **New command** — add a `Commands` factory, a case in `SimFacade.apply_command()`,
  and a `_cmd_*` handler.

---

## Documentation

| Path | Contents |
|---|---|
| `docs/design/game-rules.md` | Implementation-level rules specification. |
| `docs/design/network-design.md` | Remote multiplayer protocol, sequence diagram, launch flags. |
| `docs/design/user-interface-design.md` | UI design notes and vocabulary. |
| `docs/design/game-data.md` | Data-table reference. |
| `docs/design/debug.md` | Debug-build-only subsystem spec. |
| `docs/ref/code-layout.md` | How the code is structured and connects at runtime. |
| `docs/user/quick-start.md` | End-user quick-start guide. |
| `docs/user/user-reference.md` | End-user reference. |
| `CLAUDE.md` | Contributor conventions, test commands, adding new content. |

---

## License

Humanish is free software, licensed under the **GNU General Public License v3.0**.
See [`LICENSE`](LICENSE) for the full text. You may redistribute and/or modify it under
those terms; it comes with **no warranty**.
