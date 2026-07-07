---
title: "User Interface — Functional Specification"
role: design
summary: >
  Functional (not aesthetic) specification of the UI contract between the rules engine
  (src/sim/, src/api/) and the presentation layer (scenes/). Defines the display model
  (dirty-flag invalidation), the full command vocabulary (controls, unit commands,
  unit missions), the widget dispatch system, map-targeting modes, popups, selection
  state, notifications, tooltip/help text generation, and the standard screen inventory.
  Also documents the SimFacade signal interface (§8.1) and the implemented ControlType
  enum values (§3.1.1). The scenes/ layer must drive the engine exclusively through
  these interfaces; nothing in src/sim/ or src/world/ may reference scenes or input.
audience:
  - Coding agents implementing or auditing scenes/, src/api/sim_facade.gd
  - Contributors adding new screens, HUD elements, or command vocabulary
  - Reviewers checking that a UI feature correctly uses the facade interface
key_files:
  - src/api/sim_facade.gd        # public API — apply_command, signals, queries
  - src/api/commands.gd          # Command factory methods
  - src/api/selection_state.gd   # active selection (unit / city / tile)
  - src/api/dirty_flags.gd       # per-region invalidation bit set
  - src/api/text_gen.gd          # all tooltip/breakdown/help text generation
  - src/core/ids.gd              # ControlType, UnitCmd, UnitMission, DirtyRegion enums
  - data/hotkeys.json            # key→ControlType default bindings
  - scenes/main.gd               # scene root; wires facade signals to screens
  - scenes/hud/hud.gd            # dirty-flag dispatcher to HUD panels
  - scenes/hud/selection_panel.gd
  - scenes/hud/menu_bar.gd       # advisor button bar (§11.1)
  - scenes/input/input_router.gd # keyboard/mouse → Commands
  - scenes/screens/             # all secondary screen implementations
sections:
  "§1  Roles & three-way split": "sim ↔ UIService interface ↔ presentation host boundary"
  "§2  Display model":           "Dirty-flag invalidation — DirtyRegion enum, set/clear/rebuild cycle"
  "§3  Interaction model":       "Input → validated action → ordered command pipeline"
  "§3.1 Controls":               "Global command vocabulary; §3.1.1 implemented ControlType table (provisional)"
  "§3.2 Unit commands":          "Direct immediate orders (wake, fortify, promote, disband, gift, load/unload)"
  "§3.3 Unit missions":          "Queued multi-turn orders; multi-turn go-to persistence"
  "§4  Widget catalog":          "Uniform {type,data1,data2} dispatch — help-text, action, alt-action, is-link"
  "§5  Map-targeting modes":     "Interface modes (go-to, ranged attack, airlift, paradrop, etc.)"
  "§6  Popups":                  "Popup descriptor, construction primitives, functional popup types"
  "§7  Selection model":         "Active unit/stack or city subject; cycling; camera/focus control"
  "§8  Messages & notifications":"Event log, turn log, talking-head messages, combat log, pings/signs"
  "§8.1 Facade signals":         "All 14 SimFacade signals with parameter types (provisional)"
  "§9  Help text":               "Centralized tooltip/breakdown/encyclopedia text generation (src/api/text_gen.gd)"
  "§10 Display-gating queries":  "End-turn states, HUD visibility, capability gates, tile/flyout presentation"
  "§11 Standard screens":        "Full screen inventory with per-screen functional description; §11.1 HUD advisor bar"
  "§12 Reconstruction checklist":"11-step checklist for reimplementing the full UI contract"
editorial_rule: >
  Modify only with explicit user consent. §3.1.1, §8.1, and §11.1 are provisional
  (implemented but names/values not yet verified against the spec vocabulary). All
  other sections are authoritative design intent. When adding a new screen, command,
  or signal, add it to the relevant section and mark it provisional if unverified.
---

# User Interface — Functional Specification

A functional (not aesthetic) description of the user interface that the game-core module
defines and drives. The goal is reproducibility of **behavior**: what interactive
elements exist, what they do, how the display is kept current, how input becomes game
actions, and what dialogs/screens/notifications exist — without prescribing any visual
layout, art, color, font, or animation.

> **Core principle.** The rules/simulation module does **not** render pixels or read raw
> input devices. It defines the *interface contract*: a vocabulary of interactive
> elements, a set of state queries, a refresh/invalidation model, and a command channel.
> A host presentation layer renders that contract however it likes. Any front end that
> implements the same contract reproduces the functionality.

