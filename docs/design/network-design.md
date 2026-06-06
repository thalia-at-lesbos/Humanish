# Network Design — Remote Multiplayer

How Humanish plays over the internet. This covers the transport choice, the
message protocol, the turn model, and how server and client modes are launched.

The guiding constraint: **simple for Godot 3, and transparent across the public
internet** — no UDP hole-punching, no NAT traversal, no client-side firewall
rules. Only the server's single listen port must be reachable, the same routing
concession any web service makes.

---

## At a glance

```
            ws:// (TCP, one port)
  ┌────────────┐   STATE  ───────────▶ ┌────────────┐
  │  Client A  │                        │            │   authoritative
  │ (desktop,  │   ◀───────  SUBMIT     │   Server   │   SimFacade
  │  windowed) │                        │ (headless, │   (the one true
  └────────────┘                        │  windowless)│    GameState)
  ┌────────────┐                        │            │
  │  Client B  │  …                     │  + AI slots │
  └────────────┘                        └────────────┘
```

* The **server** runs the same engine windowless and holds the *one*
  authoritative `GameState`. It plays any AI slots itself and relays turns
  between human clients.
* A **client** is an ordinary windowed game whose `SimFacade` is fed whole-state
  snapshots by the server. It plays its own turn locally, then pushes the
  resulting snapshot back.
* The model is **full-state handoff**, **round robin**. No per-command
  replication is on the wire — only whole `GameState` snapshots and small
  control frames.

---

## Transport: WebSocket

Godot 3 ships `WebSocketServer` and `WebSocketClient` with the engine — no add-on
or external library. WebSocket runs over a single **TCP** port, so:

* Clients make ordinary **outbound** TCP connections, which pass through home
  routers and NAT untouched — no port-forwarding or firewall exceptions on the
  client side.
* Only the server exposes a port (default **9080**), exactly like any web
  service. It can sit behind a normal reverse proxy and, in a later pass, be
  upgraded to `wss://` (TLS) for encryption with no protocol changes.
* TCP gives ordered, reliable delivery, which is what a turn-based full-state
  sync wants (a snapshot must arrive whole and in order). UDP/ENet's
  unreliability and its tendency to be filtered by firewalls buy us nothing here.

Both sides widen the WebSocket frame buffers before connecting
(`set_buffers`, see `BUF_KB` in `net_server.gd`/`net_client.gd`): a full
serialized `GameState` is far larger than the default frame buffer, and the
engine raises `ERR_OUT_OF_MEMORY` on send if the buffer cannot hold the packet.

---

## The wall still holds

Networking is **presentation/transport**, exactly like the UI and `PlayerAI`. It
never lives in `src/sim/` or `src/world/`, and the rule code never references it.
Every server and client touches the engine **only** through `SimFacade`:

| Concern | Lives in | Layer |
|---|---|---|
| Wire format (encode/decode, message types) | `src/net/net_protocol.gd` | pure (`Reference`, no sockets) |
| Server command-line parsing | `src/net/net_config.gd` | pure (`Reference`, no sockets) |
| Authoritative server (transport + turn loop) | `scenes/net/net_server.gd` | client-of-facade (`Reference`) |
| Headless server entry point | `scenes/net/server_runner.gd` | `SceneTree` main loop |
| Client transport + in-game glue | `scenes/net/net_client.gd` | client-of-facade (`Node`) |
| Client lobby UI | `scenes/net/multiplayer_setup.gd` | `Control` |

The only seam added to the engine is on `SimFacade`
(`set_remote_submit_handler` / `set_remote_waiting`): a remote client's
end-of-turn is intercepted and handed to the network instead of running the
local pipeline. That seam is pure presentation wiring (a `FuncRef` into the
client object) and is **not serialized** — sim/world never see it.

---

## Message protocol

Every frame is a JSON object: `{ "v": <version>, "t": <type>, "d": <payload> }`,
built and parsed by `NetProtocol` (pure static, fully unit-tested in
`tests/net/test_net_protocol.gd`). `decode()` returns `{}` for anything
malformed or version-mismatched, so callers treat an empty frame as "ignore".

| Type | Direction | Payload | Meaning |
|---|---|---|---|
| `hello`   | client → server | `{name, player_id}` | Join request (`player_id` −1 = any free slot) |
| `welcome` | server → client | `{player_id, server_name, turn_number, players[]}` | Slot assigned |
| `reject`  | server → client | `{reason}` | Join refused (game full / version) |
| `state`   | server → client | `{snapshot, current_player_id, turn_number, active}` | Full state; `active` = your turn |
| `wait`    | server → client | `{current_player_id, current_player_name, turn_number}` | Someone else is playing |
| `submit`  | client → server | `{snapshot}` | Post-move full-state push at end of turn |
| `over`    | server → client | `{winning_alliance_id}` | Game ended |
| `bye`     | client → server | `{}` | Graceful disconnect |
| `error`   | either | `{message}` | Non-fatal notice |

