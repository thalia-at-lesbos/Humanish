# Plan: Phase 6 — Presentation and Input Abstraction Layer

> **Status: COMPLETE** (as of v0.4.x). All sub-phases 6A–6F are shipped and
> green. The test suite (382 unit + 8 integration) passes. This document is
> retained as the design record; the live code in `scenes/` and `src/api/` is
> authoritative. Post-Phase-6 additions (interactive encyclopedia, controls
> overview screen, resources on map, gold in HUD, draft UI, remote multiplayer,
> PlayerAI) are tracked in `docs/planning/designgaps.md` and the git log.

## Context

Phases 0–5 are complete: 79/79 GUT tests pass, the headless simulation engine is fully
deterministic, and the `SimFacade` API is the single gate for state mutation and event
observation. Phase 6 adds the presentation side, following the contract defined in
`docs/user-interface-design.md` (the "three-way split": rules module ↔ UI service
interface ↔ presentation host).

**Scope (from `engine-core-plan.md`):**
- Abstract flat-color 2D renderer for the square grid + clean HUD, driven by engine signals.
- Input abstraction layer: mouse, keyboard, and touch all produce the same `Commands.*`
  objects — no input logic in `sim/`.
- Hotseat shell: pass-and-play turn handoff, per-player fog-of-war, setup screen.

**Not in scope:** AI opponents, networked multiplayer, art assets, audio, animations.

---

## Architecture

The UI design spec defines a strict three-layer boundary (§1):

```
Presentation host (scenes/, Godot Nodes)
   ↕  calls UIService interface (host services)
   ↕  reads facade queries (state queries, capability gates, dirty flags)
SimFacade / rules module (src/api/, src/sim/)   ← already built
   ↕  optional scripting layer for heavy screens
```

**Core principle:** `sim/` and `world/` never reference `Node`, scenes, or input — the
existing invariant is preserved. Everything new in `scenes/` drives the engine through
`SimFacade.apply_command()` and reads it through `SimFacade.*` queries.

### New layout additions

```
src/
  api/
    dirty_flags.gd       # per-region invalidation bit set (§2)
    selection_state.gd   # active unit/city selection + cycling (§7)
    text_gen.gd          # all tooltip/breakdown/help text (§9)
  core/
    ids.gd               # extend: DirtyRegion, WidgetType, InterfaceMode,
                         #         PopupType, ControlType, UnitCmd, UnitMission
data/
  hotkeys.json           # rebindable key→ControlType table

scenes/
  main.tscn / main.gd                  # root: wires DataDB + SimFacade
  world/
    world_view.tscn / world_view.gd    # flat-color tile/unit renderer
    fog_layer.gd                        # per-player visibility overlay
    minimap.tscn / minimap.gd          # thumbnail + click-to-pan
  hud/
    hud.tscn / hud.gd                  # CanvasLayer; dirty-flag dispatcher
    selection_panel.gd                  # selected unit/city + action buttons
    slider_panel.gd                     # 4 HSliders summing to 100
    research_bar.gd                     # current tech + progress
    end_turn_button.gd                  # tri-state (ready/waiting/prompt)
    message_log.gd                      # scrollable event/notification log
    turn_score_bar.gd                   # turn number + score
  input/
    input_router.gd                     # keyboard/mouse/touch → Commands
    hotkey_map.gd                       # data-driven key bindings
  setup/
    setup_screen.tscn / setup_screen.gd
  hotseat/
    pass_device_screen.tscn / pass_device_screen.gd
    hotseat_manager.gd
  screens/
    city_screen.tscn / city_screen.gd
    tech_chooser.tscn / tech_chooser.gd
    policy_screen.tscn / policy_screen.gd
    diplomacy_screen.tscn / diplomacy_screen.gd
    save_load_screen.tscn / save_load_screen.gd

tests/
  test_phase6_ui_contract.gd   # headless tests for 6A additions
```

---

## Sub-phases

Each sub-phase must be verifiable before the next begins.

---

### Phase 6A — UI Contract Extensions (headless, testable)

Extend the rules-side API with every query the presentation layer needs. No scenes.
All additions are tested headless with GUT.

#### `src/core/ids.gd` — new enum blocks

