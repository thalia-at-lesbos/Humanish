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

# §8 / §14.6 Corporations (economic organizations).
#
# Founded by a Great Merchant (see GreatPeople._act_found_corporation), a
# corporation lives in member settlements and consumes a set of input resources
# to produce a per-city output bonus. The reference corporation model adds, on top
# of the lighter "spreads-like-a-religion" base:
#   * a headquarters structure built once in the founding city (`hq_structure`),
#     earning the founder a gold share per unit of input consumed worldwide;
#   * an executive unit (`spread_corporation` tag) that spreads the corporation to
#     a new city for a treasury cost (handled in SimFacade);
#   * per-city output that scales with the COUNT of the corporation's input
#     resources the city owner can access (not a flat amount);
#   * a per-member-city maintenance cost (halved by the Free Market civic);
#   * civic bans (Mercantilism / State Property set `corporations_disabled`, under
#     which a player's corporations produce nothing and cost no maintenance).
#
# Pure static; the single reader of the `data/econ_orgs.json` table, called from
# TurnEngine (output, maintenance, HQ gold, organic spread) and SimFacade
# (executive spread). No signals, no RNG except the organic `spread_all` roll.

# Found a corporation in `settlement`, recording its founder and erecting the HQ
# structure in the founding city. Returns false if it already exists.
static func found(org_id: String, settlement: Settlement, game_state) -> bool:
	if game_state.founded_econ_orgs.has(org_id):
		return false
	settlement.econ_org_id = org_id
	game_state.founded_econ_orgs[org_id] = settlement.owner_player_id
	var org: Dictionary = game_state.db.econ_orgs.get(org_id, {})
	var hq: String = str(org.get("hq_structure", ""))
	if hq != "" and not settlement.has_structure(hq):
		settlement.structures.append(hq)
	return true

# True if `player` runs a civic that bans corporations (Mercantilism / State
# Property): their corporations produce no output and cost no maintenance.
static func corporations_banned(player: Player, db: DataDB) -> bool:
	return player != null and PolicyEffects.has_flag(player, db, "corporations_disabled")

# Spread corporations organically across settlements each turn (costs treasury).
# A corporation may not enter a city already hosting one, nor a city whose owner
# bans corporations.
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
			if corporations_banned(game_state.get_player(s.owner_player_id), db):
				continue
			# Check adjacency to an existing member of this corporation.
			for other in game_state.settlements:
				if other.econ_org_id != org_id:
					continue
				var dist: int = game_state.map.distance(s.x, s.y, other.x, other.y)
				if dist <= 4 and rng.rand_bool_percent(spread_chance):
					s.econ_org_id = org_id
					owner.treasury -= spread_cost
					break

# Deliberately spread `org_id` into `settlement` (executive unit). Caller checks
# the unit, tile, and treasury; this only validates the corporation rules and
# stamps the city. Returns false if the city already hosts a corporation or its
# owner bans them.
static func spread_to(org_id: String, settlement: Settlement, game_state) -> bool:
	if not game_state.founded_econ_orgs.has(org_id):
		return false
	if settlement.econ_org_id != "":
		return false
	if corporations_banned(game_state.get_player(settlement.owner_player_id), game_state.db):
		return false
	settlement.econ_org_id = org_id
	return true

# The corporation a player's executive carries: the (latest-id) corporation the
# player founded, else "" if they founded none.
static func corporation_of_player(game_state, player_id: int) -> String:
	var owned: Array = []
	for org_id in game_state.founded_econ_orgs:
		if int(game_state.founded_econ_orgs[org_id]) == player_id:
			owned.append(org_id)
	if owned.empty():
		return ""
	owned.sort()
	return owned[owned.size() - 1]

# Distinct input resources of `org` the player can access (owns a connected tile
# carrying that resource — tech and improvement gated, mirroring TileOutput's
# resource-connection rule).
static func accessible_input_count(game_state, org: Dictionary, player_id: int) -> int:
	var inputs: Array = org.get("input_resources", [])
	if inputs.empty():
		return 0
	var have: Dictionary = accessible_resources(game_state, player_id)
	var count: int = 0
	for res_id in inputs:
		if have.has(res_id):
			count += 1
	return count

