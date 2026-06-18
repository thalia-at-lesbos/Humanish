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
		_add_line(vbox, "    output: " + _output_text(org) + "  /  maintenance: %d/city" % int(
			org.get("maintenance", db.get_constant("corporation_maintenance", 0))))

# Human-readable per-city output, distinguishing flat from per-input-resource scaling.
func _output_text(org) -> String:
	var parts = []
	var flat = org.get("output_delta", {})
	for ch in ["food", "production", "commerce"]:
		var v = int(flat.get(ch, 0))
		if v != 0:
			parts.append("+%d %s" % [v, ch])
	var per = org.get("output_per_input_resource", {})
	for ch in ["food", "production", "commerce"]:
		var v = int(per.get(ch, 0))
		if v != 0:
			parts.append("+%d %s/input" % [v, ch])
	return ", ".join(parts) if not parts.empty() else "—"