```gdscript
# Independently-invalidated display regions (§2)
enum DirtyRegion {
    WORLD = 0, HUD_GROUPS = 1, DATA_PANES = 2, FULL_SCREENS = 3, ALL = 4
}

# Widget type tags for {type, data1, data2} dispatch (§4)
enum WidgetType {
    UNIT_LIST = 0, CITY_SCROLLER = 1, TRAIN_UNIT = 2, CONSTRUCT_BUILDING = 3,
    CREATE_PROJECT = 4, RUSH_PRODUCTION = 5, CHANGE_SPECIALIST = 6,
    RESEARCH = 7, TECH_NODE = 8, CHANGE_SLIDER = 9,
    ACTION = 10, GENERIC_BUTTON = 11, CLOSE_SCREEN = 12,
    CONTACT_LEADER = 13, CANCEL_DEAL = 14, DIPLOMACY_RESPONSE = 15,
    UNIT_MODEL = 16, FLAG = 17, MINIMAP_HIGHLIGHT = 18,
    HELP_MAINTENANCE = 19, HELP_DEFENSE = 20, HELP_WELLBEING = 21,
    HELP_CONTENTMENT = 22, HELP_PRODUCTION = 23, HELP_CULTURE = 24,
    HELP_FINANCE = 25, HELP_PROMOTION = 26,
    ENCYCLOPEDIA = 27, BACK = 28, FORWARD = 29,
    SCRIPTABLE = 30
}

# Map-targeting modes (§5)
enum InterfaceMode {
    SELECTION = 0, PLACE_PING = 1, PLACE_SIGN = 2,
    GO_TO = 3, GO_TO_ALL = 4, ROUTE_TO = 5,
    RANGED_ATTACK = 6, AREA_BOMBARD = 7, PARADROP = 8, AIRLIFT = 9
}

# Popup kinds (§6)
enum PopupType {
    TEXT_NOTICE = 0, MAIN_MENU = 1, CONFIRM = 2, DECLARE_WAR_CONFIRM = 3,
    LOAD_UNIT = 4, CHOOSE_TECH = 5, RAZE_CITY = 6, CHOOSE_PRODUCTION = 7,
    CHANGE_POLICY = 8, CHOOSE_ELECTION = 9, ALARM = 10, DEAL_CANCELLED = 11,
    DIPLOMACY = 12, FOUND_BELIEF = 13, EVENT = 14, GAME_DETAILS = 15
}

# High-level control vocabulary (§3.1)
enum ControlType {
    CENTER_ON_SELECTION = 0, SELECT_ALL_TYPE = 1, NEXT_CITY = 2, PREV_CITY = 3,
    NEXT_UNIT = 4, PREV_UNIT = 5, NEXT_IDLE_UNIT = 6, NEXT_IDLE_WORKER = 7,
    END_TURN = 8, FORCE_END_TURN = 9,
    TOGGLE_GRID = 10, TOGGLE_YIELDS = 11, TOGGLE_RESOURCES = 12,
    OPEN_TECH = 13, OPEN_POLICY = 14, OPEN_DIPLOMACY = 15, OPEN_FINANCE = 16,
    OPEN_MILITARY = 17, OPEN_ESPIONAGE = 18, OPEN_ENCYCLOPEDIA = 19,
    OPEN_CITY_SCREEN = 20, OPEN_SAVE_LOAD = 21,
    QUICK_SAVE = 22, QUICK_LOAD = 23
}

# Direct unit orders (§3.2)
enum UnitCmd {
    WAKE = 0, SLEEP = 1, FORTIFY = 2, CANCEL_ORDERS = 3,
    DISBAND = 4, UPGRADE = 5, PROMOTE = 6, AUTOMATE = 7, STOP_AUTOMATE = 8
}

# Queued unit missions (§3.3)
enum UnitMission {
    MOVE_TO = 0, ROUTE_TO = 1, SKIP_TURN = 2, PILLAGE = 3,
    FOUND_SETTLEMENT = 4, BUILD_IMPROVEMENT = 5, BUILD_ROAD = 6,
    RANGED_ATTACK = 7, BOMBARD = 8, AIRLIFT = 9, PARADROP = 10
}
```

#### `src/api/dirty_flags.gd`

