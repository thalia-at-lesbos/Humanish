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

# Pathfinding (§1.2/§5.2): domain legality, impassable terrain, 8-direction
# diagonals, enemy/friendly destination rules, and zone-of-control halting.

func _grass(w, h):
	var m = load("res://src/world/world_map.gd").new()
	m.init(w, h, false, false)
	for tile in m.all_tiles():
		tile.terrain_id = "grassland"
	return m

func _bare_unit(type_id, pid, x, y):
	var u = load("res://src/sim/unit.gd").new()
	u.id = 0; u.unit_type_id = type_id; u.owner_player_id = pid
	u.x = x; u.y = y
	return u

# ── Basic paths ──────────────────────────────────────────────────────────────

func test_finds_straight_path() -> void:
	var gs = make_gs()
	var u = make_warrior(gs, 1, 0, 0)
	var path = Pathfinding.find_path(gs.map, 0, 0, 3, 0, u, gs.db, gs.units, 1)
	assert_false(path.empty(), "Path should exist on open grassland")
	var last = path[path.size() - 1]
	assert_eq([last[0], last[1]], [3, 0], "Path ends at the destination")

func test_open_field_returns_optimal_path() -> void:
	# An open grassland field produces a frontier full of equal-cost nodes — the
	# case that used to trip Array.sort()'s "bad comparison function" on [cost,x,y].
	var db = make_db()
	var map = _grass(8, 8)
	var u = _bare_unit("warrior", 1, 0, 0); u.id = 1
	var path = Pathfinding.find_path(map, 0, 0, 5, 3, u, db, [], 1)
	assert_false(path.empty(), "A path across open land must be found")
	var open_last = path[path.size() - 1]
	assert_eq([int(open_last[0]), int(open_last[1])], [5, 3], "Path must end at the destination")
	assert_eq(path.size(), 5, "Path length should be the Chebyshev distance max(5,3)")

func test_uses_diagonals() -> void:
	var gs = make_gs()
	var u = make_warrior(gs, 1, 5, 5)
	var path = Pathfinding.find_path(gs.map, 5, 5, 7, 7, u, gs.db, gs.units, 1)
	assert_eq(path.size(), 2, "Diagonal movement reaches (7,7) in two steps, not four")

# ── Blocking ─────────────────────────────────────────────────────────────────

func test_impassable_wall_blocks() -> void:
	var gs = make_gs()
	for y in range(20):
		gs.map.get_tile(5, y).terrain_id = "mountain"
	var u = make_warrior(gs, 1, 0, 10)
	var path = Pathfinding.find_path(gs.map, 0, 10, 10, 10, u, gs.db, gs.units, 1)
	assert_true(path.empty(), "Mountain wall should block path")

func test_sea_unit_cannot_walk_land() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "galley", 1, 0, 0)
	var path = Pathfinding.find_path(gs.map, 0, 0, 3, 0, u, gs.db, gs.units, 1)
	assert_true(path.empty(), "Naval unit cannot path through land")

# ── Enemy & friendly destinations ──────────────────────────────────────────────

func test_can_path_into_enemy_destination_but_not_through() -> void:
	var db = make_db()
	var map = _grass(8, 8)
	var attacker = _bare_unit("warrior", 0, 2, 2); attacker.id = 1
	var enemy = _bare_unit("warrior", 1, 3, 2); enemy.id = 2

	# A path INTO the enemy's tile (the destination) must be found...
	var into = Pathfinding.find_path(map, 2, 2, 3, 2, attacker, db, [attacker, enemy], 0)
	assert_false(into.empty(), "Should be able to path into an enemy destination (attack)")
	var into_last = into[into.size() - 1]
	assert_eq([int(into_last[0]), int(into_last[1])], [3, 2], "Attack path ends on the enemy tile")

	# ...but a through-route to a tile beyond must never step on the enemy tile.
	var through = Pathfinding.find_path(map, 2, 2, 4, 2, attacker, db, [attacker, enemy], 0)
	for step in through:
		assert_false(int(step[0]) == 3 and int(step[1]) == 2,
			"A through-route must not pass over the enemy-occupied tile")

func test_friendly_occupied_destination_is_legal() -> void:
	var db = make_db()
	var map = _grass(8, 8)
	var mover = _bare_unit("warrior", 0, 2, 2); mover.id = 1
	var friend = _bare_unit("warrior", 0, 3, 2); friend.id = 2
	var path = Pathfinding.find_path(map, 2, 2, 3, 2, mover, db, [mover, friend], 0)
	assert_false(path.empty(), "A friendly-occupied tile must be a legal destination")
	var friend_last = path[path.size() - 1]
	assert_eq([int(friend_last[0]), int(friend_last[1])], [3, 2], "Path ends on the friendly tile")

# ── Zone of control (§5.2) ───────────────────────────────────────────────────

func test_zone_of_control_halts_movement() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	# A two-wide land corridor on rows 5-6; everything else impassable mountain.
	for tile in gs.map.all_tiles():
		if tile.y != 5 and tile.y != 6:
			tile.terrain_id = "mountain"
	var u = make_warrior(gs, 1, 3, 5)
	u.movement_total = 1000; u.movement_left = 1000  # plenty to reach (12,5)
	make_warrior(gs, -2, 8, 6)  # wild unit beside the corridor at (8,6)
	f._cmd_move_stack({"player_id": 1, "from_x": 3, "from_y": 5, "to_x": 12, "to_y": 5})
	assert_eq(u.x, 7, "Unit halts on the tile adjacent to the hostile unit")
	assert_eq(u.movement_left, 0, "Zone of control spends remaining movement")
