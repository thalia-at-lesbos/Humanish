# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name PlayerAI

# A deliberately simple, deterministic computer player. Like the human UI, it is a
# *client* of SimFacade: it only ever mutates state through facade.apply_command(),
# so it cannot bypass rule validation. It draws every random choice from the shared
# gs.rng (never its own generator), so an AI turn is reproducible and is captured by
# save/load just like any other pipeline randomness.
#
# Turn policy (one full turn = take_turn):
#   • Research — always steer toward the cheapest tech currently researchable.
#   • Civics   — adopt the latest (most advanced) unlocked policy in each category.
#   • Cities   — keep each city's queue full of every buildable possibility, ordered
#                cheapest-first, so it rotates through them all.
#   • Units    — ~50% garrison their cities; the rest wander and cycle through
#                whatever actions they happen to be able to take, at random.

# Run an entire turn for `player_id`, then end it. No-op if it is not that player's
# turn or the player is gone/eliminated.
static func take_turn(facade, player_id: int) -> void:
	var gs = facade.get_state()
	if gs == null or gs.current_player_id != player_id:
		return
	var player = gs.get_player(player_id)
	if player == null or player.is_eliminated:
		return

	manage_research(facade, player_id)
	manage_civics(facade, player_id)
	manage_production(facade, player_id)
	manage_units(facade, player_id)

	facade.apply_command(Commands.end_turn(player_id))

# ── Research: steer toward the cheapest researchable tech ──────────────────────

static func manage_research(facade, player_id: int) -> void:
	var gs = facade.get_state()
	var player = gs.get_player(player_id)
	if player == null:
		return
	var pick: String = _cheapest_research(gs.db, player)
	if pick != "" and pick != player.current_research_id:
		facade.apply_command(Commands.set_research(player_id, pick))

# The researchable tech with the lowest base cost. Ties resolve to the first in the
# data table's (deterministic) iteration order, so the choice is reproducible.
static func _cheapest_research(db, player) -> String:
	var best_id: String = ""
	var best_cost: int = 0
	for tech_id in db.technologies:
		if not Research.can_research(tech_id, player, db):
			continue
		var cost: int = int(db.technologies[tech_id].get("cost", 100))
		if best_id == "" or cost < best_cost:
			best_id = tech_id
			best_cost = cost
	return best_id

# ── Civics: adopt the latest unlocked policy in every category ─────────────────

static func manage_civics(facade, player_id: int) -> void:
	var gs = facade.get_state()
	var player = gs.get_player(player_id)
	if player == null:
		return
	# Walk the policy table in order; the last unlocked policy seen for a category
	# is its "latest". Data lists policies oldest→newest within a category, so this
	# yields the most advanced one the player currently qualifies for.
	var latest: Dictionary = {}   # category -> policy_id
	var policies: Dictionary = gs.db.policies.get("policies", {})
	for pol_id in policies:
		var pol: Dictionary = policies[pol_id]
		if not _tech_ok(pol.get("tech_required", null), player):
			continue
		latest[str(pol.get("category", "other"))] = pol_id
	for cat in latest:
		if player.policies.get(cat, "") != latest[cat]:
			facade.apply_command(Commands.set_policy(player_id, cat, latest[cat]))

# ── Cities: rotate through every buildable item, cheapest first ────────────────

static func manage_production(facade, player_id: int) -> void:
	var gs = facade.get_state()
	var player = gs.get_player(player_id)
	if player == null:
		return
	for s in gs.settlements:
		if s.owner_player_id != player_id:
			continue
		# Only (re)plan when the city has run dry, so it works steadily through the
		# whole cheapest-first list rather than restarting on the cheapest each turn.
		if not s.production_queue.empty():
			continue
		var queue: Array = []
		for opt in _sorted_options(gs, s, player):
			queue.append({"type": opt["type"], "id": opt["id"]})
		if not queue.empty():
			facade.apply_command(Commands.set_production(player_id, s.id, queue))

# Every unit and structure this city could build right now, sorted cheapest-first.
# Great People (born, never built) and already-built structures are excluded.
static func _sorted_options(gs, s, player) -> Array:
	var db = gs.db
	var pace: Dictionary = db.get_pace(gs.pace_id)
	var opts: Array = []
	for uid in db.units:
		var u: Dictionary = db.units[uid]
		if str(u.get("classification", "")) == "great_person":
			continue
		if not _tech_ok(u.get("tech_required", null), player):
			continue
		var item_u: Dictionary = {"type": "unit", "id": uid}
		opts.append({"type": "unit", "id": uid,
			"cost": TurnEngine._item_cost(item_u, db, player, pace)})
	for sid in db.structures:
		if s.has_structure(sid):
			continue
		var st: Dictionary = db.structures[sid]
		if not _tech_ok(st.get("tech_required", null), player):
			continue
		var item_s: Dictionary = {"type": "structure", "id": sid}
		opts.append({"type": "structure", "id": sid,
			"cost": TurnEngine._item_cost(item_s, db, player, pace)})
	# Selection sort: Godot 3 cannot stably sort arrays of dictionaries via sort(),
	# and a custom comparator over (cost, type, id) keeps the order deterministic.
	var n: int = opts.size()
	for i in range(n):
		var best: int = i
		for j in range(i + 1, n):
			if _option_better(opts[j], opts[best]):
				best = j
		if best != i:
			var tmp = opts[i]
			opts[i] = opts[best]
			opts[best] = tmp
	return opts

