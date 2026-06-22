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

# The economy slider panel: four HSliders (finance/research/culture/intel) that
# always sum to 100. Issue 2: the sliders must stay off the keyboard-focus chain
# so the arrow keys pan the map (not nudge a slider / hop focus between sliders).

func _panel(facade):
	var p = load("res://scenes/hud/slider_panel.gd").new()
	add_child_autofree(p)
	p.init(facade)
	return p

# Canary: a parse error still loads but cannot instance; can_instance() reports
# the compile state without throwing, so GUT cannot silently swallow it.
func test_slider_panel_script_compiles() -> void:
	assert_true(load("res://scenes/hud/slider_panel.gd").can_instance(),
		"slider_panel.gd must compile (no parse error)")

func test_slider_panel_builds_four_sliders() -> void:
	var facade = setup_facade(50)
	facade.get_state().current_player_id = facade.get_state().players[0].id
	var panel = _panel(facade)
	assert_eq(panel._sliders.size(), 4, "Four economy sliders are built")

# Issue 2: every slider is FOCUS_NONE, so arrow keys never land on one (they pan
# the map) and the slider never steals the arrow keys to nudge its own value.
func test_sliders_take_no_keyboard_focus() -> void:
	var facade = setup_facade(51)
	facade.get_state().current_player_id = facade.get_state().players[0].id
	var panel = _panel(facade)
	for s in panel._sliders:
		assert_eq(s.focus_mode, Control.FOCUS_NONE,
			"Economy slider must not take keyboard focus (arrow keys pan the map)")
