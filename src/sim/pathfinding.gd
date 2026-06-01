class_name Pathfinding

# Shortest-path over movement costs (Dijkstra's algorithm).
# Movement costs are fixed-point (see fixed.gd). Domain legality is enforced.
# Guarantee: a unit can always move at least one tile per turn.

# Returns the path as an Array of [x, y] pairs from start (exclusive) to destination
# (inclusive), or an empty Array if no path exists within the unit's remaining movement.
static func find_path(map: WorldMap, from_x: int, from_y: int,
		to_x: int, to_y: int, unit: Unit, db: DataDB,
		all_units: Array, owner_player_id: int) -> Array:
	if from_x == to_x and from_y == to_y:
		return []

	var unit_data: Dictionary = db.get_unit(unit.unit_type_id)
	var domain: String = unit_data.get("domain", "land")

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

		for nb in map.neighbours4(cx, cy):
			var step_cost: int = _move_cost(nb, db, domain)
			if step_cost < 0:
				continue  # impassable
			if not _domain_legal(nb, domain, db):
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
	var base: int = int(ter.get("movement_cost", Fixed.MOVE_PRECISION))
	# Feature adds movement cost
	if tile.feature_id != "":
		var feat: Dictionary = db.get_feature(tile.feature_id)
		base += int(feat.get("movement_cost_add", 0))
	# Transport link reduces movement cost
	if tile.transport_id != "":
		var tr: Dictionary = db.transport.get(tile.transport_id, {}) if false else {}
		# Handled via improvement_id for roads
		pass
	if tile.improvement_id == "road":
		base = Fixed.MOVE_PRECISION / 3  # road: 1/3 movement
		base = max(1, base)
	return base

static func _domain_legal(tile: Tile, domain: String, db: DataDB) -> bool:
	var ter: Dictionary = db.get_terrain(tile.terrain_id)
	var tile_domain: String = ter.get("domain", "land")
	if domain == "land":
		return tile_domain == "land"
	if domain == "sea":
		return tile_domain == "sea" or tile_domain == "water"
	return true  # air can go anywhere

static func _has_enemy(x: int, y: int, all_units: Array, owner_id: int) -> bool:
	for u in all_units:
		if u.x == x and u.y == y and u.owner_player_id != owner_id:
			return true
	return false

static func _key(x: int, y: int) -> String:
	return str(x) + "," + str(y)
