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

# §8 / §14.6 / §15.22 Corporations (economic organizations).
#
# Founded by a Great Merchant (see GreatPeople._act_found_corporation), a
# corporation lives in member settlements and consumes a set of input resources
# to produce a per-city output bonus. The reference corporation model:
#   * a headquarters structure built once in the founding city (`hq_structure`),
#     earning the founder gold per franchise (member city) worldwide;
#   * an executive unit (`spread_corporation` tag) that spreads the corporation to
#     a new city — the ONLY spread channel (§15.22: the reference has no
#     organic/passive corporation spread; the religion-style channel Humanish
#     used to run each world step was an invention and was removed at T2).
#     The executive pays `spread_base_cost` × (100 + inflation)/100, doubled
#     into a foreign non-vassal city and ×(100 + `spread_factor`)/100 per
#     competing incumbent, then rolls the executive unit's
#     `corporation_spread_strength` (halved foreign, interpolated toward 100
#     by the city's open corporation slots — an empty city is guaranteed).
#     The cost is charged and the executive consumed even on a failed roll;
#   * per-city output that scales with the COUNT of input-resource INSTANCES the
#     city owner can access — every connected copy counts, at a ×1/100 fixed rate
#     per resource (§15.10; e.g. food 75 = +0.75 food per instance, truncating);
#   * an optional produced strategic resource (`produces_resource`): every player
#     owning a member city gains access to it while the corporation operates;
#   * a per-member-city maintenance cost scaling with the same instance count
#     (`maintenance_per_resource`, ×1/100; halved by the Free Market civic);
#   * civic bans (§15.22): State Property sets `corporations_disabled` (every
#     corporation banned); Mercantilism sets `foreign_corporations_disabled`
#     (only corporations whose HQ city the player does not own — strictly
#     player-owned, with no alliance or vassalage exemption). A banned
#     corporation's franchises go DORMANT, symmetrically: they stay in place
#     (nothing is evicted, HQ included) but produce no output, grant no
#     produced resource, pay no HQ gold, and cost no maintenance; executives
#     cannot spread into them. Everything resumes when the civic changes.
#
# Pure static; the single reader of the `data/econ_orgs.json` table, called from
# TurnEngine (output, maintenance, HQ gold) and SimFacade (executive spread).
# No signals; the only RNG is the §15.22 executive success roll in
# attempt_executive_spread (drawn from gs.rng, and skipped entirely at chance
# 100 or 0 per the §15.5 no-pointless-draws discipline).

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

# The player id owning `org_id`'s headquarters CITY (the settlement carrying its
# `hq_structure` — the HQ moves with the city on conquest), or -1 while no such
# city stands (never founded, or the HQ city was razed).
static func hq_owner(game_state, org_id: String) -> int:
	var hq: String = str(game_state.db.econ_orgs.get(org_id, {}).get("hq_structure", ""))
	if hq == "":
		return -1
	for s in game_state.settlements:
		if s.has_structure(hq):
			return s.owner_player_id
	return -1

# §15.22 civic ban, per corporation: true if `org_id` is banned — dormant — for
# `player`. Either the full `corporations_disabled` ban (State Property), or the
# `foreign_corporations_disabled` ban (Mercantilism), which bans a corporation
# whose HQ city is not owned by this player — strictly player-owned: an ally's,
# master's, or vassal's HQ still counts as foreign (no exemption of any kind).
# While banned, the player's franchises persist but yield nothing, cost no
# maintenance, and cannot be spread into; all of it resumes automatically when
# the civic changes.
static func banned_for(game_state, org_id: String, player: Player) -> bool:
	if player == null:
		return false
	var db: DataDB = game_state.db
	if PolicyEffects.has_flag(player, db, "corporations_disabled"):
		return true
	if PolicyEffects.has_flag(player, db, "foreign_corporations_disabled"):
		return hq_owner(game_state, org_id) != player.id
	return false

# ── §15.22 executive spread (the only spread channel) ─────────────────────────

# Number of corporation types in the data table (the reference "total
# corporations", 7 as shipped): the interpolation denominator of the §15.22
# success roll — each corporation the city already hosts closes one slot.
static func total_corporations(db: DataDB) -> int:
	var n: int = 0
	for org_id in db.econ_orgs:
		if str(org_id) != "_comment":
			n += 1
	return n

