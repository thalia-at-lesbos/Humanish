class_name WildForces

# Spawning of wildlife and raider forces per §9.

static func spawn_turn(game_state, rng: RNG) -> void:
	var db: DataDB = game_state.db
	var spawn_chance: int = 15 + game_state.turn_number / 10

	for tile in game_state.map.all_tiles():
		if tile.owner_player_id >= 0:
			continue  # only unclaimed tiles
		var ter: Dictionary = db.get_terrain(tile.terrain_id)
		if ter.get("domain", "land") != "land":
			continue
		if ter.get("impassable", false):
			continue
		if not Stack.at(game_state.units, tile.x, tile.y).empty():
			continue
		if rng.rand_bool_percent(spawn_chance):
			_spawn_wild_unit(tile.x, tile.y, game_state)

# Raider settlements spawn with increasing frequency
static func spawn_raider_settlement(game_state, rng: RNG) -> void:
	if rng.rand_bool_percent(max(5, game_state.turn_number / 5)):
		for tile in game_state.map.all_tiles():
			if tile.owner_player_id >= 0:
				continue
			var ter: Dictionary = game_state.db.get_terrain(tile.terrain_id)
			if ter.get("domain", "land") != "land" or ter.get("impassable", false):
				continue
			if Stack.at(game_state.units, tile.x, tile.y).empty():
				_spawn_raider_settlement(tile.x, tile.y, game_state)
				return

static func _spawn_wild_unit(x: int, y: int, game_state) -> void:
	var u := Unit.new()
	u.id = game_state.next_unit_id()
	u.unit_type_id = "warrior"
	u.owner_player_id = -2  # -2 = wild
	u.x = x; u.y = y
	var db: DataDB = game_state.db
	var unit_data: Dictionary = db.get_unit("warrior")
	u.base_strength = int(unit_data.get("base_strength", 5))
	u.movement_total = int(unit_data.get("movement", 200))
	u.movement_left = u.movement_total
	u.is_wild = true
	game_state.units.append(u)

static func _spawn_raider_settlement(x: int, y: int, game_state) -> void:
	var s := Settlement.new()
	s.id = game_state.next_settlement_id()
	s.name = "Raider Camp"
	s.owner_player_id = -2
	s.x = x; s.y = y
	s.population = 1
	game_state.settlements.append(s)
