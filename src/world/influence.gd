# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Influence

# Cultural influence accumulation and border ownership per §4.7.
# Each turn settlements add influence to nearby tiles weighted by 1/distance.
# The player with the most accumulated influence on a tile owns it.

# Add one turn of cultural spread from a settlement.
# cx, cy: settlement position
# culture_output: how much culture the settlement produces this turn
# range_rings: how many rings out influence spreads (from culture level thresholds)
# player_id: owning player
static func spread(map: WorldMap, cx: int, cy: int,
		culture_output: int, range_rings: int, player_id: int,
		db: DataDB) -> void:
	var decay: int = db.get_constant("influence_distance_falloff", 2)
	for ring in range(0, range_rings + 1):
		var tiles: Array
		if ring == 0:
			tiles = [map.get_tile(cx, cy)] if map.is_valid(cx, cy) else []
		else:
			tiles = map.ring_at_distance(cx, cy, ring)
		for tile in tiles:
			if tile == null:
				continue
			# Influence = culture_output / (decay^ring), minimum 1 if ring==0
			var amount: int
			if ring == 0:
				amount = culture_output
			else:
				amount = culture_output
				for _i in range(ring):
					amount = amount / decay
				amount = max(1, amount) if culture_output > 0 else 0
			if amount <= 0:
				continue
			if not tile.influence.has(player_id):
				tile.influence[player_id] = 0
			tile.influence[player_id] += amount

# Recompute ownership of all tiles based on accumulated influence.
# Tiles with no influence remain unowned (-1).
# Ties keep the current owner (no change).
# Wild forces (owner -2) claim tiles just like a civ does (their Raider Camp
# shows cultural borders); only the absence of *any* influence leaves a tile -1.
#
# Water reach cap (§4.7): culture cannot project indefinitely out to sea. A tile
# more than `culture_max_water_reach` tiles (Chebyshev) from the nearest land tile
# can never be culturally claimed, no matter how much influence reached it — so
# coastal borders stay close to shore. `db` is optional: when null (pure-map unit
# tests with no terrain) the cap is skipped. Land tiles are reach 0 and always
# eligible, so normal land expansion is unaffected.
static func resolve_ownership(map: WorldMap, db: DataDB = null) -> void:
	var water_reach: int = -1
	if db != null:
		water_reach = db.get_constant("culture_max_water_reach", 2)
	for tile in map.all_tiles():
		if tile.influence.empty():
			tile.owner_player_id = -1
			continue
		# Over-water reach cap: an ocean tile too far from land cannot be owned.
		if water_reach >= 0 and _too_far_from_land(map, db, tile, water_reach):
			tile.owner_player_id = -1
			continue
		var best_player: int = -1
		var best_val: int = 0
		var have_winner: bool = false
		for pid in tile.influence:
			var val: int = tile.influence[pid]
			if val > best_val:
				best_val = val
				best_player = pid
				have_winner = true
		if have_winner:
			tile.owner_player_id = best_player

# True when `tile` is a water/sea tile lying strictly more than `max_reach` tiles
# (Chebyshev) from the nearest land tile — i.e. culture should not project here.
# A land tile is reach 0 and is never "too far". The search is bounded to the
# (max_reach)-radius ring around the tile, so it is O(reach^2) per water tile.
static func _too_far_from_land(map: WorldMap, db: DataDB, tile: Tile, max_reach: int) -> bool:
	if db.get_terrain(tile.terrain_id).get("domain", "land") == "land":
		return false   # land itself is always claimable
	# Any land tile within max_reach rings ⇒ within reach.
	for r in range(1, max_reach + 1):
		for nb in map.ring_at_distance(tile.x, tile.y, r):
			if nb != null and db.get_terrain(nb.terrain_id).get("domain", "land") == "land":
				return false
	return true

# Immediately claim a radius of tiles for a new settlement (founding).
# This establishes the minimal initial border.
static func found_claim(map: WorldMap, cx: int, cy: int,
		player_id: int, radius: int, initial_influence: int, db: DataDB = null) -> void:
	for tile in map.tiles_in_range(cx, cy, radius):
		if tile == null:
			continue
		var dist: int = map.distance(cx, cy, tile.x, tile.y)
		var amount: int = max(1, initial_influence / max(1, dist + 1))
		if not tile.influence.has(player_id):
			tile.influence[player_id] = 0
		tile.influence[player_id] += amount
	resolve_ownership(map, db)
