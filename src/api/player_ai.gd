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

	manage_economy(facade, player_id)
	manage_research(facade, player_id)
	manage_civics(facade, player_id)
	manage_religion(facade, player_id)
	manage_assembly(facade, player_id)
	manage_production(facade, player_id)
	manage_units(facade, player_id)

	facade.apply_command(Commands.end_turn(player_id))

# ── Economy: pour into research, but stay solvent ──────────────────────────────

# Treasury below this (and not already in finance mode) makes the AI redirect the
# economy toward finance until it recovers. New players default to 100% research
# (zero finance income), so without this an AI would slowly bleed its reserve dry.
const SOLVENCY_TREASURY: int = 40

# Set the allocation sliders: research-heavy by default, finance-heavy when the
# treasury runs thin. The split always respects the policy-imposed step and
# minimum-research constraints so SimFacade accepts it.
static func manage_economy(facade, player_id: int) -> void:
	var gs = facade.get_state()
	var player = gs.get_player(player_id)
	if player == null:
		return

	# Mirror SimFacade._cmd_set_sliders: governing policies set an allowed increment
	# and a research floor.
	var increment: int = 0
	var min_research: int = 0
	var policies: Dictionary = gs.db.policies.get("policies", {})
	for cat in player.policies:
		var pol: Dictionary = policies.get(player.policies[cat], {})
		increment = max(increment, int(pol.get("slider_increment", 0)))
		min_research = max(min_research, int(pol.get("slider_min_research", 0)))
	var step: int = increment if increment > 0 else 10

	# Personality tilt (§C4): an economy-leaning leader runs a standing finance
	# share (more gold, less research); a science-leaning leader pushes the other
	# way and stays at full research. A traitless leader nets zero, preserving the
	# Phase-B research-everything default.
	var db = gs.db
	var profile: Dictionary = _focus_profile(player, db)
	var tilt: int = (int(profile["economy"]) - int(profile["science"])) \
		* db.get_constant("ai_focus_finance_per_economy", 10)
	var cap: int = db.get_constant("ai_focus_finance_cap", 50)
	var focus_finance: int = tilt if tilt > 0 else 0
	focus_finance = focus_finance if focus_finance < cap else cap

	# Finance share: the larger of the personality tilt and a solvency reserve when
	# gold is low.
	var solvency: int = 50 if player.treasury < SOLVENCY_TREASURY else 0
	var finance: int = focus_finance if focus_finance > solvency else solvency
	finance = (finance / step) * step
	var research: int = 100 - finance
	# Honour the research floor by trimming finance if it would dip below it.
	if research < min_research:
		finance = ((100 - min_research) / step) * step
		research = 100 - finance
	if finance < 0:
		finance = 0
		research = 100

	# No change needed if we are already there (avoids a redundant command/hash churn).
	if player.slider_finance == finance and player.slider_research == research \
			and player.slider_culture == 0 and player.slider_intel == 0:
		return
	facade.apply_command(Commands.set_sliders(player_id, finance, research, 0, 0))

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

# ── State religion: adopt the religion the empire already follows (§8) ──────────

# The AI adopts a state religion once one is present in its cities and it has none.
# It never switches afterward, so it never pays the anarchy cost — a deliberately
# conservative policy that still exercises the state-religion path. The choice is
# the lowest-id belief present (deterministic, no RNG).
static func manage_religion(facade, player_id: int) -> void:
	var gs = facade.get_state()
	var player = gs.get_player(player_id)
	if player == null or player.state_religion != "":
		return
	var present = {}
	for s in gs.settlements:
		if s.owner_player_id == player_id and s.belief_id != "":
			present[s.belief_id] = true
	if present.empty():
		return
	var ids = present.keys()
	ids.sort()
	facade.apply_command(Commands.set_state_religion(player_id, ids[0]))

# ── Assembly: cast a self-interested vote on any open proposal (§7.2) ───────────

# When a diplomatic-assembly session is open and this computer player is an eligible
# member that has not yet voted, cast the deterministic self-interest vote chosen by
# Assembly.ai_vote (no RNG). Goes through the command path like any other action.
static func manage_assembly(facade, player_id: int) -> void:
	var gs = facade.get_state()
	if not Assembly.has_open_session(gs) or Assembly.has_voted(gs, player_id):
		return
	var p = gs.get_player(player_id)
	if p == null or not Assembly.is_member(gs, p, str(gs.assembly.get("kind", ""))):
		return
	facade.apply_command(Commands.cast_vote(player_id, Assembly.ai_vote(gs, player_id)))

# ── Cities: a role-ordered build list (§B3) ────────────────────────────────────
#
# Replaces the old cheapest-first-everything queue with a deterministic priority
# playbook: a needed garrison defender first, then growth/economy structures, then
# settlers/workers while the empire is still expanding, then everything else as a
# cheapest-first fallback. Ties at every level resolve by (cost, type, id) so the
# plan is fully reproducible without touching the RNG.

