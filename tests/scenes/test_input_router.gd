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

# InputRouter stack handling: clicking a tile cycles through the current player's
# units on it (ignoring enemies) and wraps around.

func _router():
	var ir = load("res://scenes/input/input_router.gd").new()
	add_child_autofree(ir)
	return ir

func test_click_cycles_through_stacked_units() -> void:
	var facade = setup_facade(1313, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid

	# Three friendly units sharing one tile, in a known spawn order.
	var ids = []
	for t in ["warrior", "scout", "archer"]:
		ids.append(make_unit(gs, t, pid, 4, 4).id)

	var ir = _router()
	var stack_ids = ir._owned_units_at(4, 4, gs)
	assert_eq(stack_ids, ids, "All owned units on the tile are returned in spawn order")

	# With nothing selected, the first click selects the top of the stack.
	assert_eq(ir._next_in_stack(stack_ids, -1), ids[0], "A fresh click selects the first unit")
	assert_eq(ir._next_in_stack(stack_ids, ids[0]), ids[1], "second click → unit 2")
	assert_eq(ir._next_in_stack(stack_ids, ids[1]), ids[2], "third click → unit 3")
	assert_eq(ir._next_in_stack(stack_ids, ids[2]), ids[0], "fourth click wraps to unit 1")

	# Driving the real selection through the facade cycles the head unit too.
	facade.select_unit(ir._next_in_stack(stack_ids, -1))
	assert_eq(facade.get_selection().head_unit(), ids[0], "head starts at unit 1")
	facade.select_unit(ir._next_in_stack(stack_ids, facade.get_selection().head_unit()))
	assert_eq(facade.get_selection().head_unit(), ids[1], "head advances to unit 2")

func test_owned_units_at_ignores_enemy_units() -> void:
	var facade = setup_facade(1414, "small")
	var gs = facade.get_state()
	var p0 = gs.players[0].id
	var p1 = gs.players[1].id
	gs.current_player_id = p0

	var mine = make_unit(gs, "warrior", p0, 3, 3)
	make_unit(gs, "warrior", p1, 3, 3)

	var ir = _router()
	assert_eq(ir._owned_units_at(3, 3, gs), [mine.id],
		"Only the current player's units are selectable on a shared tile")
