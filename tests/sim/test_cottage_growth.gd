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

# Cottage → hamlet → village → town maturation (§8). The improvement chain and its
# upgrade_turns live in improvements.json; this exercises the growth bookkeeping.

func _cottage_city(gs):
	var s = make_settlement(gs, 1, 5, 5, 3)
	gs.map.get_tile(6, 5).improvement_id = "cottage"
	s.worked_tiles = [[6, 5]]
	return s

func test_worked_cottage_ages_each_turn():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	_cottage_city(gs)
	TurnEngine._grow_cottages(gs, p)
	assert_eq(gs.map.get_tile(6, 5).improvement_age, 1, "a worked cottage ages 1/turn")

func test_unworked_cottage_does_not_age():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	gs.map.get_tile(6, 5).improvement_id = "cottage"
	s.worked_tiles = []  # not worked
	TurnEngine._grow_cottages(gs, p)
	assert_eq(gs.map.get_tile(6, 5).improvement_age, 0, "an unworked cottage does not grow")

func test_cottage_upgrades_to_hamlet():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	_cottage_city(gs)
	# cottage upgrade_turns is 10.
	for _i in range(10):
		TurnEngine._grow_cottages(gs, p)
	var t = gs.map.get_tile(6, 5)
	assert_eq(t.improvement_id, "hamlet", "cottage matures into a hamlet after 10 worked turns")
	assert_eq(t.improvement_age, 0, "age resets on upgrade")

func test_emancipation_doubles_growth():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	_cottage_city(gs)
	p.policies = {"labor": "emancipation"}  # improvement_upgrade_rate_modifier 100
	for _i in range(5):
		TurnEngine._grow_cottages(gs, p)
	assert_eq(gs.map.get_tile(6, 5).improvement_id, "hamlet",
		"Emancipation (+100%% upgrade rate) matures a cottage in 10×100/200 = 5 turns")

func test_upgrade_rate_modifier_truncates():
	# §15.9 pin: a synthetic +50%% rate scales the 10-turn cottage threshold to
	# 10×100/150 = 6 (truncating) — not ready at 6 ticks minus one, done at 6.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	_cottage_city(gs)
	gs.db.policies["policies"]["emancipation"]["effects"] \
		["improvement_upgrade_rate_modifier"] = 50
	p.policies = {"labor": "emancipation"}
	for _i in range(5):
		TurnEngine._grow_cottages(gs, p)
	assert_eq(gs.map.get_tile(6, 5).improvement_id, "cottage",
		"+50%% rate: still a cottage after 5 turns (threshold 6)")
	TurnEngine._grow_cottages(gs, p)
	assert_eq(gs.map.get_tile(6, 5).improvement_id, "hamlet",
		"+50%% rate: upgrades on turn 6 (10×100/150 = 6, truncating)")

func test_town_is_terminal():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	gs.map.get_tile(6, 5).improvement_id = "town"
	s.worked_tiles = [[6, 5]]
	for _i in range(50):
		TurnEngine._grow_cottages(gs, p)
	assert_eq(gs.map.get_tile(6, 5).improvement_id, "town", "a town does not upgrade further")

func test_full_chain_to_town():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	_cottage_city(gs)
	# 10 (→hamlet) + 20 (→village) + 40 (→town) = 70 worked turns.
	for _i in range(70):
		TurnEngine._grow_cottages(gs, p)
	assert_eq(gs.map.get_tile(6, 5).improvement_id, "town",
		"the worked cottage line reaches town after the full chain")

func test_plain_improvement_never_ages():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	gs.map.get_tile(6, 5).improvement_id = "farm"  # no upgrades_to
	s.worked_tiles = [[6, 5]]
	TurnEngine._grow_cottages(gs, p)
	assert_eq(gs.map.get_tile(6, 5).improvement_age, 0, "a farm never ages")