# Role ranks — lower builds first.
const ROLE_DEFENDER: int = 0    # a military land unit while the city is under its floor
const ROLE_ECONOMY: int = 1     # any structure (growth/commerce/infrastructure)
const ROLE_EXPANSION: int = 2   # settler/worker while the empire still wants them
const ROLE_FALLBACK: int = 3    # extra military and everything else, cheapest-first

static func manage_production(facade, player_id: int) -> void:
	var gs = facade.get_state()
	var player = gs.get_player(player_id)
	if player == null:
		return
	for s in gs.settlements:
		if s.owner_player_id != player_id:
			continue
		# Only (re)plan when the city has run dry, so it works steadily through the
		# whole priority list rather than restarting on the top item each turn.
		if not s.production_queue.empty():
			continue
		var queue: Array = []
		for opt in _sorted_options(gs, s, player):
			queue.append({"type": opt["type"], "id": opt["id"]})
		if not queue.empty():
			facade.apply_command(Commands.set_production(player_id, s.id, queue))

# Every unit and structure this city could build right now, role-ranked then
# cheapest-first within a rank. Great People (born, never built), already-built
# structures, and expansion units the empire does not currently want are excluded.
static func _sorted_options(gs, s, player) -> Array:
	var db = gs.db
	var pace: Dictionary = db.get_pace(gs.pace_id)
	# Build context: does this city need a defender, and is the empire expanding?
	var needs_defender: bool = _city_defender_count(gs, s, player.id) < _defender_target(gs, s, player.id)
	var wants_settler: bool = _wants_settler(gs, player)
	var wants_worker: bool = _wants_worker(gs, player)
	# Leader personality (§C3): within a role, items on the leader's stronger axes
	# sort earlier — a soft bias, applied *below* the role floors so the defender
	# floor still wins. A traitless leader has an all-zero profile, leaving the
	# Phase-B cheapest-first order untouched.
	var profile: Dictionary = _focus_profile(player, db)
	var opts: Array = []
	for uid in db.units:
		var u: Dictionary = db.units[uid]
		if str(u.get("classification", "")) == "great_person":
			continue
		if not _tech_ok(u.get("tech_required", null), player):
			continue
		# Religion-spreaders (missionaries) need a religion plus either a monastery
		# (trains_missionaries) or the Organized Religion civic (§8).
		if "requires_religion" in u.get("tags", []) and not _can_train_missionary(gs, s, player):
			continue
		# Drop expansion units the empire does not currently want, so the AI never
		# spams settlers with nowhere to go or workers it cannot use.
		if bool(u.get("can_found", false)) and not wants_settler:
			continue
		if _is_worker_unit(u) and not wants_worker:
			continue
		var item_u: Dictionary = {"type": "unit", "id": uid}
		opts.append({"type": "unit", "id": uid, "role": _unit_role(u, needs_defender),
			"focus": int(profile.get(_unit_axis(u), 0)),
			"cost": TurnEngine._item_cost(item_u, db, player, pace)})
	for sid in db.structures:
		if s.has_structure(sid):
			continue
		var st: Dictionary = db.structures[sid]
		if bool(st.get("corporation_hq", false)):
			continue  # HQs are granted by founding a corporation, not built (§14.6)
		if not _tech_ok(st.get("tech_required", null), player):
			continue
		var item_s: Dictionary = {"type": "structure", "id": sid}
		opts.append({"type": "structure", "id": sid, "role": ROLE_ECONOMY,
			"focus": int(profile.get(_structure_axis(st), 0)),
			"cost": TurnEngine._item_cost(item_s, db, player, pace)})
	# Selection sort: Godot 3 cannot stably sort arrays of dictionaries via sort(),
	# and a custom comparator over (role, cost, type, id) keeps the order determined.
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

# Role rank for a unit option, given whether the city still needs a garrison.
# A military land unit fills the defender slot first; otherwise (and for every
# non-military unit) it is a cheapest-first fallback, with expansion units ranked
# between economy and the fallback when the empire wants them.
static func _unit_role(u: Dictionary, needs_defender: bool) -> int:
	if _is_military_unit(u):
		return ROLE_DEFENDER if needs_defender else ROLE_FALLBACK
	if bool(u.get("can_found", false)) or _is_worker_unit(u):
		return ROLE_EXPANSION
	return ROLE_FALLBACK

