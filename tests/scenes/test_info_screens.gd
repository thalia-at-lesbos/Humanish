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

# The simple read-only advisor/info screens (§3.1 OPEN_* controls, §11) build
# their text content from real game state without error.

var _SCREENS = [
	"res://scenes/screens/religion_screen.gd",
	"res://scenes/screens/corporation_screen.gd",
	"res://scenes/screens/turn_log_screen.gd",
	"res://scenes/screens/domestic_advisor_screen.gd",
	"res://scenes/screens/victory_progress_screen.gd",
	"res://scenes/screens/options_screen.gd",
	"res://scenes/screens/finance_screen.gd",
	"res://scenes/screens/military_screen.gd",
	"res://scenes/screens/espionage_screen.gd",
	"res://scenes/screens/encyclopedia_screen.gd",
]

func test_info_screens_build_without_error() -> void:
	var facade = setup_facade(91)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	make_settlement(gs, gs.players[0].id, 5, 5, 3)
	make_unit(gs, "warrior", gs.players[0].id, 6, 6)

	for path in _SCREENS:
		var screen = load(path).new()
		add_child_autofree(screen)
		screen.init(facade)
		screen.show_screen()
		assert_true(screen.visible, "Screen %s should be visible after show_screen()" % path)
		assert_true(screen.get_child_count() > 0,
			"Screen %s should build text content from state" % path)

func test_close_screen_hides_info_screen() -> void:
	var facade = setup_facade(93)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	make_settlement(gs, gs.players[0].id, 5, 5, 3)

	for path in _SCREENS:
		var screen = load(path).new()
		add_child_autofree(screen)
		screen.init(facade)
		screen.show_screen()
		assert_true(screen.visible, "Screen %s visible after show_screen()" % path)
		screen.close_screen()
		assert_false(screen.visible, "Screen %s hidden after close_screen()" % path)

func test_options_screen_score_toggle_routes_through_facade() -> void:
	var facade = setup_facade(92)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var screen = load("res://scenes/screens/options_screen.gd").new()
	add_child_autofree(screen)
	screen.init(facade)
	screen.show_screen()
	watch_signals(facade)
	screen._on_toggle_score()
	assert_signal_emitted(facade, "screen_requested",
		"Options score toggle should emit screen_requested (TOGGLE_SCORE)")
