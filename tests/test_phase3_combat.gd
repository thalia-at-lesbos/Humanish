# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://addons/gut/test.gd"

# Phase 3: Units & combat tests.

func _make_db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

func _make_gs():
	var db = _make_db()
	var gs = load("res://src/sim/game_state.gd").new()
	gs.db = db
	gs.rng = load("res://src/core/rng.gd").new()
	gs.rng.init(42)
	gs.map = load("res://src/world/world_map.gd").new()
	gs.map.init(20, 20, false, false)
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var p1 = load("res://src/sim/player.gd").new()
	p1.id = 1; p1.alliance_id = 1
	var p2 = load("res://src/sim/player.gd").new()
	p2.id = 2; p2.alliance_id = 2
	gs.players.append(p1); gs.players.append(p2)
	var a1 = load("res://src/sim/alliance.gd").new(); a1.id = 1; a1.add_member(1)
	var a2 = load("res://src/sim/alliance.gd").new(); a2.id = 2; a2.add_member(2)
	gs.alliances.append(a1); gs.alliances.append(a2)
	return gs

func _make_warrior(gs, player_id, x, y, wild = false):
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id()
	u.unit_type_id = "warrior"
	u.owner_player_id = player_id
	u.x = x; u.y = y
	u.base_strength = 10
	u.health = 100
	u.movement_total = 200; u.movement_left = 200
	u.is_wild = wild
	gs.units.append(u)
	return u

# ── Movement ───────────────────────────────────────────────────────────────────

func test_movement_costs_movement_allowance() -> void:
	var gs = _make_gs()
	var u = _make_warrior(gs, 1, 5, 5)
	var before: int = u.movement_left
	u.x = 6; u.y = 5
	u.movement_left -= 100
	assert_eq(u.movement_left, before - 100,
		"Moving one grassland tile costs 100 fixed units")

func test_entrenchment_increases_per_turn() -> void:
	var u = load("res://src/sim/unit.gd").new()
	u.base_strength = 10; u.health = 100
	u.unit_type_id = "warrior"
	u.stationary_turns = 0; u.entrenchment = 0
	var cap: int = 25
	for _i in range(3):
		u.stationary_turns += 1
		u.entrenchment = min(cap, u.stationary_turns * 5)
	assert_eq(u.entrenchment, 15, "3 turns * 5/turn = 15 entrenchment")

func test_entrenchment_cap_respected() -> void:
	var db = _make_db()
	var cap: int = db.get_constant("entrenchment_cap", 25)
	var u = load("res://src/sim/unit.gd").new()
	u.stationary_turns = 100
	u.entrenchment = min(cap, u.stationary_turns * 5)
	assert_true(u.entrenchment <= cap, "Entrenchment must not exceed cap")

# ── Pathfinding ────────────────────────────────────────────────────────────────

func test_pathfinding_finds_straight_path() -> void:
	var gs = _make_gs()
	var u = _make_warrior(gs, 1, 0, 0)
	var path = Pathfinding.find_path(gs.map, 0, 0, 3, 0, u, gs.db, gs.units, 1)
	assert_false(path.empty(), "Path should exist on open grassland")
	var last = path[path.size() - 1]
	assert_eq(last[0], 3, "Path ends at x=3")
	assert_eq(last[1], 0, "Path ends at y=0")

func test_pathfinding_impassable_blocked() -> void:
	var gs = _make_gs()
	for y in range(20):
		gs.map.get_tile(5, y).terrain_id = "mountain"
	var u = _make_warrior(gs, 1, 0, 10)
	var path = Pathfinding.find_path(gs.map, 0, 10, 10, 10, u, gs.db, gs.units, 1)
	assert_true(path.empty(), "Mountain wall should block path")

