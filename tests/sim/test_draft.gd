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

# Conscription / the draft (§6.4). Gated on the can_draft civic (Nationhood);
# spends population for the most advanced draftable unit the player can field.

func _facade_with_city(pop = 5):
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.technologies.append("gunpowder")  # unlocks the Musketman (draftable)
	gs.current_player_id = 1
	var s = make_settlement(gs, 1, 5, 5, pop)
	return [bare_facade(gs), gs, p, s]

func test_draft_requires_can_draft_civic():
	var ctx = _facade_with_city()
	var f = ctx[0]; var gs = ctx[1]; var s = ctx[3]
	assert_false(f.apply_command(Commands.draft(1, s.id)),
		"cannot draft without the Nationhood civic")
	assert_eq(gs.units.size(), 0, "no unit raised")

func test_draft_raises_unit_and_costs_population():
	var ctx = _facade_with_city(5)
	var f = ctx[0]; var gs = ctx[1]; var p = ctx[2]; var s = ctx[3]
	p.policies = {"government": "nationhood"}
	assert_true(f.apply_command(Commands.draft(1, s.id)), "draft accepted")
	assert_eq(gs.units.size(), 1, "a unit was conscripted")
	assert_eq(gs.units[0].unit_type_id, "musketman", "Musketman drafted at gunpowder")
	assert_eq(s.population, 5 - gs.db.get_constant("draft_population_cost", 1),
		"draft costs population")
	assert_true(s.rush_anger_turns > 0, "conscription stirs unhappiness")

func test_draft_picks_most_advanced_draftable():
	var ctx = _facade_with_city(5)
	var f = ctx[0]; var gs = ctx[1]; var p = ctx[2]; var s = ctx[3]
	# Infantry needs the compound assembly_line + rifling AND set (§15.12).
	p.technologies.append("assembly_line")
	p.technologies.append("rifling")
	p.policies = {"government": "nationhood"}
	assert_true(f.apply_command(Commands.draft(1, s.id)))
	assert_eq(gs.units[0].unit_type_id, "infantry",
		"the strongest available draftable unit is chosen")

func test_draft_rejected_without_tech():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.policies = {"government": "nationhood"}  # can_draft, but no military tech
	gs.current_player_id = 1
	var s = make_settlement(gs, 1, 5, 5, 5)
	var f = bare_facade(gs)
	assert_false(f.apply_command(Commands.draft(1, s.id)),
		"no draftable unit unlocked yet")

func test_draft_rejected_below_min_population():
	var ctx = _facade_with_city(1)  # below draft_min_population (2)
	var f = ctx[0]; var gs = ctx[1]; var p = ctx[2]; var s = ctx[3]
	p.policies = {"government": "nationhood"}
	assert_false(f.apply_command(Commands.draft(1, s.id)),
		"a city too small cannot be drafted")
	assert_eq(gs.units.size(), 0, "no unit raised")

func test_conscript_gets_half_the_citys_production_xp():
	# §15.20: a conscripted unit receives half the city's total production XP
	# (civics + buildings + settled Great General instructors), truncated.
	var ctx = _facade_with_city(5)
	var f = ctx[0]; var gs = ctx[1]; var p = ctx[2]; var s = ctx[3]
	p.policies = {"government": "nationhood"}
	s.structures.append("barracks")            # land_xp 3
	s.specialists = {"great_general": 1}       # military instructor +2 (§15.20)
	assert_eq(TurnEngine.new_unit_xp(gs, s, p, "musketman"), 5,
		"fixture sanity: a trained Musketman would start with 5 XP here")
	assert_true(f.apply_command(Commands.draft(1, s.id)), "draft accepted")
	assert_eq(gs.units[0].experience, 2,
		"the conscript receives half the city's 5 production XP, truncated to 2")

func test_draft_rejected_in_disorder():
	var ctx = _facade_with_city(5)
	var f = ctx[0]; var gs = ctx[1]; var p = ctx[2]; var s = ctx[3]
	p.policies = {"government": "nationhood"}
	s.in_disorder = true
	assert_false(f.apply_command(Commands.draft(1, s.id)),
		"a city in disorder cannot be drafted")