# True if option `a` should be built before `b`: lower role first; then, within a
# role, the leader's stronger focus axis first (§C3 personality bias); then
# cheaper, ties broken by type then id so the ordering is fully determined. Focus
# sits *below* role so a role floor (e.g. the defender slot) always outranks it.
static func _option_better(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("role", ROLE_FALLBACK)) != int(b.get("role", ROLE_FALLBACK)):
		return int(a.get("role", ROLE_FALLBACK)) < int(b.get("role", ROLE_FALLBACK))
	if int(a.get("focus", 0)) != int(b.get("focus", 0)):
		return int(a.get("focus", 0)) > int(b.get("focus", 0))
	if int(a["cost"]) != int(b["cost"]):
		return int(a["cost"]) < int(b["cost"])
	if str(a["type"]) != str(b["type"]):
		return str(a["type"]) < str(b["type"])
	return str(a["id"]) < str(b["id"])

# ── §C3 Option focus axis (data-driven) ────────────────────────────────────────
#
# Map a buildable to the strategic axis a focus profile weights it on, so the §C3
# comparator can nudge a leader's dominant axis earlier within a role.

# Structure effect keys that mark a building as military-flavoured even without an
# explicit defence bonus (barracks → land_xp, stable → mounted_xp, …).
const MILITARY_EFFECT_KEYS: Array = ["city_defense", "military_production_city",
	"heals_units", "free_promotion", "free_promotion_all", "block_barbarians",
	"great_general_rate"]

# A unit's axis: military units bias `military`, settlers `expand`, workers
# `economy`; anything else has no axis ("" → zero weight).
static func _unit_axis(u: Dictionary) -> String:
	if _is_military_unit(u):
		return "military"
	if bool(u.get("can_found", false)):
		return "expand"
	if _is_worker_unit(u):
		return "economy"
	return ""

# A structure's axis from its data bonuses/effects: a research building biases
# `science`, a defensive or military-training building `military`, and every other
# growth/commerce/infrastructure building `economy` (the broad default).
static func _structure_axis(st: Dictionary) -> String:
	if int(st.get("science_bonus", 0)) > 0:
		return "science"
	if int(st.get("defence_bonus", 0)) > 0 or int(st.get("cultural_defence_bonus", 0)) > 0:
		return "military"
	var effects: Dictionary = st.get("effects", {})
	for k in effects:
		if str(k).ends_with("_xp") or str(k) in MILITARY_EFFECT_KEYS:
			return "military"
	return "economy"

# ── Units: a flat, deterministic playbook (§B1–B6) ─────────────────────────────
#
# Wholly deterministic — no RNG. Each unit is handled exactly once per turn, in
# four ordered passes:
#   1. Settlers walk toward the best legal city site and found there (§B1).
#   2. Garrisons: each city's defender slots are filled nearest-first from idle
#      military units, which fortify in place (§B4); a threatened city raises its
#      target by one so a free unit is pulled in (§B5).
#   3. Free military units attack an adjacent target they clearly out-power, else
#      advance on the nearest threat or fortify (§B6).
#   4. Workers improve their tile; recon explores; anything else digs in.

static func manage_units(facade, player_id: int) -> void:
	var gs = facade.get_state()
	var player = gs.get_player(player_id)
	if player == null:
		return
	# Snapshot ids up front: a command may remove a unit (found a city), so we
	# re-fetch and null-check before acting on each one. `handled` guarantees each
	# unit acts in exactly one pass.
	var unit_ids: Array = []
	for u in gs.units:
		if u.owner_player_id == player_id and u.transported_by < 0:
			unit_ids.append(u.id)
	var handled: Dictionary = {}

	# Pass 1 — settlers.
	for uid in unit_ids:
		var su = gs.get_unit(uid)
		if su == null or not bool(gs.db.get_unit(su.unit_type_id).get("can_found", false)):
			continue
		_manage_settler(facade, gs, su, player)
		handled[uid] = true

	# Pass 2 — garrison assignment (nearest-first, deterministic).
	for uid in _assign_garrisons(facade, gs, unit_ids, handled, player_id):
		handled[uid] = true

	# Pass 3 & 4 — remaining units by role.
	for uid in unit_ids:
		if handled.get(uid, false):
			continue
		var u = gs.get_unit(uid)
		if u == null:
			continue
		var udata: Dictionary = gs.db.get_unit(u.unit_type_id)
		if _is_military_unit(udata):
			_manage_free_military(facade, gs, u, player_id)
		elif _is_worker_unit(udata):
			_manage_worker(facade, gs, u, player_id)
		elif str(udata.get("classification", "")) == "recon":
			facade.apply_command(Commands.mission_explore(player_id, u.id))
		else:
			facade.apply_command(Commands.unit_fortify(player_id, u.id))

# ── §B1 Expansion: settlers seek the best site and found ───────────────────────

