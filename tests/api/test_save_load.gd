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

# The determinism gate: identical seeds + identical commands produce identical
# state hashes, save/load reproduces the hash mid-game and resumes deterministically,
# and the start-menu "Load Game" path (init_for_load) loads into a fresh facade.

func test_same_seed_same_hash() -> void:
	var f1 = setup_facade(7777)
	var f2 = setup_facade(7777)
	run_turns(f1, 5)
	run_turns(f2, 5)
	assert_eq(f1.state_hash(), f2.state_hash(),
		"Same seed + same commands → identical state hash")

func test_different_seeds_different_hash() -> void:
	var f1 = setup_facade(1111)
	var f2 = setup_facade(2222)
	run_turns(f1, 3)
	run_turns(f2, 3)
	assert_ne(f1.state_hash(), f2.state_hash(),
		"Different seeds should produce different state hashes")

func test_save_load_resume() -> void:
	var facade = setup_facade(5555)
	run_turns(facade, 3)
	var mid_hash: int = facade.state_hash()
	var save_str: String = facade.save()
	run_turns(facade, 2)
	var final_hash_orig: int = facade.state_hash()
	facade.load_save(save_str)
	assert_eq(facade.state_hash(), mid_hash, "Loaded state hash matches pre-save hash")
	run_turns(facade, 2)
	assert_eq(facade.state_hash(), final_hash_orig,
		"Post-load hash matches original continued hash")

func test_save_load_roundtrip_fidelity() -> void:
	var facade = setup_facade(600)
	run_turns(facade, 2)
	var h1: int = facade.state_hash()
	facade.load_save(facade.save())
	assert_eq(h1, facade.state_hash(), "Hash identical after save→load roundtrip")

# A pre-2 save stored movement on the old 100-unit scale; loading it must rescale
# unit movement to the MOVE_DENOMINATOR=60 scale (§5.2 migration).
func test_pre_v2_save_migrates_movement_scale() -> void:
	var facade = setup_facade(800)
	run_turns(facade, 1)
	var d: Dictionary = JSON.parse(facade.save()).result
	# Forge an old save: drop the version and put a unit's movement on the 100 scale.
	d.erase("save_version")
	assert_true(d["units"].size() > 0, "fixture produced at least one unit")
	d["units"][0]["movement_total"] = 200   # 2 tiles on the old scale
	d["units"][0]["movement_left"] = 200
	var migrated = GameState.deserialize(d, make_db())
	assert_eq(migrated.units[0].movement_total, 120,
		"Old 200 (2 tiles @100) migrates to 120 (2 tiles @60)")
	assert_eq(migrated.units[0].movement_left, 120, "movement_left migrated too")

# The start-menu "Load Game" path: a brand-new facade is scaffolded with
# init_for_load() (no setup()) and then fed a save string.
func test_init_for_load_loads_into_fresh_facade() -> void:
	var facade = setup_facade(700)
	run_turns(facade, 2)
	var save_str: String = facade.save()
	var orig_hash: int = facade.state_hash()

	var fresh = load("res://src/api/sim_facade.gd").new()
	fresh.init_for_load(make_db())
	assert_true(fresh.load_save(save_str), "load_save succeeds on a fresh facade")
	assert_eq(fresh.state_hash(), orig_hash, "Fresh facade matches the saved state hash")
	# Scaffolding the presentation layer relies on must exist post-load.
	assert_not_null(fresh.get_dirty(), "dirty flags initialized")
	assert_not_null(fresh.get_selection(), "selection state initialized")
	assert_not_null(fresh.get_state(), "game state populated")
