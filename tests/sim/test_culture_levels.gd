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

# Culture levels (§15.4 / §29.4, D2 + C4): the reference geometric 5-level
# border curve per pace, the culture-level city defence it grants, bombardment
# knocking that defence down, and the 5-points/turn heal.

# The scene layer reads CultureLevels/Combat too — canary against silent parse
# failures (GUT swallows script load errors).
func test_culture_levels_script_compiles() -> void:
	assert_true(load("res://src/sim/culture_levels.gd").can_instance(),
		"culture_levels.gd compiles")

# ── D2: the reference curve (5 levels × 4 speeds) ─────────────────────────────

func test_thresholds_pin_the_reference_table_per_pace() -> void:
	# game-data §29.4 (verified against the reference): geometric 10→100→500→
	# 5000→50000 at normal; quick ×½, epic ×1.5, marathon ×3.
	var expected := {
		"quick":    [5, 50, 250, 2500, 25000],
		"normal":   [10, 100, 500, 5000, 50000],
		"epic":     [15, 150, 750, 7500, 75000],
		"marathon": [30, 300, 1500, 15000, 150000],
	}
	var db = make_db()
	for pace_id in expected:
		assert_eq(CultureLevels.thresholds(db, pace_id), expected[pace_id],
			"pace '%s' carries the reference culture-level thresholds" % pace_id)

func test_level_for_boundaries_at_normal_pace() -> void:
	var db = make_db()
	var cases := {0: 0, 9: 0, 10: 1, 99: 1, 100: 2, 499: 2, 500: 3,
		4999: 3, 5000: 4, 49999: 4, 50000: 5, 999999: 5}
	for total in cases:
		assert_eq(CultureLevels.level_for(db, "normal", total), cases[total],
			"%s culture is level %s at normal pace" % [total, cases[total]])

func test_level_for_uses_the_pace_column() -> void:
	var db = make_db()
	assert_eq(CultureLevels.level_for(db, "quick", 5), 1,
		"5 culture reaches fledgling on quick")
	assert_eq(CultureLevels.level_for(db, "marathon", 29), 0,
		"29 culture is still poor on marathon")
	assert_eq(CultureLevels.level_for(db, "marathon", 300), 2,
		"300 culture reaches developing on marathon")

func test_legendary_threshold_per_pace() -> void:
	var db = make_db()
	var expected := {"quick": 25000, "normal": 50000,
		"epic": 75000, "marathon": 150000}
	for pace_id in expected:
		assert_eq(CultureLevels.legendary_threshold(db, pace_id), expected[pace_id],
			"legendary culture on %s is %s" % [pace_id, expected[pace_id]])

func test_border_ring_follows_the_curve() -> void:
	# TurnEngine._settlement_culture recomputes ring = level + 1 from the pace
	# table (a fresh city is ring 1; legendary reaches ring 6).
	var gs = make_gs(2)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_commerce = 0
	var cases := {0: 1, 10: 2, 100: 3, 500: 4, 5000: 5, 50000: 6, 60000: 6}
	for total in cases:
		s.culture_total = total
		TurnEngine._settlement_culture(gs, s, gs.get_player(1))
		assert_eq(s.culture_ring, cases[total],
			"%s culture gives border ring %s" % [total, cases[total]])

func test_border_ring_respects_pace() -> void:
	var gs = make_gs(2)
	gs.pace_id = "marathon"
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_commerce = 0
	s.culture_total = 100   # a level-2 total at normal is still level 1 on marathon
	TurnEngine._settlement_culture(gs, s, gs.get_player(1))
	assert_eq(s.culture_ring, 2, "100 culture on marathon is only ring 2")

func test_level_names() -> void:
	var db = make_db()
	assert_eq(CultureLevels.level_name(db, 0), "Poor", "level 0 is Poor")
	assert_eq(CultureLevels.level_name(db, 5), "Legendary", "level 5 is Legendary")
	assert_eq(CultureLevels.level_name(db, 9), "Legendary",
		"an out-of-range level clamps to the top name")

# ── C4: culture-level city defence ────────────────────────────────────────────

func test_defence_pct_per_level() -> void:
	var db = make_db()
	var expected := [0, 20, 40, 60, 80, 100]
	for level in range(expected.size()):
		assert_eq(CultureLevels.defence_pct(db, level), expected[level],
			"level %s grants +%s%% city defence" % [level, expected[level]])
	assert_eq(CultureLevels.defence_pct(db, 9), 100,
		"a pre-D2 save's oversized level clamps to the top defence entry")

func test_settlement_defence_includes_culture_level() -> void:
	var gs = make_gs(2)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.culture_ring = 3   # developing → +40%
	assert_eq(Combat.culture_defence(s, gs.db), 40, "developing culture defends +40%")
	assert_eq(Combat.settlement_defence(s, gs.db), 40,
		"the settlement defence sum carries the culture contribution")
	s.structures = ["walls"]   # defence_bonus 50 + cultural_defence_bonus 10
	assert_eq(Combat.settlement_defence(s, gs.db), 100,
		"structure and culture defences stack additively")

func test_bombard_damage_degrades_culture_defence_proportionally() -> void:
	var gs = make_gs(2)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.culture_ring = 6   # legendary → +100%
	s.defence_damage = 50
	assert_eq(Combat.culture_defence(s, gs.db), 50,
		"50 points of bombardment halve the culture defence")
	s.defence_damage = 100
	assert_eq(Combat.culture_defence(s, gs.db), 0,
		"maximum bombardment flattens the culture defence")
	s.defence_damage = 0
	assert_eq(Combat.culture_defence(s, gs.db), 100,
		"an undamaged legendary city defends at the full +100%")

# ── C4: the bombard mission knocks the defence down ───────────────────────────