# Walk toward the best legal city site and found on arrival. With no positive site
# in range, found in place if legal, else wander toward open land.
static func _manage_settler(facade, gs, u, player) -> void:
	var player_id: int = player.id
	var site = _best_city_site(gs, u, player)
	if site == null:
		if _legal_site(gs, u.x, u.y):
			facade.apply_command(Commands.found_settlement(player_id, u.id))
		else:
			_seek_open_land(facade, gs, u, player_id)
		return
	if u.x == int(site["x"]) and u.y == int(site["y"]):
		facade.apply_command(Commands.found_settlement(player_id, u.id))
		return
	# Move toward the site; if the move reaches it this turn, found immediately.
	facade.apply_command(Commands.mission_move_to(player_id, u.id, int(site["x"]), int(site["y"])))
	var after = gs.get_unit(u.id)
	if after != null and after.x == int(site["x"]) and after.y == int(site["y"]):
		facade.apply_command(Commands.found_settlement(player_id, after.id))

# The highest-scoring legal unclaimed city site within the settler's search radius,
# or null if none scores above the floor. Fully deterministic: ties resolve by
# higher score then lower tile id (y * width + x).
static func _best_city_site(gs, u, player):
	var db = gs.db
	var radius: int = db.get_constant("ai_settle_search_radius", 6)
	var dist_penalty: int = db.get_constant("ai_site_distance_penalty", 2)
	var min_score: int = db.get_constant("ai_site_min_score", 1)
	var best = null
	var best_score: int = 0
	var best_key: int = 0
	for t in gs.map.tiles_in_range(u.x, u.y, radius):
		if not _legal_site(gs, t.x, t.y):
			continue
		var score: int = _site_score(gs, t.x, t.y) \
			- gs.map.distance(u.x, u.y, t.x, t.y) * dist_penalty
		if score < min_score:
			continue
		var key: int = t.y * gs.map.width + t.x
		if best == null or score > best_score or (score == best_score and key < best_key):
			best = {"x": t.x, "y": t.y}
			best_score = score
			best_key = key
	return best

# Sum of the surrounding tiles' weighted base yields over the city work radius (2).
static func _site_score(gs, cx: int, cy: int) -> int:
	var db = gs.db
	var fw: int = db.get_constant("ai_site_yield_food_weight", 2)
	var pw: int = db.get_constant("ai_site_yield_production_weight", 2)
	var cw: int = db.get_constant("ai_site_yield_commerce_weight", 1)
	var total: int = 0
	for t in gs.map.tiles_in_range(cx, cy, 2):
		var bo: Dictionary = db.get_terrain(t.terrain_id).get("base_output", {})
		total += int(bo.get("food", 0)) * fw + int(bo.get("production", 0)) * pw \
			+ int(bo.get("commerce", 0)) * cw
	return total

# A tile is a legal settlement site when it is passable land and no existing
# settlement is closer than the minimum spacing — mirrors SimFacade._cmd_found.
static func _legal_site(gs, cx: int, cy: int) -> bool:
	var tile = gs.map.get_tile(cx, cy)
	if tile == null:
		return false
	var ter: Dictionary = gs.db.get_terrain(tile.terrain_id)
	if str(ter.get("domain", "land")) != "land" or bool(ter.get("impassable", false)):
		return false
	var min_dist: int = gs.db.get_constant("min_settlement_distance", 3)
	for s in gs.settlements:
		if gs.map.distance(cx, cy, s.x, s.y) < min_dist:
			return false
	return true

# No good site in range: step toward open land (the neighbour that maximises the
# distance to the nearest settlement), so the settler keeps seeking. Falls back to
# fortify when nothing improves, so it never stalls the turn loop.
static func _seek_open_land(facade, gs, u, player_id: int) -> void:
	var here: int = _nearest_settlement_distance(gs, u.x, u.y)
	var best = null
	var best_d: int = here
	var best_key: int = 0
	for t in gs.map.neighbours8(u.x, u.y):
		var ter: Dictionary = gs.db.get_terrain(t.terrain_id)
		if str(ter.get("domain", "land")) != "land" or bool(ter.get("impassable", false)):
			continue
		var d: int = _nearest_settlement_distance(gs, t.x, t.y)
		var key: int = t.y * gs.map.width + t.x
		if d > best_d or (d == best_d and best != null and key < best_key):
			best = t
			best_d = d
			best_key = key
	if best != null:
		facade.apply_command(Commands.mission_move_to(player_id, u.id, best.x, best.y))
	else:
		facade.apply_command(Commands.unit_fortify(player_id, u.id))

static func _nearest_settlement_distance(gs, x: int, y: int) -> int:
	var best: int = -1
	for s in gs.settlements:
		var d: int = gs.map.distance(x, y, s.x, s.y)
		if best < 0 or d < best:
			best = d
	return best if best >= 0 else 0

# ── §B2 City-count target: keep expanding while good land remains ──────────────

