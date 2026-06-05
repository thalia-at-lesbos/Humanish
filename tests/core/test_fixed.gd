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

# Fixed-point integer math (§1, §5): the sim never uses floats, so every helper
# here must return exact integers — percentage scales, additive bonus stacking,
# proportions, and the ×100 movement scale.

func test_scale() -> void:
	assert_eq(Fixed.scale(100, 25), 25, "100 * 25% = 25")
	assert_eq(Fixed.scale(10, 50), 5, "10 * 50% = 5")
	assert_eq(Fixed.scale(7, 0), 0, "anything * 0% = 0")

func test_scale_up() -> void:
	assert_eq(Fixed.scale_up(100, 25), 125, "100 + 25% = 125")
	assert_eq(Fixed.scale_up(8, 50), 12, "8 + 50% = 12")

func test_apply_stacked_bonus() -> void:
	assert_eq(Fixed.apply_stacked_bonus(10, 50), 15, "10 * 150% = 15")
	assert_eq(Fixed.apply_stacked_bonus(10, 0), 10, "10 * 100% = 10")

func test_proportion() -> void:
	assert_eq(Fixed.proportion(5, 10, 1000), 500, "5/10 * 1000 = 500")
	assert_eq(Fixed.proportion(3, 4, 1000), 750, "3/4 * 1000 = 750")
	assert_eq(Fixed.proportion(0, 10, 1000), 0, "0/10 * 1000 = 0")

func test_move_conversion() -> void:
	assert_eq(Fixed.tiles_to_move(2), 200, "2 tiles = 200 fixed units")
	assert_eq(Fixed.move_to_tiles(200), 2, "200 units = 2 tiles")
	assert_eq(Fixed.move_to_tiles(150), 1, "150 units = 1 tile (floor)")

func test_clamp_min0() -> void:
	assert_eq(Fixed.clamp_min0(-5), 0, "negative clamped to 0")
	assert_eq(Fixed.clamp_min0(0), 0, "zero stays zero")
	assert_eq(Fixed.clamp_min0(10), 10, "positive unchanged")
