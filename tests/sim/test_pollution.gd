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

# Pollution (§11): a polluted flat tile beside water floods to coast, while an
# inland flat tile degrades toward barren terrain instead.

func test_polluted_flat_tile_floods_beside_water() -> void:
	var gs = make_gs()
	gs.map.get_tile(6, 5).terrain_id = "coast"  # adjacent water
	var tile = gs.map.get_tile(5, 5)
	tile.terrain_id = "grassland"; tile.feature_id = ""
	Pollution._degrade_tile(gs, tile, gs.db)
	assert_eq(tile.terrain_id, "coast", "A polluted flat tile beside water floods to coast")

func test_inland_flat_tile_degrades_not_floods() -> void:
	var gs = make_gs()
	var tile = gs.map.get_tile(5, 5)
	tile.terrain_id = "grassland"; tile.feature_id = ""
	Pollution._degrade_tile(gs, tile, gs.db)
	assert_eq(tile.terrain_id, "plains", "An inland flat tile degrades toward barren, not water")
