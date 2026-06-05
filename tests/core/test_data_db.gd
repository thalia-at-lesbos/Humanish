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

# DataDB loading mechanics and content integrity. Everything the engine reads at
# runtime — tables, cross-references, the tech tree shape, civics, starting
# units — must be present and internally consistent before any rule runs.

func _db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

# ── Loading & getters ──────────────────────────────────────────────────────────

func test_loads_without_errors() -> void:
	var db = _db()
	if not db.get_errors().empty():
		for err in db.get_errors():
			gut.p("DataDB error: " + err)
	assert_true(db.get_errors().empty(),
		"DataDB.load_all() must succeed with no cross-reference errors")

func test_terrains_present() -> void:
	var db = _db()
	assert_true(db.terrains.has("grassland"), "grassland terrain must exist")
	assert_true(db.terrains.has("ocean"), "ocean terrain must exist")

func test_get_constant_default() -> void:
	var db = _db()
	assert_eq(db.get_constant("nonexistent_key", 42), 42,
		"Missing key returns default value")

func test_get_constant_loaded() -> void:
	var db = _db()
	assert_gt(db.get_constant("combat_scale", 0), 0,
		"combat_scale must be a positive integer")

# ── Tech tree shape ──────────────────────────────────────────────────────────

func test_tech_tree_ages_present() -> void:
	var db = _db()
	for tid in ["agriculture", "pottery", "writing", "alphabet"]:
		assert_false(db.get_technology(tid).empty(), "Tech '%s' must exist" % tid)

func test_tech_tree_is_linear_progression() -> void:
	var db = _db()
	assert_eq(db.get_technology("pottery").get("prereqs_all"), ["agriculture"],
		"pottery requires agriculture")
	assert_eq(db.get_technology("writing").get("prereqs_all"), ["pottery"],
		"writing requires pottery")
	assert_eq(db.get_technology("alphabet").get("prereqs_all"), ["writing"],
		"alphabet requires writing")

# ── Civics ───────────────────────────────────────────────────────────────────

func test_civics_all_four_present() -> void:
	var db = _db()
	var pols = db.policies.get("policies", {})
	for cid in ["communism", "anarcho_communism", "anarcho_capitalism", "fascism"]:
		assert_true(pols.has(cid), "Civic '%s' must exist" % cid)
		assert_eq(str(pols[cid].get("category", "")), "civic",
			"Civic '%s' is in the 'civic' category" % cid)

func test_civic_category_registered() -> void:
	var db = _db()
	assert_true("civic" in db.policies.get("categories", []),
		"'civic' must be a registered policy category")

# ── Units & societies ──────────────────────────────────────────────────────────

func test_scout_unit_exists() -> void:
	var db = _db()
	assert_false(db.get_unit("scout").empty(), "A 'scout' unit type must exist")

func test_every_society_has_required_starting_units() -> void:
	var db = _db()
	var required = ["settler", "worker", "scout", "warrior", "archer"]
	for sid in db.get_societies():
		var su = db.get_society(sid).get("starting_units", [])
		for r in required:
			assert_true(r in su,
				"Society '%s' starting_units must include a %s" % [sid, r])
