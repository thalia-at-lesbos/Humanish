# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name PolicyEffects

# Reads the gameplay `effects` carried by a player's active civics (§8). The
# mechanical policy fields (upkeep, sliders, anger, transition) are consumed
# directly by SimFacade/TurnEngine; this module is the single reader for the
# per-civic *effects* — the headline gameplay bonuses from the design table.
#
# An effect may live in one of two places on a policy record:
#   • inside the per-civic `effects` dictionary (most civics), or
#   • as a bare top-level key (a handful carry their lone effect there —
#     `worker_speed_bonus`, `pop_rush`).
# Both helpers below check both locations so callers never care which it is.

# Sum a numeric effect across every active policy. Absent keys contribute 0.
static func sum_int(player: Player, db: DataDB, key: String) -> int:
	var total: int = 0
	var policies: Dictionary = db.policies.get("policies", {})
	for cat in player.policies:
		var pol: Dictionary = policies.get(player.policies[cat], {})
		total += int(pol.get(key, 0))
		total += int(pol.get("effects", {}).get(key, 0))
	return total

# True if any active policy sets `key` truthy, in either location.
static func has_flag(player: Player, db: DataDB, key: String) -> bool:
	var policies: Dictionary = db.policies.get("policies", {})
	for cat in player.policies:
		var pol: Dictionary = policies.get(player.policies[cat], {})
		if bool(pol.get(key, false)) or bool(pol.get("effects", {}).get(key, false)):
			return true
	return false

# The set of a player's `n` most-populous settlement ids (ties broken by lowest
# id for determinism). Used by civics that reward only the largest cities, e.g.
# Representation's happiness in the largest cities.
static func largest_city_ids(gs: GameState, player_id: int, n: int) -> Array:
	var owned: Array = []
	for s in gs.settlements:
		if s.owner_player_id == player_id:
			owned.append(s)
	var ids: Array = []
	# Selection by (population desc, id asc); avoids Array.sort on objects, which
	# Godot 3 cannot order ("bad comparison function").
	while not owned.empty() and ids.size() < n:
		var best_i: int = 0
		for i in range(1, owned.size()):
			var a: Settlement = owned[i]
			var b: Settlement = owned[best_i]
			if a.population > b.population \
					or (a.population == b.population and a.id < b.id):
				best_i = i
		ids.append(owned[best_i].id)
		owned.remove(best_i)
	return ids

# A structure counts as religious — for Organized Religion's production bonus —
# if it offers a priest specialist slot or requires a state religion. The data
# tables carry no explicit "religious" tag, so this structural signal stands in.
static func is_religious_structure(db: DataDB, struct_id: String) -> bool:
	var st: Dictionary = db.get_structure(struct_id)
	if bool(st.get("effects", {}).get("requires_state_religion", false)):
		return true
	return st.get("specialist_slots", {}).has("priest")