# Whether `settlement` is foreign for §15.22 spread pricing/odds: owned by a
# player of another alliance (the Humanish "team") that is not a vassal of the
# spreader's alliance. A vassal's city prices and rolls as domestic.
static func is_foreign_for_spread(game_state, settlement: Settlement, spreader_player_id: int) -> bool:
	if settlement.owner_player_id == spreader_player_id:
		return false
	var mine: Alliance = game_state.get_player_alliance(spreader_player_id)
	var theirs: Alliance = game_state.get_player_alliance(settlement.owner_player_id)
	if mine == null or theirs == null:
		return true
	if mine.id == theirs.id:
		return false
	return theirs.is_subordinate_to != mine.id

# Two corporations compete iff they share at least one input resource (§15.22).
static func competes_with(db: DataDB, a_id: String, b_id: String) -> bool:
	var a_inputs: Array = db.econ_orgs.get(a_id, {}).get("input_resources", [])
	var b_inputs: Array = db.econ_orgs.get(b_id, {}).get("input_resources", [])
	for res_id in a_inputs:
		if res_id in b_inputs:
			return true
	return false

# Corporations active in `settlement` that compete with `org_id` (share an input
# resource). Under Humanish's one-corporation-per-city model a city hosts at
# most one, and an incumbent blocks spread outright (can_spread_to), so at
# runtime this is always empty on an eligible target — the §15.22 competition
# surcharge is implemented faithfully in structure but vacuous in play.
static func competing_incumbents(game_state, org_id: String, settlement: Settlement) -> Array:
	var out: Array = []
	var inc: String = settlement.econ_org_id
	if inc != "" and inc != org_id and competes_with(game_state.db, org_id, inc):
		out.append(inc)
	return out

# §15.22 executive spread cost (integer division after every step):
#   1. spread_base_cost × (100 + inflation%) / 100   (clamped at 0 first)
#   2. foreign non-vassal city: × foreign-spread-cost percent / 100 (×2)
#   3. per competing incumbent: × (100 + its spread_factor) / 100 (×3 each —
#      vacuous under one-corporation-per-city, see competing_incumbents).
# `inflation_pct` is the §15.1 economy-wide rate (TurnEngine.inflation_rate),
# passed in by the caller so this module stays free of TurnEngine references.
static func executive_spread_cost(game_state, org_id: String, settlement: Settlement,
		spreader_player_id: int, inflation_pct: int) -> int:
	var db: DataDB = game_state.db
	var org: Dictionary = db.econ_orgs.get(org_id, {})
	var scaled: int = int(org.get("spread_base_cost", 50)) * (100 + inflation_pct)
	scaled = scaled if scaled > 0 else 0
	var cost: int = scaled / 100
	if is_foreign_for_spread(game_state, settlement, spreader_player_id):
		cost = cost * db.get_constant("corporation_foreign_spread_cost_percent", 200) / 100
	for inc_id in competing_incumbents(game_state, org_id, settlement):
		var factor: int = int(db.econ_orgs.get(inc_id, {}).get("spread_factor", 200))
		cost = cost * (100 + factor) / 100
	return cost

# §15.22 success chance in percent: the executive unit's
# `corporation_spread_strength` (40), halved in a foreign city, then topped up
# by (total − corporations_in_city) × (100 − prob) / total — the fraction of
# the corporation slots the city has open. An empty city lands on exactly 100
# (own or foreign — guaranteed spread); each incumbent lowers it (own-team with
# one incumbent 91, foreign 88). Under one-corporation-per-city every eligible
# target is empty, so in play the chance is always 100 and no draw is made.
static func executive_spread_chance(game_state, org_id: String, settlement: Settlement,
		spreader_player_id: int) -> int:
	var db: DataDB = game_state.db
	var org: Dictionary = db.econ_orgs.get(org_id, {})
	var exe_unit: Dictionary = db.get_unit(str(org.get("executive_unit", "")))
	var prob: int = int(exe_unit.get("corporation_spread_strength", 40))
	if is_foreign_for_spread(game_state, settlement, spreader_player_id):
		prob = prob / 2
	var total: int = total_corporations(db)
	var in_city: int = 1 if settlement.econ_org_id != "" else 0
	if total > 0:
		prob += (total - in_city) * (100 - prob) / total
	return prob

