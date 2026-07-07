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

# The economy rate panel: three adjustable rates (Science/Culture/Espionage)
# with −/+ buttons in 10% steps, plus a read-only Economy label showing the
# derived remainder (100 − the three). Issue 2: the buttons must stay off the
# keyboard-focus chain so the arrow keys pan the map.

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

func test_panel_builds_three_rate_rows_and_economy_label() -> void:
	var facade = setup_facade(50)
	facade.get_state().current_player_id = facade.get_state().players[0].id
	var panel = _panel(facade)
	assert_eq(panel._labels.size(), 3, "Three adjustable rate labels are built")
	assert_eq(panel._minus_buttons.size(), 3, "Each rate has a minus button")
	assert_eq(panel._plus_buttons.size(), 3, "Each rate has a plus button")
	assert_not_null(panel._economy_label, "A read-only Economy label is built")

# Issue 2: every button is FOCUS_NONE, so arrow keys never land on one (they
# pan the map) and a focused control never steals keyboard input.
func test_buttons_take_no_keyboard_focus() -> void:
	var facade = setup_facade(51)
	facade.get_state().current_player_id = facade.get_state().players[0].id
	var panel = _panel(facade)
	for b in panel._minus_buttons:
		assert_eq(b.focus_mode, Control.FOCUS_NONE,
			"Rate minus button must not take keyboard focus")
	for b in panel._plus_buttons:
		assert_eq(b.focus_mode, Control.FOCUS_NONE,
			"Rate plus button must not take keyboard focus")

func test_minus_steps_down_and_emits_command() -> void:
	var facade = setup_facade(52)
	var gs = facade.get_state()
	var p = gs.players[0]
	gs.current_player_id = p.id
	var panel = _panel(facade)
	# Defaults: research 100, finance 0.
	panel._minus_buttons[0].emit_signal("pressed")
	assert_eq(p.slider_research, 90, "Science − steps research down by 10")
	assert_eq(p.slider_finance, 10, "Economy picks up the freed 10 as remainder")
	assert_true(panel._labels[0].text.find("90%") != -1,
		"Science label shows the new rate")
	assert_true(panel._economy_label.text.find("10%") != -1,
		"Economy label shows the derived remainder")

func test_plus_steps_up_and_emits_command() -> void:
	var facade = setup_facade(53)
	var gs = facade.get_state()
	var p = gs.players[0]
	gs.current_player_id = p.id
	var panel = _panel(facade)
	panel._minus_buttons[0].emit_signal("pressed")  # research 90, finance 10
	panel._plus_buttons[1].emit_signal("pressed")   # culture takes the headroom
	assert_eq(p.slider_culture, 10, "Culture + steps culture up by 10")
	assert_eq(p.slider_finance, 0, "Economy remainder shrinks back to 0")
	assert_true(panel._economy_label.text.find("0%") != -1,
		"Economy label reads the remainder")

func test_plus_with_no_headroom_does_nothing() -> void:
	var facade = setup_facade(54)
	var gs = facade.get_state()
	var p = gs.players[0]
	gs.current_player_id = p.id
	var panel = _panel(facade)
	# Defaults: research 100, so the three already sum to 100 (finance 0).
	assert_true(panel._plus_buttons[2].disabled,
		"With no Economy headroom the plus buttons are disabled")
	panel._on_step(2, 10)  # even a forced click is a no-op
	assert_eq(p.slider_intel, 0, "A step over 100 does nothing")
	assert_eq(p.slider_research, 100, "Other rates are untouched")

func test_minus_at_zero_does_nothing() -> void:
	var facade = setup_facade(55)
	var gs = facade.get_state()
	var p = gs.players[0]
	gs.current_player_id = p.id
	var panel = _panel(facade)
	assert_true(panel._minus_buttons[1].disabled,
		"A rate at 0 has its minus button disabled")
	panel._on_step(1, -10)  # even a forced click is a no-op
	assert_eq(p.slider_culture, 0, "A step below 0 does nothing")

func test_science_minus_respects_policy_research_floor() -> void:
	var facade = setup_facade(56)
	var gs = facade.get_state()
	var p = gs.players[0]
	gs.current_player_id = p.id
	p.policies = {"government": "republic"}  # slider_min_research 10
	var panel = _panel(facade)
	# Walk research down to the floor; every step below it must be refused.
	for _i in range(12):
		panel._on_step(0, -10)
	assert_eq(p.slider_research, 10,
		"Science stops at the policy minimum research share")
	panel.rebuild()
	assert_true(panel._minus_buttons[0].disabled,
		"Science minus is disabled at the policy research floor")
