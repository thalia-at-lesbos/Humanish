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

# TileOutput (§1.3): terrain base → feature → resource → improvement → transport,
# each gated by tech/improvement and clamped to non-negative at the end.

func _db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

func _tile(terrain):
	var t = load("res://src/world/tile.gd").new(0, 0)
	t.terrain_id = terrain
	return t

func test_grassland_base_output() -> void:
	var out = TileOutput.compute(_tile("grassland"), _db(), [])
	assert_eq(out[IDs.Output.FOOD], 2, "Grassland: 2 food")
	assert_eq(out[IDs.Output.PRODUCTION], 0, "Grassland: 0 production (reference)")

func test_river_commerce_bonus_on_river_tiles() -> void:
	# A5 (reference): grass/plains/desert/tundra river tiles yield +1 commerce;
	# the bonus only applies when the caller reports a river border.
	var db = _db()
	for ter in ["grassland", "plains", "desert", "tundra"]:
		var dry = TileOutput.compute(_tile(ter), db, [], false)
		var wet = TileOutput.compute(_tile(ter), db, [], true)
		assert_eq(wet[IDs.Output.COMMERCE], dry[IDs.Output.COMMERCE] + 1,
			ter + ": +1 commerce adjacent to river")

func test_river_commerce_not_on_hills_or_snow() -> void:
	var db = _db()
	for ter in ["hills", "snow", "coast", "mountain"]:
		var dry = TileOutput.compute(_tile(ter), db, [], false)
		var wet = TileOutput.compute(_tile(ter), db, [], true)
		assert_eq(wet[IDs.Output.COMMERCE], dry[IDs.Output.COMMERCE],
			ter + ": no river commerce bonus")

func test_river_commerce_survives_feature() -> void:
	# Flood plains on a desert river tile keeps the desert's river +1C (reference:
	# flood plains 3F/0P/1C).
	var db = _db()
	var tile = _tile("desert")
	tile.feature_id = "flood_plains"
	var out = TileOutput.compute(tile, db, [], true)
	assert_eq(out[IDs.Output.FOOD], 3, "Flood plains: 3 food")
	assert_eq(out[IDs.Output.COMMERCE], 1, "Flood plains river tile: 1 commerce")

func test_mountain_yields_nothing_and_is_unworkable() -> void:
	# A5 (reference): peaks yield nothing and can never be worked.
	var db = _db()
	var tile = _tile("mountain")
	var out = TileOutput.compute(tile, db, [], true)
	assert_eq(out[IDs.Output.FOOD], 0, "Mountain: 0 food")
	assert_eq(out[IDs.Output.PRODUCTION], 0, "Mountain: 0 production (reference)")
	assert_eq(out[IDs.Output.COMMERCE], 0, "Mountain: 0 commerce")
	assert_false(TileOutput.workable(tile, db), "Mountain is unworkable")
	assert_true(TileOutput.workable(_tile("hills"), db), "Hills stay workable")

func test_hills_base_output() -> void:
	var out = TileOutput.compute(_tile("hills"), _db(), [])
	assert_eq(out[IDs.Output.FOOD], 1, "Hills: 1 food (net grass-hill)")
	assert_eq(out[IDs.Output.PRODUCTION], 1, "Hills: 1 production (net grass-hill, reference)")

func test_output_clamps_to_non_negative() -> void:
	var out = TileOutput.compute(_tile("snow"), _db(), [])
	for v in out:
		assert_true(v >= 0, "No output type should be negative")

func test_improvement_requires_tech() -> void:
	var db = _db()
	var tile = _tile("hills")
	tile.improvement_id = "mine"
	var out_no_tech = TileOutput.compute(tile, db, [])
	var out_with_tech = TileOutput.compute(tile, db, ["mining"])
	assert_true(out_with_tech[IDs.Output.PRODUCTION] >= out_no_tech[IDs.Output.PRODUCTION],
		"Mine production with tech >= without tech")

func test_improvement_adds_documented_bonus() -> void:
	# Building a farm on grassland (agriculture known) adds exactly its documented
	# +1 food bonus over the bare-tile output.
	var db = _db()
	var tile = _tile("grassland")
	var base = TileOutput.compute(tile, db, ["agriculture"])
	tile.improvement_id = "farm"
	var improved = TileOutput.compute(tile, db, ["agriculture"])
	var bonus: int = int(db.get_improvement("farm").get("output_delta", {}).get("food", 0))
	assert_eq(improved[IDs.Output.FOOD], base[IDs.Output.FOOD] + bonus,
		"Farm adds its documented food bonus to grassland output")

func test_cottage_line_base_yields_match_reference() -> void:
	# A6 (documented): cottage-line commerce is 1/2/3/4; the town's +1F/+1P come
	# from civics, not the improvement. Village keeps its documented +1 Food
	# (game-data §"Improvements" table: Village = +3 Commerce +1 Food).
	var db = _db()
	var expected := {"cottage": 1, "hamlet": 2, "village": 3, "town": 4}
	var food_bonus := {"cottage": 0, "hamlet": 0, "village": 1, "town": 0}
	for imp in expected:
		var tile = _tile("grassland")
		tile.improvement_id = imp
		var techs = ["pottery", "printing_press", "nationalism"]
		var out = TileOutput.compute(tile, db, techs)
		assert_eq(out[IDs.Output.FOOD], 2 + food_bonus[imp],
			imp + ": documented food above the grassland base")
		assert_eq(out[IDs.Output.PRODUCTION], 0, imp + ": no base production")
		assert_eq(out[IDs.Output.COMMERCE], expected[imp],
			imp + ": base commerce matches the reference")

func test_workshop_trades_food_for_production() -> void:
	# A6 (reference): workshop is -1 food / +1 production at base.
	var db = _db()
	var tile = _tile("grassland")
	tile.improvement_id = "workshop"
	var out = TileOutput.compute(tile, db, ["metal_casting"])
	assert_eq(out[IDs.Output.FOOD], 1, "Workshop: grassland 2 food less the workshop's 1")
	assert_eq(out[IDs.Output.PRODUCTION], 1, "Workshop: +1 production")

func test_resource_needs_tech_and_improvement() -> void:
	var db = _db()
	var tile = _tile("hills")
	tile.resource_id = "gold"
	tile.improvement_id = "mine"
	var out_no = TileOutput.compute(tile, db, [])
	var out_yes = TileOutput.compute(tile, db, ["mining"])
	assert_gt(out_yes[IDs.Output.COMMERCE], out_no[IDs.Output.COMMERCE],
		"Gold commerce visible only with tech + improvement")
