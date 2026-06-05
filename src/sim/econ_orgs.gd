# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name EconOrgs

# Economic organization founding (by special person) and spread.

static func found(org_id: String, settlement: Settlement, game_state) -> bool:
	if game_state.founded_econ_orgs.has(org_id):
		return false
	settlement.econ_org_id = org_id
	game_state.founded_econ_orgs[org_id] = settlement.owner_player_id
	return true

# Spread economic organizations each turn (costs treasury).
static func spread_all(game_state, rng: RNG) -> void:
	var db: DataDB = game_state.db
	for org_id in game_state.founded_econ_orgs:
		var org: Dictionary = db.econ_orgs.get(org_id, {})
		var spread_chance: int = int(org.get("spread_chance_base", 15))
		var spread_cost: int = int(org.get("spread_cost", 200))
		var owner_player_id: int = game_state.founded_econ_orgs[org_id]
		var owner: Player = game_state.get_player(owner_player_id)
		if owner == null or owner.treasury < spread_cost:
			continue
		for s in game_state.settlements:
			if s.econ_org_id == org_id:
				continue
			if s.econ_org_id != "":
				continue  # competing orgs cannot coexist
			# Check adjacency
			for other in game_state.settlements:
				if other.econ_org_id != org_id:
					continue
				var dist: int = game_state.map.distance(s.x, s.y, other.x, other.y)
				if dist <= 4 and rng.rand_bool_percent(spread_chance):
					s.econ_org_id = org_id
					owner.treasury -= spread_cost
					break

# Compute the extra output a settlement gets from its economic organization.
static func get_output_delta(settlement: Settlement, db: DataDB) -> Array:
	if settlement.econ_org_id == "":
		return [0, 0, 0]
	var org: Dictionary = db.econ_orgs.get(settlement.econ_org_id, {})
	if org.empty():
		return [0, 0, 0]
	var delta: Dictionary = org.get("output_delta", {})
	return [
		int(delta.get("food", 0)),
		int(delta.get("production", 0)),
		int(delta.get("commerce", 0))
	]