---

## 1. Roles and the three-way split

```
┌─────────────────────────────────────────────────────────────┐
│ Presentation host (renderer + input + windowing)             │
│  • draws the world, panels, buttons, text, cursors           │
│  • captures mouse/keyboard, hit-tests interactive elements    │
│  • owns dialog windows and on-screen message areas            │
└───────▲───────────────────────────────────────────▲──────────┘
        │ host services the module calls             │ module exports the
        │ (selection, popups, messages, camera,      │ element vocabulary,
        │  dirty bits, screen toggles)               │ tooltip text, actions,
        │                                            │ and state queries
┌───────┴───────────────────────────────────────────┴──────────┐
│ Rules / simulation module                                     │
│  • defines every interactive element TYPE and its behavior     │
│  • answers "what is at this tile / in this list / on this      │
│    button" and "is this action currently allowed"             │
│  • turns validated input into ordered game commands           │
│  • generates all explanatory/tooltip/help text                 │
└───────────────────────────────────────────────────────────────┘
        │ scripting/extension layer (optional)
        ▼
  high-level windows (full-screen advisor screens, encyclopedia,
  setup screens) authored as replaceable scripts
```

* **Presentation host** — supplies a UI service interface the module calls to manipulate
  selection, raise dialogs, post messages, move the camera, toggle screens, and mark
  regions of the display stale.
* **Rules module** — defines the element catalog (§4), validates and executes actions
  (§3), generates tooltip/help text (§9), and answers display-gating queries (§10).
* **Scripting layer** — authors the heavy full-screen windows and setup flows as
  swappable scripts; it reads the same game state through the module's data accessors.

A clone may collapse these layers, but keeping the contract (element vocabulary + state
queries + refresh model + command channel) is what preserves functionality.

---

## 2. Display model: pull + invalidation ("dirty bits")

The UI is **state-driven**, not push-rendered by the rules. The display is rebuilt from
current game state on demand; the rules tell the host *which parts of the display are now
stale* by setting **invalidation flags**. Each frame the host rebuilds any flagged region
and clears its flag.

Functional set of independently-invalidated regions (names are functional, not visual):

* **World/camera**: selection-camera recenter, fog-of-war, waypoints, highlighted tile,
  colored tiles, blockaded tiles, globe-overlay layers and their info.
* **HUD control groups**: economic-rate buttons, misc action buttons, the on-tile unit
  list, the selection action buttons, citizen-assignment buttons, research buttons,
  replay buttons.
* **Data panes**: aggregate game data, score, selection data, the per-unit info pane, the
  per-city info pane, the city screen, the generic info pane, the turn timer, the help/
  tooltip area, the minimap section, the cursor type, the flag display, the event/message
  area.
* **Full screens**: financial, foreign-relations, domestic advisor, espionage advisor,
  the soundtrack indicator, popups, and the advanced-start editor.

Implementation note for a clone: model this as a bit set with one flag per region; expose
`isDirty(region)` / `setDirty(region, bool)` and a "mark everything dirty" reset. The
rules module sets flags whenever it mutates state the player can see (e.g. selecting a
unit flags the unit list, unit info pane, and action buttons).

---

## 3. Interaction model: input → validated action → ordered command

All player intent flows through one validate-then-execute pipeline so that
multiplayer/replay stays deterministic:

```
host captures input and hit-tests an element
    → module: "is this allowed right now?"  (capability query)
    → module: package the request as an ordered game command (network message)
    → command is applied identically on every client, in order
    → state mutates → invalidation flags set → host rebuilds affected regions
```

There are four families of player intent, each with its own vocabulary and capability
query:

| Family | What it represents | Capability gate | Executes |
|--------|--------------------|-----------------|----------|
| **Controls** | global/UI-level commands & screen toggles (end turn, cycle units, open a screen, toggle an overlay, save/load, camera modes) | "can do control?" | "do control" |
| **Actions** | context actions available to the current selection on a target tile (build, attack-move, special abilities) | "can handle action?" (optionally test-visible) | "handle action" |
| **Unit commands** | direct orders to selected units (promote, upgrade, automate, wake, sleep, disband, gift, load/unload) | per-command "can do" on the unit | issue command |
| **Unit missions** | movement/work orders queued on a unit stack (move-to, route-to, fortify, pillage, bombard, found, build improvement, spread belief, special-person actions, etc.) | per-mission "can start" on the stack | push mission onto the stack's order queue |

