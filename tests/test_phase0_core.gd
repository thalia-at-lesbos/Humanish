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

# Phase 0: Scaffold & deterministic core tests.

func test_rng_same_seed_same_sequence() -> void:
	var rng1 = load("res://src/core/rng.gd").new()
	rng1.init(12345)
	var rng2 = load("res://src/core/rng.gd").new()
	rng2.init(12345)
	for _i in range(20):
		assert_eq(rng1.randi(), rng2.randi(),
			"Same seed must produce identical sequence")

func test_rng_different_seeds_differ() -> void:
	var rng1 = load("res://src/core/rng.gd").new()
	rng1.init(1)
	var rng2 = load("res://src/core/rng.gd").new()
	rng2.init(2)
	var same_count: int = 0
	for _i in range(10):
		if rng1.randi() == rng2.randi():
			same_count += 1
	assert_lt(same_count, 10, "Different seeds should not produce identical sequences")

func test_rng_state_save_restore() -> void:
	var rng = load("res://src/core/rng.gd").new()
	rng.init(99999)
	for _i in range(5):
		rng.randi()
	var state: Dictionary = rng.get_state()
	var expected := []
	for _i in range(5):
		expected.append(rng.randi())
	rng.restore_state(state)
	for i in range(5):
		assert_eq(rng.randi(), expected[i],
			"Restored state must replay same sequence (draw %d)" % i)

func test_rng_rand_bool_percent_extremes() -> void:
	var rng = load("res://src/core/rng.gd").new()
	rng.init(777)
	for _i in range(50):
		assert_true(rng.rand_bool_percent(100), "100% should always be true")
		assert_false(rng.rand_bool_percent(0), "0% should always be false")

func test_rng_rand_weighted_only_bucket() -> void:
	var rng = load("res://src/core/rng.gd").new()
	rng.init(42)
	var weights := [0, 100, 0]
	for _i in range(20):
		assert_eq(rng.rand_weighted(weights), 1,
			"Only bucket 1 has weight, must always return 1")

func test_rng_randi_range_bounds() -> void:
	var rng = load("res://src/core/rng.gd").new()
	rng.init(555)
	for _i in range(100):
		var v: int = rng.randi_range(5, 10)
		assert_true(v >= 5 and v <= 10, "randi_range must be in [5,10]")

func test_fixed_scale() -> void:
	assert_eq(Fixed.scale(100, 25), 25, "100 * 25% = 25")
	assert_eq(Fixed.scale(10, 50), 5,  "10 * 50% = 5")
	assert_eq(Fixed.scale(7, 0), 0,    "anything * 0% = 0")

func test_fixed_scale_up() -> void:
	assert_eq(Fixed.scale_up(100, 25), 125, "100 + 25% = 125")
	assert_eq(Fixed.scale_up(8, 50), 12,   "8 + 50% = 12")

func test_fixed_apply_stacked_bonus() -> void:
	assert_eq(Fixed.apply_stacked_bonus(10, 50), 15, "10 * 150% = 15")
	assert_eq(Fixed.apply_stacked_bonus(10, 0), 10,  "10 * 100% = 10")

func test_fixed_proportion() -> void:
	assert_eq(Fixed.proportion(5, 10, 1000), 500, "5/10 * 1000 = 500")
	assert_eq(Fixed.proportion(3, 4, 1000), 750,  "3/4 * 1000 = 750")
	assert_eq(Fixed.proportion(0, 10, 1000), 0,   "0/10 * 1000 = 0")

func test_fixed_move_conversion() -> void:
	assert_eq(Fixed.tiles_to_move(2), 200, "2 tiles = 200 fixed units")
	assert_eq(Fixed.move_to_tiles(200), 2, "200 units = 2 tiles")
	assert_eq(Fixed.move_to_tiles(150), 1, "150 units = 1 tile (floor)")

func test_fixed_clamp_min0() -> void:
	assert_eq(Fixed.clamp_min0(-5), 0,  "negative clamped to 0")
	assert_eq(Fixed.clamp_min0(0), 0,   "zero stays zero")
	assert_eq(Fixed.clamp_min0(10), 10, "positive unchanged")

func test_data_db_loads() -> void:
	var db = load("res://src/core/data_db.gd").new()
	var ok: bool = db.load_all()
	if not ok:
		for err in db.get_errors():
			gut.p("DataDB error: " + err)
	assert_true(ok, "DataDB.load_all() must succeed with no errors")

func test_data_db_terrains_present() -> void:
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	assert_true(db.terrains.has("grassland"), "grassland terrain must exist")
	assert_true(db.terrains.has("ocean"), "ocean terrain must exist")

func test_data_db_tech_prereqs_valid() -> void:
	var db = load("res://src/core/data_db.gd").new()
	var ok: bool = db.load_all()
	assert_true(ok, "No cross-reference errors in data tables")

func test_data_db_get_constant_default() -> void:
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	assert_eq(db.get_constant("nonexistent_key", 42), 42,
		"Missing key returns default value")

func test_data_db_get_constant_loaded() -> void:
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	var scale: int = db.get_constant("combat_scale", 0)
	assert_gt(scale, 0, "combat_scale must be a positive integer")
