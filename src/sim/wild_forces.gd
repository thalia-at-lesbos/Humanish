# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name WildForces

# Spawning of wildlife and raider forces per §9.
#
# Wild units are capped relative to the map's land area and only a few spawn per
# world step, gated by a single global roll. The previous implementation rolled
# a 15%+ chance on EVERY unclaimed land tile every turn, which flooded the map
# with hundreds of barbarian units (the "light grey squares" that piled up on
# screen each End Turn) and had no upper bound.

static func spawn_turn(game_state, rng: RNG) -> void:
	var db: DataDB = game_state.db

	# Gather unclaimed, passable, unoccupied land tiles and count the land budget.
	var land_tiles: int = 0
	var candidates: Array = []
	var wild_count: int = 0
	for u in game_state.units:
		if u.is_wild:
			wild_count += 1
	for tile in game_state.map.all_tiles():
		var ter: Dictionary = db.get_terrain(tile.terrain_id)
		if ter.get("domain", "land") != "land" or ter.get("impassable", false):
			continue
		land_tiles += 1
		if tile.owner_player_id >= 0:
			continue
		if not Stack.at(game_state.units, tile.x, tile.y).empty():
			continue
		candidates.append(tile)

	# Population cap: roughly one wild unit per N land tiles.
	var per_unit: int = int(db.constants.get("wild_land_per_unit", 80))
	var max_wild: int = land_tiles / per_unit
	if max_wild < 1:
		max_wild = 1
	if wild_count >= max_wild or candidates.empty():
		return

	# A few spawns per turn, each gated by one modest roll that creeps up slowly.
	var per_turn: int = int(db.constants.get("wild_spawn_per_turn", 2))
	var base_chance: int = int(db.constants.get("wild_spawn_base_chance", 30))
	var chance: int = base_chance + game_state.turn_number / 20
	if chance > 70:
		chance = 70

	var spawned: int = 0
	while spawned < per_turn and (wild_count + spawned) < max_wild and not candidates.empty():
		if not rng.rand_bool_percent(chance):
			break
		var idx: int = rng.randi_range(0, candidates.size() - 1)
		var t = candidates[idx]
		_spawn_wild_unit(t.x, t.y, game_state)
		candidates.remove(idx)
		spawned += 1

# Raider settlements spawn rarely and are likewise capped by land area.
static func spawn_raider_settlement(game_state, rng: RNG) -> void:
	var db: DataDB = game_state.db

	var land_tiles: int = 0
	var raider_camps: int = 0
	for s in game_state.settlements:
		if s.owner_player_id == -2:
			raider_camps += 1
	for tile in game_state.map.all_tiles():
		var ter: Dictionary = db.get_terrain(tile.terrain_id)
		if ter.get("domain", "land") == "land" and not ter.get("impassable", false):
			land_tiles += 1

	var per_camp: int = int(db.constants.get("raider_land_per_camp", 350))
	var max_camps: int = land_tiles / per_camp
	if max_camps < 1:
		max_camps = 1
	if raider_camps >= max_camps:
		return

	var chance: int = game_state.turn_number / 5
	if chance < 5:
		chance = 5
	if not rng.rand_bool_percent(chance):
		return

	for tile in game_state.map.all_tiles():
		if tile.owner_player_id >= 0:
			continue
		var ter: Dictionary = db.get_terrain(tile.terrain_id)
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
