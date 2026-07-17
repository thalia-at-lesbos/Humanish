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
#     `pop_rush`).
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

# Civic-pressure anger for `player`, in anger percentage points (§15.9). A civic
# carrying a `civic_percent_anger` weight in its `effects` (Emancipation, the
# reference weight 400) angers every player NOT running it, scaled by the share
# of rival players that have adopted it. Mirrors the reference formula: anger
# per-mille = weight × adopters / possible, charged as pop × anger / 1000 unhappy
# citizens — expressed here in the contentment phase's percent units, so
#   points = weight × adopters × 100 / (possible × civic_percent_anger_divisor)
# with `civic_percent_anger_divisor` 1000 (the reference PERCENT_ANGER_DIVISOR),
# truncating. `possible` counts living rivals outside the player's own alliance
# (the reference excludes the player's team from both counts); adopters are the
# subset running the civic. 0 when the player runs the civic, when no rival
# exists, or when no rival has adopted it. Deterministic, no RNG.
static func civic_pressure_anger(gs: GameState, player: Player, db: DataDB) -> int:
	var total: int = 0
	var divisor: int = db.get_constant("civic_percent_anger_divisor", 1000)
	if divisor < 1:
		divisor = 1
	var policies: Dictionary = db.policies.get("policies", {})
	for pol_id in policies:
		var weight: int = int(policies[pol_id].get("effects", {}).get("civic_percent_anger", 0))
		if weight <= 0:
			continue
		if player.policies.values().has(pol_id):
			continue  # adopters are exempt from their own civic's pressure
		var adopters: int = 0
		var possible: int = 0
		for o in gs.players:
			if o.id == player.id or o.is_eliminated:
				continue
			if player.alliance_id != -1 and o.alliance_id == player.alliance_id:
				continue  # own team never pressures itself
			possible += 1
			if o.policies.values().has(pol_id):
				adopters += 1
		if possible <= 0 or adopters <= 0:
			continue
		total += (weight * adopters * 100) / (possible * divisor)
	return total

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
