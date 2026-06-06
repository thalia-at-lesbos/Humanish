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

func test_auto_advance_selects_next_idle_unit() -> void:
	var facade = setup_facade(1717, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 4, 4)
	var b = make_unit(gs, "scout", pid, 7, 7)
	facade.select_unit(a.id)
	a.has_moved = true   # a has finished acting

	var ir = _router()
	ir._facade = facade
	ir._maybe_auto_advance(gs)
	assert_eq(facade.get_selection().head_unit(), b.id,
		"Once the active unit is done, selection advances to the next idle unit")

func test_no_auto_advance_while_unit_can_still_act() -> void:
	var facade = setup_facade(1818, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 4, 4)
	make_unit(gs, "scout", pid, 7, 7)
	facade.select_unit(a.id)   # a is fresh and idle

	var ir = _router()
	ir._facade = facade
	ir._maybe_auto_advance(gs)
	assert_eq(facade.get_selection().head_unit(), a.id,
		"A unit that can still act stays selected")

func test_auto_advance_can_be_disabled() -> void:
	var facade = setup_facade(1919, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 4, 4)
	make_unit(gs, "scout", pid, 7, 7)
	facade.select_unit(a.id)
	a.has_moved = true

	var ir = _router()
	ir._facade = facade
	ir.auto_advance = false
	ir._maybe_auto_advance(gs)
	assert_eq(facade.get_selection().head_unit(), a.id,
		"With auto-advance off, selection does not move on its own")

# ── Click priority: a selected unit treats other tiles as move destinations ───

func test_selected_unit_moves_onto_friendly_unit_tile() -> void:
	var facade = setup_facade(2020, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(3, 3).terrain_id = "grassland"
	gs.map.get_tile(4, 3).terrain_id = "grassland"
	var mover = make_unit(gs, "warrior", pid, 3, 3)
	make_unit(gs, "scout", pid, 4, 3)   # a friendly unit sits on the destination
	facade.select_unit(mover.id)

	var ir = _router()
	ir._facade = facade
	ir._handle_selection_click(4, 3, gs)
	assert_eq([mover.x, mover.y], [4, 3],
		"A selected unit moves onto a friendly-occupied tile, not selecting it")

func test_selected_unit_moves_onto_friendly_city_tile() -> void:
	var facade = setup_facade(2121, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(3, 3).terrain_id = "grassland"
	gs.map.get_tile(4, 3).terrain_id = "grassland"
	var mover = make_unit(gs, "warrior", pid, 3, 3)
	make_settlement(gs, pid, 4, 3, 2)   # a friendly city on the destination
	facade.select_unit(mover.id)

	var ir = _router()
	ir._facade = facade
	ir._handle_selection_click(4, 3, gs)
	assert_eq([mover.x, mover.y], [4, 3],
		"A selected unit garrisons a friendly city instead of selecting it")
	assert_eq(facade.get_selection().head_city(), -1,
		"…and the city is not selected by the move click")

func test_clicking_selected_units_own_tile_cycles_stack() -> void:
	var facade = setup_facade(2222, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 3, 3)
	var b = make_unit(gs, "scout", pid, 3, 3)
	facade.select_unit(a.id)

	var ir = _router()
	ir._facade = facade
	ir._handle_selection_click(3, 3, gs)   # same tile as the selected unit
	assert_eq(facade.get_selection().head_unit(), b.id,
		"Clicking the selected unit's own tile cycles to the next stack member")

func test_click_selects_friendly_unit_when_nothing_selected() -> void:
	var facade = setup_facade(2323, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 6, 6)
	facade.clear_selection()

	var ir = _router()
	ir._facade = facade
	ir._handle_selection_click(6, 6, gs)
	assert_eq(facade.get_selection().head_unit(), u.id,
		"With nothing selected, clicking a friendly unit selects it")

func test_click_selects_city_when_nothing_selected() -> void:
	var facade = setup_facade(2424, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var c = make_settlement(gs, pid, 5, 5, 2)
	facade.clear_selection()

	var ir = _router()
	ir._facade = facade
	ir._handle_selection_click(5, 5, gs)
	assert_eq(facade.get_selection().head_city(), c.id,
		"With nothing selected, clicking a friendly city selects it")
