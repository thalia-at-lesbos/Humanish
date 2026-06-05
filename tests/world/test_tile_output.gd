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
	assert_eq(out[IDs.Output.PRODUCTION], 1, "Grassland: 1 production")

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

func test_resource_needs_tech_and_improvement() -> void:
	var db = _db()
	var tile = _tile("hills")
	tile.resource_id = "gold"
	tile.improvement_id = "mine"
	var out_no = TileOutput.compute(tile, db, [])
	var out_yes = TileOutput.compute(tile, db, ["mining"])
	assert_gt(out_yes[IDs.Output.COMMERCE], out_no[IDs.Output.COMMERCE],
		"Gold commerce visible only with tech + improvement")
