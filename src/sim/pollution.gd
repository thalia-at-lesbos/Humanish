# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Pollution

# Environmental degradation per §11.

# Accumulate pollution on tiles from settlements each turn.
static func accumulate(game_state) -> void:
	var db: DataDB = game_state.db
	for s in game_state.settlements:
		var tile: Tile = game_state.map.get_tile(s.x, s.y)
		if tile == null:
			continue
		var pop_pollution: int = s.population / 4
		var struct_pollution: int = 0
		for struct_id in s.structures:
			var struct: Dictionary = db.get_structure(struct_id)
			struct_pollution += int(struct.get("pollution", 0))
		tile.pollution += pop_pollution + struct_pollution

# Apply random degradation to polluted tiles. Consumes RNG draws.
static func degrade(game_state, rng: RNG) -> void:
	var db: DataDB = game_state.db
	var chance_scale: int = db.get_constant("pollution_degradation_chance", 5)
	for tile in game_state.map.all_tiles():
		if tile.pollution <= 0:
			continue
		var chance: int = min(50, tile.pollution * chance_scale / 10)
		if not rng.rand_bool_percent(chance):
			continue
		# Degrade: strip feature (vegetation), or shift terrain toward barren
		_degrade_tile(game_state, tile, db)

static func _degrade_tile(game_state, tile: Tile, db: DataDB) -> void:
	if tile.feature_id != "":
		# Strip vegetation feature first
		tile.feature_id = ""
		return
	var ter: Dictionary = db.get_terrain(tile.terrain_id)
	var domain: String = ter.get("domain", "land")
	if domain != "land":
		return
	# Flooding (§11): a heavily polluted flat tile beside water can flood and
	# become coast. Flat tiles are those not classed as hill/peak/mountain.
	# A tile hosting a settlement is NEVER flooded — a founded city sits on land,
	# and turning its tile to coast (sea domain) would strand the capital on water
	# (it cannot be re-founded there) and orphan its garrison. Degrade it toward
	# barren instead, like an inland tile.
	var landform: String = str(ter.get("landform", "flat"))
	var has_settlement: bool = game_state.get_settlement_at(tile.x, tile.y) != null
	if landform == "flat" and not has_settlement and _adjacent_to_water(game_state, tile, db):
		tile.terrain_id = "coast"
		tile.improvement_id = ""
		tile.owner_player_id = -1
		return
	# Otherwise shift terrain toward desert/barren
	match tile.terrain_id:
		"grassland": tile.terrain_id = "plains"
		"plains":    tile.terrain_id = "desert"
		"tundra":    tile.terrain_id = "snow"

static func _adjacent_to_water(game_state, tile: Tile, db: DataDB) -> bool:
	for nb in game_state.map.neighbours8(tile.x, tile.y):
		if db.get_terrain(nb.terrain_id).get("domain", "land") != "land":
			return true
	return false
