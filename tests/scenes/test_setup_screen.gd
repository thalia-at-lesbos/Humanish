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
func _on_start(_facade, _db) -> void:
	_started = true

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
