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

# Nuclear weapons & radioactive fallout (§5.7). Covers eligibility, the area-effect
# blast on units/settlements/tiles, Bomb-Shelter mitigation, fallout contamination,
# interception, the no_nuclear ban, the clean-fallout worker action, and meltdowns.

# Give a settlement a Manhattan Project so Nuclear.nukes_enabled() is true.
func _enable_nukes(gs, owner_id):
	var s = make_settlement(gs, owner_id, 0, 0, 1)
	s.structures.append("manhattan_project")
	return s

func test_is_nuke_detects_tagged_units():
	var gs = make_gs(1)
	var nuke = make_unit(gs, "tactical_nuke", 1, 5, 5)
	var warrior = make_warrior(gs, 1, 6, 6)
	assert_true(Nuclear.is_nuke(gs.db, nuke), "tactical_nuke carries the nuke tag")
	assert_false(Nuclear.is_nuke(gs.db, warrior), "a warrior is not a nuke")

func test_nukes_enabled_requires_manhattan_project():
	var gs = make_gs(1)
	assert_false(Nuclear.nukes_enabled(gs), "no nukes before the Manhattan Project")
	_enable_nukes(gs, 1)
	assert_true(Nuclear.nukes_enabled(gs), "Manhattan Project enables nukes globally")

func test_blast_radius_from_data():
	var gs = make_gs(1)
	var tac = make_unit(gs, "tactical_nuke", 1, 5, 5)
	var icbm = make_unit(gs, "icbm", 1, 5, 5)
	assert_eq(Nuclear.blast_radius(gs.db, tac), 0, "tactical nuke is a point strike")
	assert_eq(Nuclear.blast_radius(gs.db, icbm), 1, "ICBM has radius 1")

func test_detonate_increments_nuke_tally():
	# §11 global warming reads gs.nukes_exploded; every detonation bumps it.
	var gs = make_gs(2)
	var attacker = make_unit(gs, "tactical_nuke", 1, 5, 5)
	assert_eq(gs.nukes_exploded, 0, "Tally starts at zero")
	Nuclear.detonate(gs, attacker, 8, 8, gs.rng)
	assert_eq(gs.nukes_exploded, 1, "A detonation increments the nuke tally")

func test_detonate_softens_units_but_floors_at_one():
	var gs = make_gs(2)
	var attacker = make_unit(gs, "tactical_nuke", 1, 5, 5)
	var victim = make_warrior(gs, 2, 8, 8)
	victim.health = 100
	var res = Nuclear.detonate(gs, attacker, 8, 8, gs.rng)
	assert_true(victim.id in res["units_hit"], "victim recorded as hit")
	assert_true(victim.health < 100, "victim took blast damage")
	assert_true(victim.health >= 1, "a strike never wipes a unit to zero")

func test_detonate_hits_friendly_units_too():
	var gs = make_gs(1)
	var attacker = make_unit(gs, "tactical_nuke", 1, 1, 1)
	var own = make_warrior(gs, 1, 8, 8)
	Nuclear.detonate(gs, attacker, 8, 8, gs.rng)
	assert_true(own.health < 100, "no friendly-fire exemption: own units are hit")

func test_detonate_damages_settlement_without_destroying():
	var gs = make_gs(2)
	var attacker = make_unit(gs, "tactical_nuke", 1, 1, 1)
	var city = make_settlement(gs, 2, 8, 8, 10)
	city.peak_population = 10
	var res = Nuclear.detonate(gs, attacker, 8, 8, gs.rng)
	assert_true(city.id in res["settlements_hit"], "settlement recorded as hit")
	assert_true(city.population < 10, "settlement lost population")
	assert_true(city.population >= 1, "a strike never destroys a settlement outright")
	assert_true(city in gs.settlements, "settlement still exists after the strike")

