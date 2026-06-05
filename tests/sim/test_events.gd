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

# Events & exploration (§9): the events table loads, scripted events fire once
# after their min-turn, and entering a discovery site consumes it for a reward.

func test_events_table_loads() -> void:
	var gs = make_gs()
	assert_true(gs.db.events.has("ancient_windfall"), "events.json loads into DataDB")
	assert_true(gs.db.get_errors().empty(), "DataDB still loads cleanly with the events table")

func test_scripted_event_fires_once_after_min_turn() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.treasury = 0
	gs.turn_number = 10  # >= min_turn 8
	var fired = Events.process_player_events(p, gs, gs.rng)
	assert_eq(fired.size(), 1, "Event fires when its min_turn is reached")
	assert_eq(p.treasury, 50, "Event treasury effect applied")
	Events.process_player_events(p, gs, gs.rng)
	assert_eq(p.treasury, 50, "A once-fired event does not repeat")

func test_scripted_event_held_before_min_turn() -> void:
	var gs = make_gs()
	gs.turn_number = 2  # < min_turn 8
	var fired = Events.process_player_events(gs.get_player(1), gs, gs.rng)
	assert_true(fired.empty(), "Event does not fire before its min_turn")

func test_entering_discovery_site_yields_reward() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	gs.map.get_tile(6, 5).has_discovery = true
	make_unit(gs, "warrior", 1, 5, 5)
	f._cmd_move_stack({"player_id": 1, "from_x": 5, "from_y": 5, "to_x": 6, "to_y": 5})
	assert_false(gs.map.get_tile(6, 5).has_discovery, "Discovery site is consumed on entry")