`snapshot` is the exact string from `SimFacade.save()` — i.e. `SaveLoad`'s JSON
output, embedded as a string inside the frame. The shared RNG state travels
inside it (serialized as strings, per the engine invariant), so stochastic
results that happened on a client during its turn carry over to the server
verbatim.

---

## Turn model: full-state handoff, round robin

The authoritative game lives on the server. One turn:

```
            ┌─────────────────────── server (authoritative facade) ───────────────────────┐
            │                                                                              │
 current player is AI ─▶ PlayerAI.take_turn(facade, id)  ──┐  (ends turn, advances)        │
            │                                              └─▶ loop: re-check current ──────┤
 current player is a connected remote human:                                               │
            │   send STATE(active=true) to that client ─────────────────────────────┐      │
            │   send WAIT to the others                                              │      │
            └────────────────────────────────────────────────────────────────────┐ │      │
                                                                                  ▼ ▼      │
   client: loads snapshot ▶ plays via apply_command(...) ▶ presses End Turn         │      │
           │ SimFacade intercepts End Turn → NetClient.submit_turn()                │      │
           └─▶ SUBMIT { snapshot = facade.save() }  ───────────────────────────────▶│      │
                                                                                    │      │
   server: load_save(snapshot) ▶ apply_command(end_turn) ▶ _drive() again ──────────┘      │
            └──────────────────────────────────────────────────────────────────────────────┘
```

Key points:

* **Clients run only their own turn.** Their moves (including combat, which draws
  from the shared RNG) happen locally; the post-move snapshot captures the
  result. The client never advances the turn counter — pressing End Turn is
  intercepted by the facade seam and turned into a `SUBMIT`.
* **The server owns the pipeline.** On receiving `SUBMIT` it adopts the snapshot
  (`load_save`), then runs the authoritative `apply_command(end_turn)` — so
  `player_step`, `world_step`, win checks, and AI turns all execute on the
  server. This keeps a single source of pipeline truth.
* **The driver (`_drive()`) is the one place turn *policy* lives.** It walks the
  round robin: play AI slots, then park on the first connected remote human and
  push them the state. An unclaimed remote slot holds the game until its client
  connects.
* **Bootstrap & re-sync.** On `hello` the server sends a `welcome` plus an
  initial `state` (so even a waiting client can render the world), then drives.
  A client that disconnects and reconnects with the same `player_id` is re-sent
  the current state.

### Trust model

Full-state handoff trusts each client to submit an honest snapshot — appropriate
for a friendly/co-op async game. There is no validation that a client only moved
its own pieces. Hardening (a server-side state diff/whitelist, or switching to
**command replication** where the client sends its command list and the server
replays them) is future work; the protocol already isolates this behind the
`submit` message so the change would not touch the UI.

---

## Autosave

The server **autosaves the authoritative game to disk after every turn**, so a
crash or restart loses at most the turn in progress (and a saved game can be
resumed with `--load`). `NetServer` connects to the facade's
`player_turn_started` signal — which fires on every turn transition, from both
human `submit`s and the AI turns the server plays — and writes `facade.save()`
to the configured file. It also writes the opening state at `listen()`. A bare
save name lands under the user saves dir (`user://saves/`); a name containing a
`/` is used as a full path. Because of this, **a default save file is
mandatory**: the CLI rejects `--server` without `--save`, and the GUI host
screen requires a save-file name.

## Server mode — headless (command line)

The headless server has **no UI**. It is the engine run windowless as a
`SceneTree` main loop — `scenes/net/server_runner.gd` — which never loads the
menu or any scene: it builds `DataDB` + a `SimFacade`, stands up `NetServer`, and
polls the socket on every `idle_frame`.

```bash
# 2-player game, port 9080, server plays no slots, autosaving to game.sav:
./run_server.sh --save=game.sav

# 3 slots, server plays 1 AI, on a small continents map:
./run_server.sh --save=game.sav --players=3 --ai=1 --world=small --map=continents

# resume an authoritative save, autosaving onward to ongoing.sav:
./run_server.sh --save=ongoing.sav --load=/path/to/game.sav --port=9000
```

`run_server.sh` is a thin wrapper over:

```bash
godot3 --no-window -s res://scenes/net/server_runner.gd -- --server --save=<file> [flags…]
```

