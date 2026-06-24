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

# Event-choice popup presenter (§9, §4): the scene-layer half that surfaces a
# mandatory random-event / quest-reward choice and routes the answer back through
# apply_command(RESOLVE_EVENT).

const SCREEN := "res://scenes/screens/event_choice_screen.gd"

# Canary: a parse error would make load() return a broken script that still
# reports green elsewhere (GUT swallows it). can_instance() reports compile state
# without throwing.
func test_event_choice_screen_compiles() -> void:
	assert_true(load(SCREEN).can_instance(), "event_choice_screen.gd must compile")

func test_show_event_builds_a_button_per_choice() -> void:
	var screen = load(SCREEN).new()
	add_child_autofree(screen)
	screen.init(null)
	screen.show_event({
		"event_id": "forest_fire", "name": "Forest Fire", "text": "A fire breaks out.",
		"choices": [{"id": "douse", "text": "Pay the brigades"},
			{"id": "let_burn", "text": "Let it burn"}]
	})
	assert_true(screen.visible, "screen is visible after show_event")
	var buttons := []
	_collect_buttons(screen, buttons)
	assert_eq(buttons.size(), 2, "one button per choice")

func test_choice_routes_resolve_command_and_clears_pending() -> void:
	var gs = make_gs(2, 42)
	gs.current_player_id = 1
	var f = bare_facade(gs)
	# Park a mandatory choice for the human, as the event step would.
	gs.pending_event_choices.append({
		"event_id": "forest_fire", "player_id": 1, "trigger_id": "",
		"resolved_choices": [{"id": "douse", "text": "Pay the brigades",
			"effects": [{"verb": "gold", "amount": -10}]}]
	})
	assert_false(f.get_pending_event(1).empty(), "a choice is owed before resolving")
	var screen = load(SCREEN).new()
	add_child_autofree(screen)
	screen.init(f)
	screen.show_event({
		"event_id": "forest_fire", "name": "Forest Fire", "text": "A fire breaks out.",
		"choices": [{"id": "douse", "text": "Pay the brigades"}]
	})
	screen._on_choice("douse")
	assert_true(f.get_pending_event(1).empty(), "the choice is resolved and cleared")
	assert_false(screen.visible, "screen hides after a choice")

func _collect_buttons(node, out) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child)
		if child.get_child_count() > 0:
			_collect_buttons(child, out)

func test_show_info_builds_a_single_continue_button() -> void:
	var screen = load(SCREEN).new()
	add_child_autofree(screen)
	screen.init(null)
	screen.show_info({"name": "New Quest", "text": "Do the thing.",
		"objective": "Build 7 libraries.", "reward_lines": ["Choose:", "• A", "• B"]})
	assert_true(screen.visible, "info popup is visible after show_info")
	var buttons := []
	_collect_buttons(screen, buttons)
	assert_eq(buttons.size(), 1, "an informational popup has a single Continue button")
