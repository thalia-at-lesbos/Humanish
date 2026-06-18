# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Fixed

# Fixed-point helpers. Movement allowances are stored as integers scaled by
# MOVE_DENOMINATOR (60 = 1 tile). 60 divides cleanly by 2/3/4/5/6 so route and
# terrain costs (e.g. a road's 1/3 tile) land on exact integers. This avoids
# floats entering sim code. All other outputs (food/production/commerce) are
# plain integers.

const MOVE_DENOMINATOR: int = 60   # internal units per 1 tile of movement
const PERCENT_BASE: int = 100      # 100 = 100%, used for all percentage math

# Convert a whole-tile movement allowance to fixed-point units.
static func tiles_to_move(tiles: int) -> int:
	return tiles * MOVE_DENOMINATOR

# Convert fixed-point movement units back to whole tiles (floor).
static func move_to_tiles(fixed: int) -> int:
	return fixed / MOVE_DENOMINATOR

# Apply a percentage modifier to a value; returns integer result (floor).
# e.g. scale(10, 25) = 2  (10 * 25 / 100)
static func scale(value: int, percent: int) -> int:
	return (value * percent) / PERCENT_BASE

# Increase a value by a percentage bonus.
# e.g. scale_up(10, 25) = 12  (10 + 2 = 12)
static func scale_up(value: int, percent: int) -> int:
	return value + scale(value, percent)

# Combine stacked percentage modifiers into an effective bonus.
# Each modifier is an integer percentage (e.g. 25 = +25%). They stack additively.
# effective_strength = base * (100 + sum_of_bonuses) / 100
static func apply_stacked_bonus(base: int, bonus_sum: int) -> int:
	return (base * (PERCENT_BASE + bonus_sum)) / PERCENT_BASE

# Clamp a value to be no lower than zero.
static func clamp_min0(value: int) -> int:
	return 0 if value < 0 else value

# Integer ceiling division: ceil(a / b) = (a + b - 1) / b
static func ceil_div(a: int, b: int) -> int:
	return (a + b - 1) / b

# Proportional share: return a's portion of total, scaled to scale_to.
# Used in combat odds: a_str * 1000 / (a_str + b_str)
static func proportion(a: int, total: int, scale_to: int) -> int:
	if total <= 0:
		return scale_to / 2
	return (a * scale_to) / total
