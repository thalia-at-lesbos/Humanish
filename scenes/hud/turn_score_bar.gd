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

var _facade
var _label: Label

func init(facade) -> void:
	_facade = facade
	_label = Label.new()
	add_child(_label)
	rebuild()

func rebuild() -> void:
	if _facade == null or _label == null:
		return
	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id)
	var score_str: String = str(p.score) if p != null else "0"
	var who: String = p.name if p != null else "—"
	var era_str: String = str(_facade.get_player_era(gs.current_player_id).get("name", ""))
	var gold_str: String = str(p.treasury) if p != null else "0"
	# turn_number is 0-based internally; show it 1-based for players.
	_label.text = "Turn: " + str(gs.turn_number + 1) + "/" + str(gs.max_turns) + \
		"   " + who + "   Era: " + era_str + "   Score: " + score_str + \
		"   Gold: " + gold_str