# §15.22 executive spread eligibility (treasury and unit checks are the
# caller's): the corporation is founded; the target city hosts no corporation
# (Humanish's one-per-city rule — it also covers the reference "not already
# hosting this corporation" and "not a competing HQ" clauses); the city owner's
# civics allow corporations; and the city has at least one of the corporation's
# input resources. The reference resource gate is city-level; Humanish resource
# access is owner-wide (§15.10), so it collapses to the CITY OWNER having ≥1
# accessible input resource of this corporation.
static func can_spread_to(org_id: String, settlement: Settlement, game_state) -> bool:
	if not game_state.founded_econ_orgs.has(org_id):
		return false
	if settlement.econ_org_id != "":
		return false
	if banned_for(game_state, org_id, game_state.get_player(settlement.owner_player_id)):
		return false
	var org: Dictionary = game_state.db.econ_orgs.get(org_id, {})
	return accessible_input_count(game_state, org, settlement.owner_player_id) > 0

# Run one §15.22 executive spread attempt against `settlement`: charge the full
# cost, then roll the success chance through the shared gs.rng (skipping the
# draw at chance 100 or 0 — the §15.5 no-pointless-draws discipline) and stamp
# the city on success. THE COST IS CHARGED EVEN ON FAILURE (the executive is
# consumed by the caller either way). Assumes can_spread_to and the treasury
# check already passed. Returns {"cost": int, "chance": int, "success": bool}.
static func attempt_executive_spread(game_state, org_id: String, settlement: Settlement,
		spreader_player_id: int, inflation_pct: int) -> Dictionary:
	var cost: int = executive_spread_cost(
		game_state, org_id, settlement, spreader_player_id, inflation_pct)
	var player: Player = game_state.get_player(spreader_player_id)
	if player != null:
		player.treasury -= cost
	var chance: int = executive_spread_chance(game_state, org_id, settlement, spreader_player_id)
	var success: bool = true
	if chance <= 0:
		success = false
	elif chance < 100:
		success = game_state.rng.rand_bool_percent(chance)
	if success:
		settlement.econ_org_id = org_id
	return {"cost": cost, "chance": chance, "success": success}

# Deliberately spread `org_id` into `settlement` (executive unit). Caller checks
# the unit, tile, and treasury; this only validates the corporation rules and
# stamps the city. Returns false if the city already hosts a corporation or its
# owner bans them.
static func spread_to(org_id: String, settlement: Settlement, game_state) -> bool:
	if not game_state.founded_econ_orgs.has(org_id):
		return false
	if settlement.econ_org_id != "":
		return false
	if banned_for(game_state, org_id, game_state.get_player(settlement.owner_player_id)):
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
	# A corporation dormant under a civic ban (§15.22) grants nothing.
	var seen_orgs: Dictionary = {}
	for s in game_state.settlements:
		if s.owner_player_id != player_id or s.econ_org_id == "":
			continue
		if seen_orgs.has(s.econ_org_id):
			continue
		seen_orgs[s.econ_org_id] = true
		if banned_for(game_state, s.econ_org_id, player):
			continue
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
	if banned_for(game_state, settlement.econ_org_id,
			game_state.get_player(settlement.owner_player_id)):
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
	if banned_for(game_state, settlement.econ_org_id,
			game_state.get_player(settlement.owner_player_id)):
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
# Market civic's `corporation_maintenance_reduction` percent. A franchise dormant
# under a civic ban (§15.22 — and thus yielding no output) owes nothing: the
# yield and maintenance cutoffs are symmetric.
static func maintenance_for(game_state, db: DataDB, player: Player) -> int:
	var total: int = 0
	var instances: Dictionary = {}  # org_id → the player's input-instance count
	for s in game_state.settlements:
		if s.owner_player_id != player.id or s.econ_org_id == "":
			continue
		if banned_for(game_state, s.econ_org_id, player):
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
# city worldwide (reference +4 gold per franchise, §15.10). A franchise dormant
# under its owner's civic ban (§15.22) is not operating and pays nothing.
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
			if banned_for(game_state, org_id, game_state.get_player(s.owner_player_id)):
				continue
			gold += per_franchise
	return gold