# True while the empire is below its city target AND a positive-scoring open site
# exists near one of its cities (or it has no city yet). Drives both settler
# production (§B3) and whether a settler bothers to look for a site.
static func _wants_settler(gs, player) -> bool:
	if _owned_city_count(gs, player.id) >= _city_target(player, gs.db):
		return false
	return _open_site_exists(gs, player)

# The empire's city-count target: the base, plus the leader's `expand` focus (§C4)
# so an expansionist settles wider while a homebody stops at the baseline.
static func _city_target(player, db) -> int:
	return db.get_constant("ai_city_target", 6) \
		+ int(_focus_profile(player, db)["expand"]) * db.get_constant("ai_focus_city_per_expand", 1)

# A worker is wanted while the empire has fewer workers than cities.
static func _wants_worker(gs, player) -> bool:
	var workers: int = 0
	for u in gs.units:
		if u.owner_player_id == player.id and _is_worker_unit(gs.db.get_unit(u.unit_type_id)):
			workers += 1
	return workers < _owned_city_count(gs, player.id)

# Is there a legal, positive-scoring city site within settling range of the empire?
# Scanned around each city (and a no-city player always qualifies so it can settle
# its first one). The scan is O(cities × tiles_in_range), never O(tiles²).
static func _open_site_exists(gs, player) -> bool:
	var radius: int = gs.db.get_constant("ai_settle_search_radius", 6)
	var min_score: int = gs.db.get_constant("ai_site_min_score", 1)
	var anchors: Array = []
	for s in gs.settlements:
		if s.owner_player_id == player.id:
			anchors.append(s)
	if anchors.empty():
		return true
	var seen: Dictionary = {}
	for s in anchors:
		for t in gs.map.tiles_in_range(s.x, s.y, radius):
			var key: int = t.y * gs.map.width + t.x
			if seen.has(key):
				continue
			seen[key] = true
			if _legal_site(gs, t.x, t.y) and _site_score(gs, t.x, t.y) >= min_score:
				return true
	return false

static func _owned_city_count(gs, player_id: int) -> int:
	var n: int = 0
	for s in gs.settlements:
		if s.owner_player_id == player_id:
			n += 1
	return n

# ── §B4/§B5 Military floor: garrison each city to strength ─────────────────────

# Fill every city's defender slots from the nearest idle military units, deciding
# the whole assignment before issuing orders so it is order-independent. An
# assigned unit standing on its city fortifies; otherwise it marches to it.
# Returns the ids it handled. A threatened city's target is raised by one (§B5).
static func _assign_garrisons(facade, gs, unit_ids: Array, handled: Dictionary, player_id: int) -> Array:
	var military: Array = []
	for uid in unit_ids:
		if handled.get(uid, false):
			continue
		var u = gs.get_unit(uid)
		if u != null and _is_military_unit(gs.db.get_unit(u.unit_type_id)):
			military.append(uid)
	# Cities in id order for a stable assignment.
	var cities: Array = []
	for s in gs.settlements:
		if s.owner_player_id == player_id:
			cities.append(s)
	_sort_by_id(cities)

	var assigned: Dictionary = {}   # uid -> settlement
	for s in cities:
		var target: int = _defender_target(gs, s, player_id)
		var count: int = 0
		while count < target:
			var pick: int = _nearest_unassigned(gs, military, assigned, s)
			if pick < 0:
				break
			assigned[pick] = s
			count += 1
	var done: Array = []
	for uid in assigned:
		var u = gs.get_unit(uid)
		if u == null:
			continue
		var s = assigned[uid]
		if u.x == s.x and u.y == s.y:
			facade.apply_command(Commands.unit_fortify(player_id, u.id))
		else:
			facade.apply_command(Commands.mission_move_to(player_id, u.id, s.x, s.y))
		done.append(uid)
	return done

# The id of the nearest military unit not yet assigned, or -1. Ties resolve by
# lower unit id so the choice is fully determined.
static func _nearest_unassigned(gs, military: Array, assigned: Dictionary, s) -> int:
	var best: int = -1
	var best_d: int = 0
	for uid in military:
		if assigned.has(uid):
			continue
		var u = gs.get_unit(uid)
		if u == null:
			continue
		var d: int = gs.map.distance(u.x, u.y, s.x, s.y)
		if best < 0 or d < best_d or (d == best_d and uid < best):
			best = uid
			best_d = d
	return best

# A city's defender target: the base floor, raised by the leader's `military`
# focus (§C4), and +1 more while a hostile stack is near (§B5). A peaceful leader
# keeps the baseline floor — focus only ever adds, never gates below it.
static func _defender_target(gs, s, player_id: int) -> int:
	var target: int = gs.db.get_constant("ai_min_defenders", 1)
	var p = gs.get_player(player_id)
	var divisor: int = gs.db.get_constant("ai_focus_defenders_divisor", 3)
	if p != null and divisor > 0:
		target += int(_focus_profile(p, gs.db)["military"]) / divisor
	if _threats_near(gs, s, player_id):
		target += 1
	return target

