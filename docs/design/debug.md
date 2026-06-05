# Advanced Debugging

Developer-facing debugging tools for Humanish: extra event logging, a runtime
command console for inspecting and modifying game values, and an in-game debug
menu. **Everything here is gated to interactive debug builds** — release exports
and the headless test runner never enable it, so it cannot leak into shipped
play or interfere with CI.

> Scope reminder: like `PlayerAI`, the debug tools are *clients* of `SimFacade`,
> not part of the engine. Nothing in `src/sim/` or `src/world/` references them,
> and the hard sim ↔ api ↔ scenes wall (see `code-layout.md`) is preserved. The
> console mutates state through the facade / `GameState`, exactly as the UI does.

---

## 1. When it is active

The subsystem is "active" only when **all** of these hold (checked in
`scenes/main.gd:_debug_active()` and `terminal_console.gd:_is_interactive_debug()`):

1. `OS.is_debug_build()` is `true` (editor run or a debug export), **and**
2. the process was **not** launched headless / under GUT — i.e. the command line
   contains neither `--no-window` nor `addons/gut/gut_cmdln.gd`.

| Context | Logging | '~' overlay | Terminal console |
|---|---|---|---|
| Editor / debug export (windowed) | on | on | on |
| `--no-window` headless run | off | inert | off |
| GUT test run | off | inert | off |
| Release export | off | inert | off |

In the inert states the nodes still exist in the tree but do nothing: the log
buffer drops appends (`DebugLog.enabled = false`), the overlay's `~` handler
early-returns on `OS.is_debug_build()`, and the terminal reader thread is never
started.

---

## 2. Components

```
src/core/debug_log.gd            DebugLog   — pure, capped ring buffer of log lines (+ stdout mirror)
src/api/debug_console.gd         DebugConsole — shared command engine; a SimFacade client
scenes/debug/terminal_console.gd (Node)     — stdin reader thread → DebugConsole on the main thread
scenes/debug/debug_overlay.gd    (Control)  — the '~' in-game menu: live info pane + embedded console
```

Wiring lives in `scenes/main.gd:_wire_debug()`. It builds **one** `DebugLog` and
**one** `DebugConsole`, hands both to the overlay and the terminal node (so they
share state), and connects the facade's signals into the log.

```
                 ┌───────────────┐
   facade signals│   DebugLog    │  ←─ stdout mirror ("[DBG] …")
   ─────────────▶│ (ring buffer) │
                 └───────┬───────┘
                         │ shared
         ┌───────────────┴────────────────┐
         ▼                                ▼
 ┌───────────────┐                ┌────────────────────┐
 │ DebugConsole  │◀── same engine─│  DebugConsole       │
 │ (terminal)    │                │  (overlay)          │
 └──────┬────────┘                └─────────┬───────────┘
        │ stdin (worker thread)             │ LineEdit ('~' menu)
        ▼                                   ▼
   launching terminal                  on-screen panel
```

---

## 3. Extra logging

When active, `main.gd` subscribes to every meaningful `SimFacade` signal and
mirrors it into the `DebugLog`:

| Signal | Logged as |
|---|---|
| `turn_advanced` | `[turn] turn advanced -> N` |
| `player_turn_started` | `[turn] player turn started: #id name` |
| `combat_resolved` | `[combat] atk_hp=… def_hp=… atk_survived=…` |
| `unit_created` | `[unit] unit created #id` |
| `settlement_founded` | `[city] settlement founded #id` |
| `technology_completed` | `[research] player #id completed tech` |
| `event_emitted` | `[event] <type>` |
| `game_won` | `[game] game won by alliance N` |

Each entry carries `{turn, category, text}`. The buffer is capped
(`DebugLog.MAX_LINES = 500`, oldest evicted first). Every appended line is also
printed to stdout as `[DBG] T<turn> [category] text`, so the **launching
terminal shows the same feed** as the in-game log pane.

`DebugConsole` writes its own `console` category entries (the command line and
its output), so the log doubles as a console history.

---

## 4. The console command engine (`DebugConsole`)

A single `execute(line: String) -> String` parses one whitespace-separated
command and returns its result text (also echoed into the log). The **same
engine** backs both the terminal and the overlay, so a command behaves
identically wherever you type it.

Read/write commands operate on `facade.get_state()`. Write commands deliberately
mutate `GameState` **directly** (that is the point of a debug console) and then
call `facade.get_dirty().mark_all()` so the UI repaints. War/peace and `endturn`
route through `facade.apply_command()` so they exercise the real pipeline.

### Command reference

