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

# Treasury & upkeep (§6.1): commerce income, unit/improvement upkeep, distance
# scaling, insolvency handling, and the commerce slider split (§6.2).

# ── Commerce allocation ──────────────────────────────────────────────────────

func test_slider_partition_sums_to_100() -> void:
	var p = load("res://src/sim/player.gd").new()
	p.slider_finance = 40; p.slider_research = 30; p.slider_culture = 20; p.slider_intel = 10
	assert_eq(p.get_slider_sum(), 100, "Sliders must sum to 100")

func test_split_commerce_partitions_correctly() -> void:
	var p = load("res://src/sim/player.gd").new()
	p.slider_finance = 50; p.slider_research = 30; p.slider_culture = 10; p.slider_intel = 10
	var split = p.split_commerce(100)
	assert_eq(split[0], 50, "50% finance of 100 = 50")
	assert_eq(split[1], 30, "30% research of 100 = 30")
	assert_eq(split[0] + split[1] + split[2] + split[3], 100, "Split totals must equal input")

# ── Treasury & unit upkeep ───────────────────────────────────────────────────

func test_treasury_increases_from_commerce() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1); p.treasury = 100
	make_settlement(gs, 1, 5, 5).output_commerce = 10
	var before: int = p.treasury
	TurnEngine._update_treasury(gs, p)
	assert_true(p.treasury >= before, "Treasury should not decrease when commerce > upkeep")

func test_unit_upkeep_reduces_treasury() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1); p.treasury = 100
	make_unit(gs, "warrior", 1, 5, 5)
	TurnEngine._update_treasury(gs, p)
	assert_lt(p.treasury, 100, "Warrior upkeep reduces treasury")

func test_distant_settlement_costs_more_upkeep() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	make_settlement(gs, 1, 1, 1, 1)  # capital
	p.treasury = 1000
	TurnEngine._update_treasury(gs, p)
	var near_treasury: int = p.treasury

	var gs2 = make_gs(1)
	var p2 = gs2.get_player(1)
	make_settlement(gs2, 1, 1, 1, 1)
	make_settlement(gs2, 1, 18, 18, 1)  # far from capital
	p2.treasury = 1000
	TurnEngine._update_treasury(gs2, p2)
	assert_lt(p2.treasury, near_treasury, "A distant second settlement raises upkeep")

# ── Tile / improvement upkeep (§3.3) ─────────────────────────────────────────

func test_owned_improvement_charges_upkeep() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1); p.treasury = 10
	var tile = gs.map.get_tile(5, 5)
	tile.owner_player_id = 1
	tile.improvement_id = "road"  # upkeep 1
	TurnEngine._tile_upkeep(gs)
	assert_eq(p.treasury, 9, "Owned improvements charge their upkeep")

func test_unowned_improvement_not_charged() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10
	var tile = gs.map.get_tile(5, 5)
	tile.owner_player_id = -1
	tile.improvement_id = "road"
	TurnEngine._tile_upkeep(gs)
	assert_eq(gs.get_player(1).treasury, 10, "Unowned improvements charge nobody")

# ── Inflation (§15.1) ────────────────────────────────────────────────────────

func test_inflation_zero_at_game_start_on_every_pace() -> void:
	var gs = make_gs(1)
	gs.difficulty_id = "monarch"
	for pace in ["quick", "normal", "epic", "marathon"]:
		gs.pace_id = pace
		gs.turn_number = 0
		assert_eq(TurnEngine.inflation_rate(gs), 0,
			"%s: no inflation at game start" % pace)
	# The negative offset delays onset: still zero at the onset turn itself.
	gs.pace_id = "normal"
	gs.turn_number = 90
	assert_eq(TurnEngine.inflation_rate(gs), 0,
		"normal: onset delayed until past turn 90")

func test_inflation_progression_at_fixed_turn_across_paces() -> void:
	# Turn 300 at monarch (100% handicap): rate = (300 + offset) × pace% / 100.
	var gs = make_gs(1)
	gs.difficulty_id = "monarch"
	gs.turn_number = 300
	var expected = {"quick": 108, "normal": 63, "epic": 33, "marathon": 3}
	for pace in expected:
		gs.pace_id = pace
		assert_eq(TurnEngine.inflation_rate(gs), expected[pace],
			"%s: reference rate at turn 300" % pace)