A `Reference` holding one boolean per `IDs.DirtyRegion`. `SimFacade` creates one and
mutates it whenever state visible to the player changes.

```gdscript
class_name DirtyFlags extends Reference
var _flags: Array  # one bool per DirtyRegion

func _init() -> void:
    _flags = [false, false, false, false]  # one per region (not ALL)

func set_dirty(region: int) -> void:   # accepts ALL to set all
func is_dirty(region: int) -> bool:
func clear(region: int) -> void:
func clear_all() -> void:
func mark_all() -> void:
```

**Integration:** Every `_cmd_*` handler in `SimFacade` calls `_dirty.set_dirty(...)` on the
regions it affects (e.g., `MOVE_STACK` sets `WORLD` and `DATA_PANES`; `SET_SLIDERS` sets
`HUD_GROUPS`). The facade exposes `get_dirty() -> DirtyFlags`.

#### `src/api/selection_state.gd`

Tracks the active subject (unit IDs or city ID) separately from `GameState`, since
selection is a UI concern, not a simulation invariant.

```gdscript
class_name SelectionState extends Reference
var selected_unit_ids: Array   # int IDs, ordered (head = [0])
var selected_city_id: int      # -1 if none
var city_screen_open: bool
var active_city_tab: int       # 0=units 1=buildings 2=wonders

func select_unit(id: int, clear: bool, toggle: bool) -> void:
func select_city(id: int, raise_screen: bool) -> void:
func clear() -> void:
func head_unit() -> int:   # first selected unit id or -1
func head_city() -> int:
```

**SimFacade additions:**
```gdscript
var _selection: SelectionState
var _interface_mode: int   # IDs.InterfaceMode
var _popup_queue: Array    # Array of popup descriptor Dicts

func get_selection() -> SelectionState:
func select_unit(unit_id: int, clear: bool = true, toggle: bool = false) -> void:
func select_city(city_id: int, raise_screen: bool = false) -> void:
func cycle_idle_units(workers_only: bool = false) -> void:
func cycle_cities(forward: bool = true) -> void:

func get_interface_mode() -> int:
func can_enter_mode(mode: int) -> bool:   # requires valid selection for non-default modes
func enter_interface_mode(mode: int) -> void:
func exit_interface_mode() -> void:
func get_mode_tile_validity(x: int, y: int) -> int:  # 0=invalid 1=valid 2=highlighted

func push_popup(descriptor: Dictionary) -> void:
func get_pending_popup() -> Dictionary:   # empty if queue is empty
func resolve_popup(result: Dictionary) -> void:  # pops front, applies game command if any

func can_do_control(ctrl_type: int) -> bool:
func can_handle_action(action_id: int, target_x: int, target_y: int) -> bool:

func get_end_turn_state() -> int:   # 0=ready 1=waiting_on_others 2=show_prompt
func get_hud_visibility() -> Dictionary:  # keys: show_research, show_flag, show_minimap_center
func get_tile_highlights() -> Dictionary: # tile_key→color_int
func get_flyout_menu(x: int, y: int) -> Array:  # Array of {action_id, label, target_x, target_y}
func get_dirty() -> DirtyFlags:
```

#### `src/api/text_gen.gd`

Static class. Every help/tooltip/breakdown string lives here — nothing in `scenes/`.
The host always calls `SimFacade.widget_help(widget)` which delegates here.

```gdscript
class_name TextGen

static func widget_help(widget: Dictionary, gs: GameState, db: DataDB) -> String:
    # routes by widget.type to specialist methods:
static func _help_unit(unit_id: int, gs: GameState, db: DataDB) -> String:
static func _help_city(city_id: int, gs: GameState, db: DataDB) -> String:
static func _help_tech(tech_id: String, gs: GameState, db: DataDB) -> String:
static func _help_finance(player_id: int, gs: GameState, db: DataDB) -> String:
static func _help_production(city_id: int, gs: GameState, db: DataDB) -> String:
static func _help_promotion(promo_id: String, db: DataDB) -> String:
# ... one method per major HELP_* widget group
```

**SimFacade additions:**
```gdscript
func widget_help(widget: Dictionary) -> String:
func widget_action(widget: Dictionary) -> bool:    # applies the widget's command
func widget_alt_action(widget: Dictionary) -> bool:
func widget_is_link(widget: Dictionary) -> bool:
```

