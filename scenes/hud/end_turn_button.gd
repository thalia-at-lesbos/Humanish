# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends Button

# Tri-state end-turn button:
#   0 (ready)   → normal text "End Turn"
#   1 (waiting) → dimmed "Waiting…"
#   2 (prompt)  → highlighted "End Turn?" (idle units remain)

var _facade

func init(facade) -> void:
	_facade = facade
	connect("pressed", self, "_on_pressed")
	rebuild()

func rebuild() -> void:
	if _facade == null:
		return
	var state: int = _facade.get_end_turn_state()
	match state:
		0:
			text = "End Turn"
			disabled = false
			modulate = Color.white
		1:
			text = "Waiting…"
			disabled = true
			modulate = Color(0.6, 0.6, 0.6)
		2:
			text = "End Turn?"
			disabled = false
			modulate = Color(1.0, 0.9, 0.3)

func _on_pressed() -> void:
	if _facade == null:
		return
	var gs = _facade.get_state()
	_facade.apply_command(Commands.end_turn(gs.current_player_id))
