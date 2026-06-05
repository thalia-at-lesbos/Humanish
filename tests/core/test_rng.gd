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

# The seeded PCG32 RNG: identical seeds replay identical sequences, and state
# save/restore reproduces the stream mid-game. This is the foundation of the
# determinism guarantees the integration suite leans on.

func _rng(seed_val):
	var r = load("res://src/core/rng.gd").new()
	r.init(seed_val)
	return r

func test_same_seed_same_sequence() -> void:
	var rng1 = _rng(12345)
	var rng2 = _rng(12345)
	for _i in range(20):
		assert_eq(rng1.randi(), rng2.randi(),
			"Same seed must produce identical sequence")

func test_different_seeds_differ() -> void:
	var rng1 = _rng(1)
	var rng2 = _rng(2)
	var same_count: int = 0
	for _i in range(10):
		if rng1.randi() == rng2.randi():
			same_count += 1
	assert_lt(same_count, 10, "Different seeds should not produce identical sequences")

func test_state_save_restore() -> void:
	var rng = _rng(99999)
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

func test_rand_bool_percent_extremes() -> void:
	var rng = _rng(777)
	for _i in range(50):
		assert_true(rng.rand_bool_percent(100), "100% should always be true")
		assert_false(rng.rand_bool_percent(0), "0% should always be false")

func test_rand_weighted_only_bucket() -> void:
	var rng = _rng(42)
	var weights := [0, 100, 0]
	for _i in range(20):
		assert_eq(rng.rand_weighted(weights), 1,
			"Only bucket 1 has weight, must always return 1")

func test_randi_range_bounds() -> void:
	var rng = _rng(555)
	for _i in range(100):
		var v: int = rng.randi_range(5, 10)
		assert_true(v >= 5 and v <= 10, "randi_range must be in [5,10]")
