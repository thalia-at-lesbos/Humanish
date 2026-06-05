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

# SimFacade command routing: founding settlements (and the min-distance rule),
# setting research, class-bounded moves, friendly stacking, and the settler's
# Found City action surfaced through the flyout.

func _settler(facade, player_id, x, y):
	var gs = facade.get_state()
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id(); u.unit_type_id = "settler"
	u.owner_player_id = player_id; u.x = x; u.y = y
	u.base_strength = 0; u.health = 100
	u.movement_total = 200; u.movement_left = 200
	gs.units.append(u)
	return u.id

# ── Found settlement ─────────────────────────────────────────────────────────

func test_found_settlement_creates_settlement() -> void:
	var facade = setup_facade(100)
	var gs = facade.get_state()
	var uid: int = _settler(facade, gs.players[0].id, 5, 5)
	gs.current_player_id = gs.players[0].id
	assert_true(facade.apply_command(Commands.found_settlement(gs.players[0].id, uid, "Alpha")),
		"Found settlement command should succeed")
	assert_eq(gs.settlements.size(), 1, "One settlement should exist")
	assert_eq(gs.settlements[0].name, "Alpha", "Settlement name set correctly")

func test_found_settlement_too_close_fails() -> void:
	var facade = setup_facade(200)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var uid1: int = _settler(facade, gs.players[0].id, 5, 5)
	facade.apply_command(Commands.found_settlement(gs.players[0].id, uid1, "A"))
	var uid2: int = _settler(facade, gs.players[0].id, 6, 5)
	assert_false(facade.apply_command(Commands.found_settlement(gs.players[0].id, uid2, "B")),
		"Cannot found within min distance")

func test_found_city_action_offered_and_works() -> void:
	var facade = setup_facade(31, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(6, 6).terrain_id = "grassland"
	var u = make_unit(gs, "settler", pid, 6, 6)

	var found_item = {}
	for it in facade.get_flyout_menu(6, 6):
		if int(it.get("action_id", -1)) == IDs.UnitMission.FOUND_SETTLEMENT:
			found_item = it
			break
	assert_false(found_item.empty(), "Flyout should offer Found City for a settler")

	var before = gs.settlements.size()
	assert_true(facade.apply_command(Commands.found_settlement(pid, int(found_item.get("unit_id", u.id)))),
		"Found settlement command should succeed")
	assert_eq(gs.settlements.size(), before + 1, "A new settlement should exist")
	assert_null(gs.get_unit(u.id), "The founding settler should be consumed")

func test_found_city_not_offered_for_warrior() -> void:
	var facade = setup_facade(32, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 7, 7)
	for it in facade.get_flyout_menu(7, 7):
		assert_true(int(it.get("action_id", -1)) != IDs.UnitMission.FOUND_SETTLEMENT,
			"A warrior must not be offered Found City")

# ── Research command ───────────────────────────────────────────────────────────

func test_set_research_command() -> void:
	var facade = setup_facade(300)
	var gs = facade.get_state()
	var p = gs.players[0]
	gs.current_player_id = p.id
	assert_true(facade.apply_command(Commands.set_research(p.id, "mining")),
		"Set research should succeed")
	assert_eq(p.current_research_id, "mining", "Research target set")

# ── Movement & stacking via commands ───────────────────────────────────────────

func test_move_stack_command_succeeds_on_open_map() -> void:
	var facade = setup_facade(123, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 2, 2)
	assert_true(facade.apply_command(Commands.move_stack(pid, 2, 2, 3, 2)),
		"Moving a unit one tile on open land should succeed")

func test_friendly_units_may_stack_on_one_tile() -> void:
	var facade = setup_facade(1212, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_warrior(gs, pid, 5, 5)  # already on the target tile
	var b = make_unit(gs, "scout", pid, 6, 5)

	assert_true(facade.apply_command(Commands.move_stack(pid, 6, 5, 5, 5)),
		"A unit must be able to move onto a friendly-occupied tile")
	assert_eq([gs.get_unit(b.id).x, gs.get_unit(b.id).y], [5, 5],
		"The moving unit ends up on the shared tile")
	assert_eq(Stack.at(gs.units, 5, 5, pid).size(), 2, "Both friendly units now occupy the same tile")