func test_inflation_difficulty_multiplier() -> void:
	# Normal pace, turn 290 → effective turn 200 → base rate 60%, scaled by the
	# per-difficulty handicap percent (§29.10).
	var gs = make_gs(1)
	gs.pace_id = "normal"
	gs.turn_number = 290
	var expected = {"settler": 36, "chieftain": 42, "warlord": 48, "noble": 54,
		"prince": 57, "monarch": 60, "emperor": 60, "immortal": 60, "deity": 60}
	for diff in expected:
		gs.difficulty_id = diff
		assert_eq(TurnEngine.inflation_rate(gs), expected[diff],
			"%s: handicap-scaled rate" % diff)

func test_inflation_inflates_gold_upkeep_and_treasury_delta() -> void:
	var gs = make_gs(1)
	gs.pace_id = "normal"
	gs.difficulty_id = "monarch"
	var p = gs.get_player(1)
	for i in range(10):
		make_unit(gs, "warrior", 1, i, 0)   # 10 gold base upkeep
	gs.turn_number = 0
	assert_eq(TurnEngine.gold_upkeep(gs, p), 10,
		"base upkeep before inflation onset")
	gs.turn_number = 290   # effective turn 200 → +60%
	assert_eq(TurnEngine.gold_upkeep(gs, p), 16,
		"expenses × (100 + 60) / 100, truncating")
	p.treasury = 100
	TurnEngine._update_treasury(gs, p)
	assert_eq(p.treasury, 84,
		"the applied treasury delta uses the inflated expense total")

# ── Insolvency ───────────────────────────────────────────────────────────────

func test_insolvency_clamps_treasury_to_zero() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1); p.treasury = 0
	for i in range(10):
		make_unit(gs, "warrior", 1, i, 0)
	TurnEngine._update_treasury(gs, p)
	assert_true(p.treasury >= 0, "Treasury never goes negative (clamped)")

func test_insolvency_disbands_units() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.treasury = 0; p.insolvent_turns = 5  # already past the grace period
	for i in range(10):
		make_unit(gs, "warrior", 1, i, 0)
	var before: int = gs.units.size()
	TurnEngine._update_treasury(gs, p)
	assert_true(gs.units.size() < before, "Insolvency disbands units to cover upkeep")
	assert_true(p.treasury >= 0, "Treasury is non-negative after insolvency handling")

func test_insolvency_never_sells_structures() -> void:
	# Buildings and their invested costs are always retained: prolonged
	# insolvency may only disband units, never sell a structure.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.treasury = 0; p.insolvent_turns = 5
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.structures = ["granary"]
	make_unit(gs, "warrior", 1, 6, 6)
	for i in range(20):
		make_unit(gs, "warrior", 1, i, 1)
	var units_before: int = gs.units.size()
	TurnEngine._update_treasury(gs, p)
	assert_eq(s.structures, ["granary"], "Structures are never sold during insolvency")
	assert_true(gs.units.size() < units_before, "Units are disbanded instead")
	assert_true(p.treasury >= 0, "Treasury is non-negative after insolvency handling")

func test_insolvency_with_no_units_clamps_treasury_at_zero() -> void:
	# With nothing left to disband the treasury simply clamps at 0 and the
	# city keeps every structure.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.treasury = -500; p.insolvent_turns = 5
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.structures = ["granary", "barracks"]
	TurnEngine._update_treasury(gs, p)
	assert_eq(p.treasury, 0, "Treasury clamps at 0 when there is nothing to disband")
	assert_eq(s.structures, ["granary", "barracks"],
		"Structures survive insolvency even with no units to disband")

func test_insolvency_disbands_only_until_solvent() -> void:
	# Regression (bug tstb8): a single insolvent turn must disband only ENOUGH
	# units to cover upkeep, never the whole army. With no city income, 3 units of
	# support relief, and 5 warriors (upkeep 1 each), only the 2 units beyond the
	# relief threshold need to go — disbanding drops upkeep to 0, at which point the
	# loop must stop with 3 units still standing. Before the fix the loop compared
	# every disband against the same stale negative treasury and removed all 5.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.treasury = 0
	p.insolvent_turns = 5           # past the grace period
	p.unit_support_relief = 3       # first 3 units cost no upkeep (§9 UNIT_SUPPORT)
	for i in range(5):
		make_unit(gs, "warrior", 1, i, 0)
	TurnEngine._update_treasury(gs, p)
	assert_eq(gs.units.size(), 3,
		"Disbands only the units beyond upkeep coverage, not the whole army")
	assert_true(p.treasury >= 0, "Treasury is non-negative after shedding just enough")
