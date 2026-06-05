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

# Phase 5: End-to-end determinism and integration tests.

func _make_facade(sv = 1234):
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade._db = db
	facade._hooks = load("res://src/sim/hooks.gd").new()
	facade.setup(db, sv, "tiny", "normal", "warlord",
		[
			{"name": "Alice", "leader_id": "", "traits": [], "starting_gold": 50},
			{"name": "Bob",   "leader_id": "", "traits": [], "starting_gold": 50}
		],
		["last_standing", "time"])
	return facade

func _place_settler(facade, player_id, x, y):
	var gs = facade.get_state()
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id(); u.unit_type_id = "settler"
	u.owner_player_id = player_id; u.x = x; u.y = y
	u.base_strength = 0; u.health = 100
	u.movement_total = 200; u.movement_left = 200
	gs.units.append(u)
	return u.id

func _run_turns(facade, n: int) -> void:
	var gs = facade.get_state()
	for _t in range(n):
		if gs.winning_alliance_id >= 0:
			break
		for p in gs.players:
			if p.is_eliminated:
				continue
			gs.current_player_id = p.id
			facade.apply_command(Commands.end_turn(p.id))

# ── Determinism gate ───────────────────────────────────────────────────────────

func test_determinism_same_seed_same_hash() -> void:
	var f1 = _make_facade(7777)
	var f2 = _make_facade(7777)
	_run_turns(f1, 5)
	_run_turns(f2, 5)
	assert_eq(f1.state_hash(), f2.state_hash(),
		"Same seed + same commands → identical state hash")

func test_determinism_save_load_resume() -> void:
	var facade = _make_facade(5555)
	_run_turns(facade, 3)
	var mid_hash: int = facade.state_hash()
	var save_str: String = facade.save()
	_run_turns(facade, 2)
	var final_hash_orig: int = facade.state_hash()
	facade.load_save(save_str)
	assert_eq(facade.state_hash(), mid_hash,
		"Loaded state hash matches pre-save hash")
	_run_turns(facade, 2)
	assert_eq(facade.state_hash(), final_hash_orig,
		"Post-load hash matches original continued hash")

func test_determinism_different_seeds_different_hash() -> void:
	var f1 = _make_facade(1111)
	var f2 = _make_facade(2222)
	_run_turns(f1, 3)
	_run_turns(f2, 3)
	assert_ne(f1.state_hash(), f2.state_hash(),
		"Different seeds should produce different state hashes")

# ── Settlement founding ────────────────────────────────────────────────────────

func test_found_settlement_creates_settlement() -> void:
	var facade = _make_facade(100)
	var gs = facade.get_state()
	var uid: int = _place_settler(facade, gs.players[0].id, 5, 5)
	gs.current_player_id = gs.players[0].id
	var ok: bool = facade.apply_command(
		Commands.found_settlement(gs.players[0].id, uid, "Alpha"))
	assert_true(ok, "Found settlement command should succeed")
	assert_eq(gs.settlements.size(), 1, "One settlement should exist")
	assert_eq(gs.settlements[0].name, "Alpha", "Settlement name set correctly")

func test_found_settlement_too_close_fails() -> void:
	var facade = _make_facade(200)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var uid1: int = _place_settler(facade, gs.players[0].id, 5, 5)
	facade.apply_command(Commands.found_settlement(gs.players[0].id, uid1, "A"))
	var uid2: int = _place_settler(facade, gs.players[0].id, 6, 5)
	var ok: bool = facade.apply_command(
		Commands.found_settlement(gs.players[0].id, uid2, "B"))
	assert_false(ok, "Cannot found within min distance")

# ── Research flow ──────────────────────────────────────────────────────────────

func test_set_research_command() -> void:
	var facade = _make_facade(300)
	var gs = facade.get_state()
	var p = gs.players[0]
	gs.current_player_id = p.id
	var ok: bool = facade.apply_command(Commands.set_research(p.id, "mining"))
	assert_true(ok, "Set research should succeed")
	assert_eq(p.current_research_id, "mining", "Research target set")

# ── Win conditions ─────────────────────────────────────────────────────────────

func test_last_standing_win() -> void:
	var facade = _make_facade(400)
	var gs = facade.get_state()
	gs.players[1].is_eliminated = true
	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id(); s.owner_player_id = gs.players[0].id
	s.x = 5; s.y = 5; s.population = 1
	gs.settlements.append(s)
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id(); u.unit_type_id = "warrior"
	u.owner_player_id = gs.players[0].id; u.x = 5; u.y = 6
	u.base_strength = 10; u.health = 100
	gs.units.append(u)
	var winner: int = WinConditions.check_all(gs)
	assert_eq(winner, gs.players[0].alliance_id,
		"Player 1's alliance wins last_standing")

func test_save_load_roundtrip_fidelity() -> void:
	var facade = _make_facade(600)
	_run_turns(facade, 2)
	var save1: String = facade.save()
	var h1: int = facade.state_hash()
	facade.load_save(save1)
	var h2: int = facade.state_hash()
	assert_eq(h1, h2, "Hash identical after save→load roundtrip")

# The start-menu "Load Game" path: a brand-new facade is scaffolded with
# init_for_load() (no setup()) and then fed a save string.
func test_init_for_load_loads_into_fresh_facade() -> void:
	var facade = _make_facade(700)
	_run_turns(facade, 2)
	var save_str: String = facade.save()
	var orig_hash: int = facade.state_hash()

	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	var fresh = load("res://src/api/sim_facade.gd").new()
	fresh.init_for_load(db)
	assert_true(fresh.load_save(save_str), "load_save succeeds on a fresh facade")
	assert_eq(fresh.state_hash(), orig_hash,
		"Fresh facade matches the saved state hash")
	# Scaffolding the presentation layer relies on must exist post-load.
	assert_not_null(fresh.get_dirty(), "dirty flags initialized")
	assert_not_null(fresh.get_selection(), "selection state initialized")
	assert_not_null(fresh.get_state(), "game state populated")
