# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name NetProtocol

# The wire protocol for remote multiplayer. Pure static: it only builds and
# parses message Dictionaries / JSON strings — it never touches sockets, scenes,
# or GameState. This keeps the message format testable headlessly and shared
# verbatim by both the server (scenes/net/net_server.gd) and the client
# (scenes/net/net_client.gd).
#
# Every message is a JSON object: { "v": <protocol version>, "t": <type>, "d": <payload> }.
# The transport model is full-state handoff (see docs/design/network-design.md):
# the server holds the authoritative GameState; at the start of a remote player's
# turn the server pushes the whole serialized state ("state"), and at the end of
# the turn the client pushes its mutated state back ("submit"). No per-command
# replication is on the wire — only whole snapshots and small control frames.

const VERSION: int = 1

# ── Message types ──────────────────────────────────────────────────────────────
# Client → server
const HELLO: String = "hello"     # {name, player_id}  — join request (player_id -1 = any free slot)
const SUBMIT: String = "submit"   # {snapshot}         — post-turn full-state push
const BYE: String = "bye"         # {}                 — graceful disconnect

# Server → client
const WELCOME: String = "welcome" # {player_id, server_name, turn_number, players[]}
const REJECT: String = "reject"   # {reason}           — join refused (game full / bad version)
const STATE: String = "state"     # {snapshot, current_player_id, turn_number, active}
const WAIT: String = "wait"       # {current_player_id, current_player_name, turn_number}
const GAME_OVER: String = "over"  # {winning_alliance_id}
const ERROR: String = "error"     # {message}          — non-fatal notice (either direction)

# ── Encoding ───────────────────────────────────────────────────────────────────

# Build a complete wire frame Dictionary for the given type and payload.
static func make(msg_type: String, payload: Dictionary = {}) -> Dictionary:
	return {"v": VERSION, "t": msg_type, "d": payload}

# Serialize a frame to a JSON string ready to put on the socket.
static func encode(msg_type: String, payload: Dictionary = {}) -> String:
	return JSON.print(make(msg_type, payload))

# Parse a received JSON string into a frame Dictionary. On any malformed input
# (bad JSON, missing/typed-wrong fields, version mismatch) returns an empty
# Dictionary so callers can treat "{}" as "ignore this frame".
static func decode(text: String) -> Dictionary:
	var parsed: JSONParseResult = JSON.parse(text)
	if parsed.error != OK or not (parsed.result is Dictionary):
		return {}
	var frame: Dictionary = parsed.result
	if int(frame.get("v", -1)) != VERSION:
		return {}
	if not (frame.get("t", "") is String) or str(frame.get("t", "")) == "":
		return {}
	var data = frame.get("d", {})
	if not (data is Dictionary):
		data = {}
	return {"v": VERSION, "t": str(frame["t"]), "d": data}

# Convenience accessors so call sites do not repeat the get/cast dance.
static func type_of(frame: Dictionary) -> String:
	return str(frame.get("t", ""))

static func data_of(frame: Dictionary) -> Dictionary:
	var d = frame.get("d", {})
	return d if (d is Dictionary) else {}
