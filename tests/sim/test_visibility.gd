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

# Terrain-aware visibility: the shared Visibility helper (sight bonus + LOS
# blocking). make_gs() lays a flat all-grassland map (no sight bonus, no
# blockers) so the base behaviour is a clean Manhattan radius; individual tests
# paint hills/forest to exercise the two terrain rules.

func _set_terrain(gs, x, y, terrain_id) -> void:
	gs.map.get_tile(x, y).terrain_id = terrain_id

func _set_feature(gs, x, y, feature_id) -> void:
	gs.map.get_tile(x, y).feature_id = feature_id

func _key(x, y) -> String:
	return str(x) + "," + str(y)

# ── Canary ──────────────────────────────────────────────────────────────────

func test_visibility_script_loads() -> void:
	assert_true(load("res://src/world/visibility.gd").can_instance(),
		"Visibility helper must compile")

# ── Sight bonus ───────────────────────────────────────────────────────────────

func test_flat_source_sees_base_manhattan_radius() -> void:
	var gs = make_gs(1)
	var seen = Visibility.visible_tiles(gs.map, gs.db, 10, 10, 2)
	# A tile at Manhattan distance == base radius is visible (clear line).
	assert_true(seen.has(_key(12, 10)), "Flat source sees out to the base radius")
	# A tile one past the radius is not.
	assert_false(seen.has(_key(13, 10)), "Flat source does not see beyond the base radius")

func test_hills_source_sees_one_ring_farther() -> void:
	var gs = make_gs(1)
	_set_terrain(gs, 10, 10, "hills")   # sight_bonus 1
	var seen = Visibility.visible_tiles(gs.map, gs.db, 10, 10, 2)
	assert_true(seen.has(_key(13, 10)),
		"Hills (sight_bonus 1) extend the visible radius by one tile")
	assert_false(seen.has(_key(14, 10)),
		"…but only by one tile")

# ── LOS blocking ──────────────────────────────────────────────────────────────

func test_blocker_hides_clear_line_tile_behind_it() -> void:
	# Forest at distance 2 east; the tile directly behind it (distance 3) must be
	# hidden, while a tile at distance 3 on a clear line stays visible.
	var gs = make_gs(1)
	_set_feature(gs, 12, 10, "forest")          # blocker two tiles east
	var seen = Visibility.visible_tiles(gs.map, gs.db, 10, 10, 4)
	assert_true(seen.has(_key(12, 10)), "The blocker itself is visible (near face)")
	assert_false(seen.has(_key(13, 10)),
		"A tile directly behind the blocker is occluded")
	# A clear line in another direction at the same distance is still visible.
	assert_true(seen.has(_key(13, 11)),
		"An unobstructed tile at the same distance stays visible")

func test_mountain_terrain_blocks_line_of_sight() -> void:
	var gs = make_gs(1)
	# Blocker at distance 2 (outside the always-visible adjacency ring).
	_set_terrain(gs, 12, 10, "mountain")
	var seen = Visibility.visible_tiles(gs.map, gs.db, 10, 10, 4)
	assert_false(seen.has(_key(14, 10)),
		"Mountain (blocks_sight) occludes the tiles in line behind it")

func test_jungle_feature_blocks_line_of_sight() -> void:
	var gs = make_gs(1)
	_set_feature(gs, 12, 10, "jungle")
	var seen = Visibility.visible_tiles(gs.map, gs.db, 10, 10, 4)
	assert_false(seen.has(_key(14, 10)),
		"Jungle (blocks_sight feature) occludes tiles in line behind it")

# ── Adjacency is always visible ───────────────────────────────────────────────

func test_adjacent_tiles_always_visible_even_with_blockers() -> void:
	var gs = make_gs(1)
	# Ring the source in blockers; every neighbour (Chebyshev 1) must still show.
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			_set_terrain(gs, 10 + dx, 10 + dy, "hills")   # hills block sight
	var seen = Visibility.visible_tiles(gs.map, gs.db, 10, 10, 2)
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			assert_true(seen.has(_key(10 + dx, 10 + dy)),
				"Source and all eight neighbours stay visible through adjacent blockers")

func test_source_tile_always_visible() -> void:
	var gs = make_gs(1)
	_set_terrain(gs, 10, 10, "mountain")
	var seen = Visibility.visible_tiles(gs.map, gs.db, 10, 10, 2)
	assert_true(seen.has(_key(10, 10)), "The source tile is always visible")

# ── Determinism ───────────────────────────────────────────────────────────────

func test_visibility_is_deterministic() -> void:
	var gs = make_gs(1)
	_set_terrain(gs, 11, 11, "hills")
	_set_feature(gs, 9, 9, "forest")
	var a = Visibility.visible_tiles(gs.map, gs.db, 10, 10, 3)
	var b = Visibility.visible_tiles(gs.map, gs.db, 10, 10, 3)
	assert_eq(a.size(), b.size(), "Same inputs yield the same visible set size")
	for k in a:
		assert_true(b.has(k), "Visible set is identical across calls")
