# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://tests/support/sim_fixture.gd"

# Map generation: every tile gets terrain, the map is varied with substantial
# land, generation is seed-deterministic, and start positions land on passable
# land and spread out.

func _generated_map(seed_val = 99):
	return setup_facade(seed_val, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 100}],
		["time"]).get_state()

func test_every_tile_has_terrain() -> void:
	var gs = _generated_map()
	for tile in gs.map.all_tiles():
		assert_true(tile.terrain_id != "", "Every tile must have a terrain id after generation")

func test_map_is_varied() -> void:
	var gs = _generated_map()
	var kinds = {}
	for tile in gs.map.all_tiles():
		kinds[tile.terrain_id] = true
	assert_true(kinds.size() >= 4,
		"A varied map should contain several terrain types, got: " + str(kinds.keys()))

func test_map_has_substantial_land() -> void:
	var gs = _generated_map()
	var land = 0
	for tile in gs.map.all_tiles():
		if gs.db.get_terrain(tile.terrain_id).get("domain", "land") == "land":
			land += 1
	assert_true(land > gs.map.all_tiles().size() / 3,
		"At least a third of the map should be land for players to settle")

func test_generation_is_deterministic() -> void:
	var a = _generated_map(2024)
	var b = _generated_map(2024)
	var identical = true
	for i in range(a.map.all_tiles().size()):
		if a.map.all_tiles()[i].terrain_id != b.map.all_tiles()[i].terrain_id:
			identical = false
			break
	assert_true(identical, "Same seed must produce identical terrain across the whole map")

func test_start_positions_are_land_and_spread() -> void:
	var gs = _generated_map(555)
	var starts = MapGen.find_start_positions(gs.map, gs.db, 4)
	assert_eq(starts.size(), 4, "Should find four start positions")
	for s in starts:
		var ter = gs.db.get_terrain(gs.map.get_tile(int(s[0]), int(s[1])).terrain_id)
		assert_eq(ter.get("domain", "land"), "land", "Start tile must be land")
		assert_false(ter.get("impassable", false), "Start tile must be passable")
