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

# ── Wrap-x pathfinding ──────────────────────────────────────────────────────

func test_pathfinding_wraps_east_west_seam() -> void:
	# On a wrap_x map, a unit at column 1 should find a short path to (width-1)
	# going west through column 0→(width-1) rather than all the way east.
	var db = make_db()
	var m = load("res://src/world/world_map.gd").new()
	m.init(10, 6, true, false)  # wrap_x=true, 10 wide
	for t in m.all_tiles():
		t.terrain_id = "grassland"
	var u = _bare_unit("warrior", 1, 1, 2); u.id = 1
	# From (1,2) to (9,2): direct east path = 8 steps; wrap path = 2 steps (via col 0)
	var path = Pathfinding.find_path(m, 1, 2, 9, 2, u, db, [], 1)
	assert_false(path.empty(), "Wrap-x: path must exist from col 1 to col 9")
	var last = path[path.size() - 1]
	assert_eq([int(last[0]), int(last[1])], [9, 2], "Path ends at destination")
	# The shortest wrap path should be 2 steps (1→0→9), not 8 steps going east
	assert_eq(path.size(), 2, "Wrap-x: shortest path through seam is 2 steps, not 8")

# ── Movement costs & the denominator (§5.2) ──────────────────────────────────

func test_road_costs_one_third_tile_at_denom_60() -> void:
	var gs = make_gs()
	var t = gs.map.get_tile(5, 5)
	t.terrain_id = "grassland"; t.feature_id = ""; t.improvement_id = "road"
	var cost: int = Pathfinding._move_cost(t, gs.db, "land")
	assert_eq(cost, Fixed.MOVE_DENOMINATOR / 3, "Road resolves to exactly 1/3 tile (20)")
	assert_eq(cost, 20, "Road = 20 fixed units at MOVE_DENOMINATOR 60")

func test_open_terrain_costs_one_full_tile() -> void:
	var gs = make_gs()
	var t = gs.map.get_tile(5, 5)
	t.terrain_id = "grassland"; t.feature_id = ""; t.improvement_id = ""
	assert_eq(Pathfinding._move_cost(t, gs.db, "land"), Fixed.MOVE_DENOMINATOR,
		"Open grassland costs one full tile (60)")

func test_two_move_unit_crosses_three_road_tiles() -> void:
	# A 2-tile unit (120 units) on a road (20/tile) can cross many tiles; with the
	# always-move-at-least-one guarantee it never stalls. Here it reaches a 3-tile
	# road destination well within its allowance.
	var gs = make_gs()
	var f = bare_facade(gs)
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
		tile.feature_id = ""
		tile.improvement_id = "road"
	var u = make_warrior(gs, 1, 3, 5)  # movement_total = 120
	gs.current_player_id = 1
	f._cmd_move_stack({"player_id": 1, "from_x": 3, "from_y": 5, "to_x": 6, "to_y": 5})
	assert_eq([u.x, u.y], [6, 5], "A 2-move unit crosses 3 road tiles (3×20 = 60 ≤ 120)")

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

# ── Deep-water (ocean) entry gating (§5) ─────────────────────────────────────
#
# Rule: to ENTER a deep_water (ocean) tile a sea unit must be ocean_capable AND
# its owner must have researched the ocean_travel_tech (optics). Waiver: the rule
# is lifted inside the mover's own (or an alliance-mate's) cultural territory.
# Coast (landform "water") is always enterable; wild/ownerless units skip the
# tech check. find_path must route around an illegal ocean tile.

# A water world: column x=0 is coast (always enterable), columns x>=1 are ocean.
func _sea_gs(num_players = 2):
	var gs = make_gs(num_players)
	for tile in gs.map.all_tiles():
		tile.terrain_id = "coast" if tile.x == 0 else "ocean"
	return gs

func test_coastal_unit_cannot_enter_ocean() -> void:
	# A galley (coastal_only, no ocean_capable flag) starts on coast at (0,5) and
	# tries to reach ocean at (2,5). No legal path onto deep water.
	var gs = _sea_gs()
	var u = make_unit(gs, "galley", 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 2, 5, u, gs.db, gs.units, 1, gs)
	assert_true(path.empty(), "A coastal galley cannot path onto ocean")

func test_ocean_unit_without_tech_cannot_enter_neutral_ocean() -> void:
	# A caravel is ocean_capable but its owner lacks optics → still gated.
	var gs = _sea_gs()
	gs.get_player(1).technologies = []  # no optics
	var u = make_unit(gs, "caravel", 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 2, 5, u, gs.db, gs.units, 1, gs)
	assert_true(path.empty(), "An ocean-capable hull without optics cannot enter neutral ocean")

