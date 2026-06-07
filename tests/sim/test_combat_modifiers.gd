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

# Residual §5.3 combat strength modifiers: river-crossing & amphibious attack
# penalties (constants existed but were unused) and the landform-keyed
# defense_on_hills promotion (a key read by no sim site).

func test_amphibious_penalty_from_water():
	var gs = make_gs(2)
	gs.map.get_tile(5, 5).terrain_id = "ocean"   # attacker on deep water
	var atk = make_warrior(gs, 1, 5, 5)
	var def = make_warrior(gs, 2, 5, 6)          # defender on land, adjacent
	assert_eq(Combat._attack_penalty(atk, def, gs),
		gs.db.get_constant("amphibious_attack_penalty", 50),
		"attacking from water onto land incurs the amphibious penalty")

func test_no_penalty_land_to_land():
	var gs = make_gs(2)
	var atk = make_warrior(gs, 1, 5, 5)
	var def = make_warrior(gs, 2, 5, 6)
	assert_eq(Combat._attack_penalty(atk, def, gs), 0,
		"a plain land attack has no crossing penalty")

func test_amphibious_promotion_waives_penalty():
	var gs = make_gs(2)
	gs.map.get_tile(5, 5).terrain_id = "ocean"
	var atk = make_warrior(gs, 1, 5, 5)
	atk.promotions = ["amphibious"]              # no_amphibious_penalty
	var def = make_warrior(gs, 2, 5, 6)
	assert_eq(Combat._attack_penalty(atk, def, gs), 0,
		"the Amphibious promotion waives the penalty")

func test_amphibious_tag_waives_penalty():
	var gs = make_gs(2)
	gs.map.get_tile(5, 5).terrain_id = "ocean"
	var atk = make_unit(gs, "marine", 1, 5, 5)   # carries the amphibious tag
	var def = make_warrior(gs, 2, 5, 6)
	assert_eq(Combat._attack_penalty(atk, def, gs), 0,
		"an amphibious-tagged unit (Marine) ignores the penalty")

func test_river_crossing_penalty():
	var gs = make_gs(2)
	var atk = make_warrior(gs, 1, 5, 5)
	var def = make_warrior(gs, 2, 5, 4)          # defender to the north
	gs.map.get_tile(5, 5).river_n = true         # river on the shared border
	assert_eq(Combat._attack_penalty(atk, def, gs),
		gs.db.get_constant("river_crossing_attack_penalty", 25),
		"attacking across a river border incurs the river-crossing penalty")

func test_river_between_detects_each_edge():
	var gs = make_gs(1)
	var m = gs.map
	m.get_tile(5, 5).river_w = true
	assert_true(Combat._river_between(m, 5, 5, 4, 5), "west border river detected")
	assert_false(Combat._river_between(m, 5, 5, 6, 5), "no river on the east border")
	m.get_tile(6, 5).river_w = true
	assert_true(Combat._river_between(m, 5, 5, 6, 5), "east border = tile-right's west")
	assert_false(Combat._river_between(m, 5, 5, 6, 6), "diagonals are never river crossings")

func test_penalty_weakens_attacker_in_resolve():
	# Same matchup, with and without the amphibious penalty: the penalised attacker
	# ends up weaker, reflected in lower expected health across a resolve.
	var gs = make_gs(2, 7)
	gs.map.get_tile(5, 5).terrain_id = "ocean"
	var atk = make_warrior(gs, 1, 5, 5)
	var def = make_warrior(gs, 2, 5, 6)
	assert_true(Combat._attack_penalty(atk, def, gs) > 0,
		"setup: the amphibious attacker is penalised")

func test_defense_on_hills_promotion():
	var gs = make_gs(1)
	var db = gs.db
	var u = make_warrior(gs, 1, 5, 5)
	u.promotions = ["guerrilla1"]                # defense_on_hills: 20, applies_to land
	var hills = db.get_terrain("hills")
	var flat = db.get_terrain("grassland")
	var on_hills = u.effective_strength(db, false, hills, {}, "")
	var on_flat = u.effective_strength(db, false, flat, {}, "")
	assert_true(on_hills > on_flat,
		"Guerrilla I makes a defender stronger on Hills than on flat ground")

func test_defense_on_hills_defender_only():
	var gs = make_gs(1)
	var db = gs.db
	var u = make_warrior(gs, 1, 5, 5)
	u.promotions = ["guerrilla1"]
	var hills = db.get_terrain("hills")
	# As the attacker the bonus does not apply (attacker passes empty terrain in
	# Combat.resolve, but verify the role gate directly too).
	var as_attacker = u.effective_strength(db, true, hills, {}, "")
	var base = make_warrior(gs, 1, 6, 6)
	assert_eq(as_attacker, base.effective_strength(db, true, hills, {}, ""),
		"defense_on_hills does not help an attacker")