#### `src/api/commands.gd` — new factories

```gdscript
# Unit commands (§3.2)
static func unit_wake(player_id: int, unit_id: int) -> Dictionary:
static func unit_sleep(player_id: int, unit_id: int) -> Dictionary:
static func unit_fortify(player_id: int, unit_id: int) -> Dictionary:
static func unit_cancel_orders(player_id: int, unit_id: int) -> Dictionary:
static func unit_disband(player_id: int, unit_id: int) -> Dictionary:
static func unit_upgrade(player_id: int, unit_id: int) -> Dictionary:
static func unit_promote(player_id: int, unit_id: int, promotion_id: String) -> Dictionary:

# Unit missions (§3.3)
static func mission_move_to(player_id: int, unit_id: int, tx: int, ty: int) -> Dictionary:
static func mission_build_road(player_id: int, unit_id: int) -> Dictionary:
static func mission_skip_turn(player_id: int, unit_id: int) -> Dictionary:
static func mission_pillage(player_id: int, unit_id: int) -> Dictionary:
static func mission_bombard(player_id: int, unit_id: int, tx: int, ty: int) -> Dictionary:
static func mission_airlift(player_id: int, unit_id: int, tx: int, ty: int) -> Dictionary:

# Controls
static func do_control(player_id: int, ctrl_type: int, data: Dictionary = {}) -> Dictionary:
```

#### Tests: `tests/test_phase6_ui_contract.gd`

```
test_dirty_flags_set_by_move_stack
test_dirty_flags_set_by_set_sliders
test_dirty_flags_clear_after_read
test_select_unit_updates_selection_state
test_select_city_updates_selection_state
test_cycle_idle_units_visits_all_idle
test_can_do_control_end_turn_allowed
test_can_handle_action_move_blocked_by_mode
test_interface_mode_tile_validity_in_go_to_mode
test_popup_queue_serializes_and_pops_in_order
test_widget_help_unit_returns_nonempty_string
test_widget_help_finance_breakdown_contains_numbers
test_widget_help_tech_lists_prereqs
test_end_turn_state_ready_when_no_pending_orders
test_flyout_menu_nonempty_on_owned_unit_tile
test_new_unit_commands_accepted_by_facade
```

---

### Phase 6B — Scene Scaffold + Flat-color World Renderer

First running Godot scene. Goal: `godot3 scenes/main.tscn` opens, shows the world grid
with colored tiles and unit squares, and accepts camera pan/zoom.

#### `scenes/main.gd`

On `_ready()`:
1. Create `DataDB`, call `db.load_all()`.
2. Create `SimFacade`, call `facade.setup(...)` with default small world + 2 players.
3. Wire facade signals (`combat_resolved`, `turn_advanced`, `game_won`) to log prints.
4. Add `WorldView`, `HUD`, `InputRouter`, `HotseatManager` as children.
5. Pass facade reference to all children via `init(facade)` calls.

#### `scenes/world/world_view.gd` (Node2D)

- **Tile rendering:** `draw_rect` in `_draw()` for each tile; color keyed on terrain type
  from a static color table (`FLAT`→pale green, `HILL`→brown, `PEAK`→grey, `WATER`→blue,
  `DEEP_WATER`→dark blue). Tile size: 40×40px default.
- **Unit icons:** colored filled rect (player color) + 2-letter domain abbreviation
  (`LD`/`SE`/`AI`) drawn with `draw_string` at tile center.
- **Selection highlight:** 2px border rect in white around selected unit's tile.
- **Movement range overlay:** semi-transparent green tint on reachable tiles (queried
  from facade when `InterfaceMode.GO_TO` is active).
- **Camera:** `_offset: Vector2` + `_zoom: float`. Arrow keys or middle-mouse drag pans;
  scroll wheel zooms. Camera is clamped to map bounds.
- **Dirty rebuild:** `_process()` checks `facade.get_dirty().is_dirty(IDs.DirtyRegion.WORLD)`;
  on true calls `update()` (triggers `_draw()`) and clears the flag.
- **Facade signals:** `combat_resolved` → flash attacker/defender tiles red for one second
  (via a Timer). `settlement_founded` → queue_update.