func _bombard_board():
	# Player 2 city (fledgling culture) garrisoned by a warrior; a player-1
	# catapult adjacent to it. Returns [gs, facade, settlement, catapult, warrior].
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.alliances[0].at_war_with = [2]
	gs.alliances[1].at_war_with = [1]
	var s = make_settlement(gs, 2, 6, 5, 3)
	s.culture_total = 10
	s.culture_ring = 2   # fledgling → +20%
	var w = make_unit(gs, "warrior", 2, 6, 5)
	var cat = make_unit(gs, "catapult", 1, 5, 5)
	return [gs, f, s, cat, w]

func test_bombard_mission_reduces_city_defence_without_combat() -> void:
	var b = _bombard_board()
	var gs = b[0]; var f = b[1]; var s = b[2]; var cat = b[3]; var w = b[4]
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD,
		"player_id": 1, "unit_id": cat.id, "target_x": 6, "target_y": 5}),
		"bombarding an adjacent hostile city resolves")
	assert_eq(s.defence_damage, 8, "a catapult (bombard_rate 8) knocks off 8 points")
	assert_eq(Combat.culture_defence(s, gs.db), 18,
		"20% fledgling defence degraded by 8/100 damage is 18%")
	assert_eq(w.health, 100, "defence bombardment never touches the garrison")
	assert_eq(cat.x, 5, "the bombarding unit holds its tile")
	assert_true(cat.has_moved, "the bombardment consumes the unit's turn")

func test_bombard_damage_caps_at_max() -> void:
	var b = _bombard_board()
	var f = b[1]; var s = b[2]; var cat = b[3]
	s.culture_ring = 6   # legendary — keeps the effective defence above zero
	s.defence_damage = 97
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD,
		"player_id": 1, "unit_id": cat.id, "target_x": 6, "target_y": 5}),
		"a near-flattened defence can still be bombarded")
	assert_eq(s.defence_damage, 100,
		"defence damage caps at max_city_defence_damage (100)")

func test_bombard_from_range_rejected_for_ground_units() -> void:
	var b = _bombard_board()
	var gs = b[0]; var f = b[1]; var s = b[2]; var cat = b[3]
	cat.x = 3   # distance 3 from the city
	assert_false(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD,
		"player_id": 1, "unit_id": cat.id, "target_x": 6, "target_y": 5}),
		"ground bombardment only works from an adjacent tile")
	assert_eq(s.defence_damage, 0, "a rejected mission changes nothing")

func test_bombard_falls_through_to_attack_when_defence_is_flat() -> void:
	# Once the culture defence is gone the same mission is the ranged attack it
	# always was — the garrison takes the hit.
	var b = _bombard_board()
	var gs = b[0]; var f = b[1]; var s = b[2]; var cat = b[3]; var w = b[4]
	s.defence_damage = 100
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD,
		"player_id": 1, "unit_id": cat.id, "target_x": 6, "target_y": 5}),
		"bombarding a flattened city resolves as an attack")
	assert_eq(s.defence_damage, 100, "no further defence damage accrues")
	assert_true(w.health < 100 or gs.get_unit(w.id) == null,
		"the garrison fought the ranged attack")

func test_bombard_without_rate_attacks_as_before() -> void:
	# A unit with no bombard_rate (an archer) never bombards defences — its
	# mission is the plain ranged attack even against a cultured city.
	var b = _bombard_board()
	var gs = b[0]; var f = b[1]; var s = b[2]; var w = b[4]
	var archer = make_unit(gs, "archer", 1, 5, 5)
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD,
		"player_id": 1, "unit_id": archer.id, "target_x": 6, "target_y": 5}),
		"a rate-less unit's bombard mission resolves as combat")
	assert_eq(s.defence_damage, 0, "no defence damage without a bombard_rate")
	assert_true(w.health < 100 or gs.get_unit(w.id) == null,
		"the garrison fought the ranged attack")

func test_air_bombard_reduces_defences_within_range() -> void:
	var b = _bombard_board()
	var gs = b[0]; var f = b[1]; var s = b[2]
	var bomber = make_unit(gs, "bomber", 1, 2, 5)   # distance 4 ≤ air range
	assert_true(f._cmd_mission({"type": IDs.CommandType.MISSION_BOMBARD,
		"player_id": 1, "unit_id": bomber.id, "target_x": 6, "target_y": 5}),
		"an air unit bombards city defences at range")
	assert_eq(s.defence_damage, 16, "a bomber (bombard_rate 16) knocks off 16 points")

func test_defence_damage_heals_five_per_turn() -> void:
	var gs = make_gs(2)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.defence_damage = 12
	TurnEngine._settlement_upkeep(gs, s, gs.get_player(1))
	assert_eq(s.defence_damage, 7, "city defence heals 5 points per turn")
	TurnEngine._settlement_upkeep(gs, s, gs.get_player(1))
	TurnEngine._settlement_upkeep(gs, s, gs.get_player(1))
	assert_eq(s.defence_damage, 0, "healing floors at zero")

func test_defence_damage_survives_save_load_with_identical_hash() -> void:
	var f = setup_facade(77)
	var gs = f.get_state()
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.culture_total = 100
	s.culture_ring = 2
	s.defence_damage = 23
	var save_json: String = f.save()
	var h1: int = f.state_hash()
	var f2 = load("res://src/api/sim_facade.gd").new()
	f2.init_for_load(make_db())
	f2.load_save(save_json)
	assert_eq(f2.state_hash(), h1,
		"defence damage survives save/load with an identical hash")
	var s2 = f2.get_state().settlements[f2.get_state().settlements.size() - 1]
	assert_eq(s2.defence_damage, 23, "the loaded city keeps its bombardment damage")
