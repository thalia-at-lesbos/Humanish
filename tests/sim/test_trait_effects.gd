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

# TraitEffects — the PolicyEffects analogue for leader traits (B4): the single
# reader of the trait build-speed carriers `double_production_structures`
# (+trait_double_production_pct on listed structures) and
# `unit_production_modifiers` (per-unit +%).

func test_sum_int_sums_across_traits() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.traits = ["expansive", "charismatic"]
	assert_eq(TraitEffects.sum_int(p, gs.db, "health_bonus"), 2,
		"Expansive contributes its +2 health")
	assert_eq(TraitEffects.sum_int(p, gs.db, "happiness_bonus"), 1,
		"Charismatic contributes its +1 happiness")
	assert_eq(TraitEffects.sum_int(p, gs.db, "no_such_key"), 0,
		"An absent key contributes 0")
	assert_eq(TraitEffects.sum_int(null, gs.db, "health_bonus"), 0,
		"A null player sums to 0")

func test_production_pct_doubles_listed_structure() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.traits = ["aggressive"]
	assert_eq(TraitEffects.production_pct(p, gs.db,
		{"type": "structure", "id": "barracks"}), 100,
		"Aggressive grants +100% toward a barracks")
	assert_eq(TraitEffects.production_pct(p, gs.db,
		{"type": "structure", "id": "library"}), 0,
		"An unlisted structure gets nothing")
	assert_eq(TraitEffects.production_pct(p, gs.db,
		{"type": "unit", "id": "settler"}), 0,
		"Aggressive carries no unit modifiers")

func test_production_pct_reads_unit_modifiers() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.traits = ["imperialistic", "expansive"]
	assert_eq(TraitEffects.production_pct(p, gs.db,
		{"type": "unit", "id": "settler"}), 50,
		"Imperialistic trains settlers +50% (reference)")
	assert_eq(TraitEffects.production_pct(p, gs.db,
		{"type": "unit", "id": "worker"}), 25,
		"Expansive trains workers +25% (reference)")
	assert_eq(TraitEffects.production_pct(p, gs.db,
		{"type": "unit", "id": "warrior"}), 0,
		"An unlisted unit gets nothing")

func test_production_pct_stacks_same_item_across_traits() -> void:
	# Two traits listing the same structure sum additively (no shipped pair does,
	# but the reader must not silently cap at one hit).
	var gs = make_gs(1)
	gs.db.leaders_traits["traits"]["test_extra"] = {"id": "test_extra",
		"double_production_structures": ["barracks"]}
	var p = gs.get_player(1)
	p.traits = ["aggressive", "test_extra"]
	assert_eq(TraitEffects.production_pct(p, gs.db,
		{"type": "structure", "id": "barracks"}), 200,
		"Two traits listing the same structure sum their percentages")

func test_production_pct_null_player_and_projects() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.traits = ["aggressive"]
	assert_eq(TraitEffects.production_pct(null, gs.db,
		{"type": "structure", "id": "barracks"}), 0,
		"A null player (wild settlement) gets nothing")
	assert_eq(TraitEffects.production_pct(p, gs.db,
		{"type": "project", "id": "apollo_program"}), 0,
		"Projects are outside the trait model")
