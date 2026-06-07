# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://scenes/screens/info_screen.gd"

# Espionage advisor (§3.1 OPEN_ESPIONAGE, §11): the intel slider and accumulated
# espionage points against each rival alliance. Read-only.

func init(facade) -> void:
	_title = "Espionage"
	.init(facade)

const MISSIONS = [
	["steal_tech", "Steal Tech"],
	["sabotage", "Sabotage"],
	["incite_unrest", "Incite Unrest"],
]

func _populate(vbox) -> void:
	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id)
	if p == null:
		_add_line(vbox, "No active player.")
		return
	_add_line(vbox, "Intel slider: %d%%" % p.slider_intel)
	if p.intel_points.empty():
		_add_line(vbox, "No espionage points accumulated.")
		return
	var min_cost = gs.db.get_constant("intel_mission_cost", 100)
	_add_line(vbox, "Espionage points by alliance:")
	for alliance_id in p.intel_points:
		var pts = int(p.intel_points[alliance_id])
		_add_line(vbox, "  alliance %s: %d" % [str(alliance_id), pts])
		# Offer a mission per rival the player has banked enough points against.
		if pts >= min_cost:
			_add_mission_buttons(vbox, int(alliance_id))

func _add_mission_buttons(vbox, alliance_id: int) -> void:
	var row = HBoxContainer.new()
	for m in MISSIONS:
		var btn = Button.new()
		btn.text = m[1]
		btn.connect("pressed", self, "_on_mission", [alliance_id, m[0]])
		row.add_child(btn)
	vbox.add_child(row)

func _on_mission(alliance_id: int, mission: String) -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.espionage_mission(gs.current_player_id, alliance_id, mission))
	rebuild()
