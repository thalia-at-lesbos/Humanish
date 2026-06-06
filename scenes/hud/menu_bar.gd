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

# Advisor/menu bar (§11 main HUD): a visible row of buttons that open the info
# and advisor screens. Without this the screens were reachable only by a few
# F-keys (and most had no binding at all), so they were effectively inaccessible.
# Each button routes through the command pipeline as a DO_CONTROL(OPEN_*), the
# same path the hotkeys use; main.gd's screen_requested handler raises the screen.

# [button label, ControlType]. Order groups the common screens first.
const ENTRIES: Array = [
	["Science", IDs.ControlType.OPEN_TECH],
	["Civics", IDs.ControlType.OPEN_POLICY],
	["Diplomacy", IDs.ControlType.OPEN_DIPLOMACY],
	["Finance", IDs.ControlType.OPEN_FINANCE],
	["Military", IDs.ControlType.OPEN_MILITARY],
	["Espionage", IDs.ControlType.OPEN_ESPIONAGE],
	["Religion", IDs.ControlType.OPEN_RELIGION],
	["Corp", IDs.ControlType.OPEN_CORPORATION],
	["Domestic", IDs.ControlType.OPEN_DOMESTIC_ADVISOR],
	["Victory", IDs.ControlType.OPEN_VICTORY_PROGRESS],
	["Log", IDs.ControlType.OPEN_TURN_LOG],
	["Pedia", IDs.ControlType.OPEN_ENCYCLOPEDIA],
	["Options", IDs.ControlType.OPEN_OPTIONS],
]

var _facade

func init(facade) -> void:
	_facade = facade
	_build()

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for entry in ENTRIES:
		var btn: Button = Button.new()
		btn.text = entry[0]
		btn.connect("pressed", self, "_on_open", [entry[1]])
		add_child(btn)

func _on_open(ctrl_type: int) -> void:
	if _facade == null:
		return
	if not _facade.can_do_control(ctrl_type):
		return
	var gs = _facade.get_state()
	_facade.apply_command(Commands.do_control(gs.current_player_id, ctrl_type))