func test_bomb_shelter_reduces_population_loss():
	var gs = make_gs(2, 7)
	var attacker = make_unit(gs, "tactical_nuke", 1, 1, 1)
	# Two identical cities; one has a Bomb Shelter.
	var bare = make_settlement(gs, 2, 8, 8, 10)
	bare.peak_population = 10
	var gs2 = make_gs(2, 7)
	var attacker2 = make_unit(gs2, "tactical_nuke", 1, 1, 1)
	var sheltered = make_settlement(gs2, 2, 8, 8, 10)
	sheltered.peak_population = 10
	sheltered.structures.append("bomb_shelter")
	Nuclear.detonate(gs, attacker, 8, 8, gs.rng)
	Nuclear.detonate(gs2, attacker2, 8, 8, gs2.rng)
	assert_true(sheltered.population > bare.population,
		"Bomb Shelter softens the population loss")

func test_detonate_creates_fallout():
	var gs = make_gs(1)
	gs.db.constants["nuke_fallout_chance"] = 100
	gs.db.constants["nuke_fallout_ring_chance"] = 0
	var attacker = make_unit(gs, "tactical_nuke", 1, 1, 1)
	var res = Nuclear.detonate(gs, attacker, 8, 8, gs.rng)
	var t = gs.map.get_tile(8, 8)
	assert_eq(t.feature_id, "fallout", "target tile is contaminated at 100% chance")
	assert_true([8, 8] in res["fallout_tiles"], "fallout tile reported in result")

func test_detonate_strips_improvement():
	var gs = make_gs(1)
	gs.db.constants["nuke_fallout_chance"] = 0
	gs.db.constants["nuke_fallout_ring_chance"] = 0
	var attacker = make_unit(gs, "tactical_nuke", 1, 1, 1)
	var t = gs.map.get_tile(8, 8)
	t.improvement_id = "farm"
	Nuclear.detonate(gs, attacker, 8, 8, gs.rng)
	assert_eq(t.improvement_id, "", "improvements are stripped by the blast")

func test_detonate_accrues_war_fatigue_on_attacker():
	var gs = make_gs(2)
	var attacker = make_unit(gs, "tactical_nuke", 1, 1, 1)
	make_warrior(gs, 2, 8, 8)
	Nuclear.detonate(gs, attacker, 8, 8, gs.rng)
	var aa = gs.get_alliance(1)
	assert_true(int(aa.war_fatigue.get(2, 0)) > 0,
		"the attacker's alliance accrues war-fatigue against the victim")

func test_facade_strike_consumes_unit_and_emits():
	var gs = make_gs(2)
	_enable_nukes(gs, 1)
	gs.current_player_id = 1
	var f = bare_facade(gs)
	watch_signals(f)
	var nuke = make_unit(gs, "tactical_nuke", 1, 5, 5)
	make_warrior(gs, 2, 7, 7)
	var ok = f.apply_command(Commands.nuclear_strike(1, nuke.id, 7, 7))
	assert_true(ok, "strike accepted")
	assert_null(gs.get_unit(nuke.id), "the missile is consumed on launch")
	assert_signal_emitted(f, "nuclear_detonated")

func test_facade_strike_rejected_without_manhattan_project():
	var gs = make_gs(2)
	gs.current_player_id = 1
	var f = bare_facade(gs)
	var nuke = make_unit(gs, "tactical_nuke", 1, 5, 5)
	assert_false(f.apply_command(Commands.nuclear_strike(1, nuke.id, 7, 7)),
		"cannot launch without nukes enabled")
	assert_not_null(gs.get_unit(nuke.id), "unit not consumed on a rejected launch")

func test_facade_strike_forbidden_under_non_proliferation():
	var gs = make_gs(2)
	_enable_nukes(gs, 1)
	gs.assembly = {"standing": {"no_nuclear": true}}
	gs.current_player_id = 1
	var f = bare_facade(gs)
	var nuke = make_unit(gs, "tactical_nuke", 1, 5, 5)
	assert_false(f.apply_command(Commands.nuclear_strike(1, nuke.id, 7, 7)),
		"Non-Proliferation forbids launching")
	assert_not_null(gs.get_unit(nuke.id), "unit survives the forbidden launch")

