# Humanish

A turn-based, empire-building **4X strategy game** at roughly *Civilization IV* scale —
a tiled world, settlements with growth/production/culture, units with detailed combat,
research, policies, alliances and diplomacy, beliefs, economic organizations, Great
People, and multiple victory conditions.

Built in **Godot 3.6 / GDScript**. The repository ships a fully headless,
deterministic rules engine plus a flat-color prototype UI for playing it.

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
| `src/sim/` | Pure rules: `GameState`, `TurnEngine`, combat, settlements, research, Great People… |
| `src/world/` | World map and tiles. |
| `src/api/` | Public surface: `SimFacade`, `Commands`, `SaveLoad`, dirty-flag tracking. |
| `src/core/` | `DataDB`, `IDs`, `Fixed`, `RNG`, shared primitives. |
| `data/` | JSON tables — all game content and tuning. |
| `scenes/` | Godot scenes/scripts: menus, setup, world view, HUD, input, screens. |
| `tests/` | GUT test suites. |
| `docs/` | Game rules spec, code layout, engine plans, UI design, data reference. |
| `CLAUDE.md` | Working notes and conventions for contributors (and Claude Code). |

---

## Running the game

Open the project in the Godot 3.6 editor and run it, or launch headless from the CLI.
The main scene is `scenes/menus/start_menu.tscn` (New Game / Load Game).

```bash
godot3 scenes/menus/start_menu.tscn
```

In game:

- **F5 / F9** — quick-save / quick-load (the `quicksave.sav` slot).
- **Escape** — pause menu: Resume / Save / Load / New Game / Quit.

Saves are written to `user://saves/*.sav`. A game can also be resumed from the title
screen's **Load Game** picker.

---

## Tests

The engine is covered by **243** tests using **GUT 7.4.3**, organised by functional
area under `tests/{core,world,sim,api,scenes}/` to mirror the source layout.

```bash
# Run all tests (headless) — -ginclude_subdirs recurses the functional subdirs
godot3 --no-window -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

# Run a single test file
godot3 --no-window -s addons/gut/gut_cmdln.gd -gtest=res://tests/sim/test_combat.gd -gexit

# Run a single test by name
godot3 --no-window -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/sim/test_combat.gd \
  -gunit_test_name=test_combat_same_seed_identical_outcome -gexit
```

---

## Extending content

Most additions are data-only. See `CLAUDE.md` and `docs/game-data.md` for the full
recipes, but in brief:

- **New unit / structure / tech / improvement** — add a JSON entry under `data/`.
- **New society** — add to the `"societies"` block in `data/leaders_traits.json`; it
  appears automatically in the setup screen.
- **New rule / phase override** — register a hook:
  `facade.get_hooks().register(IDs.Phase.X, obj, "method")`.
- **New command** — add a `Commands` factory, a case in `SimFacade.apply_command()`, and
  a `_cmd_*` handler.

---

## Documentation

- `docs/game-rules.md` — the generic, implementation-level rules specification.
- `docs/code-layout.md` — how the code is structured and connects at runtime.
- `docs/engine-core-plan.md`, `docs/phase6-plan.md` — engine build plans.
- `docs/user-interface-design.md` — UI design notes.
- `docs/game-data.md` — data-table reference.

---

## License

Humanish is free software, licensed under the **GNU General Public License v3.0**.
See [`LICENSE`](LICENSE) for the full text. You may redistribute and/or modify it under
those terms; it comes with **no warranty**.