### 3.1 Controls (global command vocabulary)
A flat enumeration of high-level commands the host binds to buttons/hotkeys. Functional
groupings:

* **Selection & navigation**: center on selection; select all units of a type / all units
  on a tile; select a city; select capital; next/previous city; next/previous unit; cycle
  to next idle unit (and a variant); cycle to next idle worker; reselect last unit.
* **Turn flow**: end turn (and a modifier variant); force end turn; trigger queued
  automatic moves.
* **World overlays & view**: place a map ping; place a sign; toggle grid; toggle bare-map
  mode; toggle tile-yield display; toggle show-all-resources; toggle unit icons; toggle
  globe-overlay layer; toggle score display; toggle globe (3D) view; multiple camera modes
  (orthographic, flying, mouse-flying, top-down, isometric rotate left/right, cycle flying
  modes).
* **Screens**: encyclopedia, religion, corporation, policy/civics, foreign relations,
  finance, military, tech chooser, turn log, domestic advisor, victory progress, espionage,
  hall of fame, game details, admin details, options, world-builder/editor, diplomacy,
  generic info screen.
* **Session**: load game, quick-save, quick-load, save (normal and group variants),
  retire, all-chat, team-chat, free-colony.
* **Convenience selections**: select only healthy units; select-healthy variants.
* **Assembly**: cast a Yea/Nay/Abstain vote on the open assembly proposal (`CAST_VOTE`) — §7.2.

#### 3.1.1 Implemented ControlType values (provisional)

> **⚠️ Provisional — implemented, values not verified against spec naming.** The following
> table enumerates the `IDs.ControlType` enum values currently wired in the engine
> (`src/core/ids.gd`). The functional description above lists the full intended vocabulary;
> this table records what is actually dispatched through `SimFacade.apply_command`. Values
> without a ✓ in the "Wired" column are declared in the enum but have no handler (they may
> be set by a hotkey or button without producing a game-state change).

| Value | Name | Wired | Notes |
|-------|------|-------|-------|
| 0 | `CENTER_ON_SELECTION` | ✓ | Pan camera to selected unit/city |
| 1 | `SELECT_ALL_TYPE` | ✓ | Select all units of the same type on this tile |
| 2 | `NEXT_CITY` | ✓ | Cycle to the next owned settlement |
| 3 | `PREV_CITY` | ✓ | Cycle to the previous owned settlement |
| 4 | `NEXT_UNIT` | ✓ | Cycle to the next unit |
| 5 | `PREV_UNIT` | ✓ | Cycle to the previous unit |
| 6 | `NEXT_IDLE_UNIT` | ✓ | Cycle to the next unit with moves remaining |
| 7 | `NEXT_IDLE_WORKER` | ✓ | Cycle to the next idle worker |
| 8 | `END_TURN` | ✓ | End the current player's turn |
| 9 | `FORCE_END_TURN` | ✓ | End turn even if units remain idle |
| 10 | `TOGGLE_GRID` | ✓ | Toggle tile grid overlay |
| 11 | `TOGGLE_YIELDS` | ✓ | Toggle per-tile yield display |
| 12 | `TOGGLE_RESOURCES` | ✓ | Toggle resource icon display |
| 13 | `OPEN_TECH` | ✓ | Open tech chooser screen |
| 14 | `OPEN_POLICY` | ✓ | Open policy/civics screen |
| 15 | `OPEN_DIPLOMACY` | ✓ | Open diplomacy screen |
| 16 | `OPEN_FINANCE` | ✓ | Open finance advisor screen |
| 17 | `OPEN_MILITARY` | ✓ | Open military advisor screen |
| 18 | `OPEN_ESPIONAGE` | ✓ | Open espionage advisor screen |
| 19 | `OPEN_ENCYCLOPEDIA` | ✓ | Open interactive encyclopedia |
| 20 | `OPEN_CITY_SCREEN` | ✓ | Open the city management screen for the selected city |
| 21 | `OPEN_SAVE_LOAD` | ✓ | Open the save/load screen |
| 22 | `QUICK_SAVE` | ✓ | Save to the quicksave slot (F5) |
| 23 | `QUICK_LOAD` | ✓ | Load from the quicksave slot (F9) |
| 24 | `OPEN_MENU` | ✓ | Toggle the pause/ESC menu |
| 25 | `TOGGLE_SCORE` | ✓ | Toggle score overlay |
| 26 | `OPEN_RELIGION` | ✓ | Open religion / state-religion advisor screen |
| 27 | `OPEN_CORPORATION` | ✓ | Open economic-organizations advisor screen |
| 28 | `OPEN_TURN_LOG` | ✓ | Open the turn event log screen |
| 29 | `OPEN_DOMESTIC_ADVISOR` | ✓ | Open the domestic advisor screen |
| 30 | `OPEN_VICTORY_PROGRESS` | ✓ | Open the victory-conditions progress screen |
| 31 | `OPEN_OPTIONS` | ✓ | Open the in-game options screen |