func test_ocean_unit_with_tech_can_enter_ocean() -> void:
	var gs = _sea_gs()
	gs.get_player(1).technologies = ["optics"]
	var u = make_unit(gs, "caravel", 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 2, 5, u, gs.db, gs.units, 1, gs)
	assert_false(path.empty(), "An ocean-capable hull with optics enters ocean")
	var last = path[path.size() - 1]
	assert_eq([int(last[0]), int(last[1])], [2, 5], "Path reaches the ocean destination")

func test_waiver_own_territory_lets_coastal_unit_onto_ocean() -> void:
	# A galley (coastal, no tech) may enter an ocean tile its owner culturally owns.
	var gs = _sea_gs()
	gs.get_player(1).technologies = []
	gs.map.get_tile(1, 5).owner_player_id = 1
	gs.map.get_tile(2, 5).owner_player_id = 1
	var u = make_unit(gs, "galley", 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 2, 5, u, gs.db, gs.units, 1, gs)
	assert_false(path.empty(), "Coastal unit may enter own-territory ocean (waiver)")

func test_waiver_allied_territory_lets_unit_onto_ocean() -> void:
	# Players 1 and 2 share an alliance; player 2 owns the ocean tiles. Player 1's
	# pre-tech galley may enter via the alliance (open-borders proxy).
	var gs = _sea_gs(2)
	gs.get_player(1).technologies = []
	# Put both players in alliance id 1 (player 1's alliance).
	gs.get_player(2).alliance_id = 1
	gs.get_alliance(1).add_member(2)
	gs.map.get_tile(1, 5).owner_player_id = 2
	gs.map.get_tile(2, 5).owner_player_id = 2
	var u = make_unit(gs, "galley", 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 2, 5, u, gs.db, gs.units, 1, gs)
	assert_false(path.empty(), "Coastal unit may enter allied-territory ocean (waiver)")

func test_neutral_owned_ocean_does_not_waive() -> void:
	# An unrelated player (3) owning the ocean grants no waiver to player 1.
	var gs = _sea_gs(3)
	gs.get_player(1).technologies = []
	gs.map.get_tile(1, 5).owner_player_id = 3
	gs.map.get_tile(2, 5).owner_player_id = 3
	var u = make_unit(gs, "galley", 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 2, 5, u, gs.db, gs.units, 1, gs)
	assert_true(path.empty(), "Foreign-owned ocean grants no entry waiver")

func test_wild_ocean_capable_unit_skips_tech_check() -> void:
	# A wild (owner -2) ocean_capable hull may enter deep water with no tech/player.
	var gs = _sea_gs()
	var u = make_unit(gs, "frigate", -2, 0, 5)
	u.is_wild = true
	var path = Pathfinding.find_path(gs.map, 0, 5, 2, 5, u, gs.db, gs.units, -2, gs)
	assert_false(path.empty(), "A wild ocean-capable unit enters ocean without tech")

func test_wild_coastal_unit_still_blocked_on_ocean() -> void:
	var gs = _sea_gs()
	var u = make_unit(gs, "galley", -2, 0, 5)
	u.is_wild = true
	var path = Pathfinding.find_path(gs.map, 0, 5, 2, 5, u, gs.db, gs.units, -2, gs)
	assert_true(path.empty(), "A wild coastal unit cannot enter ocean")

func test_find_path_routes_around_illegal_ocean() -> void:
	# Coast spans rows; a single ocean tile sits between start and goal on the
	# direct line. A coastal unit must detour around it (or find no path). We set
	# up a coast field with one ocean tile at (3,5) and confirm the returned path
	# never steps onto it.
	var gs = make_gs()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "coast"
	gs.map.get_tile(3, 5).terrain_id = "ocean"
	var u = make_unit(gs, "galley", 1, 1, 5)  # coastal, pre-tech
	var path = Pathfinding.find_path(gs.map, 1, 5, 5, 5, u, gs.db, gs.units, 1, gs)
	assert_false(path.empty(), "A detour around the lone ocean tile exists on coast")
	for step in path:
		assert_false(int(step[0]) == 3 and int(step[1]) == 5,
			"Path must never step onto the illegal ocean tile (3,5)")

func test_move_command_rejects_illegal_ocean_destination() -> void:
	# The facade move guard: a direct MOVE_STACK onto an illegal ocean tile fails
	# (empty path), leaving the unit in place.
	var gs = _sea_gs()
	gs.get_player(1).technologies = []
	gs.current_player_id = 1
	var f = bare_facade(gs)
	var u = make_unit(gs, "galley", 1, 0, 5)
	var ok = f._cmd_move_stack({"player_id": 1, "from_x": 0, "from_y": 5, "to_x": 2, "to_y": 5})
	assert_false(ok, "Move onto illegal ocean is rejected")
	assert_eq([u.x, u.y], [0, 5], "Unit stays on its coast tile")

