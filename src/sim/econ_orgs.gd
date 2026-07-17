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
#     earning the founder gold per franchise (member city) worldwide;
#   * an executive unit (`spread_corporation` tag) that spreads the corporation to
#     a new city for a treasury cost (handled in SimFacade);
#   * per-city output that scales with the COUNT of input-resource INSTANCES the
#     city owner can access — every connected copy counts, at a ×1/100 fixed rate
#     per resource (§15.10; e.g. food 75 = +0.75 food per instance, truncating);
#   * an optional produced strategic resource (`produces_resource`): every player
#     owning a member city gains access to it while the corporation operates;
#   * a per-member-city maintenance cost scaling with the same instance count
#     (`maintenance_per_resource`, ×1/100; halved by the Free Market civic);
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

# Distinct input resources of `org` the player can access (at least one instance
# each). Presence, not volume — the quest/event "owns every input" checks read this;
# output and maintenance scale with accessible_input_instances instead.
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

# Total input-resource INSTANCES of `org` the player can access: the sum over the
# input list of every connected copy (accessible_resource_counts). This is the
# §15.10 scaling term for per-city output and maintenance.
static func accessible_input_instances(game_state, org: Dictionary, player_id: int) -> int:
	var inputs: Array = org.get("input_resources", [])
	if inputs.empty():
		return 0
	var counts: Dictionary = accessible_resource_counts(game_state, player_id)
	var total: int = 0
	for res_id in inputs:
		total += int(counts.get(res_id, 0))
	return total

# Set (Dictionary used as a set) of resource ids the player has connected — from
# its own connected tiles, any received through an active recurring deal (§7), and
# any produced by a corporation the player hosts (`produces_resource`, §15.10).
# Public: also the availability half of the compound unit resource gate (§15.12) —
# UnitPrereqs.resource_ok checks a unit's resource_required against this set, so
# corporations, the production/upgrade/draft gates, the AI, and the UI all agree
# on what "having a resource" means.
static func accessible_resources(game_state, player_id: int) -> Dictionary:
	var out: Dictionary = {}
	for res_id in accessible_resource_counts(game_state, player_id):
		out[res_id] = true
	return out

# Instance counts (resource id → int) of every resource the player can access:
#   * each owned connected tile carrying the resource counts one copy (tech and
#     improvement gated, mirroring TileOutput's resource-connection rule);
#   * each active recurring deal supplying the resource counts one copy (the
#     supplier holds the connection; access lasts for the life of the deal);
#   * a corporation with `produces_resource` grants its member cities' owner one
#     copy while it operates (any member city owned, owner not banning corps).
static func accessible_resource_counts(game_state, player_id: int) -> Dictionary:
	var out: Dictionary = {}
	var db: DataDB = game_state.db
	var player: Player = game_state.get_player(player_id)
	if player == null:
		return out
	for tile in game_state.map.all_tiles():
		if tile.owner_player_id != player_id or tile.resource_id == "":
			continue
		var res: Dictionary = db.get_resource(tile.resource_id)
		if res.empty():
			continue
		var tech_req = res.get("tech_required", null)
		var imp_req = res.get("improvement_required", null)
		var tech_ok: bool = (tech_req == null or tech_req == "" or player.has_tech(tech_req))
		var imp_ok: bool = (imp_req == null or imp_req == "" or tile.improvement_id == imp_req)
		if tech_ok and imp_ok:
			out[tile.resource_id] = int(out.get(tile.resource_id, 0)) + 1
	# Resources traded in via active deals: one instance per supplying deal.
	for d in game_state.deals:
		var rec: Dictionary = d.get("recurring", {})
		var incoming: Array = []
		if int(d.get("accepter_player_id", -1)) == player_id:
			incoming = rec.get("give", {}).get("resources", [])
		elif int(d.get("proposer_player_id", -1)) == player_id:
			incoming = rec.get("receive", {}).get("resources", [])
		for r in incoming:
			out[str(r)] = int(out.get(str(r), 0)) + 1
	# Corporation-produced resources (§15.10): one instance per operating
	# corporation the player hosts, regardless of how many member cities they own.
	if not corporations_banned(player, db):
		var seen_orgs: Dictionary = {}
		for s in game_state.settlements:
			if s.owner_player_id != player_id or s.econ_org_id == "":
				continue
			if seen_orgs.has(s.econ_org_id):
				continue
			seen_orgs[s.econ_org_id] = true
			var produced: String = str(db.econ_orgs.get(s.econ_org_id, {}).get(
				"produces_resource", ""))
			if produced != "":
				out[produced] = int(out.get(produced, 0)) + 1
	return out