### 3.2 Unit commands
Direct, immediate orders on the current unit selection: choose a promotion; upgrade to a
more advanced type; toggle automation; wake from sleep/sentry; cancel current order;
cancel all orders; stop automation; disband; gift to another player; load into a
transport; load a specific unit; unload; unload all; invoke a bound hotkey action.

### 3.3 Unit missions (the order queue)
Missions are queued on a unit stack and executed over subsequent turns. The functional set
covers: move-to, route-to (lay transport while moving), move-to-unit, skip turn, sleep,
fortify (entrench), plunder, air patrol, sea patrol, heal, sentry, airlift, strike with
area weapon, scout/recon, paradrop, area bombard, ranged attack, bombard defenses,
pillage, sabotage, destroy, steal plans, found settlement, spread belief, spread economic
organization, join settlement as specialist, construct wonder, discover technology, rush
production, establish trade route, perform a special-person "great work", infiltrate,
trigger celebration age, build improvement, attach as leader, run espionage mission, plus
internal animation/combat-sequencing pseudo-missions (begin/end combat, surrender,
captured, idle, die, damage, multi-select/deselect).

**Multi-turn go-to.** The move-to (and the stack-move it issues) is a *persistent*
order: when the path to the target is longer than the unit's remaining movement, the
destination is remembered on the unit and the journey resumes automatically at the start
of each subsequent turn — the player issues the order once and the unit walks there over
as many turns as it takes. The order is dropped on arrival, when it can no longer be
pathed, or when the unit enters combat (so a go-to never auto-re-attacks). The host should
surface the standing destination in the unit's selection readout (see §7 / the unit info
pane) so the player can see a unit is en route, and re-issuing any order replaces it.

---

## 4. Interactive element catalog ("widgets")

Every hoverable/clickable thing the rules module recognizes is a **widget**: a small
tagged data record carrying a *type* plus up to two integer parameters identifying the
subject (e.g. which unit type, which technology, which tile-list index). Widgets give the
module a uniform way to answer two questions for any element:

1. **What does it explain?** → produce tooltip/help text for the element (§9).
2. **What happens on click?** → execute its primary action; some widgets also define an
   **alternate action** (the secondary/right-click behavior). Some widgets are pure
   display/links (no action).

A clone should implement widgets as `{type, data1, data2}` and route them through three
module entry points: *parse-help(widget) → text*, *execute-action(widget) → did something*,
*execute-alt-action(widget) → did something*, plus *is-link(widget)*.

### 4.1 Functional widget groups

* **City production & management**: on-tile unit list (and a shift variant for reordering),
  city scroller, train-unit, construct-building, create-project, set-process,
  rush/hurry, conscript, change-specialist, citizen / free-citizen / disabled-citizen /
  angry-citizen tiles, emphasize (economic focus), automate-citizens, automate-production,
  rename city, rename unit, liberate city, city tab selector (units / buildings / wonders),
  zoom-to-city.
* **Empire economy & research**: research selection, tech-tree node, change-economic-rate
  percentage (+/− in 10% steps on the three adjustable rates — science, culture,
  espionage — with economy the read-only derived remainder), launch-victory project,
  religion conversion, score breakdown.
* **Generic action**: the catch-all action widget (maps to a context action, §3), generic
  button, close-screen.
* **Diplomacy & trade**: contact another leader, a tradeable-item toggle, cancel/kill a
  deal, diplomacy response, leader portrait, leader-relationship line.
* **Map & flags**: unit model, flag, minimap highlight, globe-overlay layer / layer option
  / layer toggle.