# How many of the player's military units currently stand on this city's tile.
static func _city_defender_count(gs, s, player_id: int) -> int:
	var n: int = 0
	for u in gs.units:
		if u.owner_player_id == player_id and u.x == s.x and u.y == s.y \
				and _is_military_unit(gs.db.get_unit(u.unit_type_id)):
			n += 1
	return n

# Any hostile (enemy or wild) unit within the threat radius of the settlement.
static func _threats_near(gs, s, player_id: int) -> bool:
	var radius: int = gs.db.get_constant("ai_threat_radius", 3)
	for u in gs.units:
		if not _is_hostile_owner(gs, player_id, u.owner_player_id):
			continue
		if gs.map.distance(s.x, s.y, u.x, u.y) <= radius:
			return true
	return false

# ── §B6 Threat response & opportunistic offense ────────────────────────────────

# A free military unit attacks an adjacent target it clearly out-powers; otherwise
# it advances on the nearest threat (consolidating toward the front) or, with none
# in range, fortifies. Deliberately conservative — no long-range invasions in v1.
static func _manage_free_military(facade, gs, u, player_id: int) -> void:
	var target = _adjacent_attack_target(gs, u, player_id)
	if target != null:
		facade.apply_command(Commands.mission_move_to(player_id, u.id, int(target["x"]), int(target["y"])))
		return
	var threat = _nearest_threat(gs, u, player_id)
	if threat != null:
		facade.apply_command(Commands.mission_move_to(player_id, u.id, int(threat["x"]), int(threat["y"])))
	else:
		facade.apply_command(Commands.unit_fortify(player_id, u.id))

# An adjacent tile holding a hostile target this unit should attack: a defender it
# out-powers by the data margin, or an undefended hostile city. Scans neighbours in
# the map's deterministic order and returns the first qualifying tile.
static func _adjacent_attack_target(gs, u, player_id: int):
	var db = gs.db
	var p = gs.get_player(player_id)
	var margin: int = _attack_margin(p, db) if p != null else db.get_constant("ai_attack_margin", 20)
	var atk_power: int = _attack_power(u, db)
	for t in gs.map.neighbours8(u.x, u.y):
		var s = gs.get_settlement_at(t.x, t.y)
		var hostile_city: bool = s != null and _is_hostile_owner(gs, player_id, s.owner_player_id)
		var defender = Stack.get_defender(gs.units, t.x, t.y, player_id, gs)
		if defender != null:
			# A non-owned unit is only a target if it is actually hostile (at war or
			# wild) — never attack a neutral. Then only when clearly stronger.
			if not _is_hostile_owner(gs, player_id, defender.owner_player_id):
				continue
			if atk_power * 100 >= _defence_power(gs, defender) * (100 + margin):
				return {"x": t.x, "y": t.y}
		elif hostile_city:
			# Undefended hostile city: safe to assault.
			return {"x": t.x, "y": t.y}
	return null

# The power edge an attack needs, lowered by the leader's `military` focus (§C4):
# an aggressive leader strikes on a slimmer margin, a peaceful one needs a clearer
# advantage. Floored at zero so it never demands a negative edge.
static func _attack_margin(player, db) -> int:
	var margin: int = db.get_constant("ai_attack_margin", 20) \
		- int(_focus_profile(player, db)["military"]) * db.get_constant("ai_focus_margin_per_military", 5)
	return margin if margin > 0 else 0

# The nearest *non-adjacent* hostile unit within twice the threat radius, or null.
# Lets a free unit advance toward the front instead of milling at home. Adjacent
# enemies are deliberately excluded — the attack decision (_adjacent_attack_target)
# already ruled on them, so a unit that declined a too-strong neighbour holds rather
# than blundering into it.
static func _nearest_threat(gs, u, player_id: int):
	var reach: int = gs.db.get_constant("ai_threat_radius", 3) * 2
	var best = null
	var best_d: int = 0
	var best_key: int = 0
	for other in gs.units:
		if not _is_hostile_owner(gs, player_id, other.owner_player_id):
			continue
		var d: int = gs.map.distance(u.x, u.y, other.x, other.y)
		if d <= 1 or d > reach:
			continue
		var key: int = other.y * gs.map.width + other.x
		if best == null or d < best_d or (d == best_d and key < best_key):
			best = {"x": other.x, "y": other.y}
			best_d = d
			best_key = key
	return best

