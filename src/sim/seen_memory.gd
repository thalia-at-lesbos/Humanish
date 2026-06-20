# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name SeenMemory
extends Reference

# §3/§fog — persistent per-player fog-of-war memory (pure static).
#
# Records, per player that needs fog, the set of tiles that player has *ever*
# seen plus a compact LAST-SEEN snapshot of each one. Currently-visible tiles
# render live from gs.map/gs.settlements; a previously-seen tile that has since
# left sight is rendered by the presentation layer from this snapshot instead —
# so the player keeps seeing the terrain/feature/improvement/transport/borders/
# settlement as they last observed them, but NOT live (out-of-sight) units.
#
# Data lives on GameState as `gs.seen_memory` and is the single serialized source
# of the "explored" set; the scene fog layer derives its explored set from this
# (via SimFacade.get_seen_memory), so revealed fog now survives save/load.
#
# Shape (pure plain Dictionaries/Arrays of ints/strings, JSON-safe):
#   gs.seen_memory[player_id (int)] = {
#       "x,y" (String): {                      # one entry per ever-seen tile
#           "terrain_id": String,
#           "feature_id": String,
#           "improvement_id": String,
#           "transport_id": String,
#           "owner_player_id": int,            # borders as last seen (-1 unowned)
#           "settlement_owner": int,           # -999 = no settlement remembered
#       },
#       ...
#   }
# The "x,y" tile keys are already strings (no JSON coercion needed); the outer
# player_id keys and the per-snapshot int fields ARE coerced back to int on
# deserialize (the JSON float/string-key gotcha) — see `deserialize`.

# Sentinel stored in a snapshot when the remembered tile carried no settlement.
const NO_SETTLEMENT: int = -999

# Commit the player's CURRENT visibility into their persistent memory: every tile
# in `visible_keys` ("x,y" → true) is marked seen and its snapshot overwritten
# with the tile's present state (and any settlement on it). Deterministic and
# order-free — called from the turn pipeline, never the scene, so the serialized
# state never depends on render timing.
static func commit_visible(gs, player_id: int, visible_keys: Dictionary) -> void:
	if gs == null or gs.map == null:
		return
	var mem: Dictionary = gs.seen_memory.get(player_id, {})
	for key in visible_keys:
		var parts: Array = key.split(",")
		if parts.size() != 2:
			continue
		var tx: int = int(parts[0])
		var ty: int = int(parts[1])
		var tile = gs.map.get_tile(tx, ty)
		if tile == null:
			continue
		var s = gs.get_settlement_at(tx, ty)
		mem[key] = {
			"terrain_id": tile.terrain_id,
			"feature_id": tile.feature_id,
			"improvement_id": tile.improvement_id,
			"transport_id": tile.transport_id,
			"owner_player_id": int(tile.owner_player_id),
			"settlement_owner": int(s.owner_player_id) if s != null else NO_SETTLEMENT,
		}
	gs.seen_memory[player_id] = mem

# The "x,y" → snapshot map for one player (empty Dictionary if none recorded).
static func for_player(gs, player_id: int) -> Dictionary:
	return gs.seen_memory.get(player_id, {})

# The last-seen snapshot for one tile, or an empty Dictionary if never seen.
static func snapshot(gs, player_id: int, x: int, y: int) -> Dictionary:
	var mem: Dictionary = gs.seen_memory.get(player_id, {})
	return mem.get(str(x) + "," + str(y), {})

# True if the player has ever seen the tile.
static func has_seen(gs, player_id: int, x: int, y: int) -> bool:
	var mem: Dictionary = gs.seen_memory.get(player_id, {})
	return mem.has(str(x) + "," + str(y))

# ── Serialization helpers ───────────────────────────────────────────────────────
# GameState owns the gs.seen_memory field directly; these mirror its (de)serialize
# so the int-coercion discipline lives next to the structure it protects.

static func serialize(seen_memory: Dictionary) -> Dictionary:
	# Snapshots are plain int/string dicts; a deep duplicate is enough.
	return seen_memory.duplicate(true)

static func deserialize(d) -> Dictionary:
	var out: Dictionary = {}
	if typeof(d) != TYPE_DICTIONARY:
		return out
	for pkey in d:
		# JSON makes the player_id key a String; coerce back to int so post-load
		# lookups by int player id still match.
		var pid: int = int(pkey)
		var tiles_in: Dictionary = d[pkey]
		var tiles_out: Dictionary = {}
		for tkey in tiles_in:
			# Tile keys are "x,y" strings — they survive the roundtrip unchanged.
			var snap = tiles_in[tkey]
			tiles_out[str(tkey)] = {
				"terrain_id": str(snap.get("terrain_id", "")),
				"feature_id": str(snap.get("feature_id", "")),
				"improvement_id": str(snap.get("improvement_id", "")),
				"transport_id": str(snap.get("transport_id", "")),
				"owner_player_id": int(snap.get("owner_player_id", -1)),
				"settlement_owner": int(snap.get("settlement_owner", NO_SETTLEMENT)),
			}
		out[pid] = tiles_out
	return out