* **Explanatory (display-only) help widgets**: a large family that produces breakdown
  tooltips for derived quantities — maintenance, belief/affiliation, defense, wellbeing,
  contentment, population, production, culture, special-person and leader bonuses,
  building/feature/yield effects, technology prerequisites and obsolescence, trade
  abilities (map/tech/gold/passage/defensive-pact/alliance/subjugation), terrain/water
  work, the full finance breakdown (unit count, unit cost, away-supply, settlement
  maintenance, policy upkeep, foreign income, inflation, gross income, net finance,
  reserve), promotions, and modifier explanations.
* **Encyclopedia navigation**: jump-to entries for technology, unit, building, required/
  derived technology, resource, promotion, unit-class, improvement, policy, faction,
  leader, specialist, project, terrain, feature, belief, organization; plus back, forward,
  main, and description widgets.
* **Editor / setup / session**: file list and edit boxes, save/load buttons, map editor
  toggles (reveal all, erase, regenerate, plot/player/diplomacy modes), event choosers,
  revolution chooser, turn-event navigation, foreign-advisor refresh, popup-queue,
  scriptable widget (defers display and execution to the scripting layer).

The exact membership is data-extensible; the requirement for a clone is the **uniform
{type,data} dispatch to help-text and action**, not the specific list.

---

## 5. Map-targeting modes ("interface modes")

When an action needs a target the player must pick on the map, the UI enters a transient
**interface mode** that changes what a click on a tile means and what feedback the cursor/
overlay shows. Functional modes:

* default **selection** mode;
* **place ping**, **place sign**, **camera grip/drag**, **globe-overlay input**;
* movement targeting: **go-to**, **go-to (by type)**, **go-to (all)**, **route-to**;
* combat/special targeting: **airlift**, **area-strike (nuke)**, **recon**, **paradrop**,
  **area bombard**, **ranged attack**, **air strike**, **rebase**;
* scripting-driven **pick a plot**; and an editor **save tile geometry** mode.

The module exposes "can enter this mode with the current selection?" and the host sets/gets
the current mode. While in a targeting mode the host asks the module, per hovered tile,
whether the target is valid and what highlight/cursor to show.

---

## 6. Dialogs and popups

Transient modal/queued dialogs are built by the rules module and displayed by the host. A
**popup queue** serializes them so only one shows at a time (with priority/front
insertion), and there are queries for "is a popup or diplomacy screen waiting/up".

### 6.1 Popup descriptor
The module raises a popup by handing the host a **popup descriptor** that carries: a popup
*type* (selecting the semantics/handler), the target player, immediate-vs-queued and
front-vs-back flags, and a small payload of integer/string parameters. On dismissal the
host returns a **popup result** record (which button/option was chosen, edit-box text,
selected list indices, checkbox/radio states) back to the module, which then issues the
corresponding game command.

### 6.2 Popup construction primitives
For module/script-built popups, the host offers content primitives (functional, not
styled): set header text; set body text; add an image; add a separator; add a generic
button (optionally tagged with a widget type + data so it carries tooltip/action
semantics); create an edit box (with default text, char limits, enable/disable); create a
group of radio buttons and set each label; create a group of checkboxes and set each label
and checked state; launch the popup (optionally auto-adding a confirm button) in a given
queue state; mark cancelled; query "is dying".

### 6.3 Functional popup types
Text notice; main menu; confirm-menu; declare-war-to-move confirmation; confirm-command;
load-unit / lead-unit choosers; espionage mission and target choosers; choose-technology;
raze/disband-city; choose-production; change-policy; change-belief; choose-election;
diplomatic-vote; alarm; deal-cancelled notice; scripting popup and scripting full-screen;
game details; admin details and admin-password; extended-game prompt; diplomacy; add-buddy;
forced-disconnect / host-disconnect / kicked notices; subjugation tribute demand/grant;
event; free-colony; launch-victory; found-belief.

> ⚠️ **Provisional — Espionage mission menu** (`scenes/screens/espionage_menu.gd`):
> A modal overlay opened from the Espionage advisor screen when the player clicks
> "Select Mission vs. \<target\>…". Displays target alliance name, the player's
> current EP against that target, the mission cost (computed by
> `SimFacade.get_espionage_mission_cost()`), and the interception chance
> (`SimFacade.get_espionage_interception_chance()`). Offers three mission buttons —
> **Steal Tech**, **Sabotage**, **Incite Unrest** — each labelled with its EP cost
> and disabled when the player cannot afford it. An **Abort** button closes the
> popup without acting. Selecting a mission fires `Commands.espionage_mission` and
> invokes a rebuild callback on the parent screen. The popup is an alliance-scope
> action; spy-unit-on-tile mission verbs remain unbuilt (see §3 deferred items).