#### `scenes/world/fog_layer.gd` (Node2D, child of WorldView)

- Maintains `_visible_tiles: Dictionary` (key = "x,y" → bool) for the current player.
- Rebuilt when `hotseat_manager` emits a turn-handoff signal.
- `_draw()` overlays a semi-transparent black rect on every tile not in `_visible_tiles`.
- Visibility rule (simplified): a tile is visible if any owned unit or settlement is
  within 2 tiles (Manhattan distance).

#### `scenes/world/minimap.gd` (Control, in HUD CanvasLayer)

- `ImageTexture` updated each turn: one pixel per tile, color = player territory color or
  terrain color if unowned.
- Click on minimap pans `WorldView._offset` proportionally.

**Verification:** open `scenes/main.tscn`, confirm tiles render with terrain colors, a
unit square appears at its position, camera pan/zoom works, fog of war covers unexplored
tiles.

---

### Phase 6C — HUD Panels

All HUD nodes live in a `CanvasLayer` (draw-order above world, always on-screen).
`hud.gd` owns a `_dirty: DirtyFlags` reference and drives per-panel rebuilds each frame.

#### `scenes/hud/hud.gd`

```gdscript
func _process(_delta: float) -> void:
    var d: DirtyFlags = _facade.get_dirty()
    if d.is_dirty(IDs.DirtyRegion.HUD_GROUPS):
        _selection_panel.rebuild()
        _slider_panel.rebuild()
        _research_bar.rebuild()
        _end_turn_button.rebuild()
        d.clear(IDs.DirtyRegion.HUD_GROUPS)
    if d.is_dirty(IDs.DirtyRegion.DATA_PANES):
        _message_log.rebuild()
        _turn_score_bar.rebuild()
        d.clear(IDs.DirtyRegion.DATA_PANES)
```

#### `scenes/hud/selection_panel.gd`

- If `facade.get_selection().head_unit() >= 0`: show unit name, type, health, movement.
  Generate action buttons from `facade.get_flyout_menu(unit.x, unit.y)` — each is a
  `Button` whose `pressed` signal calls `facade.widget_action(widget)`.
- If `facade.get_selection().head_city() >= 0`: show city name, population, production
  item + progress bar.
- Tooltip on hover: `facade.widget_help(widget)` → shown in a `Label` at cursor.

#### `scenes/hud/slider_panel.gd`

Four `HSlider` nodes (`Finance`, `Research`, `Culture`, `Intel`). On any slider change:
1. Read all four values.
2. Clamp the changed one and adjust others proportionally to keep sum = 100.
3. Emit `facade.apply_command(Commands.set_sliders(...))`.

#### `scenes/hud/end_turn_button.gd`

- `rebuild()` reads `facade.get_end_turn_state()`:
  - `0` (ready) → "End Turn" normal style
  - `1` (waiting on others) → "Waiting…" dimmed style
  - `2` (show prompt) → "End Turn?" highlighted style
- `pressed` → `facade.apply_command(Commands.end_turn(player_id))`.

#### `scenes/hud/message_log.gd`

- `rebuild()` reads `facade.get_notification_queue()`, appends new entries to a
  `RichTextLabel`. Entries are `{text, category, turn}` dicts.
- A `ScrollContainer` wraps it; auto-scrolls to bottom on new entry.

#### `scenes/hud/research_bar.gd`

- Shows current tech name + `{turns_remaining} turns` estimate.
- Click opens `TechChooserScreen`.

#### `scenes/hud/turn_score_bar.gd`

- Shows `Turn {N}/{max}` and player score from `facade.get_state().scoring`.

**Verification:** sliders update on drag and sum stays 100; end-turn button changes
appearance based on state; message log grows when events fire; research bar updates after
tech completes.

---

### Phase 6D — Input Abstraction Layer

#### `scenes/input/input_router.gd` (Node, autoload or child of main)

Handles `_unhandled_input(event)`. All branches produce `Commands.*` dicts and call
`facade.apply_command()`.

**Mouse left-click on world:**
1. Convert screen pos → tile (x, y) via `WorldView.screen_to_tile(pos)`.
2. If in a targeting mode (`facade.get_interface_mode() != SELECTION`):
   - If `facade.get_mode_tile_validity(x, y) > 0`: dispatch the mode's command (e.g., `Commands.mission_move_to`). Exit mode.
   - Else: ignore.
