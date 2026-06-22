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

func test_settlement_tile_never_floods_to_coast() -> void:
	# Regression (pt-b-11.sav: capital at (49,29) flooded to coast under the city):
	# a polluted flat coastal tile that HOSTS a settlement must never flood to coast
	# — a founded city sits on land and stranding it on water cannot be re-founded.
	# It degrades toward barren instead, like an inland tile.
	var gs = make_gs()
	gs.map.get_tile(6, 5).terrain_id = "coast"  # adjacent water → would normally flood
	var tile = gs.map.get_tile(5, 5)
	tile.terrain_id = "grassland"; tile.feature_id = ""
	make_settlement(gs, 1, 5, 5, 7)             # capital occupies this very tile
	Pollution._degrade_tile(gs, tile, gs.db)
	assert_ne(tile.terrain_id, "coast", "A settlement tile never floods to coast")
	assert_eq(tile.terrain_id, "plains", "A polluted settlement tile degrades toward barren instead")
	assert_eq(gs.db.get_terrain(tile.terrain_id).get("domain"), "land",
		"The capital's tile stays land after pollution")