| Command | Effect |
|---|---|
| `help` (`?`) | List all commands |
| `state` (`status`) | Turn / current player / object-count summary |
| `players` | List players (id, name, gold, tech count, alliance, AI flag) |
| `cities` | List settlements (id, name, owner, pop, position) |
| `units` | List units (id, type, owner, hp, position) |
| `log [n]` | Show the last `n` log lines (default 20) |
| `clearlog` | Empty the log buffer |
| `gold <pid> <amt>` | **Set** a player's treasury |
| `addgold <pid> <amt>` | **Add** to a player's treasury (use a negative amount to subtract) |
| `tech <pid> <tech_id>` | Grant a technology (validated against `DataDB`) |
| `pop <sid> <n>` | Set a settlement's population (floored at 1) |
| `heal <uid \| all>` | Restore unit health to 100 (`all` = current player's units) |
| `kill <uid>` | Remove a unit |
| `war <pid> <alliance_id>` | Declare war on an alliance (via the facade) |
| `peace <pid> <alliance_id>` | Make peace with an alliance (via the facade) |
| `setturn <n>` | Set the turn counter |
| `win <alliance_id>` | Force a winning alliance |
| `seed` | Print the RNG seed/state |
| `hash` | Print the determinism `state_hash()` |
| `endturn` | End the current player's turn |

**GUI-only view helpers** (added by the overlay, since they touch presentation,
not game state — see `debug_overlay.gd:_run()`):

| Command | Effect |
|---|---|
| `reveal` | Lift the fog of war over the whole map (`FogLayer.reveal_all()`) |
| `fog` | Restore normal fog for the current player |

> Determinism note: directly editing values (e.g. `gold`, `pop`) bypasses the
> command pipeline, so it is **not** captured by replay and will diverge a
> save's `state_hash` from an untouched run. That is expected for a debug tool —
> use it for inspection and experimentation, not for producing canonical saves.

---

## 5. The terminal console (`scenes/debug/terminal_console.gd`)

In a windowed debug build, `start_console()` spawns a worker `Thread` that blocks
on `OS.read_string_from_stdin()`. Because `GameState` must only be touched on the
main thread, the reader never executes anything itself — it `call_deferred`s each
typed line to `_run_line()`, which runs `DebugConsole.execute()` on the main
thread and prints the result.

Type commands directly into the terminal you launched the game from:

```
$ godot3 path/to/project        # or run from the editor
[DBG] terminal console ready — type 'help' (commands run on the game thread)
state
turn=1/500  current=1 (Player 1)  players=2  cities=0  units=4  winner=-1
addgold 1 1000
Player 1 treasury = 1100
```

**Known limitation (documented, not a bug):** a thread parked in
`read_string_from_stdin()` only unblocks on the next line of input. On quit,
`_exit_tree()` flips the running flag and joins the thread, so you may need to
press **Enter** once in the terminal for the process to finish exiting. This only
affects the interactive debug build; headless/test runs never start the thread.

---

## 6. The in-game debug menu (`scenes/debug/debug_overlay.gd`)

Press **`~`** (the `~`/`` ` `` key — `KEY_QUOTELEFT`, scancode 96, Quake-console
style) to toggle the overlay. It lives on the `Screens` `CanvasLayer` above the
other full-screen overlays and is built programmatically like the other screens.

The overlay grabs the `~` key in `_input()` (before GUI/`_unhandled_input`), so
it always toggles regardless of focus and the key never lands in the console's
text field. **Escape** also closes it while open (consumed there so it doesn't
fall through to the pause menu). While open it captures input (full-rect
`Control`), so clicks and keys feed the console rather than the map.

Layout:

* **Info pane** (top) — refreshed every frame while open: turn, current player &
  gold, player/city/unit counts, interface mode, winner, FPS.
* **Output pane** (middle) — the console transcript plus a live mirror of new
  `DebugLog` entries (auto-scrolls).
* **Input line** (bottom) — type a command and press Enter; the result is
  appended to the output pane. It runs the same `DebugConsole.execute()` as the
  terminal, plus the `reveal`/`fog` view helpers.

---

## 7. Tests

`tests/api/test_debug_console.gd` covers the pure, headless-testable core:

* **`DebugLog`** — append/format, the `enabled` gate, the `MAX_LINES` cap and
  oldest-first eviction, the `appended` signal, and `clear()`.
* **`DebugConsole`** — `help`/`state`/unknown-command/blank-line handling; every
  value-modification command (`gold`, `addgold`, `tech` incl. validation, `pop`
  floor, `heal`/`heal all`, `kill`, `setturn`, `win`); `war`/`peace` routed
  through the facade; `hash` matching `facade.state_hash()`; and the
  console↔log integration (command echo + the `log` command).

The Node-based surfaces (`debug_overlay`, `terminal_console`) are thin
presentation/threading wrappers around this tested core; the whole-scene smoke
test `tests/scenes/test_main_scene.gd` exercises that `main.tscn` still boots and
wires its overlays with the debug nodes present.

Run just the debug suite:

```bash
godot3 --no-window -s addons/gut/gut_cmdln.gd \
    -gtest=res://tests/api/test_debug_console.gd -gexit
```

---

## 8. Extending it

* **Add a console command** — add a `case` to `DebugConsole._dispatch()` and a
  line to `_help()`. Read commands query `facade.get_state()`; write commands
  mutate state then call `_refresh()`. Add a test in
  `tests/api/test_debug_console.gd`.
* **Add a logged event** — connect another `SimFacade` signal in
  `scenes/main.gd:_wire_debug()` to a new `_dbg_on_*` handler that calls
  `_dbg_log.append(category, text)`.
* **Add a view-only helper** (needs scene nodes, e.g. camera/fog) — handle it in
  `debug_overlay.gd:_run()` before delegating to the shared engine, so it stays
  out of the pure `DebugConsole`.
