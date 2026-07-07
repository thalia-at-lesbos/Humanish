# Humanish — Quick Start Guide

A turn-based empire-building strategy game for 2–4 players (human or AI).

---

## Installation

Unzip the archive for your platform and run the executable — no installer needed.

| Platform | Executable |
|----------|-----------|
| Linux    | `Humanish-linux-amd64` |
| Windows  | `Humanish-windows-amd64.exe` |
| macOS    | Open `Humanish-macos.app` inside the `.zip` |

Saves are stored in your user data folder:

| Platform | Path |
|----------|------|
| Linux    | `~/.local/share/godot/app_userdata/Humanish/saves/` |
| Windows  | `%APPDATA%\Godot\app_userdata\Humanish\saves\` |
| macOS    | `~/Library/Application Support/Godot/app_userdata/Humanish/saves/` |

---

## Starting a New Game

1. Click **New Game** on the title screen.
2. Choose the number of players (2–4), then fill each player row:
   - **Name** — anything you like.
   - **Society** — your civilization. Each has a unique leader trait that affects combat, growth, or economy. You can read the description before committing.
   - **Human / AI** — uncheck to let the computer play that slot.
3. Set world options:
   - **World size** — Duel (40×24) through Huge (160×100). Larger maps mean longer games.
   - **Map type** — Continents is a safe starting choice. See the [User Reference](user-reference.md) for the full list.
   - **Pace** — Standard is balanced. Slow or Marathon extend research and build times.
   - **Difficulty** — Prince is the recommended starting point for new players.
4. Click **Start Game**.

---

## The Game Screen at a Glance

```
┌─────────────────────────────────────────────────┐
│ Advisor bar (F1–F4 screens + score)             │
│ Research bar (current tech, progress)           │
│ Economy rates (Science / Culture / Espionage    │
│   via +/− buttons; Economy = the remainder)     │
├─────────────────────────────────────────────────┤
│                                                 │
│               Map (most of screen)              │
│                                                 │
├─────────────────────────────────────────────────┤
│ Selection panel (selected unit or city)         │
│ Message log (recent events)                     │
│                                 [End Turn]      │
└─────────────────────────────────────────────────┘
```

---

## Your First Turns

### Turn 1 — Settle

You begin with a **Settler** unit (and usually a **Warrior** escort).

1. **Right-click** a tile to move your Settler there, or use it where it stands if the terrain looks good.  
   Good founding sites have: grassland or plains nearby, a river or coast (fresh water speeds growth), and resources.
2. With the Settler selected, click **Found City** in the selection panel. Your first city appears.
3. Your city immediately starts producing — pick something from the production queue in the City Screen (**F** or double-click the city).

### Turn 2–5 — Explore and grow

- **Move units**: right-click the target tile. Multi-turn journeys remember their destination automatically.
- **Attack**: right-click an enemy unit's tile to initiate combat.
- **Left-click** any tile to inspect it (terrain yields, units, owner). Selecting one of your own units or a city also shows that tile's terrain in the selection panel.
- **Left-click** your own units or cities to select them.
- **Minimap**: click or drag anywhere on the minimap to recenter the main view there.
- Press **N** to jump to your next idle unit; press **E** (or click **End Turn**) when done.

### Research

Open the **Tech Tree** (F2) and pick a technology.  
The **Science** rate of your economy funds it each turn; the Research bar at the top shows progress.

### Cities

Double-click a city (or press **F3** while a city is selected) to open the **City Screen**, where you:

- Choose what to build (units, structures, wonders).
- Lock or unlock worked tiles around the city.
- Assign specialists (generates Great People over time).
- Toggle **Automate Citizens** to let the computer optimise tile assignments.

### Economy rates

You adjust three rates — **Science**, **Culture**, **Espionage** — with the **+/−** buttons on the HUD, in 10% steps.  
**Economy** (gold income) is shown next to them and is always the remainder: 100 minus the three.
A click that would push the total over 100 (or a rate below its minimum) is simply unavailable.

---

## Mouse Controls

| Action | How |
|--------|-----|
| Select a unit or city | Left-click its tile (the selection panel also shows that tile's terrain) |
| Inspect an empty or foreign tile | Left-click it |
| Move selected unit(s) | Right-click the destination tile |
| Attack an enemy | Right-click the enemy tile |
| Deselect | Left-click an empty tile |
| Recenter the map | Click (or drag) on the minimap |

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| **E** | End Turn |
| **N** | Next idle unit |
| **B** | Next idle worker |
| **C** | Centre camera on selection |
| **F1** | Encyclopedia |
| **F2** | Tech Tree |
| **F3** | Policy / Civics |
| **F4** | Diplomacy |
| **F5** | Quick Save |
| **F9** | Quick Load |
| **Escape** | Pause menu (Resume / Save / Load / New Game / Quit) |

---

## Winning

At game setup you choose which victory conditions are active. A game ends as soon as any
alliance achieves one of the enabled conditions:

| Victory | How to win |
|---------|-----------|
| **Conquest** | Eliminate every other alliance (no settlements or units remain). |
| **Domination** | Hold 66 % of land tiles *and* 66 % of population. |
| **Space Race** | Complete all seven spaceship stages (requires Apollo Program wonder). |
| **Cultural** | Bring three of your cities to Legendary culture (50,000 culture each). |
| **Diplomatic** | Win the United Nations election with 67 % of the vote. |
| **Time** | Have the highest score when the turn limit is reached. |

Track your progress in the **Victory Progress** screen (open from the advisor bar).

---

## Save and Load

- **F5** — Quick Save (overwrites `quicksave.sav` instantly).
- **F9** — Quick Load (restores the last quick save).
- **Escape → Save / Load** — the full save browser with named slots.
- **Title screen → Load Game** — resume any saved game without starting a new one.

---

## Multiplayer

Humanish supports online multiplayer via a dedicated server.

**Hosting (in-game):** Title screen → **Multiplayer Server** → configure port, player count, and save file → Start.

**Joining:** Title screen → **Multiplayer** → enter the host address and port → Connect.

**Headless server** (no GUI, for always-on hosting):

```bash
./run_server.sh --save=game.sav --players=3 --ai=1 --port=9080
```

The server auto-saves after every turn so nothing is lost if it restarts.

---

## Tips for New Players

- **Settle near fresh water** (rivers, coast, oasis) — it gives cities a growth bonus.
- **Keep at least one warrior per city** early on to deter raiders.
- **Don't ignore Culture**: high culture expands your borders and eventually flips nearby cities.
- **Research unlocks everything**: units, structures, improvements, and resources are all gated by technology.
- **Use the high ground**: a unit on hills sees one tile farther, and forests, jungle, hills, and mountains block your line of sight to what lies beyond them — scout from open or elevated terrain.
- **You can't cross the open ocean early**: coastal ships (Work Boat, Galley, Trireme) are stuck near the shore. Deep ocean tiles need an ocean-capable ship *and* the enabling technology (Optics) — though you may always sail through your own or an allied civilization's coastal waters.
- **Watch the advisor bar**: the Finance, Military, Domestic, and Espionage advisors surface actionable warnings.
- If an enemy city is close and well-cultured, your border tiles may start flipping to them — defend with cultural output or military pressure.