# Attacker / defender power proxies: effective strength scaled by current health,
# in the same units, so the margin comparison is apples-to-apples. Neutral terrain
# for the attacker; the defender's own tile (terrain + settlement bonus) for it.
static func _attack_power(u, db) -> int:
	return u.effective_strength(db, true, {}, {}, "", false, 0) * u.health

static func _defence_power(gs, d) -> int:
	var db = gs.db
	var tile = gs.map.get_tile(d.x, d.y)
	var ter: Dictionary = db.get_terrain(tile.terrain_id) if tile != null else {}
	var feat: Dictionary = db.get_feature(tile.feature_id) if tile != null and tile.feature_id != "" else {}
	var at_settlement: bool = gs.get_settlement_at(d.x, d.y) != null
	return d.effective_strength(db, false, ter, feat, "", at_settlement, 0) * d.health

# ── §B-units worker handling ───────────────────────────────────────────────────

# A worker automates construction in priority order: finish whatever it is
# already building, then improve a visible resource (on its tile, else walk to the
# nearest owned resource that needs it), then road a bare tile in our territory
# (here, else walk to the nearest one), and finally sleep when nothing remains.
# Critically it never re-issues a build that is already underway (which would
# reset its progress), so builds actually complete.
static func _manage_worker(facade, gs, u, player_id: int) -> void:
	# Already building or chopping: hold the tile (issue no command) so the order
	# advances to completion in the turn pipeline instead of being restarted.
	if u.building_improvement != "" or u.clearing_feature != "":
		return

	# 1. Resources first — improve the current tile's resource, else head for the
	#    nearest owned resource tile that still needs improving.
	var here = gs.map.get_tile(u.x, u.y)
	var here_res: String = _resource_improvement_for(gs, here, player_id)
	if here_res != "":
		_wake_if_sleeping(facade, u, player_id)
		if facade.apply_command(Commands.build_improvement(player_id, u.id, here_res)):
			return
	var res_tile = _nearest_work_tile(gs, u, player_id, true)
	if res_tile != null:
		_wake_if_sleeping(facade, u, player_id)
		if facade.apply_command(Commands.mission_move_to(player_id, u.id, res_tile.x, res_tile.y)):
			return

	# 2. Roads in our territory — road the current bare owned tile, else walk to the
	#    nearest owned tile that still lacks a road.
	if _needs_road(gs, here, player_id):
		_wake_if_sleeping(facade, u, player_id)
		if facade.apply_command(Commands.mission_build_road(player_id, u.id)):
			return
	var road_tile = _nearest_work_tile(gs, u, player_id, false)
	if road_tile != null:
		_wake_if_sleeping(facade, u, player_id)
		if facade.apply_command(Commands.mission_move_to(player_id, u.id, road_tile.x, road_tile.y)):
			return

	# 3. Nothing left to build — sleep until there is.
	if not u.is_sleeping:
		facade.apply_command(Commands.unit_sleep(player_id, u.id))

static func _wake_if_sleeping(facade, u, player_id: int) -> void:
	if u.is_sleeping:
		facade.apply_command(Commands.unit_wake(player_id, u.id))

# The resource improvement a worker should build on `tile` for this player, or ""
# when the tile carries no improvable, visible resource — i.e. it is unowned, has
# no resource, is already improved, the resource is not yet revealed (its tech is
# unresearched), or the improvement's tech/landform requirement is unmet.
static func _resource_improvement_for(gs, tile, player_id: int) -> String:
	if tile == null or tile.resource_id == "" or tile.owner_player_id != player_id:
		return ""
	var db = gs.db
	var res: Dictionary = db.get_resource(tile.resource_id)
	var imp_id: String = str(res.get("improvement_required", ""))
	if imp_id == "" or tile.improvement_id == imp_id:
		return ""
	var player = gs.get_player(player_id)
	if player == null:
		return ""
	var reveal = res.get("tech_required", null)   # resource visibility tech
	if reveal != null and str(reveal) != "" and not player.has_tech(str(reveal)):
		return ""
	var imp: Dictionary = db.get_improvement(imp_id)
	if imp.empty():
		return ""
	var itech = imp.get("tech_required", null)
	if itech != null and str(itech) != "" and not player.has_tech(str(itech)):
		return ""
	var landform: String = str(db.get_terrain(tile.terrain_id).get("landform", "flat"))
	var allowed: Array = imp.get("allowed_landforms", [])
	return imp_id if (allowed.empty() or landform in allowed) else ""

# True when `tile` is owned land that can take a road and has no improvement yet
# (a road occupies the single improvement slot, so only bare tiles qualify).
static func _needs_road(gs, tile, player_id: int) -> bool:
	if tile == null or tile.owner_player_id != player_id or tile.improvement_id != "":
		return false
	var road: Dictionary = gs.db.get_improvement("road")
	var landform: String = str(gs.db.get_terrain(tile.terrain_id).get("landform", "flat"))
	var allowed: Array = road.get("allowed_landforms", [])
	return allowed.empty() or landform in allowed