---

## 7. Selection and the active subject

The UI always has a current **subject**: either a unit/stack selection or a city selection.
The module/host contract provides:

* **Unit selection**: select a unit (clear/toggle/sound options); select a whole stack;
  select-all on a tile; insert/remove from the selection list; iterate the selection list;
  query head-selected unit; "mirrors a single stack?"; "can the selection found a
  settlement?"; goto/original/single-move target tiles; on-tile unit list paging (column/
  offset).
* **City selection**: select a city (optionally raising its screen); add/clear selected
  cities; iterate selected cities; query head-selected city; "is the city screen up?";
  set the active city tab.
* **Cycling helpers** the module implements for the host: cycle through cities forward/
  back; cycle through idle unit stacks (optionally workers only); cycle units stacked on a
  tile; "next active player".
* **Focus/camera**: look-at a tile/selection; center camera on a unit; lock/release camera;
  combat-focus toggle; mouse-over tile query.

---

## 8. Messages and notifications

Out-of-band feedback to the player, posted by the rules module and surfaced by the host:

* **Event/log messages**: a player-targeted message with text, a display duration, an
  optional sound, a message *category* (info/major/minor/combat/etc.), an optional icon,
  and optional on-/off-screen locator arrows pointing at a flashing tile coordinate.
  Specialized variants exist for combat results and quest updates.
* **Turn log**: a scrollable history of the above, with show/hide/dirty controls and a
  chat-target scope.
* **Talking-head / leader messages**: longer narrative messages shown with a portrait;
  can be flushed/cleared.
* **Combat log**: per-fight calculation and per-hit notifications emitted during combat so
  the host can show a running combat readout.
* **Map pings** and **signs**: transient attention markers placed on tiles, optionally
  shared with other players.

### 8.1 Facade signals (provisional)

> **⚠️ Provisional — implemented, names not verified.** The signal names below match the
> current `SimFacade` implementation (`src/api/sim_facade.gd`). They represent the engine's
> push interface: the host subscribes to these and reacts (rebuild HUD, show popup, etc.).
> Signal parameters are GDScript Dictionaries unless noted.

| Signal | Parameters | When emitted |
|--------|-----------|--------------|
| `event_emitted` | `event_dict` | Generic player-targeted notification (exploration reward, scripted event, etc.) |
| `turn_advanced` | `turn_number: int` | After the whole-world step completes and a new player's turn begins |
| `game_won` | `alliance_id: int` | When a win condition is satisfied |
| `unit_created` | `unit_id: int` | When a new unit is placed (production, draft, GP spawn) |
| `settlement_founded` | `settlement_id: int` | When a settler founds a city |
| `city_conquered` | `settlement_id, captor_player_id: int` | Settlement was captured and kept (enters revolt) — §4.8 |
| `city_razed` | `settlement_id, by_player_id: int` | Settlement was destroyed — §4.8 |
| `city_flipped` | `settlement_id, from_player_id, to_player_id: int` | Settlement changed hands via cultural pressure — §4.9 |
| `technology_completed` | `player_id, tech_id: int/String` | A player finishes researching a technology |
| `era_advanced` | `player_id, from_era, to_era: int` | A player's era increases — §2.1 |
| `combat_resolved` | `result_dict` | A combat round resolves (attacker/defender IDs, outcome, damage) |
| `player_turn_started` | `player_id: int` | At the start of each player's turn slot |
| `screen_requested` | `screen_id: int` | A `DO_CONTROL` command requests a screen to open (`IDs.ControlType`) |
| `assembly_event` | `event_dict` | Assembly session opened or resolution resolved — §7.2 |
| `nuclear_detonated` | `result_dict` | Nuclear strike resolved with area-effect — §5.7 |

The host connects these signals in its scene's `_ready()` and uses them to trigger dirty-flag
sets, popup pushes, notification appends, and one-shot visual effects (e.g. combat flash).

---

## 9. Explanatory / tooltip / help text

