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

# The HUD advisor menu bar: a visible button per info/advisor screen, each
# routed through the command pipeline as DO_CONTROL(OPEN_*) so the screens are
# reachable without hotkeys.

func _bar(facade):
	var bar = load("res://scenes/hud/menu_bar.gd").new()
	add_child_autofree(bar)
	bar.init(facade)
	return bar

# Canary: a parse error in the menu bar script still loads (load() returns a
# broken GDScript) but cannot instance; can_instance() reports the compile state
# without throwing, so this fails loudly instead of GUT silently swallowing it.
func test_menu_bar_script_compiles() -> void:
	assert_true(load("res://scenes/hud/menu_bar.gd").can_instance(),
		"menu_bar.gd must compile (no parse error)")

# Issue 2: the advisor buttons are FOCUS_NONE so arrow keys (map-pan) never hop
# keyboard focus onto them, and a focused button never swallows Enter (End Turn).
func test_menu_bar_buttons_take_no_keyboard_focus() -> void:
	var facade = setup_facade(43)
	facade.get_state().current_player_id = facade.get_state().players[0].id
	var bar = _bar(facade)
	var checked = 0
	for c in bar.get_children():
		if c is Button:
			checked += 1
			assert_eq(c.focus_mode, Control.FOCUS_NONE,
				"Advisor button '" + c.text + "' must not take keyboard focus")
	assert_true(checked > 0, "There is at least one advisor button to check")

func test_menu_bar_builds_a_button_per_entry() -> void:
	var facade = setup_facade(40)
	facade.get_state().current_player_id = facade.get_state().players[0].id
	var bar = _bar(facade)
	var buttons = 0
	for c in bar.get_children():
		if c is Button:
			buttons += 1
	assert_eq(buttons, bar.ENTRIES.size(),
		"The menu bar renders one button per advisor screen")
	assert_true(buttons > 0, "There is at least one advisor button")

func test_menu_bar_button_opens_screen_via_command() -> void:
	var facade = setup_facade(41)
	facade.get_state().current_player_id = facade.get_state().players[0].id
	var bar = _bar(facade)
	watch_signals(facade)
	# Science → OPEN_TECH should reach the screen_requested signal.
	bar._on_open(IDs.ControlType.OPEN_TECH)
	assert_signal_emitted(facade, "screen_requested",
		"A menu-bar button routes through DO_CONTROL → screen_requested")

func test_menu_bar_includes_core_advisors() -> void:
	var facade = setup_facade(42)
	var bar = _bar(facade)
	var ctrls = []
	for e in bar.ENTRIES:
		ctrls.append(e[1])
	# The screens the user called out as inaccessible must be present.
	assert_true(IDs.ControlType.OPEN_TECH in ctrls, "Science is on the bar")
	assert_true(IDs.ControlType.OPEN_POLICY in ctrls, "Civics is on the bar")
	assert_true(IDs.ControlType.OPEN_TURN_LOG in ctrls, "Turn log (chat history) is on the bar")