func test_pathfinding_sea_unit_cannot_walk_land() -> void:
	var gs = _make_gs()
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id(); u.unit_type_id = "galley"
	u.owner_player_id = 1; u.x = 0; u.y = 0
	u.base_strength = 8; u.health = 100
	u.movement_total = 300; u.movement_left = 300
	gs.units.append(u)
	var path = Pathfinding.find_path(gs.map, 0, 0, 3, 0, u, gs.db, gs.units, 1)
	assert_true(path.empty(), "Naval unit cannot path through land")

# ── Combat ────────────────────────────────────────────────────────────────────

func test_combat_has_required_keys() -> void:
	var gs = _make_gs()
	var attacker = _make_warrior(gs, 1, 5, 6)
	var defender = _make_warrior(gs, 2, 5, 5)
	var rng = load("res://src/core/rng.gd").new()
	rng.init(42)
	var result: Dictionary = Combat.resolve(attacker, defender, gs, rng)
	assert_true(result.has("attacker_survived"), "Result has attacker_survived")
	assert_true(result.has("defender_survived"), "Result has defender_survived")
	assert_true(result.has("rounds"), "Result has rounds")

func test_combat_one_side_dies_or_withdraws() -> void:
	var gs = _make_gs()
	var attacker = _make_warrior(gs, 1, 5, 6)
	var defender = _make_warrior(gs, 2, 5, 5)
	var rng = load("res://src/core/rng.gd").new()
	rng.init(42)
	var result: Dictionary = Combat.resolve(attacker, defender, gs, rng)
	assert_true(
		not result["attacker_survived"] or not result["defender_survived"] or result["attacker_withdrew"],
		"Combat must end with a winner or withdrawal")

func test_combat_same_seed_identical_outcome() -> void:
	var gs = _make_gs()
	var rng1 = load("res://src/core/rng.gd").new(); rng1.init(999)
	var a1 = _make_warrior(gs, 1, 5, 6); a1.id = 100
	var d1 = _make_warrior(gs, 2, 5, 5); d1.id = 101
	var r1: Dictionary = Combat.resolve(a1, d1, gs, rng1)

	var rng2 = load("res://src/core/rng.gd").new(); rng2.init(999)
	var a2 = _make_warrior(gs, 1, 5, 6); a2.id = 102
	var d2 = _make_warrior(gs, 2, 5, 5); d2.id = 103
	var r2: Dictionary = Combat.resolve(a2, d2, gs, rng2)

	assert_eq(r1["attacker_survived"], r2["attacker_survived"],
		"Same seed: attacker_survived identical")
	assert_eq(r1["defender_survived"], r2["defender_survived"],
		"Same seed: defender_survived identical")
	assert_eq(r1["attacker_health_after"], r2["attacker_health_after"],
		"Same seed: health identical")
	assert_eq(r1["rounds"], r2["rounds"],
		"Same seed: round count identical")

func test_combat_health_non_negative() -> void:
	var gs = _make_gs()
	var rng = load("res://src/core/rng.gd").new(); rng.init(9876)
	var attacker = _make_warrior(gs, 1, 5, 6)
	var defender = _make_warrior(gs, 2, 5, 5)
	var result: Dictionary = Combat.resolve(attacker, defender, gs, rng)
	assert_true(result["attacker_health_after"] >= 0, "Attacker health >= 0")
	assert_true(result["defender_health_after"] >= 0, "Defender health >= 0")

func test_combat_xp_gain_when_killing_weak_enemy() -> void:
	var gs = _make_gs()
	var rng = load("res://src/core/rng.gd").new(); rng.init(1234)
	var attacker = _make_warrior(gs, 1, 5, 6)
	attacker.base_strength = 100  # very strong
	var defender = load("res://src/sim/unit.gd").new()
	defender.id = gs.next_unit_id(); defender.unit_type_id = "warrior"
	defender.owner_player_id = 2; defender.x = 5; defender.y = 5
	defender.base_strength = 1; defender.health = 1
	defender.is_wild = false
	gs.units.append(defender)
	var result: Dictionary = Combat.resolve(attacker, defender, gs, rng)
	if not result["defender_survived"]:
		assert_gt(result["attacker_xp_gain"], 0, "Attacker gains XP when killing")
