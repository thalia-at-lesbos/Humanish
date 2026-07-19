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

# ── §15.14 air interception (M3) ─────────────────────────────────────────────

func test_air_strike_intercepted_aborts_mission() -> void:
	# A patrolling, unmoved enemy fighter (intercept 100) always engages a
	# 0-evasion bomber: the strike is aborted and the ground target untouched.
	var gs = make_gs()
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	var bomber = make_unit(gs, "bomber", 1, 5, 5)
	var target = make_unit(gs, "warrior", 2, 8, 5)
	var fi = make_unit(gs, "fighter", 2, 8, 6)  # air_range 6 covers the target
	fi.is_patrolling = true
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": bomber.id, "target_x": 8, "target_y": 5}),
		"An intercepted strike still consumes the mission")
	assert_eq(target.health, 100,
		"The intercepted strike leaves the ground target untouched")
	assert_true(fi.has_intercepted,
		"The interceptor is marked as having intercepted this turn")
	assert_true(bomber.has_moved, "The striker's turn is spent")

func test_interceptor_once_per_turn() -> void:
	# The spent fighter cannot engage a second inbound strike this turn.
	var gs = make_gs()
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	var b1 = make_unit(gs, "bomber", 1, 5, 5)
	var b2 = make_unit(gs, "bomber", 1, 5, 6)
	var target = make_unit(gs, "warrior", 2, 8, 5)
	target.base_strength = 1; target.health = 1
	var fi = make_unit(gs, "fighter", 2, 8, 6)
	fi.is_patrolling = true
	f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": b1.id, "target_x": 8, "target_y": 5})
	assert_true(fi.has_intercepted, "The first strike is engaged")
	assert_eq(target.health, 1, "The first strike is aborted")
	f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": b2.id, "target_x": 8, "target_y": 5})
	assert_eq(gs.get_unit(target.id), null,
		"The spent interceptor lets the second strike through")

func test_evasion_skips_interception() -> void:
	# With the evasion cap raised, a 100-evasion guided missile always slips
	# past a guaranteed interceptor: the mission proceeds unengaged.
	var gs = make_gs()
	gs.db.constants["air_evasion_cap"] = 100
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	var missile = make_unit(gs, "guided_missile", 1, 5, 5)
	var target = make_unit(gs, "warrior", 2, 8, 5)
	target.base_strength = 1; target.health = 1
	var fi = make_unit(gs, "fighter", 2, 8, 6)
	fi.is_patrolling = true
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": missile.id, "target_x": 8, "target_y": 5}),
		"The evading strike resolves")
	assert_false(fi.has_intercepted, "A fully evaded strike is never engaged")
	assert_eq(gs.get_unit(target.id), null, "The strike lands and kills the target")

func test_intercepted_missile_still_consumed() -> void:
	var gs = make_gs()
	gs.db.units["guided_missile"]["evasion_chance"] = 0  # force the engagement
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	var missile = make_unit(gs, "guided_missile", 1, 5, 5)
	var target = make_unit(gs, "warrior", 2, 8, 5)
	var fi = make_unit(gs, "fighter", 2, 8, 6)
	fi.is_patrolling = true
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": missile.id, "target_x": 8, "target_y": 5}),
		"The intercepted launch still resolves")
	assert_eq(gs.get_unit(missile.id), null,
		"A one_use weapon is consumed even when intercepted")
	assert_eq(target.health, 100, "The aborted strike deals no ground damage")

func test_ground_interceptor_engages_unharmed() -> void:
	# A SAM guarding the target tile (chance pinned to 100) engages the strike
	# and, being a ground unit, takes no damage from the engagement.
	var gs = make_gs()
	gs.db.units["sam_infantry"]["intercept_chance"] = 100
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	var bomber = make_unit(gs, "bomber", 1, 5, 5)
	var sam = make_unit(gs, "sam_infantry", 2, 8, 5)
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": bomber.id, "target_x": 8, "target_y": 5}),
		"The contested strike resolves")
	assert_true(sam.has_intercepted, "The SAM engaged the strike")
	assert_eq(sam.health, 100, "A ground interceptor takes no engagement damage")
	assert_true(gs.get_unit(bomber.id) == null or bomber.health < 100,
		"The striker takes interception damage (50 per lost round)")

func test_unpatrolled_fighter_lets_strike_through() -> void:
	# An idle (non-patrolling) fighter is not on the intercept stance: the
	# clean-run path — the strike resolves with no engagement.
	var gs = make_gs()
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]; gs.alliances[1].at_war_with = [1]
	var bomber = make_unit(gs, "bomber", 1, 5, 5)
	var target = make_unit(gs, "warrior", 2, 8, 5)
	target.base_strength = 1; target.health = 1
	var fi = make_unit(gs, "fighter", 2, 8, 6)  # not patrolling
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD, "player_id": 1,
		"unit_id": bomber.id, "target_x": 8, "target_y": 5}),
		"The uncontested strike resolves")
	assert_false(fi.has_intercepted, "The idle fighter never engaged")
	assert_eq(gs.get_unit(target.id), null, "The strike lands and kills the target")

func test_has_intercepted_resets_next_turn() -> void:
	var gs = make_gs()
	var fi = make_unit(gs, "fighter", 2, 8, 6)
	fi.has_intercepted = true
	TurnEngine.player_step(gs, 2, hooks())
	assert_false(fi.has_intercepted,
		"The once-per-turn interception flag resets on the owner's turn")
