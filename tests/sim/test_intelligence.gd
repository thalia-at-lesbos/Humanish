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

# Intelligence missions (§7): espionage spends accrued intel points and a
# steal-tech mission transfers a tech the thief lacks.

func test_espionage_spends_intel_points() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(2).technologies = ["mining"]
	var cost: int = gs.db.get_constant("intel_mission_cost", 100)
	gs.get_player(1).intel_points = {2: cost + 50}
	assert_true(f._cmd_espionage_mission({"player_id": 1, "target_alliance_id": 2,
		"mission": "steal_tech"}), "Mission runs when points suffice")
	assert_eq(int(gs.get_player(1).intel_points.get(2, 0)), 50,
		"Mission spends its intel cost regardless of interception")

func test_espionage_rejected_without_points() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(1).intel_points = {2: 10}
	assert_false(f._cmd_espionage_mission({"player_id": 1, "target_alliance_id": 2,
		"mission": "steal_tech"}), "Mission fails without enough points")

func test_steal_tech_transfers_unknown_tech() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(2).technologies = ["mining"]
	f._espionage_steal_tech(gs.get_player(1), gs.alliances[1])
	assert_true(gs.get_player(1).has_tech("mining"), "Steal grants a tech the thief lacked")

# ── Accumulation: structures feed espionage points (§7, §15.5 provisional) ─────

func test_building_espionage_accumulates() -> void:
	var gs = make_gs(2)
	gs.alliances[0].contacts = [2]
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_commerce = 0           # isolate the flat building contribution
	s.structures = ["jail"]         # Jail grants +4 flat espionage
	TurnEngine._apply_intelligence(gs, gs.get_player(1))
	assert_eq(int(gs.get_player(1).intel_points.get(2, 0)), 4,
		"A Jail's flat espionage accrues against the one known alliance")

func test_espionage_output_multiplier() -> void:
	var gs = make_gs(2)
	gs.alliances[0].contacts = [2]
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_commerce = 0
	# Intelligence Agency: +8 flat espionage, +50% espionage output → 8 + 4 = 12.
	s.structures = ["intelligence_agency"]
	TurnEngine._apply_intelligence(gs, gs.get_player(1))
	assert_eq(int(gs.get_player(1).intel_points.get(2, 0)), 12,
		"espionage_output scales the city's espionage before distribution")

# ── Mission cost scales with the defender's EP advantage (§15.5 provisional) ───

func test_mission_cost_scales_with_defender_ep() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var base: int = gs.db.get_constant("intel_mission_cost", 100)
	gs.get_player(2).technologies = ["mining"]
	# Attacker holds exactly `base`; defender holds far more against the attacker,
	# so the mission costs more than `base` and is refused.
	gs.get_player(1).intel_points = {2: base}
	gs.get_player(2).intel_points = {1: base * 3}
	assert_false(f._cmd_espionage_mission({"player_id": 1, "target_alliance_id": 2,
		"mission": "steal_tech"}), "A well-defended rival costs more than the base")
	assert_eq(f._espionage_mission_cost(gs.get_player(1), gs.alliances[1], base), base * 3,
		"Cost = base × (1 + EP-advantage/100); 200%% advantage trebles it")

func test_mission_cost_floors_at_base_when_attacker_ahead() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var base: int = gs.db.get_constant("intel_mission_cost", 100)
	gs.get_player(1).intel_points = {2: base * 5}
	assert_eq(f._espionage_mission_cost(gs.get_player(1), gs.alliances[1], base * 5), base,
		"No surcharge when the attacker out-spies the defender")

# ── espionage_defense raises interception chance (§15.5 provisional) ───────────

func test_espionage_defense_raises_interception() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var base_chance: int = gs.db.get_constant("intel_interception_chance", 25)
	assert_eq(f._espionage_interception_chance(gs.alliances[1]), base_chance,
		"Undefended alliance keeps the base interception chance")
	var s = make_settlement(gs, 2, 8, 8, 3)
	s.structures = ["security_bureau"]   # +50% espionage defense
	assert_eq(f._espionage_interception_chance(gs.alliances[1]), base_chance + 50,
		"A Security Bureau adds its espionage_defense to interception")

# ── Incite unrest tips the largest enemy city into disorder (§7 provisional) ───

func test_incite_unrest_puts_largest_city_in_disorder() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	make_settlement(gs, 2, 8, 8, 2)
	var big = make_settlement(gs, 2, 10, 10, 6)
	f._espionage_incite_unrest(gs.alliances[1])
	assert_true(big.in_disorder, "The most populous enemy city falls into disorder")
	assert_eq(big.discontented, big.population, "Its whole population is discontented")