# Set (Dictionary used as a set) of resource ids the player has connected — from
# its own connected tiles plus any received through an active recurring deal (§7).
# Public: also the availability half of the compound unit resource gate (§15.12) —
# UnitPrereqs.resource_ok checks a unit's resource_required against this set, so
# corporations, the production/upgrade/draft gates, the AI, and the UI all agree
# on what "having a resource" means.
static func accessible_resources(game_state, player_id: int) -> Dictionary:
	var out: Dictionary = {}
	var db: DataDB = game_state.db
	var player: Player = game_state.get_player(player_id)
	if player == null:
		return out
	for tile in game_state.map.all_tiles():
		if tile.owner_player_id != player_id or tile.resource_id == "":
			continue
		if out.has(tile.resource_id):
			continue
		var res: Dictionary = db.get_resource(tile.resource_id)
		if res.empty():
			continue
		var tech_req = res.get("tech_required", null)
		var imp_req = res.get("improvement_required", null)
		var tech_ok: bool = (tech_req == null or tech_req == "" or player.has_tech(tech_req))
		var imp_ok: bool = (imp_req == null or imp_req == "" or tile.improvement_id == imp_req)
		if tech_ok and imp_ok:
			out[tile.resource_id] = true
	# Resources traded in via an active deal count as connected (the supplier holds
	# the connection; the receiver enjoys access for the life of the deal).
	for res_id in Diplomacy.deal_resources_for(game_state, player_id):
		out[res_id] = true
	return out

# Extra [food, production, commerce] a settlement gets from its corporation:
# the flat `output_delta` plus `output_per_input_resource × accessible-input-count`
# (scaled by the city owner's resource access). Zero if the owner bans corporations.
static func get_output_delta(game_state, settlement: Settlement) -> Array:
	if settlement.econ_org_id == "":
		return [0, 0, 0]
	var db: DataDB = game_state.db
	var org: Dictionary = db.econ_orgs.get(settlement.econ_org_id, {})
	if org.empty():
		return [0, 0, 0]
	var owner: Player = game_state.get_player(settlement.owner_player_id)
	if corporations_banned(owner, db):
		return [0, 0, 0]
	var flat: Dictionary = org.get("output_delta", {})
	var per: Dictionary = org.get("output_per_input_resource", {})
	var count: int = 0
	if not per.empty():
		count = accessible_input_count(game_state, org, settlement.owner_player_id)
	return [
		int(flat.get("food", 0))       + int(per.get("food", 0))       * count,
		int(flat.get("production", 0)) + int(per.get("production", 0)) * count,
		int(flat.get("commerce", 0))   + int(per.get("commerce", 0))   * count
	]

# Total corporation maintenance a player owes this turn: each member city they own
# charges its corporation's `maintenance`, reduced by the Free Market civic's
# `corporation_maintenance_reduction` percent. Cities whose owner bans corporations
# (and thus get no output) owe nothing.
static func maintenance_for(game_state, db: DataDB, player: Player) -> int:
	if corporations_banned(player, db):
		return 0
	var total: int = 0
	for s in game_state.settlements:
		if s.owner_player_id != player.id or s.econ_org_id == "":
			continue
		var org: Dictionary = db.econ_orgs.get(s.econ_org_id, {})
		total += int(org.get("maintenance", db.get_constant("corporation_maintenance", 0)))
	var reduction: int = PolicyEffects.sum_int(player, db, "corporation_maintenance_reduction")
	if reduction > 0:
		total -= Fixed.scale(total, reduction)
	return total if total >= 0 else 0

# Gold the founder earns from the HQ this turn: a share per unit of input consumed
# in every member city worldwide. A city consumes one "unit" per distinct input
# resource its owner can access (the same count that scales its output); cities
# whose owner bans corporations consume nothing.
static func hq_gold_for(game_state, db: DataDB, player: Player) -> int:
	var gold: int = 0
	for org_id in game_state.founded_econ_orgs:
		if int(game_state.founded_econ_orgs[org_id]) != player.id:
			continue
		var org: Dictionary = db.econ_orgs.get(org_id, {})
		var per_input: int = int(org.get("hq_gold_per_input",
			db.get_constant("corporation_hq_gold_per_input", 0)))
		if per_input <= 0:
			continue
		for s in game_state.settlements:
			if s.econ_org_id != org_id:
				continue
			if corporations_banned(game_state.get_player(s.owner_player_id), db):
				continue
			gold += per_input * accessible_input_count(game_state, org, s.owner_player_id)
	return gold