3. Else (selection mode):
   - If tile has owned units: `facade.select_unit(lead_unit_id)`.
   - Else if tile has owned settlement: `facade.select_city(city_id)`.
   - Else if a unit is selected and tile is reachable: `facade.apply_command(Commands.move_stack(...))`.

**Mouse right-click on world:**
1. Compute tile.
2. `facade.get_flyout_menu(x, y)` → populate a `PopupMenu` node.
3. On item selected: call `facade.apply_command(Commands.do_control(...))`.

**Keyboard:**
```gdscript
func _handle_keyboard(event: InputEventKey) -> void:
    var ctrl_type: int = _hotkey_map.lookup(event.scancode, event.shift, event.ctrl)
    if ctrl_type < 0:
        return
    if not _facade.can_do_control(ctrl_type):
        return
    _facade.apply_command(Commands.do_control(_current_player_id, ctrl_type))
```

**Touch:**
- Single tap → same as left-click at tap position (tile hit-test).
- Two-finger pinch → zoom `WorldView._zoom`.
- Single-finger drag (no unit selected) → pan camera.

#### `scenes/input/hotkey_map.gd`

Loads `data/hotkeys.json`. Format:
```json
{
  "e": {"ctrl": false, "shift": false, "action": 8},
  "F1": {"ctrl": false, "shift": false, "action": 19}
}
```
`lookup(scancode, shift, ctrl) -> int` returns `IDs.ControlType` or `-1`.

#### `data/hotkeys.json` (default bindings)

| Key | ControlType |
|-----|-------------|
| `E` | END_TURN |
| `N` | NEXT_UNIT |
| `B` | NEXT_IDLE_WORKER |
| `C` | CENTER_ON_SELECTION |
| `F1` | OPEN_ENCYCLOPEDIA |
| `F2` | OPEN_TECH |
| `F3` | OPEN_POLICY |
| `F4` | OPEN_DIPLOMACY |
| `F5` | QUICK_SAVE |
| `F9` | QUICK_LOAD |

**Verification:** press E → end turn fires; click owned unit → selection panel updates;
click empty reachable tile with unit selected → unit moves; right-click tile → flyout menu
appears with correct options.

---

### Phase 6E — Hotseat Shell

#### `scenes/setup/setup_screen.gd`

Shown as the initial screen before `SimFacade.setup()` is called.

- `SpinBox` for player count (2–8).
- Per-player row: name `LineEdit`, leader `OptionButton` (populated from `db.leaders`).
- `OptionButton` for world size, pace, difficulty.
- `LineEdit` for seed (blank = random, populated with `randi()` on focus).
- "Start Game" `Button` → validates, calls `facade.setup(...)`, switches to main scene.

#### `scenes/hotseat/hotseat_manager.gd`

Subscribes to `facade.turn_advanced`. On signal:
1. Show `PassDeviceScreen` with "Pass to [next_player_name]".
2. Rebuild fog of war for the incoming player.
3. Re-center camera on that player's capital.

#### `scenes/hotseat/pass_device_screen.gd`

Full-screen overlay with player name and a single "OK" button. On OK: hide overlay,
rebuild fog, enable input. Prevents the outgoing player from seeing the incoming
player's units/territory through the transition.

#### Fog of war enforcement

`FogLayer.rebuild(player_id)`:
1. Query all units + settlements owned by `player_id` from `facade.get_state()`.
2. Compute visible tile set: for each owned entity, add all tiles within sight range
   (2 for units, 3 for settlements — read from `db.get_constant("unit_sight", 2)`).
3. Store in `_visible_tiles`. Call `update()`.

`WorldView._draw()` passes `fog_layer._visible_tiles` to its tile loop: tiles outside
the set are skipped (drawn by `FogLayer` as dark overlay instead).

**Verification:** start 2-player game, end Player 1 turn → pass-device screen appears
→ click OK → world redraws with Player 2's fog. Player 2's units are visible; Player 1's
units outside Player 2's sight range are hidden.

---

### Phase 6F — Essential Secondary Screens

