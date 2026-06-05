# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Regions

# Computes connected regions (land masses / water bodies) and supply groups.
# Regions: connected components of tiles sharing the same domain (land/sea).
# Supply groups: connected, same-owner, transport-linked subsets.

# Returns a Dictionary: tile_key -> region_id (int, 1-based)
# tile_key = "x,y"
static func compute_regions(map: WorldMap, db: DataDB) -> Dictionary:
	var region_map := {}
	var next_id := 1

	for tile in map.all_tiles():
		var key: String = _key(tile.x, tile.y)
		if region_map.has(key):
			continue
		var domain: String = db.get_terrain(tile.terrain_id).get("domain", "land")
		var flood := [tile]
		var visited := {key: true}
		while not flood.empty():
			var current: Tile = flood.pop_back()
			region_map[_key(current.x, current.y)] = next_id
			for nb in map.neighbours4(current.x, current.y):
				var nk: String = _key(nb.x, nb.y)
				if visited.has(nk):
					continue
				var nb_domain: String = db.get_terrain(nb.terrain_id).get("domain", "land")
				if nb_domain == domain:
					visited[nk] = true
					flood.append(nb)
		next_id += 1

	return region_map

# Supply groups: contiguous tiles owned by the same player that are connected
# via transport links. Returns Dictionary: tile_key -> group_id (int, 1-based)
static func compute_supply_groups(map: WorldMap, _db: DataDB) -> Dictionary:
	var group_map := {}
	var next_id := 1

	for tile in map.all_tiles():
		var key: String = _key(tile.x, tile.y)
		if group_map.has(key) or tile.owner_player_id < 0:
			continue
		if tile.transport_id == "" and tile.improvement_id != "road":
			continue
		var owner: int = tile.owner_player_id
		var flood := [tile]
		var visited := {key: true}
		while not flood.empty():
			var current: Tile = flood.pop_back()
			group_map[_key(current.x, current.y)] = next_id
			for nb in map.neighbours4(current.x, current.y):
				var nk: String = _key(nb.x, nb.y)
				if visited.has(nk):
					continue
				if nb.owner_player_id != owner:
					continue
				if nb.transport_id == "" and nb.improvement_id != "road":
					continue
				visited[nk] = true
				flood.append(nb)
		next_id += 1

	return group_map

static func _key(x: int, y: int) -> String:
	return str(x) + "," + str(y)
