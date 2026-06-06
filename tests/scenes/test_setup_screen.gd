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

# SetupScreen new-game gating: Start is blocked until every player has chosen a
# society, and an error is shown.

var _started = false
var _started_facade = null
func _on_start(facade, _db) -> void:
	_started = true
	_started_facade = facade

func test_blocks_start_until_every_player_picks_a_society() -> void:
	var screen = load("res://scenes/setup/setup_screen.gd").new()
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	add_child_autofree(screen)
	screen.init(make_db(), funcref(self, "_on_start"))
	_started = false

	# Default 2 players. Leave player 1 at "— No Society —" (index 0).
	screen._player_rows[0]["society_btn"].select(0)
	screen._player_rows[1]["society_btn"].select(1)
	assert_eq(screen._players_missing_society(2), [1],
		"Player 1 should be flagged as missing a society")

	screen._on_start_pressed()
	assert_false(_started, "Start must be blocked while any player has no society")
	assert_true(screen._error_label.visible, "An error message should be shown")

	# Give player 1 a society too → start should now proceed.
	screen._player_rows[0]["society_btn"].select(1)
	assert_eq(screen._players_missing_society(2), [],
		"No players should be missing a society now")
	screen._on_start_pressed()
	assert_true(_started, "Start proceeds once all players have chosen a society")

func test_ai_toggle_flows_into_player_is_ai() -> void:
	var screen = load("res://scenes/setup/setup_screen.gd").new()
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	add_child_autofree(screen)
	screen.init(make_db(), funcref(self, "_on_start"))
	_started = false
	_started_facade = null

	# Two players, both with a society so Start proceeds.
	screen._player_rows[0]["society_btn"].select(1)
	screen._player_rows[1]["society_btn"].select(1)
	# Player 1 = human, player 2 = AI (its default).
	screen._player_rows[0]["ai_check"].pressed = false
	screen._player_rows[1]["ai_check"].pressed = true

	screen._on_start_pressed()
	assert_true(_started, "Start should proceed")
	var gs = _started_facade.get_state()
	assert_false(gs.get_player(1).is_ai, "Player 1 is human")
	assert_true(gs.get_player(2).is_ai, "Player 2 is AI")

	# Player 1 opens with exactly a settler + tech-derived escort (game-data.md §3).
	var sid = screen._player_rows[0]["society_ids"][0]
	var techs = make_db().get_society(sid).get("starting_techs", [])
	var escort = "scout" if "hunting" in techs else "warrior"
	var p1_types = []
	for u in gs.units:
		if u.owner_player_id == gs.get_player(1).id:
			p1_types.append(u.unit_type_id)
	p1_types.sort()
	var expected = ["settler", escort]; expected.sort()
	assert_eq(p1_types, expected,
		"Player 1 (society %s) starts with settler + %s" % [sid, escort])
