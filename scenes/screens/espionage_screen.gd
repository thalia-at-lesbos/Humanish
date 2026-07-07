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

# Espionage advisor (§3.1 OPEN_ESPIONAGE, §11): the intel slider, then a block
# per rival civ/leader — accumulated EP, the "Select Mission…" launcher for the
# active catalogue, the alliance-scope passive intel (§25.6: demographics,
# research, mission detection; shown live once the EP threshold is met, as
# "have/need EP" progress until then), and every city of that rival with its
# defensive readout plus the two city-scope passive rows (investigate,
# visibility).

func init(facade) -> void:
	_title = "Espionage"
	.init(facade)

func _populate(vbox) -> void:
	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id)
	if p == null:
		_add_line(vbox, "No active player.")
		return
	_add_line(vbox, "Espionage rate: %d%%" % p.slider_intel)
	var min_cost: int = gs.db.get_constant("intel_mission_cost", 100)
	var listed_any: bool = false
	for alliance in gs.alliances:
		if alliance.id == p.alliance_id or alliance.member_player_ids.empty():
			continue
		listed_any = true
		var pts: int = int(p.intel_points.get(alliance.id, 0))
		_add_line(vbox, "")
		_add_line(vbox, "%s — %d EP" % [_alliance_label(gs, alliance), pts])
		if pts >= min_cost:
			var btn = Button.new()
			btn.text = "Select Mission vs. " + _alliance_label(gs, alliance) + "…"
			btn.connect("pressed", self, "_on_select_mission", [int(alliance.id)])
			vbox.add_child(btn)
		_populate_alliance_intel(vbox, gs, alliance, pts)
		_populate_cities(vbox, gs, alliance, pts)
	if not listed_any:
		_add_line(vbox, "No rival civilizations known.")

# The rival's civ/leader names — every member of the alliance, comma-joined.
func _alliance_label(gs, alliance) -> String:
	var names: Array = []
	for pid in alliance.member_player_ids:
		var member = gs.get_player(int(pid))
		if member != null:
			names.append(member.name)
	return PoolStringArray(names).join(", ") if not names.empty() else "Alliance %d" % alliance.id

# Alliance-scope passive intel rows (§25.6): each shows its live product once
# the viewer's EP meets the threshold, or "have/need EP" progress until then.
func _populate_alliance_intel(vbox, gs, alliance, pts: int) -> void:
	for m in gs.db.get_espionage_missions():
		if str(m.get("kind", "active")) != "passive" or str(m.get("scope", "")) != "alliance":
			continue
		var mid: String = str(m.get("id", ""))
		var mname: String = str(m.get("name", mid))
		if not _facade.passive_intel_active(mid, alliance.id):
			_add_line(vbox, "  %s: %d/%d EP" % [mname, pts,
				_facade.passive_intel_threshold(mid, alliance.id)])
			continue
		match mid:
			"see_demographics":
				_add_line(vbox, "  %s:" % mname)
				for pid in alliance.member_player_ids:
					var member = gs.get_player(int(pid))
					if member == null:
						continue
					var d: Dictionary = _facade.player_demographics(member.id)
					_add_line(vbox, "    %s: pop %d, %d cities, %d land, %d prod, %d GNP, %d units (power %d)" \
						% [member.name, d["population"], d["cities"], d["land"],
						d["production"], d["gnp"], d["soldiers"], d["power"]])
			"see_research":
				for pid in alliance.member_player_ids:
					var member = gs.get_player(int(pid))
					if member == null:
						continue
					var info: Dictionary = _facade.player_research_info(member.id)
					if info.empty():
						_add_line(vbox, "  %s: %s is researching nothing" % [mname, member.name])
					else:
						var tech_name: String = str(gs.db.get_technology(str(info["tech"])).get("name", info["tech"]))
						_add_line(vbox, "  %s: %s is researching %s (%d/%d)" \
							% [mname, member.name, tech_name, int(info["progress"]), int(info["cost"])])
			"detect_missions":
				_add_line(vbox, "  %s: active — their missions against you are attributed" % mname)
			_:
				_add_line(vbox, "  %s: active" % mname)

# Every city of the rival (§25.6): the defensive readout the information fog
# permits (full civilian details once investigate_city is met), plus the two
# city-scope passive rows as have/need progress.
func _populate_cities(vbox, gs, alliance, pts: int) -> void:
	for pid in alliance.member_player_ids:
		for s in gs.settlements:
			if s.owner_player_id != int(pid):
				continue
			for line in _facade.city_intel_lines(s.id):
				_add_line(vbox, "  " + str(line))
			var status: Array = []
			for mid in ["investigate_city", "city_visibility"]:
				var m: Dictionary = gs.db.get_espionage_mission(mid)
				var mname: String = str(m.get("name", mid))
				if _facade.passive_intel_active(mid, alliance.id, s.id):
					status.append("%s: active" % mname)
				else:
					status.append("%s: %d/%d EP" % [mname, pts,
						_facade.passive_intel_threshold(mid, alliance.id, s.id)])
			_add_line(vbox, "    " + PoolStringArray(status).join("   "))

func _on_select_mission(alliance_id: int) -> void:
	var menu = load("res://scenes/screens/espionage_menu.gd").new()
	add_child(menu)
	menu.init(_facade, alliance_id, funcref(self, "rebuild"))