# Nearest owned tile (excluding the worker's own) that needs work: a resource to
# improve when `resources` is true, otherwise a road site. Deterministic — least
# distance, ties broken by (y, x) — so the AI stays reproducible from gs.rng alone.
static func _nearest_work_tile(gs, u, player_id: int, resources: bool):
	var best = null
	var best_d: int = 0
	for t in gs.map.all_tiles():
		if t.x == u.x and t.y == u.y:
			continue
		var wanted: bool = (_resource_improvement_for(gs, t, player_id) != "") if resources \
			else _needs_road(gs, t, player_id)
		if not wanted:
			continue
		var d: int = gs.map.distance(u.x, u.y, t.x, t.y)
		if best == null or d < best_d \
				or (d == best_d and (t.y < best.y or (t.y == best.y and t.x < best.x))):
			best = t
			best_d = d
	return best

# A garrison unit holds its city. If it is not standing on one of the player's own
# settlements, it heads for the nearest one; with no city to hold, it simply digs in.
# Retained for the per-unit garrison path and exercised directly by tests.
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

# ── Unit classification (data-driven) ──────────────────────────────────────────

# A land combat unit able to garrison/attack: has strength, is land-domain, and is
# neither a civilian nor a wild animal.
static func _is_military_unit(udata: Dictionary) -> bool:
	var cls: String = str(udata.get("classification", ""))
	if cls == "civilian" or cls == "animal" or cls == "great_person":
		return false
	if str(udata.get("domain", "land")) != "land":
		return false
	return int(udata.get("base_strength", 0)) > 0

static func _is_worker_unit(udata: Dictionary) -> bool:
	return bool(udata.get("can_build", false)) and not bool(udata.get("can_found", false))

# True when `owner` is hostile to `player_id`: a different player at war, or any
# wild force (negative owner id, e.g. -2).
static func _is_hostile_owner(gs, player_id: int, owner: int) -> bool:
	if owner == player_id:
		return false
	if owner < 0:
		return true
	return gs.are_at_war(player_id, owner)

# In-place selection sort of a settlement array by id, ascending (deterministic).
static func _sort_by_id(arr: Array) -> void:
	var n: int = arr.size()
	for i in range(n):
		var best: int = i
		for j in range(i + 1, n):
			if arr[j].id < arr[best].id:
				best = j
		if best != i:
			var tmp = arr[i]
			arr[i] = arr[best]
			arr[best] = tmp

# ── §C2 Trait-driven strategic focus ───────────────────────────────────────────
#
# A leader's personality is a soft bias layered on the one competent brain: it
# only tilts emphasis above a baseline floor, never gates a behaviour. The focus
# profile sums each trait's `ai_focus` block (data, §C1) over four axes; the
# Phase-C decision sites (production order, sliders, city target, defender floor,
# attack appetite) read it as `base + k·axis`, so a peaceful leader still defends
# and expands a little. Pure integer sums, no RNG — recomputed per turn (trivial).

const FOCUS_AXES: Array = ["expand", "military", "economy", "science"]

# Sum `ai_focus` across the player's traits into {expand, military, economy,
# science}. A traitless player (or unknown trait) yields all-zero, which makes
# every Phase-C `base + k·axis` collapse to its Phase-B baseline.
static func _focus_profile(player, db) -> Dictionary:
	var profile: Dictionary = {"expand": 0, "military": 0, "economy": 0, "science": 0}
	for tid in player.traits:
		var focus: Dictionary = db.get_trait(str(tid)).get("ai_focus", {})
		for axis in FOCUS_AXES:
			profile[axis] += int(focus.get(axis, 0))
	return profile

# ── Shared helpers ─────────────────────────────────────────────────────────────

# A tech requirement is satisfied when it is absent/empty or the player knows it.
static func _tech_ok(req, player) -> bool:
	return req == null or req == "" or player.has_tech(str(req))

# True when a city can train missionaries (§8): the player must have a religion to
# spread, and the city must hold a `trains_missionaries` structure (Monastery) or
# the player must run the Organized Religion civic (missionary_without_monastery).
static func _can_train_missionary(gs, s, player) -> bool:
	var db = gs.db
	var has_religion: bool = player.state_religion != "" or s.belief_id != ""
	if not has_religion:
		for bid in gs.founded_beliefs:
			if int(gs.founded_beliefs[bid]) == player.id:
				has_religion = true
				break
	if not has_religion:
		return false
	if PolicyEffects.has_flag(player, db, "missionary_without_monastery"):
		return true
	for sid in s.structures:
		if db.get_structure(sid).get("effects", {}).get("trains_missionaries", false):
			return true
	return false
