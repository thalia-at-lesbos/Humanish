# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Pathfinding

# Shortest-path over movement costs (Dijkstra's algorithm).
# Movement costs are fixed-point (see fixed.gd). Domain legality is enforced.
# Guarantee: a unit can always move at least one tile per turn.

# Returns the path as an Array of [x, y] pairs from start (exclusive) to destination
# (inclusive), or an empty Array if no path exists within the unit's remaining movement.
static func find_path(map: WorldMap, from_x: int, from_y: int,
		to_x: int, to_y: int, unit: Unit, db: DataDB,
		all_units: Array, owner_player_id: int, game_state = null) -> Array:
	if from_x == to_x and from_y == to_y:
		return []

	var unit_data: Dictionary = db.get_unit(unit.unit_type_id)
	var domain: String = unit_data.get("domain", "land")

	# Deep-water (ocean) entry is gated (§5): a sea unit may only enter a
	# "deep_water" tile if it is ocean_capable AND its owner has researched the
	# ocean-travel tech — UNLESS the tile lies in friendly/allied territory (the
	# waiver). The context below is what _domain_legal consults to apply the rule;
	# it is null for callers that don't pass a game_state (domain-only legality).
	var ocean_ctx: Dictionary = {
		"ocean_capable": bool(unit_data.get("ocean_capable", false)),
		"owner_id": owner_player_id,
		"gs": game_state,
	}

	# Dijkstra: dist[key] = cost to reach that tile
	var dist := {}
	var prev := {}
	var heap := [[0, from_x, from_y]]  # [cost, x, y]

	var start_key: String = _key(from_x, from_y)
	dist[start_key] = 0

	while not heap.empty():
		# Extract the lowest-cost node with a linear scan. Sorting the heap with
		# Array.sort() would compare [cost, x, y] sub-arrays, which Godot cannot
		# order consistently ("bad comparison function; sorting will be broken").
		var best_i: int = 0
		for i in range(1, heap.size()):
			if heap[i][0] < heap[best_i][0]:
				best_i = i
		var node: Array = heap[best_i]
		heap.remove(best_i)
		var cost: int = node[0]
		var cx: int = node[1]
		var cy: int = node[2]
		var ck: String = _key(cx, cy)

		if cost > dist.get(ck, 999999):
			continue

		if cx == to_x and cy == to_y:
			break

		for nb in map.neighbours8(cx, cy):
			var step_cost: int = _move_cost(nb, db, domain)
			if step_cost < 0:
				continue  # impassable
			if not _domain_legal(nb, domain, db, ocean_ctx):
				continue
			if _has_enemy(nb.x, nb.y, all_units, owner_player_id):
				# Cannot pass THROUGH enemies, but the destination may hold one —
				# entering it is an attack, resolved by the move command.
				if not (nb.x == to_x and nb.y == to_y):
					continue
			var new_cost: int = cost + step_cost
			var nk: String = _key(nb.x, nb.y)
			if new_cost < dist.get(nk, 999999):
				dist[nk] = new_cost
				prev[nk] = [cx, cy]
				heap.append([new_cost, nb.x, nb.y])

	# Reconstruct path
	var dest_key: String = _key(to_x, to_y)
	if not prev.has(dest_key) and not (to_x == from_x and to_y == from_y):
		return []

	var path := []
	var cur_key: String = dest_key
	while cur_key != start_key:
		var pos: Array = cur_key.split(",")
		path.push_front([int(pos[0]), int(pos[1])])
		var parent: Array = prev.get(cur_key, [])
		if parent.empty():
			return []
		cur_key = _key(parent[0], parent[1])

	return path

