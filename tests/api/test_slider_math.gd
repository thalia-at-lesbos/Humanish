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

# SliderMath.rebalance: moving one allocation slider always keeps the four-way
# split summing to 100, deterministically, taking from the following sliders first.

func _sum(a):
	var s = 0
	for v in a:
		s += int(v)
	return s

func test_rebalance_always_sums_to_100() -> void:
	var SM = load("res://src/api/slider_math.gd")
	var starts = [[40, 40, 10, 10], [25, 25, 25, 25], [100, 0, 0, 0], [70, 10, 10, 10]]
	for st in starts:
		for idx in range(4):
			for target in [0, 10, 30, 50, 70, 100]:
				var out = SM.rebalance(st, idx, target)
				assert_eq(_sum(out), 100,
					"sum must stay 100 for start %s idx %d -> %d (got %s)" % [st, idx, target, out])
				assert_eq(int(out[idx]), target, "the moved slider must hold its new value")
				for v in out:
					assert_true(int(v) >= 0 and int(v) <= 100, "each value within [0,100]")

func test_rebalance_is_deterministic() -> void:
	var SM = load("res://src/api/slider_math.gd")
	var a = SM.rebalance([40, 40, 10, 10], 0, 70)
	var b = SM.rebalance([40, 40, 10, 10], 0, 70)
	assert_eq(a, b, "Same input must give the same redistribution every time")

func test_rebalance_takes_from_following_sliders_first() -> void:
	var SM = load("res://src/api/slider_math.gd")
	# Finance 40 -> 60: the +20 is pulled from research (next index) first.
	assert_eq(SM.rebalance([40, 40, 10, 10], 0, 60), [60, 20, 10, 10],
		"Increase should be absorbed by the immediately following slider first")