A defining UI responsibility of the rules module is **generating the human-readable text**
that explains game state, because only the rules know how derived numbers are computed.
The module exposes text-generation for:

* tooltips for every widget (§4) — especially the "breakdown" widgets that itemize how a
  derived quantity (contentment, wellbeing, finance, defense, production, culture,
  maintenance, etc.) was reached;
* hover/selection summaries for units, cities, tiles, and tradeable items;
* the encyclopedia entries and cross-reference links;
* prerequisite/obsolescence and effect descriptions for technologies, units, buildings,
  policies, beliefs, organizations, promotions, and terrain/features.

A clone must centralize this text generation in the rules layer (the UI asks, the rules
answer) so displayed explanations always match actual computation.

---

## 10. Display-gating state queries

The host decides *whether/which* HUD elements to show by asking the rules module a set of
boolean/enumeration queries each frame. Functional set:

* **End-turn button**: a tri-state indicator (ready / highlighted-waiting / dimmed) plus
  separate "should the end-turn button be shown", "should it show a return prompt", "show
  end-turn prompt", "waiting on others", "waiting on you".
* **HUD visibility**: should the flag be shown; should the unit model be shown; should
  research buttons be shown; should the minimap be centered.
* **Capability gates**: "can do control X" and "can handle action Y" (with an optional
  test-visible mode that reports actions the player *could* do if a prerequisite were met,
  for graying-out vs. hiding).
* **Tile presentation**: per-tile highlight color and the set of colored/blockaded tiles;
  the new highlight tile.
* **Globe overlays**: the list of available globe-overlay layers (each with a name,
  options, whether it requires globe view, and whether cities zoom) and per-tile layer
  data.
* **Right-click context (flyout) menu**: given a tile, the module returns a list of
  context-menu items (each an action id + label + target tile) and later applies the chosen
  item.
* **Minimap**: per-tile color by minimap mode (territory / terrain / replay / military).
* **Resource reveal**: resources whose `tech_required` field is non-null are hidden on
  the map (even on explored tiles) until the active player has researched that technology.
  Once revealed by tech, resources are further filtered by `TOGGLE_RESOURCES`. The
  `tech_required` check mirrors the same field used by `TileOutput.compute` to gate
  output — a resource the player cannot see is also a resource they cannot work.

---

## 11. Standard screens (functional inventory)

The full set of secondary windows the UI provides. Each is *functional* — the spec is what
data it shows and what actions it offers, not its layout:

* **Main HUD**: world view, minimap, selected-unit/stack panel with action buttons,
  selected-city summary, economic rate controls (three +/− rate rows plus the derived
  economy remainder), research indicator, turn/score indicators,
  message area, end-turn control. The selected-unit panel shows the unit's health and
  movement plus its **current state** — the standing order or stance it is under
  (fortified, sleeping, on sentry, healing, en route to a go-to target, or building an
  improvement; otherwise whether it still has moves this turn). This state text is produced
  by the rules layer (§9) so it always matches the order's actual semantics.
  *(⚠️ Provisional: the worker/fishing-boat action panel should only show build actions
  valid for the unit's current tile, the unit's domain (land vs sea), and the player's
  known technologies. Improvements built on resource tiles before the resource's
  `tech_required` is researched should only count the tile's base yields; once the tech
  is unlocked the improvement should apply the full resource bonus.
  Workers should keep building until the improvement is complete (per-turn decrement of
  `build_turns_left`); finished tiles should display a highlighted outline and show the
  improvement name when clicked/inspected.)*
* **City screen**: worked-tile assignment, production queue and chooser, citizen/specialist
  assignment, contentment/wellbeing/food/production/commerce breakdowns, building list,
  hurry/conscript controls, tabs (units / buildings / wonders), rename, city scroll.
  *(⚠️ Provisional: city screen should also display current health/siege HP
  (`settlement.health`) and a growth indicator (growing/shrinking/stable based on
  `food_store` vs per-population threshold).)*
* **Tech chooser** and **tech tree**: pick current research, see prerequisites/derived
  techs and what each unlocks.
* **Policy/civics screen**: view and switch governing policies; see effects and switch
  cost.
* **Belief / religion screen**: state-religion selection, list of founded beliefs with
  their spread and holy-site info. (`OPEN_RELIGION` → `religion_screen.gd`)