# Movement cost to enter a tile (fixed-point units). Returns -1 if impassable.
static func _move_cost(tile: Tile, db: DataDB, domain: String) -> int:
	var ter: Dictionary = db.get_terrain(tile.terrain_id)
	if ter.get("impassable", false):
		return -1
	var base: int = int(ter.get("movement_cost", Fixed.MOVE_DENOMINATOR))
	# Feature adds movement cost
	if tile.feature_id != "":
		var feat: Dictionary = db.get_feature(tile.feature_id)
		base += int(feat.get("movement_cost_add", 0))
	# Route improvements (road/railroad) reduce the entered tile's cost to a flat
	# fraction of a tile (§5.2): the transport's movement_cost_divisor from
	# data/transport.json, applied to the move denominator so a road resolves to
	# an exact 1/divisor of a tile (road ÷3 = 20, railroad ÷100 → floored at 1).
	if tile.improvement_id != "" and db.transport.has(tile.improvement_id):
		var divisor: int = int(db.transport[tile.improvement_id].get("movement_cost_divisor", 1))
		if divisor > 1:
			base = Fixed.MOVE_DENOMINATOR / divisor
			if base < 1:
				base = 1
	return base

static func _domain_legal(tile: Tile, domain: String, db: DataDB, ocean_ctx = null) -> bool:
	var ter: Dictionary = db.get_terrain(tile.terrain_id)
	var tile_domain: String = ter.get("domain", "land")
	if domain == "land":
		return tile_domain == "land"
	if domain == "sea":
		if not (tile_domain == "sea" or tile_domain == "water"):
			return false
		# Coast (landform "water") is always enterable; only deep water is gated.
		if ter.get("landform", "") == "deep_water":
			return can_enter_deep_water(tile, db, ocean_ctx)
		return true
	return true  # air can go anywhere

# Whether a sea unit described by `ocean_ctx` may ENTER this deep_water tile (§5).
# ocean_ctx = {ocean_capable: bool, owner_id: int, gs: GameState|null}. When the
# context is missing (domain-only callers), entry is permitted so legacy/UI
# domain checks are unaffected — the gate is only enforced when a game_state is
# threaded in. Wild/ownerless units (owner_id < 0) skip the tech check.
static func can_enter_deep_water(tile: Tile, db: DataDB, ocean_ctx) -> bool:
	if ocean_ctx == null or not (ocean_ctx is Dictionary):
		return true
	var gs = ocean_ctx.get("gs", null)
	if gs == null:
		return true  # no world context to evaluate tech/ownership/alliance against
	var owner_id: int = int(ocean_ctx.get("owner_id", -1))
	# Waiver: the rule is lifted inside the mover's own cultural territory or that
	# of a same-alliance member. There is no "open borders" deal type in this
	# codebase, so alliance membership is used as the open-borders proxy (§5).
	if _tile_in_friendly_territory(tile, owner_id, gs):
		return true
	if not bool(ocean_ctx.get("ocean_capable", false)):
		return false
	# Wild/ownerless units (owner -2) have no player or tech: ocean_capable alone
	# lets them onto deep water, so skip the tech gate for them.
	if owner_id < 0:
		return true
	var player = gs.get_player(owner_id)
	if player == null:
		return false
	var tech: String = db.get_constant_str("ocean_travel_tech", "")
	if tech == "":
		return true  # no gating tech configured → ungated
	return player.has_tech(tech)

# True if `owner_id` owns this tile, or an alliance-mate of owner_id does (the
# open-borders proxy). owner_player_id == -1 means unowned.
static func _tile_in_friendly_territory(tile: Tile, owner_id: int, gs) -> bool:
	var tile_owner: int = tile.owner_player_id
	if tile_owner < 0:
		return false
	if tile_owner == owner_id:
		return true
	var alliance = gs.get_player_alliance(owner_id)
	if alliance == null:
		return false
	return tile_owner in alliance.member_player_ids

static func _has_enemy(x: int, y: int, all_units: Array, owner_id: int) -> bool:
	for u in all_units:
		if u.x == x and u.y == y and u.owner_player_id != owner_id:
			return true
	return false

static func _key(x: int, y: int) -> String:
	return str(x) + "," + str(y)
