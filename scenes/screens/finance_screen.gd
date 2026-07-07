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

# Finance advisor (§3.1 OPEN_FINANCE, §11): treasury, the economic sliders, and
# the rules-generated finance breakdown. Read-only.

func init(facade) -> void:
	_title = "Finance"
	.init(facade)

func _populate(vbox) -> void:
	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id)
	if p == null:
		_add_line(vbox, "No active player.")
		return
	_add_line(vbox, "Treasury: %d gold" % p.treasury)
	_add_line(vbox, "Rates — science %d%% / culture %d%% / espionage %d%% / economy %d%% (derived)" % [
		p.slider_research, p.slider_culture, p.slider_intel, p.slider_finance])
	var breakdown = TextGen.widget_help(
		{"type": IDs.WidgetType.HELP_FINANCE, "data1": p.id}, gs, _facade._db)
	if breakdown != "":
		_add_line(vbox, breakdown)
