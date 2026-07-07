# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends HBoxContainer

# The three adjustable allocation rates — Science (research), Culture, and
# Espionage (intel) — each shown as "Name: NN%" with −/+ buttons stepping in
# 10% increments. Economy (finance) is the read-only derived remainder
# (100 − the three) shown at the end. A step that would push the three over
# 100, below 0, or Science below the policy research floor is disabled.
# On any change emits the three-rate Commands.set_sliders to the facade.

var _facade
var _labels: Array = []        # rate labels, parallel to RATE_NAMES
var _minus_buttons: Array = []
var _plus_buttons: Array = []
var _economy_label: Label = null

const RATE_NAMES: Array = ["Science", "Culture", "Espionage"]
const STEP: int = 10

func init(facade) -> void:
	_facade = facade
	_build_ui()
	rebuild()

func _build_ui() -> void:
	for i in range(3):
		var row: HBoxContainer = HBoxContainer.new()

		var lbl: Label = Label.new()
		lbl.text = RATE_NAMES[i] + ": 0%"
		_labels.append(lbl)
		row.add_child(lbl)

		# FOCUS_NONE: keep the economy controls off the keyboard-focus chain. A
		# focused button would otherwise steal the arrow keys that pan the map
		# (and hop focus between controls on left/right). Still fully clickable.
		var minus: Button = Button.new()
		minus.text = "-"
		minus.focus_mode = Control.FOCUS_NONE
		minus.connect("pressed", self, "_on_step", [i, -STEP])
		_minus_buttons.append(minus)
		row.add_child(minus)

		var plus: Button = Button.new()
		plus.text = "+"
		plus.focus_mode = Control.FOCUS_NONE
		plus.connect("pressed", self, "_on_step", [i, STEP])
		_plus_buttons.append(plus)
		row.add_child(plus)

		# No EXPAND flag: the group takes only its minimum width and the HBox
		# packs it against the left, so all four rate readouts read
		# left-justified in a row instead of spread across the panel.
		add_child(row)

	# Read-only remainder: Economy takes whatever the three rates leave.
	_economy_label = Label.new()
	_economy_label.text = "Economy: 100%"
	add_child(_economy_label)

func rebuild() -> void:
	if _facade == null:
		return
	var p = _current_player()
	if p == null:
		return
	var vals: Array = [p.slider_research, p.slider_culture, p.slider_intel]
	for i in range(3):
		_labels[i].text = RATE_NAMES[i] + ": " + str(int(vals[i])) + "%"
		# + takes from the Economy remainder; − must not dip below the floor
		# (0, or the policy research minimum for Science).
		_plus_buttons[i].disabled = p.slider_finance < STEP
		_minus_buttons[i].disabled = int(vals[i]) - STEP < _floor_for(i)
	_economy_label.text = "Economy: " + str(int(p.slider_finance)) + "%"

func _on_step(idx: int, delta: int) -> void:
	if _facade == null:
		return
	var p = _current_player()
	if p == null:
		return
	var vals: Array = [int(p.slider_research), int(p.slider_culture), int(p.slider_intel)]
	var new_val: int = vals[idx] + delta
	# A click that would violate a constraint does nothing (buttons are also
	# disabled in rebuild(); this guards a stale click before the repaint).
	if new_val < _floor_for(idx):
		return
	if vals[0] + vals[1] + vals[2] + delta > 100:
		return
	vals[idx] = new_val
	var gs = _facade.get_state()
	_facade.apply_command(
		Commands.set_sliders(gs.current_player_id, vals[0], vals[1], vals[2]))
	rebuild()

# The lowest a rate may go: the policy-imposed minimum research share for
# Science (idx 0), zero for the others.
func _floor_for(idx: int) -> int:
	if idx != 0:
		return 0
	var p = _current_player()
	if p == null:
		return 0
	var min_research: int = 0
	var policies: Dictionary = _facade.get_state().db.policies.get("policies", {})
	for cat in p.policies:
		var pol: Dictionary = policies.get(p.policies[cat], {})
		min_research = max(min_research, int(pol.get("slider_min_research", 0)))
	return min_research

func _current_player():
	var gs = _facade.get_state()
	return gs.get_player(gs.current_player_id)