# ── Border blocking + open borders (§7) ──────────────────────────────────────
# A unit may enter a tile owned by another player ONLY when: it owns the tile, it is
# at war with the owner, they are alliance-mates, or an open-borders agreement is
# active. Own/unowned land is always traversable.

func _owned_strip(gs, owner_pid, x0, x1, y):
	# Mark a vertical-agnostic strip of tiles (x0..x1, fixed y) as owned by owner_pid.
	for x in range(x0, x1 + 1):
		gs.map.get_tile(x, y).owner_player_id = owner_pid

func test_border_blocks_foreign_territory_without_agreement() -> void:
	var gs = make_gs()  # players 1 and 2, separate alliances, at peace
	gs.current_player_id = 1
	# Player 2 owns a wall of tiles at x=2 across the path from (0,5) to (5,5).
	for y in range(3, 8):
		gs.map.get_tile(2, y).owner_player_id = 2
	var u = make_warrior(gs, 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 5, 5, u, gs.db, gs.units, 1, gs)
	for step in path:
		assert_false(gs.map.get_tile(int(step[0]), int(step[1])).owner_player_id == 2,
			"Path must never step onto player 2's territory without passage rights")

func test_border_blocked_destination_is_unreachable() -> void:
	var gs = make_gs()
	gs.current_player_id = 1
	# A fully enclosed foreign tile: player 2 owns (3,5) and every tile around it.
	for nb in gs.map.neighbours8(3, 5):
		nb.owner_player_id = 2
	gs.map.get_tile(3, 5).owner_player_id = 2
	var u = make_warrior(gs, 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 3, 5, u, gs.db, gs.units, 1, gs)
	assert_true(path.empty(), "A foreign tile behind a foreign wall is unreachable without passage")

func test_border_allows_with_open_borders() -> void:
	var gs = make_gs()
	gs.current_player_id = 1
	gs.add_open_borders(1, 2)
	for y in range(3, 8):
		gs.map.get_tile(2, y).owner_player_id = 2
	var u = make_warrior(gs, 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 5, 5, u, gs.db, gs.units, 1, gs)
	assert_false(path.empty(), "Open borders permits passage through player 2's land")
	var last = path[path.size() - 1]
	assert_eq([int(last[0]), int(last[1])], [5, 5], "Reaches the destination across foreign land")

func test_border_allows_when_at_war() -> void:
	var gs = make_gs()
	gs.current_player_id = 1
	# Put the two alliances at war (war = invasion rights).
	gs.get_alliance(1).at_war_with.append(2)
	gs.get_alliance(2).at_war_with.append(1)
	for y in range(3, 8):
		gs.map.get_tile(2, y).owner_player_id = 2
	var u = make_warrior(gs, 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 5, 5, u, gs.db, gs.units, 1, gs)
	assert_false(path.empty(), "At war you may invade foreign territory")

func test_border_allows_for_alliance_mates() -> void:
	var gs = make_gs()
	gs.current_player_id = 1
	# Put both players in one alliance (id 1).
	gs.get_player(2).alliance_id = 1
	gs.get_alliance(1).add_member(2)
	for y in range(3, 8):
		gs.map.get_tile(2, y).owner_player_id = 2
	var u = make_warrior(gs, 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 5, 5, u, gs.db, gs.units, 1, gs)
	assert_false(path.empty(), "Alliance-mates pass freely through each other's land")

func test_border_allows_own_territory() -> void:
	var gs = make_gs()
	gs.current_player_id = 1
	for y in range(3, 8):
		gs.map.get_tile(2, y).owner_player_id = 1  # the mover's own land
	var u = make_warrior(gs, 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 5, 5, u, gs.db, gs.units, 1, gs)
	assert_false(path.empty(), "A unit moves freely through its own territory")

func test_border_allows_unowned_land() -> void:
	var gs = make_gs()
	gs.current_player_id = 1
	# All tiles default to owner -1 (unowned).
	var u = make_warrior(gs, 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 5, 5, u, gs.db, gs.units, 1, gs)
	assert_false(path.empty(), "Unowned land is freely traversable")

func test_border_gate_skipped_without_game_state() -> void:
	# Domain-only callers (no game_state) are unaffected — the gate only applies when
	# a world context is threaded in.
	var gs = make_gs()
	for y in range(3, 8):
		gs.map.get_tile(2, y).owner_player_id = 2
	var u = make_warrior(gs, 1, 0, 5)
	var path = Pathfinding.find_path(gs.map, 0, 5, 5, 5, u, gs.db, gs.units, 1)  # no gs
	assert_false(path.empty(), "Without a game_state the border gate is skipped")
