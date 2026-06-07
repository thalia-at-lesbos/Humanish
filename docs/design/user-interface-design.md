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
* **HUD control groups**: economic-slider buttons, misc action buttons, the on-tile unit
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
* **Empire economy & research**: research selection, tech-tree node, change-economic-slider
  percentage, launch-victory project, religion conversion, score breakdown.
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

---

## 11. Standard screens (functional inventory)

The full set of secondary windows the UI provides. Each is *functional* — the spec is what
data it shows and what actions it offers, not its layout:

* **Main HUD**: world view, minimap, selected-unit/stack panel with action buttons,
  selected-city summary, economic sliders, research indicator, turn/score indicators,
  message area, end-turn control. The selected-unit panel shows the unit's health and
  movement plus its **current state** — the standing order or stance it is under
  (fortified, sleeping, on sentry, healing, en route to a go-to target, or building an
  improvement; otherwise whether it still has moves this turn). This state text is produced
  by the rules layer (§9) so it always matches the order's actual semantics.
* **City screen**: worked-tile assignment, production queue and chooser, citizen/specialist
  assignment, contentment/wellbeing/food/production/commerce breakdowns, building list,
  hurry/conscript controls, tabs (units / buildings / wonders), rename, city scroll.
* **Tech chooser** and **tech tree**: pick current research, see prerequisites/derived
  techs and what each unlocks.
* **Policy/civics screen**: view and switch governing policies; see effects and switch
  cost.
* **Belief / organization screens**: founded beliefs and organizations, spread, and
  state-belief selection.
* **Diplomacy screen**: contact leaders, propose/respond to trades and agreements, see
  attitudes.
* **Advisor/info screens**: domestic advisor, foreign relations, finance, military,
  espionage, victory progress, score breakdown.
* **Encyclopedia**: browsable reference for all game objects with cross-links and back/
  forward navigation.
* **Session/meta**: main menu, options, save/load, hall of fame, replay, game/admin
  details, world-builder/editor, advanced-start editor.

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