# Per-city corporation output on one channel ("food" / "production" / "commerce" /
# "gold" / "research" / "culture"): the org's `output_per_resource` rate × the
# owner's accessible input instances / 100 (×1/100 fixed scale, truncating; §15.10).
# Zero if the city hosts no corporation or the owner bans corporations.
static func settlement_channel(game_state, settlement: Settlement, channel: String) -> int:
	if settlement.econ_org_id == "":
		return 0
	var db: DataDB = game_state.db
	var org: Dictionary = db.econ_orgs.get(settlement.econ_org_id, {})
	var rate: int = int(org.get("output_per_resource", {}).get(channel, 0))
	if rate == 0:
		return 0
	if corporations_banned(game_state.get_player(settlement.owner_player_id), db):
		return 0
	return rate * accessible_input_instances(game_state, org, settlement.owner_player_id) / 100

# Extra [food, production, commerce] a settlement gets from its corporation: the
# per-resource rates × the owner's accessible input instances / 100 (§15.10).
# The gold/research/culture channels route through settlement_channel into their
# own pipelines instead. Zero if the owner bans corporations.
static func get_output_delta(game_state, settlement: Settlement) -> Array:
	if settlement.econ_org_id == "":
		return [0, 0, 0]
	var db: DataDB = game_state.db
	var org: Dictionary = db.econ_orgs.get(settlement.econ_org_id, {})
	var per: Dictionary = org.get("output_per_resource", {})
	if per.empty():
		return [0, 0, 0]
	if corporations_banned(game_state.get_player(settlement.owner_player_id), db):
		return [0, 0, 0]
	var n: int = accessible_input_instances(game_state, org, settlement.owner_player_id)
	return [
		int(per.get("food", 0))       * n / 100,
		int(per.get("production", 0)) * n / 100,
		int(per.get("commerce", 0))   * n / 100
	]

# Total corporation maintenance a player owes this turn: each member city they own
# charges `maintenance_per_resource × accessible input instances / 100` (reference
# 100 = 1 gold per resource instance per franchise, §15.10), reduced by the Free
# Market civic's `corporation_maintenance_reduction` percent. Cities whose owner
# bans corporations (and thus get no output) owe nothing.
static func maintenance_for(game_state, db: DataDB, player: Player) -> int:
	if corporations_banned(player, db):
		return 0
	var total: int = 0
	var instances: Dictionary = {}  # org_id → the player's input-instance count
	for s in game_state.settlements:
		if s.owner_player_id != player.id or s.econ_org_id == "":
			continue
		var org: Dictionary = db.econ_orgs.get(s.econ_org_id, {})
		var rate: int = int(org.get("maintenance_per_resource", 0))
		if rate <= 0:
			continue
		if not instances.has(s.econ_org_id):
			instances[s.econ_org_id] = accessible_input_instances(game_state, org, player.id)
		total += rate * int(instances[s.econ_org_id]) / 100
	var reduction: int = PolicyEffects.sum_int(player, db, "corporation_maintenance_reduction")
	if reduction > 0:
		total -= Fixed.scale(total, reduction)
	return total if total >= 0 else 0

# Gold the founder earns from the HQ this turn: `hq_gold_per_franchise` per member
# city worldwide (reference +4 gold per franchise, §15.10). Cities whose owner bans
# corporations are not operating franchises and pay nothing.
static func hq_gold_for(game_state, db: DataDB, player: Player) -> int:
	var gold: int = 0
	for org_id in game_state.founded_econ_orgs:
		if int(game_state.founded_econ_orgs[org_id]) != player.id:
			continue
		var org: Dictionary = db.econ_orgs.get(org_id, {})
		var per_franchise: int = int(org.get("hq_gold_per_franchise", 0))
		if per_franchise <= 0:
			continue
		for s in game_state.settlements:
			if s.econ_org_id != org_id:
				continue
			if corporations_banned(game_state.get_player(s.owner_player_id), db):
				continue
			gold += per_franchise
	return gold
