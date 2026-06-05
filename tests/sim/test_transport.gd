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

# Naval transport / embarkation (§5.2): loading adjacent land units, capacity
# limits, cargo following the transport, and unloading back onto land.

func _coast(gs, xs):
	for x in xs:
		gs.map.get_tile(x, 5).terrain_id = "coast"

func test_land_unit_loads_onto_transport() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	_coast(gs, [5])
	var galley = make_unit(gs, "galley", 1, 5, 5)
	var warrior = make_unit(gs, "warrior", 1, 4, 5)  # adjacent land
	assert_true(f._cmd_load_unit({"player_id": 1, "unit_id": warrior.id,
		"transport_id": galley.id}), "Adjacent land unit loads")
	assert_eq(warrior.transported_by, galley.id, "Warrior is marked transported")
	assert_true(warrior.id in galley.cargo, "Warrior is in the galley cargo")
	assert_eq(warrior.x, 5, "Warrior moved onto the transport tile")

func test_transport_respects_capacity() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	_coast(gs, [5])
	var galley = make_unit(gs, "galley", 1, 5, 5)  # capacity 2
	var w1 = make_unit(gs, "warrior", 1, 4, 5)
	var w2 = make_unit(gs, "warrior", 1, 6, 5)
	var w3 = make_unit(gs, "warrior", 1, 5, 6)
	f._cmd_load_unit({"player_id": 1, "unit_id": w1.id, "transport_id": galley.id})
	f._cmd_load_unit({"player_id": 1, "unit_id": w2.id, "transport_id": galley.id})
	assert_false(f._cmd_load_unit({"player_id": 1, "unit_id": w3.id, "transport_id": galley.id}),
		"A full transport rejects further cargo")

func test_cargo_follows_transport() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	_coast(gs, [5, 6, 7])
	var galley = make_unit(gs, "galley", 1, 5, 5)
	var warrior = make_unit(gs, "warrior", 1, 4, 5)
	f._cmd_load_unit({"player_id": 1, "unit_id": warrior.id, "transport_id": galley.id})
	f._cmd_move_stack({"player_id": 1, "from_x": 5, "from_y": 5, "to_x": 6, "to_y": 5})
	assert_eq(galley.x, 6, "Transport moved")
	assert_eq(warrior.x, 6, "Carried unit moved with the transport")

func test_unload_to_land() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	_coast(gs, [5])
	var galley = make_unit(gs, "galley", 1, 5, 5)
	var warrior = make_unit(gs, "warrior", 1, 4, 5)
	f._cmd_load_unit({"player_id": 1, "unit_id": warrior.id, "transport_id": galley.id})
	assert_true(f._cmd_unload_unit({"player_id": 1, "unit_id": warrior.id,
		"target_x": 4, "target_y": 5}), "Unload onto adjacent land")
	assert_eq(warrior.transported_by, -1, "Warrior is no longer transported")
	assert_false(warrior.id in galley.cargo, "Warrior removed from cargo")
	assert_eq(warrior.x, 4, "Warrior disembarked onto land")
