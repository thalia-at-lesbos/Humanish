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

# Global warming (§11): a map-wide pass where building unhealthiness + detonated
# nukes degrade random non-city land tiles one step toward the base terrain
# (desert), stripping vegetation first. Forest/jungle cover defends against it.

# ── Degradation chain (deterministic, no RNG) ─────────────────────────────────

func test_degrade_strips_feature_before_terrain() -> void:
	var gs = make_gs()
	var tile = gs.map.get_tile(5, 5)
	tile.terrain_id = "grassland"; tile.feature_id = "forest"
	GlobalWarming._degrade_tile(gs, tile, gs.db)
	assert_eq(tile.feature_id, "", "Vegetation feature is stripped first")
	assert_eq(tile.terrain_id, "grassland", "Terrain is untouched while a feature remains")

func test_degrade_marches_flat_terrain_toward_desert() -> void:
	var gs = make_gs()
	var tile = gs.map.get_tile(5, 5)
	tile.feature_id = ""
	tile.terrain_id = "grassland"
	GlobalWarming._degrade_tile(gs, tile, gs.db)
	assert_eq(tile.terrain_id, "plains", "grassland degrades to plains")
	GlobalWarming._degrade_tile(gs, tile, gs.db)
	assert_eq(tile.terrain_id, "desert", "plains degrades to the base terrain (desert)")
	GlobalWarming._degrade_tile(gs, tile, gs.db)
	assert_eq(tile.terrain_id, "desert", "desert is the terminal base terrain (no-op)")

func test_degrade_tundra_chain_reaches_desert() -> void:
	var gs = make_gs()
	var tile = gs.map.get_tile(5, 5)
	tile.feature_id = ""; tile.terrain_id = "tundra"
	GlobalWarming._degrade_tile(gs, tile, gs.db)
	assert_eq(tile.terrain_id, "snow", "tundra degrades to snow")
	GlobalWarming._degrade_tile(gs, tile, gs.db)
	assert_eq(tile.terrain_id, "desert", "snow continues all the way to the base terrain")

func test_degrade_erodes_hills_and_mountains_to_desert() -> void:
	# Any land tile is affected, not just flat farmland: a peak erodes all the way
	# down to the barren base terrain (mountain → hills → plains → desert).
	var gs = make_gs()
	var tile = gs.map.get_tile(5, 5)
	tile.feature_id = ""; tile.terrain_id = "mountain"
	var chain := ["hills", "plains", "desert", "desert"]
	for expected in chain:
		GlobalWarming._degrade_tile(gs, tile, gs.db)
		assert_eq(tile.terrain_id, expected, "mountain erodes one rung toward desert")

func test_degrade_never_floods_coastal_tile() -> void:
	# Global warming heads toward desert, not water: a flat grassland beside the
	# sea degrades to plains rather than flooding to coast (the old behaviour).
	var gs = make_gs()
	gs.map.get_tile(6, 5).terrain_id = "coast"  # adjacent water
	var tile = gs.map.get_tile(5, 5)
	tile.feature_id = ""; tile.terrain_id = "grassland"
	GlobalWarming._degrade_tile(gs, tile, gs.db)
	assert_eq(tile.terrain_id, "plains", "A coastal flat tile marches toward desert, never floods")

# ── GW_VALUE: strike attempts (#BAD_HEALTH + #NUKES_EXPLODED) ──────────────────

func test_building_unhealth_sums_structure_penalties_only() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5, 6)
	s.structures = ["forge", "forge"]  # forge carries health_penalty 1
	# Population-driven unhealthiness must NOT count — only buildings.
	assert_eq(GlobalWarming._building_unhealth(gs, gs.db), 2,
		"#BAD_HEALTH counts only structure health_penalty, summed across cities")

func test_nukes_drive_strike_attempts() -> void:
	# value_x100 = nukes * gw_nuclear_ratio(50); attempts = value_x100 / 100.
	var gs = make_gs()  # 20×20, no buildings → bad-health term is 0
	gs.nukes_exploded = 4
	assert_eq(GlobalWarming._strike_attempts(gs, gs.rng, gs.db), 2,
		"4 nukes × 0.5 = 2 strike attempts")
	gs.nukes_exploded = 0
	assert_eq(GlobalWarming._strike_attempts(gs, gs.rng, gs.db), 0,
		"No unhealthiness and no nukes → no attempts")

# ── Per-strike landing chance (forest defence) ────────────────────────────────

func test_strike_chance_equals_gw_chance_without_forest() -> void:
	var gs = make_gs()  # all grassland, no features
	assert_eq(GlobalWarming._strike_chance(gs, gs.db), 20,
		"With no forest cover the landing chance is gw_chance")

func test_forest_cover_reduces_strike_chance() -> void:
	var gs = make_gs(2, 42, 20, 20)  # 400 land tiles
	# 80 forest tiles → defence = 80 * gw_forest_ratio(50) / 400 = 10.
	var n = 0
	for tile in gs.map.all_tiles():
		if n >= 80:
			break
		tile.feature_id = "forest"
		n += 1
	assert_eq(GlobalWarming._strike_chance(gs, gs.db), 10,
		"Forest cover subtracts GW_DEFENSE from the landing chance")

func test_heavy_forest_clamps_chance_to_zero() -> void:
	var gs = make_gs(2, 42, 20, 20)
	for tile in gs.map.all_tiles():
		tile.feature_id = "forest"  # all 400 tiles forested → defence 50 > gw_chance
	assert_eq(GlobalWarming._strike_chance(gs, gs.db), 0,
		"Overwhelming forest cover clamps the landing chance to zero")

# ── Full pass ─────────────────────────────────────────────────────────────────

func test_tick_degrades_tiles_but_never_a_city() -> void:
	var gs = make_gs(2, 7)  # all grassland, no forest → chance = gw_chance
	var city = make_settlement(gs, 1, 10, 10, 5)
	var city_tile = gs.map.get_tile(city.x, city.y)
	city_tile.terrain_id = "grassland"
	gs.nukes_exploded = 200  # 200 × 0.5 = 100 attempts → degradation is overwhelming
	var before := []
	for tile in gs.map.all_tiles():
		before.append(tile.terrain_id)
	GlobalWarming.tick(gs, gs.rng)
	var changed := false
	var idx := 0
	for tile in gs.map.all_tiles():
		if tile.terrain_id != before[idx]:
			changed = true
		idx += 1
	assert_true(changed, "Global warming degrades at least one tile under heavy pressure")
	assert_eq(city_tile.terrain_id, "grassland", "A city tile is never chosen for degradation")

func test_tick_no_op_without_pressure() -> void:
	var gs = make_gs(2, 7)  # no buildings, no nukes
	var snapshot := []
	for tile in gs.map.all_tiles():
		snapshot.append(tile.terrain_id)
	GlobalWarming.tick(gs, gs.rng)
	var idx := 0
	for tile in gs.map.all_tiles():
		assert_eq(tile.terrain_id, snapshot[idx], "No pressure → no degradation")
		idx += 1