Flags are parsed by `NetConfig.parse_args` (pure, tested in
`tests/net/test_net_config.gd`); `NetConfig.server_config_error` enforces the
`--save` requirement. Both `--flag value` and `--flag=value` forms work; unknown
flags (like the engine's own `--no-window`) are ignored.

| Flag | Default | Meaning |
|---|---|---|
| `--server` | — | Enable server mode (implied by `run_server.sh`) |
| `--save=PATH` | **required** | File the game autosaves to every turn (bare name → saves dir; `/` → full path) |
| `--port=N` | 9080 | Listen port |
| `--name=STR` | "Humanish Server" | Name sent in `welcome` |
| `--load=PATH` | — | Resume from a `.sav` instead of a new game |
| `--players=N` | 2 | Total player slots |
| `--ai=N` | 0 | How many slots the server plays (clamped to `[0, players]`) |
| `--world=ID` | tiny | World-size id |
| `--map=ID` | continents | Map-type id |
| `--pace=ID` | normal | Pace id |
| `--difficulty=ID` | warlord | Difficulty id |
| `--seed=N` | random | RNG seed |

For a new game the first `players − ai` slots are **remote-human** slots that
clients fill; the remainder are **AI** slots the server plays.

## Server mode — in-game host

The start menu's **Multiplayer Server** button opens
`scenes/net/server_setup.gd`, which runs an authoritative `NetServer` *inside the
desktop app* (no separate process). The host:

1. sets the port, server name, and a **save file** (defaults to `mp_server.sav`),
2. chooses **New Game…** — which reuses the normal `SetupScreen` to pick
   players / society / per-player AI toggles / world / map / pace / difficulty —
   **or** **Load Saved Game…** to pick an existing `.sav`,
3. and the screen becomes a live **status panel** (port, autosave path, current
   turn, and each player's slot state: AI / connected / waiting) with a **Stop
   Server** button.

The host screen polls the `NetServer` each `_process` frame (the GUI equivalent
of the headless runner's `idle_frame` poll). The server holds and relays state
only — there is no game board on the host; remote players join with the
**Multiplayer** client menu exactly as they would against a headless server.

---

## Client mode (in-game menu)

The start menu gains a **Multiplayer** button (alongside New Game / Load Game),
which opens `scenes/net/multiplayer_setup.gd`: a small lobby collecting server
host, port, and player name. On **Connect** it creates a `NetClient`, opens the
WebSocket, and waits.

When the first `state` snapshot arrives, the `NetClient` builds a `SimFacade`
(`init_for_load` + `load_save`), installs itself as that facade's remote-submit
handler, and emits `game_ready`. The `StartMenu` then reparents the live
`NetClient` into `main.tscn` and hands over the facade — exactly the same scene
swap as the New Game and Load Game flows. From there:

* `main.gd` wires `NetClient.state_synced` → re-fog and re-center for *our*
  player and repaint (the client's equivalent of "your turn begins"; the
  `HotseatManager` pass-device flow does not run in remote play).
* The HUD End Turn button and the End Turn hotkey both route through the facade
  seam to `NetClient.submit_turn`, which pushes the snapshot and parks the turn
  (the button reads "Waiting…" until the next `state`).

---

## File map

```
src/net/
  net_protocol.gd     pure wire format: message types, encode/decode (NetProtocol)
  net_config.gd       pure server command-line parsing (NetConfig)
scenes/net/
  net_server.gd       authoritative server: WebSocketServer + round-robin turn loop
  server_runner.gd    headless SceneTree entry point (-s target)
  net_client.gd       client WebSocketClient + in-game facade glue (Node)
  multiplayer_setup.gd client lobby Control (the "Multiplayer" join menu)
  server_setup.gd     in-game host Control (the "Multiplayer Server" menu):
                      new-game/load config + running-server status panel
tests/net/
  test_net_protocol.gd, test_net_config.gd   CI unit suites (pure layers)
tests/manual/
  loopback_smoke.gd   manual end-to-end NetServer↔NetClient harness (not in CI)
run_server.sh         convenience launcher for the headless server
```

### Testing

* The **pure layers** (`NetProtocol`, `NetConfig`) and the **facade seam**
  (`tests/api/test_sim_facade_remote.gd`) run in the normal CI unit gate.
* The **live socket path** is exercised by `tests/manual/loopback_smoke.gd`
  (run by hand): it spins up an in-process server (1 remote + 1 AI player),
  connects one client, and submits turns, asserting the turn counter advances as
  the server runs the pipeline. It is kept out of CI because real sockets and
  frame-yields would make a headless gate flaky.

```bash
godot3 --no-window -s res://tests/manual/loopback_smoke.gd   # prints "SMOKE: PASS"
```

---

## Future work

* **Simultaneous turns.** Today `_drive()` advances on each client's `submit`
  (round robin). Simultaneous play means collecting *every* active client's
  `submit` for the turn, then resolving once. The driver is the single seam where
  this policy lives; the protocol (snapshots + `submit`) is unchanged, though
  conflict resolution between concurrent moves becomes the new design problem.
* **Command replication / anti-cheat.** Replace whole-snapshot trust with a
  client→server command list the server replays, validating each command's
  owner. Isolated behind the `submit` message.
* **Encryption.** Move to `wss://` (TLS); WebSocket makes this transparent.
* **Reconnection & lobby UX.** Persisted player identity, a proper pre-game
  lobby with ready states, and spectator slots.
* **Save cadence.** *(Done — per-turn autosave; see Autosave above.)* Possible
  refinements: rotating/timestamped save slots instead of one overwritten file,
  and throttling on very large maps if per-turn writes become costly.
```