# True if option `a` should be built before `b`: cheaper first, ties broken by type
# then id so the ordering is fully determined.
static func _option_better(a: Dictionary, b: Dictionary) -> bool:
	if int(a["cost"]) != int(b["cost"]):
		return int(a["cost"]) < int(b["cost"])
	if str(a["type"]) != str(b["type"]):
		return str(a["type"]) < str(b["type"])
	return str(a["id"]) < str(b["id"])

# ── Units: half garrison, the rest wander and act at random ────────────────────

static func manage_units(facade, player_id: int) -> void:
	var gs = facade.get_state()
	# Snapshot ids up front: a command may remove a unit (found a city, disband),
	# so we re-fetch and null-check before acting on each one.
	var unit_ids: Array = []
	for u in gs.units:
		if u.owner_player_id == player_id:
			unit_ids.append(u.id)
	for uid in unit_ids:
		var u = gs.get_unit(uid)
		if u == null:
			continue
		# Carried units ride with their transport; they are not moved independently.
		if u.transported_by >= 0:
			continue
		if gs.rng.rand_bool_percent(50):
			_garrison_unit(facade, gs, u, player_id)
		else:
			_random_action(facade, gs, u, player_id)

# A garrison unit holds its city. If it is not standing on one of the player's own
# settlements, it heads for the nearest one; with no city to hold, it simply digs in.
static func _garrison_unit(facade, gs, u, player_id: int) -> void:
	var here = gs.get_settlement_at(u.x, u.y)
	if here != null and here.owner_player_id == player_id:
		facade.apply_command(Commands.unit_fortify(player_id, u.id))
		return
	var target = _nearest_owned_city(gs, u, player_id)
	if target != null:
		facade.apply_command(Commands.mission_move_to(player_id, u.id, target.x, target.y))
	else:
		facade.apply_command(Commands.unit_fortify(player_id, u.id))

static func _nearest_owned_city(gs, u, player_id: int):
	var best = null
	var best_d: int = 0
	for s in gs.settlements:
		if s.owner_player_id != player_id:
			continue
		var d: int = gs.map.distance(u.x, u.y, s.x, s.y)
		if best == null or d < best_d:
			best = s
			best_d = d
	return best

# Pick one of the actions this unit can currently take and do it. The candidate set
# depends on the unit (settlers can found, workers can build, etc.); a uniform draw
# over it gives the "cycle through actions randomly" behaviour.
static func _random_action(facade, gs, u, player_id: int) -> void:
	var udata: Dictionary = gs.db.get_unit(u.unit_type_id)
	var actions: Array = ["move", "fortify", "sleep", "skip"]
	if bool(udata.get("can_found", false)):
		actions.append("found")
	if bool(udata.get("can_build", false)):
		actions.append("build_road")
	var tile = gs.map.get_tile(u.x, u.y)
	if tile != null and tile.improvement_id != "":
		actions.append("pillage")

	var pick: String = actions[gs.rng.randi_range(0, actions.size() - 1)]
	match pick:
		"move":
			_move_random(facade, gs, u, player_id)
		"fortify":
			facade.apply_command(Commands.unit_fortify(player_id, u.id))
		"sleep":
			facade.apply_command(Commands.unit_sleep(player_id, u.id))
		"skip":
			facade.apply_command(Commands.mission_skip_turn(player_id, u.id))
		"found":
			# May be rejected (too close to another city); wander instead if so.
			if not facade.apply_command(Commands.found_settlement(player_id, u.id)):
				_move_random(facade, gs, u, player_id)
		"build_road":
			facade.apply_command(Commands.mission_build_road(player_id, u.id))
		"pillage":
			facade.apply_command(Commands.mission_pillage(player_id, u.id))

static func _move_random(facade, gs, u, player_id: int) -> void:
	var nbs: Array = gs.map.neighbours8(u.x, u.y)
	if nbs.empty():
		return
	var t = nbs[gs.rng.randi_range(0, nbs.size() - 1)]
	facade.apply_command(Commands.mission_move_to(player_id, u.id, t.x, t.y))

# ── Shared helpers ─────────────────────────────────────────────────────────────

# A tech requirement is satisfied when it is absent/empty or the player knows it.
static func _tech_ok(req, player) -> bool:
	return req == null or req == "" or player.has_tech(str(req))