* **Corporation / organization screen**: list of founded economic organizations with
  spread and per-city income info. (`OPEN_CORPORATION` → `corporation_screen.gd`)
  *(provisional — content mirrors the religion screen structure)*
* **Diplomacy screen**: contact leaders, propose/respond to trades and agreements, see
  attitudes.
* **Advisor/info screens**:
  - *Domestic advisor* (`OPEN_DOMESTIC_ADVISOR`): settlement-by-settlement overview
    (population, production, happiness, tile yields). (`domestic_advisor_screen.gd`)
  - *Finance advisor* (`OPEN_FINANCE`): empire income/expense breakdown.
  - *Military advisor* (`OPEN_MILITARY`): list of all military units and their status.
  - *Espionage advisor* (`OPEN_ESPIONAGE`): accumulated EP per target alliance; a
    "Select Mission vs. \<target\>…" button (shown when EP ≥ mission cost) opens the
    ⚠️ provisional **Espionage mission menu** popup (§6.3) — displaying cost,
    interception risk, and the three mission options. (`espionage_screen.gd`,
    `espionage_menu.gd`)
  - *Victory progress* (`OPEN_VICTORY_PROGRESS`): per-condition progress bars for all
    enabled win conditions. (`victory_progress_screen.gd`)
  - *Turn log* (`OPEN_TURN_LOG`): scrollable history of all game events for the current
    session. (`turn_log_screen.gd`)
  - *Options* (`OPEN_OPTIONS`): in-game settings (sound, display, etc.).
* **Encyclopedia**: interactive tabbed reference covering units, structures, technologies,
  promotions, resources, and terrain — data pulled live from `DataDB`. Back/forward
  navigation. (`OPEN_ENCYCLOPEDIA` → `encyclopedia_screen.gd`)
* **Session/meta**: main menu, options, save/load, hall of fame, replay, game/admin
  details, world-builder/editor, advanced-start editor.
* **About / Controls** *(provisional — meta screens not in the design spec)*:
  - *About screen*: title, version, and license text. Reachable from the start menu and
    pause menu.
  - *Controls screen*: overview of all hotkeys and mouse bindings. Reachable from the
    pause menu.

#### 11.1 HUD advisor menu bar (provisional)

> **⚠️ Provisional — implemented, not in the original spec.** The advisor menu bar is an
> additional quality-of-life element added during implementation to make advisor screens
> discoverable without requiring F-key memorization.

A persistent row of buttons sits in the HUD (implemented in `scenes/hud/menu_bar.gd`),
one button per major advisor screen. Clicking a button fires the corresponding
`DO_CONTROL` command, identical to pressing the hotkey. The bar currently exposes:
Science (tech chooser), Civics (policy screen), Diplomacy, Finance, Military, Espionage,
Encyclopedia, Religion, Corporation, Turn Log, Domestic Advisor, and Victory Progress.
It is the recommended entry point for all advisor/info screens.

---

## 12. Reconstruction checklist

To duplicate the UI **functionality**:

1. **Refresh model** — a per-region invalidation flag set; rules set flags on state
   change, host rebuilds flagged regions each frame (§2).
2. **Command pipeline** — one validate→order→apply path for all intent, so MP/replay stays
   deterministic; expose capability queries for every command (§3).
3. **Four intent vocabularies** — controls, context actions, unit commands, unit missions
   (§3.1–3.3).
4. **Uniform widget dispatch** — `{type,data1,data2}` records routed to *help-text*,
   *action*, *alt-action*, *is-link* (§4).
5. **Targeting modes** — transient map-input modes with per-tile validity + cursor/
   highlight feedback (§5).
6. **Popup system** — a serialized queue, a descriptor in / result out contract, and a set
   of content primitives; the functional popup-type list (§6).
7. **Selection model** — current unit/stack or city subject, cycling helpers, camera/focus
   control (§7).
8. **Notifications** — targeted log messages with locator arrows, turn log, leader
   messages, combat log, pings/signs (§8).
9. **Centralized text generation** in the rules layer for all tooltips/breakdowns/
   encyclopedia/effect text (§9).
10. **Display-gating queries** — end-turn states, HUD visibility flags, capability gates,
    tile/globe/minimap presentation data, flyout menus (§10).
11. **Screen inventory** — the functional set of secondary windows (§11), with heavy
    screens optionally authored in a swappable scripting layer.

Everything visual — exact layout, art, color, font, sizing, animation, sound — is host
discretion and outside this contract.
