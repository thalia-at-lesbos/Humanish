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

# Air units (§5.2): bombing strikes hit at range without advancing, out-of-range
# targets are refused, and airlifts are bounded by the unit's air range.

func test_air_strike_hits_without_advancing() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	var fighter = make_unit(gs, "fighter", 1, 5, 5)
	var target = make_unit(gs, "warrior", 2, 8, 5)  # within air_range 4
	target.base_strength = 1; target.health = 1
	f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": fighter.id, "target_x": 8, "target_y": 5})
	assert_eq(fighter.x, 5, "Bomber does not advance onto the target tile")
	assert_eq(fighter.y, 5, "Bomber stays at its base position")

func test_air_strike_out_of_range_rejected() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	var fighter = make_unit(gs, "fighter", 1, 5, 5)
	make_unit(gs, "warrior", 2, 15, 5)  # distance 10 > air_range 4
	assert_false(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": fighter.id, "target_x": 15, "target_y": 5}),
		"A target beyond air range cannot be struck")

func test_guided_missile_strikes_and_is_consumed() -> void:
	# A guided missile (strength 40, tag one_use) strikes via the air-bombard
	# path and is spent on launch — it never survives its own mission.
	var gs = make_gs()
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	var missile = make_unit(gs, "guided_missile", 1, 5, 5)
	var target = make_unit(gs, "warrior", 2, 8, 5)  # within air_range 8
	target.base_strength = 1; target.health = 1
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": missile.id, "target_x": 8, "target_y": 5}),
		"A guided missile strike within range resolves")
	assert_eq(gs.get_unit(target.id), null, "The strike destroys the weak target")
	assert_eq(gs.get_unit(missile.id), null, "A one_use weapon is consumed by its strike")

func test_bomber_survives_its_strike() -> void:
	# A reusable air unit (no one_use tag) flies home after striking.
	var gs = make_gs()
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	var bomber = make_unit(gs, "bomber", 1, 5, 5)
	var target = make_unit(gs, "warrior", 2, 8, 5)
	target.base_strength = 1; target.health = 1
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": bomber.id, "target_x": 8, "target_y": 5}),
		"A bomber strike within range resolves")
	assert_ne(gs.get_unit(bomber.id), null, "A reusable air unit survives its own strike")

func test_airlift_limited_by_range() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	var fighter = make_unit(gs, "fighter", 1, 5, 5)
	assert_false(f._cmd_mission({"type": IDs.CommandType.MISSION_AIRLIFT, "player_id": 1,
		"unit_id": fighter.id, "target_x": 19, "target_y": 19}),
		"Air units cannot airlift beyond their range")
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_AIRLIFT, "player_id": 1,
		"unit_id": fighter.id, "target_x": 7, "target_y": 6}),
		"Within range the airlift succeeds")