Each screen is opened by a `ControlType` command routed through `InputRouter` → facade →
emitting a `screen_requested(screen_id)` signal that `main.gd` responds to by showing
the relevant scene node.

#### `scenes/screens/city_screen.gd`

Opened when a city is double-clicked or `OPEN_CITY_SCREEN` control fires.

- **Production queue panel:** lists queued items (unit/building/project type + progress).
  "Change" button → inline chooser list filtered by `facade.can_handle_action(...)`.
  "Rush" button → `Commands.rush_production(...)`.
- **Building list:** scrollable list of completed buildings with `facade.widget_help()`
  tooltip on hover.
- **Worked tile display:** text list of worked tiles and their output vectors (no graphical
  tile picker in Phase 6 — full graphic assignment is Phase 7+).
- **Breakdown labels:** contentment, wellbeing, food surplus, production per turn — from
  `facade.widget_help({type: HELP_PRODUCTION, data1: city_id})` etc.

#### `scenes/screens/tech_chooser.gd`

- Lists all techs grouped by era. Researchable techs (prerequisites met) are enabled;
  locked techs dimmed.
- Click enabled tech → `facade.apply_command(Commands.set_research(...))` → close screen.
- Hover → `facade.widget_help({type: TECH_NODE, data1: tech_idx})` shows prereqs +
  what it unlocks.

#### `scenes/screens/policy_screen.gd`

- One section per policy category. Current policy highlighted with a border.
- Click a different policy → confirm popup via `facade.push_popup({type: CONFIRM, ...})`;
  on OK → `Commands.set_policy(...)`.
- Transition penalty shown if applicable (from TextGen).

#### `scenes/screens/diplomacy_screen.gd`

- Lists known players with attitude indicator (at war / peace / allied).
- "Declare War" button → `Commands.declare_war(...)` (with confirm popup).
- "Make Peace" button → `Commands.make_peace(...)`.
- Phase 6 scope: no trade proposal UI (that requires the full tradeable-item widget set;
  deferred to Phase 7).

#### `scenes/screens/save_load_screen.gd`

- Save: `facade.save()` → `File.open(path, WRITE).store_string(json)`.
  Filename includes turn number and timestamp.
- Load: `File.open(path, READ).get_as_text()` → `facade.load_save(json)` → rebuild
  entire scene tree state.
- File list: `Directory.list_dir_begin()` scanning a fixed `user://saves/` path.

---

## Invariants preserved throughout Phase 6

1. **No input or scene reference enters `sim/` or `world/`.** All new Node code lives
   in `scenes/`; all query additions live in `src/api/`.
2. **Integer math only.** `scenes/` code may use floats for pixel coordinates and
   camera math, but any value passed to `facade.apply_command()` is integer-only.
3. **One command path.** Mouse, keyboard, and touch all produce `Commands.*` dicts.
   No shortcut that mutates `GameState` directly.
4. **Dirty flags gate rebuilds.** HUD panels only run `rebuild()` when the relevant
   `DirtyRegion` flag is set; not on every frame.
5. **Text generation stays in `text_gen.gd`.** No `scenes/` script computes a
   gameplay-derived string itself.

---

## Verification summary

| Sub-phase | Verification method |
|-----------|---------------------|
| 6A | GUT headless tests (`test_phase6_ui_contract.gd`); all 16 cases green |
| 6B | Visual: tiles render, unit squares visible, camera pan/zoom works |
| 6C | Visual: sliders constrain to 100; end-turn tri-state; messages appear |
| 6D | Interactive: E ends turn; click unit selects; click tile moves; right-click shows menu |
| 6E | Interactive: 2-player game, pass-device screen appears, fog is per-player |
| 6F | Interactive: each secondary screen opens, data matches sim state, actions apply |

Run full headless suite after 6A merges to confirm no regression in Phases 0–5:
```bash
godot3 --no-window -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

---

## Out of scope (Phase 7+)

- Graphical worked-tile assignment in city screen (the tile grid picker).
- Animations and combat replay.
- Trade proposal UI (tradeable-item widget set).
- Encyclopedia browser (full cross-linked reference).
- Advisor screens (domestic, espionage, military, foreign-relations).
- World builder / map editor.
- Full promotion chooser UI.
- Touch: multi-unit lasso selection.
