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

# Corporation advisor (§3.1 OPEN_CORPORATION): founded economic organizations,
# their founders, and how many cities they have spread to. Read-only.

func init(facade) -> void:
	_title = "Corporations"
	.init(facade)

func _populate(vbox) -> void:
	var gs = _facade.get_state()
	var db = gs.db
	if gs.founded_econ_orgs.empty():
		_add_line(vbox, "No corporations founded yet.")
		return
	for org_id in gs.founded_econ_orgs:
		var org = db.econ_orgs.get(org_id, {})
		var name = str(org.get("name", org_id))
		var founder_id = int(gs.founded_econ_orgs[org_id])
		var founder = gs.get_player(founder_id)
		var founder_name = founder.name if founder != null else "?"
		var spread = 0
		for s in gs.settlements:
			if s.econ_org_id == org_id:
				spread += 1
		_add_line(vbox, "%s — founded by %s — %d cities" % [name, founder_name, spread])
		var inputs = org.get("input_resources", [])
		_add_line(vbox, "    inputs: " + (", ".join(inputs) if not inputs.empty() else "none"))
		_add_line(vbox, "    output: " + _output_text(org) + "  /  maintenance: " +
			_rate_text(int(org.get("maintenance_per_resource", 0))) + " gold/resource/city")

# Human-readable per-city output: ×1/100 per-resource rates (§15.10) plus any
# produced strategic resource.
func _output_text(org) -> String:
	var parts = []
	var per = org.get("output_per_resource", {})
	for ch in ["food", "production", "commerce", "gold", "research", "culture"]:
		var v = int(per.get(ch, 0))
		if v != 0:
			parts.append("+%s %s/resource" % [_rate_text(v), ch])
	var produced = str(org.get("produces_resource", ""))
	if produced != "":
		parts.append("provides " + produced)
	return ", ".join(parts) if not parts.empty() else "—"

# Render a ×100 fixed rate as a decimal string (75 → "0.75", 200 → "2").
func _rate_text(v: int) -> String:
	if v % 100 == 0:
		return str(v / 100)
	if v % 10 == 0:
		return "%d.%d" % [v / 100, (v % 100) / 10]
	return "%d.%02d" % [v / 100, v % 100]
