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
