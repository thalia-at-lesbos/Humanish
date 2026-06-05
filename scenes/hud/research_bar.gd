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
var _bar: ProgressBar

func init(facade) -> void:
	_facade = facade
	_label = Label.new()
	add_child(_label)
	_bar = ProgressBar.new()
	_bar.min_value = 0
	_bar.rect_min_size = Vector2(120, 20)
	add_child(_bar)
	rebuild()

func rebuild() -> void:
	if _facade == null or _label == null:
		return
	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id)
	if p == null:
		_label.text = "Research: —"
		return
	if p.current_research_id == "":
		_label.text = "Research: (none)"
		_bar.value = 0
		return
	var tech = _facade._db.get_technology(p.current_research_id)
	var cost: int = int(tech.get("cost", 1))
	_label.text = "Research: " + p.current_research_id
	_bar.max_value = cost
	_bar.value = min(p.research_store, cost)
