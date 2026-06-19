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

# Canary for the HUD minimap overlay. It now carries click-to-recenter logic
# (_gui_input + pixel_to_tile), so a parse/compile error here would silently
# blank the minimap; can_instance() reports the compile state without throwing.

const Minimap = preload("res://scenes/hud/minimap.gd")

func test_minimap_script_compiles() -> void:
	assert_true(load("res://scenes/hud/minimap.gd").can_instance(),
		"hud/minimap.gd must compile (click-to-recenter logic)")

# pixel_to_tile inverts _draw()'s mapping: px = PANEL_PADDING + x * CELL.
func test_pixel_to_tile_inverts_draw_mapping() -> void:
	var pad: int = Minimap.PANEL_PADDING
	var cell: int = Minimap.CELL
	# Center of tile (3,5) on a 10x10 map.
	var px: float = pad + 3 * cell + cell * 0.5
	var py: float = pad + 5 * cell + cell * 0.5
	var t: Array = Minimap.pixel_to_tile(px, py, 10, 10)
	assert_eq(t[0], 3, "x should invert to 3")
	assert_eq(t[1], 5, "y should invert to 5")

func test_pixel_to_tile_clamps_to_bounds() -> void:
	# Far below/left clamps to 0; far above/right clamps to map-1.
	var low: Array = Minimap.pixel_to_tile(-1000.0, -1000.0, 8, 6)
	assert_eq(low[0], 0, "negative x clamps to 0")
	assert_eq(low[1], 0, "negative y clamps to 0")
	var high: Array = Minimap.pixel_to_tile(99999.0, 99999.0, 8, 6)
	assert_eq(high[0], 7, "huge x clamps to map_w-1")
	assert_eq(high[1], 5, "huge y clamps to map_h-1")