func test_facade_strike_out_of_range_rejected():
	var gs = make_gs(2, 42, 40, 40)
	_enable_nukes(gs, 1)
	gs.current_player_id = 1
	var f = bare_facade(gs)
	var nuke = make_unit(gs, "tactical_nuke", 1, 0, 0)  # air_range 12
	assert_false(f.apply_command(Commands.nuclear_strike(1, nuke.id, 30, 30)),
		"tactical nuke cannot reach beyond its range")
	assert_not_null(gs.get_unit(nuke.id), "unit not consumed on out-of-range launch")

func test_interception_aborts_strike():
	var gs = make_gs(2)
	gs.db.constants["nuke_interception_chance"] = 100
	_enable_nukes(gs, 1)
	# Players 1 and 2 at war so the SAM is hostile.
	gs.get_alliance(1).at_war_with.append(2)
	gs.current_player_id = 1
	var f = bare_facade(gs)
	var nuke = make_unit(gs, "tactical_nuke", 1, 5, 5)
	var target = make_warrior(gs, 2, 8, 8)
	make_unit(gs, "sam_infantry", 2, 8, 9)  # anti_air, adjacent to target
	var ok = f.apply_command(Commands.nuclear_strike(1, nuke.id, 8, 8))
	assert_true(ok, "intercepted strike still consumes the missile")
	assert_null(gs.get_unit(nuke.id), "missile consumed")
	assert_eq(target.health, 100, "intercepted strike does not damage the target")

func test_clean_fallout_mission():
	var gs = make_gs(1)
	gs.current_player_id = 1
	var f = bare_facade(gs)
	var worker = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).feature_id = "fallout"
	var ok = f.apply_command(Commands.mission_clean_fallout(1, worker.id))
	assert_true(ok, "worker cleans fallout")
	assert_eq(gs.map.get_tile(5, 5).feature_id, "", "fallout removed")

func test_clean_fallout_requires_fallout_present():
	var gs = make_gs(1)
	gs.current_player_id = 1
	var f = bare_facade(gs)
	var worker = make_unit(gs, "worker", 1, 5, 5)
	assert_false(f.apply_command(Commands.mission_clean_fallout(1, worker.id)),
		"nothing to clean on a clear tile")

func test_meltdown_spreads_fallout():
	var gs = make_gs(1)
	gs.db.constants["nuclear_meltdown_chance"] = 100
	var s = make_settlement(gs, 1, 8, 8, 5)
	s.structures.append("nuclear_plant")
	var newly = Nuclear.meltdown_tick(gs, gs.rng)
	assert_true(newly.size() > 0, "a guaranteed meltdown contaminates nearby tiles")
	assert_eq(gs.map.get_tile(8, 8).feature_id, "fallout", "the plant's tile is contaminated")

func test_meltdown_quiet_without_plant():
	var gs = make_gs(1)
	gs.db.constants["nuclear_meltdown_chance"] = 100
	make_settlement(gs, 1, 8, 8, 5)  # no nuclear plant
	assert_eq(Nuclear.meltdown_tick(gs, gs.rng).size(), 0,
		"no plant, no meltdown")

func test_strike_determinism_same_seed():
	var a = make_gs(2, 99)
	var b = make_gs(2, 99)
	a.db.constants["nuke_fallout_chance"] = 50
	b.db.constants["nuke_fallout_chance"] = 50
	var ua = make_unit(a, "icbm", 1, 1, 1)
	var ub = make_unit(b, "icbm", 1, 1, 1)
	make_warrior(a, 2, 8, 8)
	make_warrior(b, 2, 8, 8)
	var ra = Nuclear.detonate(a, ua, 8, 8, a.rng)
	var rb = Nuclear.detonate(b, ub, 8, 8, b.rng)
	assert_eq(ra["fallout_tiles"], rb["fallout_tiles"],
		"same seed reproduces the same craters")
