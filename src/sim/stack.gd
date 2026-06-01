class_name Stack

# A Stack is an ephemeral grouping: all units on the same tile owned by the same
# player. This file provides helpers to query stacks from the unit list.

# Return all units at (x, y) owned by player_id.
static func at(units: Array, x: int, y: int, player_id: int = -1) -> Array:
	var result := []
	for u in units:
		if u.x == x and u.y == y:
			if player_id < 0 or u.owner_player_id == player_id:
				result.append(u)
	return result

# Return the defending unit (highest effective strength) at a tile, for a given attacker.
static func get_defender(units: Array, x: int, y: int, attacker_player_id: int,
		game_state) -> Unit:
	var best: Unit = null
	var best_str: int = -1
	var db: DataDB = game_state.db
	var ter: Dictionary = db.get_terrain(game_state.map.get_tile(x, y).terrain_id)
	var feat_id: String = game_state.map.get_tile(x, y).feature_id
	var feat: Dictionary = db.get_feature(feat_id) if feat_id != "" else {}
	for u in units:
		if u.x != x or u.y != y:
			continue
		if u.owner_player_id == attacker_player_id:
			continue
		var str_val: int = u.effective_strength(db, false, ter, feat, "")
		if str_val > best_str:
			best_str = str_val
			best = u
	return best

# Total strength of all units at a tile for a player.
static func total_strength(units: Array, x: int, y: int, player_id: int,
		db: DataDB, tile: Tile) -> int:
	var ter: Dictionary = db.get_terrain(tile.terrain_id)
	var feat: Dictionary = db.get_feature(tile.feature_id) if tile.feature_id != "" else {}
	var total: int = 0
	for u in units:
		if u.x == x and u.y == y and u.owner_player_id == player_id:
			total += u.effective_strength(db, false, ter, feat, "")
	return total

# Remove a unit by id from the array (in-place).
static func remove_unit(units: Array, unit_id: int) -> void:
	for i in range(units.size() - 1, -1, -1):
		if units[i].id == unit_id:
			units.remove(i)
			return
