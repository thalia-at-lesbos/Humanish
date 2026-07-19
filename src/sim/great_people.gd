# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name GreatPeople

# Great People subsystem (§14): type-aware birth from specialists, the Great
# General accumulated from combat, Golden Ages, and the actions a Great Person
# unit can perform.
#
# Pure rules: no Node/scene references. All persistent state lives on
# GameState / Player / Settlement; every magic number comes from
# data/constants.json (read via DataDB). The great-person *types* and their
# *actions* are defined entirely in data/units.json — this module only reads
# those records, so adding a new great-person type needs no engine change.

# ── Type ↔ unit mapping ───────────────────────────────────────────────────────

# The great-person unit id a specialist type of `gen_type` births, or "" if none.
# Reads the specialists table first (e.g. "scientist" -> "great_scientist"); for
# non-specialist sources like the Great General's "combat_xp" it falls back to a
# scan of unit `generated_by` tags.
static func gp_unit_for_type(db: DataDB, gen_type: String) -> String:
	if gen_type == "":
		return ""
	var from_table: String = Specialists.great_person_unit(db, gen_type)
	if from_table != "":
		return from_table
	var ids: Array = db.units.keys()
	ids.sort()
	for unit_id in ids:
		var u: Dictionary = db.units[unit_id]
		if u.get("classification", "") == "great_person" \
				and str(u.get("generated_by", "")) == gen_type:
			return unit_id
	return ""

# The specialist type contributing the most points in `s`, "" if none assigned.
# Ties break on the lexicographically smallest type id for determinism. Types
# that bank no GP points — the auto-filled citizen default specialist (§15.19)
# and the settled great_* forms — never claim dominance: only point-banking
# working specialists direct which Great Person a city births.
static func dominant_specialist(s: Settlement, db: DataDB) -> String:
	var keys: Array = s.specialists.keys()
	keys.sort()
	var best: String = ""
	var best_count: int = 0
	for k in keys:
		if int(db.get_specialist(str(k)).get("gp_points", 0)) <= 0:
			continue
		var c: int = int(s.specialists[k])
		if c > best_count:
			best_count = c
			best = k
	return best

# ── Birth ─────────────────────────────────────────────────────────────────────

# Spawn a unit of `unit_type_id` for `player_id` at (x, y); returns the Unit, or
# null if the type is unknown. Mirrors SimFacade._spawn_unit without UI signals
# so sim-internal births stay headless.
static func spawn_unit(gs: GameState, unit_type_id: String, player_id: int,
		x: int, y: int) -> Unit:
	var udata: Dictionary = gs.db.get_unit(unit_type_id)
	if udata.empty():
		return null
	var u := Unit.new()
	u.id = gs.next_unit_id()
	u.unit_type_id = unit_type_id
	u.owner_player_id = player_id
	u.x = x
	u.y = y
	u.base_strength = int(udata.get("base_strength", 0))
	u.movement_total = int(udata.get("movement", 120))
	u.movement_left = u.movement_total
	gs.units.append(u)
	return u

# Born when a settlement crosses its specialist threshold (§14.3): the dominant
# specialist type decides which Great Person appears at the city. Returns the new
# unit id, or -1 if the dominant type maps to no great-person unit.
static func birth_from_settlement(gs: GameState, s: Settlement) -> int:
	var gen_type: String = dominant_specialist(s, gs.db)
	if gen_type == "":
		return -1
	var unit_type: String = gp_unit_for_type(gs.db, gen_type)
	if unit_type == "":
		return -1
	var u: Unit = spawn_unit(gs, unit_type, s.owner_player_id, s.x, s.y)
	if u != null:
		gs.pending_great_people.append({"player_id": s.owner_player_id, "unit_type_id": unit_type})
	return u.id if u != null else -1

# ── Per-player Great Person threshold (§15.18 / R2) ──────────────────────────

# The player-wide threshold every city's GP pool is measured against: the base
# (gp_threshold_base 100) raised by the player's accumulated escalation percent,
# then scaled by the pace great_people_scale (67/100/150/300 — reference order:
# modifier first, then pace; integer truncation at each step).
static func special_person_threshold(gs: GameState, player: Player) -> int:
	var db: DataDB = gs.db
	var base: int = db.get_constant("gp_threshold_base", 100)
	var thr: int = base * (100 + player.special_person_threshold_mod) / 100
	var pace_scale: int = int(db.get_pace(gs.pace_id).get("great_people_scale", 100))
	return Fixed.scale(thr, pace_scale)

# Record a Great Person birth in `player`'s civilization (§15.18): the civ-wide
# birth counter rises, and the threshold modifier escalates per the reference —
# gp_threshold_increase_percent (50) once for the owner's own birth, plus the
# same amount once per living same-team player, the owner included (a player
# always sits on its own team, so a solo player takes +100% of base per birth:
# 100, 200, 300, … at normal pace). Each share is multiplied by (that player's
# births ÷ 10 + 1) using the post-birth count, so increments double from the
# 10th birth on (the 11th GP is the first to cost the doubled step). Humanish
# teams are alliances; the -1 "no alliance" sentinel never groups strangers.
static func record_special_person_birth(gs: GameState, player: Player) -> void:
	if player == null:
		return
	var inc: int = gs.db.get_constant("gp_threshold_increase_percent", 50)
	player.special_persons_born += 1
	player.special_person_threshold_mod += inc * (player.special_persons_born / 10 + 1)
	for q in gs.players:
		if q.is_eliminated:
			continue
		if q.id == player.id \
				or (player.alliance_id >= 0 and q.alliance_id == player.alliance_id):
			q.special_person_threshold_mod += inc * (q.special_persons_born / 10 + 1)

# ── Great General (§14.2) ─────────────────────────────────────────────────────

# Accumulate Great General points for `player` after a combat victory worth `xp`
# experience at (x, y); a Great General is born in the field when the rising
# threshold is crossed. The Imperialistic trait and the Great Wall wonder speed
# emergence. Subsequent Great Generals cost progressively more.
static func award_combat_points(gs: GameState, player: Player,
		x: int, y: int, xp: int) -> void:
	if player == null or xp <= 0:
		return
	var db: DataDB = gs.db
	var pts: int = Fixed.scale(xp, db.get_constant("great_general_points_per_xp_pct", 100))
	var rate_bonus: int = 0
	if "imperialistic" in player.traits:
		rate_bonus += db.get_constant("imperialistic_great_general_pct", 100)
	if _player_has_active_structure(gs, player, "great_wall"):
		rate_bonus += db.get_constant("great_wall_great_general_pct", 100)
	if rate_bonus != 0:
		pts = Fixed.scale_up(pts, rate_bonus)
	if pts <= 0:
		return
	player.great_general_points += pts
	if player.great_general_threshold <= 0:
		player.great_general_threshold = db.get_constant("great_general_first_cost", 30)
	var growth: int = db.get_constant("great_general_cost_growth_pct", 50)
	var unit_type: String = gp_unit_for_type(db, "combat_xp")
	# Loop in case a large award crosses several thresholds at once.
	while player.great_general_points >= player.great_general_threshold:
		player.great_general_points -= player.great_general_threshold
		player.great_generals_produced += 1
		player.great_general_threshold = Fixed.scale_up(player.great_general_threshold, growth)
		if unit_type != "":
			spawn_unit(gs, unit_type, player.id, x, y)
			gs.pending_great_people.append({"player_id": player.id, "unit_type_id": unit_type})

# ── Golden Ages (§14.4) ───────────────────────────────────────────────────────

static func is_in_golden_age(player: Player) -> bool:
	return player != null and player.golden_age_turns > 0

# Per-worked-tile output bonus while the owner is in a Golden Age (0 otherwise).
static func golden_age_tile_bonus(gs: GameState, player: Player) -> int:
	if not is_in_golden_age(player):
		return 0
	return gs.db.get_constant("golden_age_tile_bonus", 1)

# Decrement a player's active Golden Age by one turn (call once per player turn).
static func tick_golden_age(player: Player) -> void:
	if player.golden_age_turns > 0:
		player.golden_age_turns -= 1

# Base Golden Age duration in turns: data base, scaled by the pace's own golden-age
# percent (§15.3 — quick 80 / normal 100 / epic 125 / marathon 200), +Mausoleum bonus.
static func _golden_age_duration(gs: GameState, player: Player) -> int:
	var db: DataDB = gs.db
	var turns: int = db.get_constant("golden_age_base_turns", 8)
	var pace_scale: int = int(db.get_pace(gs.pace_id).get("golden_age_scale", 100))
	turns = Fixed.scale(turns, pace_scale)
	if _player_has_active_structure(gs, player, "mausoleum"):
		turns = Fixed.scale_up(turns, db.get_constant("mausoleum_golden_age_pct", 50))
	return 1 if turns < 1 else turns

# GP cost of the next Golden Age: 1 to extend an active one, otherwise the base
# cost plus one per Golden Age already started (§14.4).
static func _golden_age_cost(gs: GameState, player: Player) -> int:
	if is_in_golden_age(player):
		return 1
	var db: DataDB = gs.db
	return db.get_constant("golden_age_gp_base_cost", 2) \
		+ player.golden_age_count * db.get_constant("golden_age_gp_cost_increment", 1)

# Grant a free Golden Age outright (§9 events, e.g. Marathon): start or extend one
# of the standard duration without consuming any Great Person, and count it toward
# the player's Golden Age tally (so the next GP-bought age costs more).
static func start_free_golden_age(gs: GameState, player: Player) -> void:
	player.golden_age_turns += _golden_age_duration(gs, player)
	player.golden_age_count += 1

# Sacrifice one Great Person toward a Golden Age. Returns true once the Golden
# Age actually starts/extends (i.e. enough GP have now been contributed).
static func contribute_to_golden_age(gs: GameState, player: Player) -> bool:
	player.pending_golden_age_gp += 1
	var cost: int = _golden_age_cost(gs, player)
	if player.pending_golden_age_gp < cost:
		return false
	player.pending_golden_age_gp -= cost
	player.golden_age_turns += _golden_age_duration(gs, player)
	player.golden_age_count += 1
	return true

# ── Actions (§14.1) ───────────────────────────────────────────────────────────

# Execute a Great Person action. `unit` must be a great-person whose data
# "actions" list includes `action`. Most actions consume the unit on success.
# `params` carries optional targeting (settlement_id, target_alliance_id,
# tech_id, org_id). Returns true if the action was applied.
static func perform_action(gs: GameState, unit: Unit, action: String,
		params: Dictionary) -> bool:
	if unit == null:
		return false
	var udata: Dictionary = gs.db.get_unit(unit.unit_type_id)
	if udata.get("classification", "") != "great_person":
		return false
	if not (action in udata.get("actions", [])):
		return false
	var player: Player = gs.get_player(unit.owner_player_id)
	if player == null:
		return false

	# Build-a-structure actions share one path: "build_<structure_id>".
	if action.begins_with("build_"):
		return _act_build_structure(gs, unit, player, action.substr(6), params)

	match action:
		"join_city":
			return _act_join_city(gs, unit, player, udata, params)
		"start_golden_age":
			contribute_to_golden_age(gs, player)
			_consume(gs, unit)
			return true
		"great_work":
			return _act_great_work(gs, unit, player, params)
		"hurry_production":
			return _act_hurry_production(gs, unit, player, params)
		"trade_mission":
			player.treasury += gs.db.get_constant("gp_trade_mission_gold", 2000)
			_consume(gs, unit)
			return true
		"found_corporation":
			return _act_found_corporation(gs, unit, player, params)
		"found_religion":
			return _act_found_religion(gs, unit, player)
		"discover_technology":
			return _act_discover_technology(gs, unit, player, params)
		"infiltration":
			return _act_infiltration(gs, unit, player, params)
		"attach_to_unit":
			return _act_attach_to_unit(gs, unit, player)
	return false

static func _consume(gs: GameState, unit: Unit) -> void:
	Stack.remove_unit(gs.units, unit.id)

static func _player_has_structure(gs: GameState, player: Player,
		struct_id: String) -> bool:
	for s in gs.settlements:
		if s.owner_player_id == player.id and s.has_structure(struct_id):
			return true
	return false

# Effect-gate variant of _player_has_structure: an obsolete wonder (§15.17) no
# longer confers its bonus (the plain check above stays for identity uses such
# as the build-uniqueness gate — an obsolete wonder still exists).
static func _player_has_active_structure(gs: GameState, player: Player,
		struct_id: String) -> bool:
	if player != null and player.structure_obsolete(gs.db, struct_id):
		return false
	return _player_has_structure(gs, player, struct_id)

# Resolve the target settlement from params.settlement_id, defaulting to the one
# under the unit. Null unless it is owned by the acting player.
static func _target_settlement(gs: GameState, unit: Unit, player: Player,
		params: Dictionary) -> Settlement:
	var sid: int = int(params.get("settlement_id", -1))
	var s: Settlement = gs.get_settlement(sid) if sid >= 0 \
		else gs.get_settlement_at(unit.x, unit.y)
	if s == null or s.owner_player_id != player.id:
		return null
	return s

static func _act_join_city(gs: GameState, unit: Unit, player: Player,
		udata: Dictionary, params: Dictionary) -> bool:
	var s: Settlement = _target_settlement(gs, unit, player, params)
	if s == null:
		return false
	# Permanent super-specialist: the settled form is the matching `great_*`
	# record in data/specialists.json (§14.1) — reference settled yields, it
	# banks no further GP points (gp_points 0), and it is FREE (§15.19): it sits
	# on top of population, consuming no worker slot. A Great General
	# (generated_by "combat_xp") settles as `great_general`, the military
	# instructor (§15.20): zero yields, +2 XP per head to combat-capable units
	# completed in the city (read at TurnEngine.new_unit_xp).
	var stype: String = str(udata.get("generated_by", ""))
	var settled: String = "great_" + stype
	if stype == "" or stype == "combat_xp":
		settled = "great_general"
	var add: int = gs.db.get_constant("gp_super_specialist_count", 1)
	s.specialists[settled] = int(s.specialists.get(settled, 0)) + add
	_consume(gs, unit)
	return true

static func _act_great_work(gs: GameState, unit: Unit, player: Player,
		params: Dictionary) -> bool:
	var s: Settlement = _target_settlement(gs, unit, player, params)
	if s == null:
		return false
	s.culture_total += gs.db.get_constant("gp_great_work_culture", 4000)
	_consume(gs, unit)
	return true

static func _act_hurry_production(gs: GameState, unit: Unit, player: Player,
		params: Dictionary) -> bool:
	var s: Settlement = _target_settlement(gs, unit, player, params)
	if s == null:
		return false
	s.production_store += gs.db.get_constant("gp_hurry_production_hammers", 500)
	_consume(gs, unit)
	return true

static func _act_found_corporation(gs: GameState, unit: Unit, player: Player,
		params: Dictionary) -> bool:
	var s: Settlement = _target_settlement(gs, unit, player, params)
	if s == null or s.econ_org_id != "":
		return false
	var org_id: String = str(params.get("org_id", ""))
	if org_id != "":
		if gs.founded_econ_orgs.has(org_id) or not gs.db.econ_orgs.has(org_id):
			return false
	else:
		var keys: Array = gs.db.econ_orgs.keys()
		keys.sort()
		for oid in keys:
			if not gs.founded_econ_orgs.has(oid):
				org_id = oid
				break
		if org_id == "":
			return false
	if not EconOrgs.found(org_id, s, gs):
		return false
	_consume(gs, unit)
	return true

static func _act_found_religion(gs: GameState, unit: Unit, player: Player) -> bool:
	# A prophet may found any unfounded belief, ignoring the tech prerequisite
	# that normally gates belief founding (§14.1).
	var host: Settlement = null
	for s in gs.settlements:
		if s.owner_player_id == player.id and s.belief_id == "":
			host = s
			break
	if host == null:
		return false
	var keys: Array = gs.db.beliefs.keys()
	keys.sort()
	var chosen: String = ""
	for bid in keys:
		if not gs.founded_beliefs.has(bid):
			chosen = bid
			break
	if chosen == "":
		return false
	gs.founded_beliefs[chosen] = player.id
	host.belief_id = chosen
	_consume(gs, unit)
	return true

static func _act_discover_technology(gs: GameState, unit: Unit, player: Player,
		params: Dictionary) -> bool:
	var tech_id: String = str(params.get("tech_id", ""))
	if tech_id == "":
		tech_id = player.current_research_id
	if tech_id == "" or player.has_tech(tech_id):
		return false
	if not gs.db.technologies.has(tech_id):
		return false
	# A tech can only be discovered when it is actually available to research.
	if not _prereqs_met(player, gs.db, tech_id):
		return false
	player.technologies.append(tech_id)
	if player.current_research_id == tech_id:
		player.current_research_id = ""
		player.research_store = 0
	_consume(gs, unit)
	return true

static func _prereqs_met(player: Player, db: DataDB, tech_id: String) -> bool:
	var tech: Dictionary = db.get_technology(tech_id)
	for pre in tech.get("prereqs_all", []):
		if not player.has_tech(pre):
			return false
	var any: Array = tech.get("prereqs_any", [])
	if any.size() > 0:
		var ok: bool = false
		for pre in any:
			if player.has_tech(pre):
				ok = true
				break
		if not ok:
			return false
	return true

static func _act_infiltration(gs: GameState, unit: Unit, player: Player,
		params: Dictionary) -> bool:
	var target_aid: int = int(params.get("target_alliance_id", -1))
	if target_aid < 0 or target_aid == player.alliance_id:
		return false
	if gs.get_alliance(target_aid) == null:
		return false
	var amt: int = gs.db.get_constant("gp_infiltration_espionage", 3000)
	player.intel_points[target_aid] = int(player.intel_points.get(target_aid, 0)) + amt
	_consume(gs, unit)
	return true

static func _act_attach_to_unit(gs: GameState, unit: Unit, player: Player) -> bool:
	# Grant the Leader marker and the Leadership promotion to every friendly
	# military unit sharing the tile; the General merges into the stack (§14.1).
	# At least one recipient is required. `leader` is the reference-style
	# attached-General marker (`granted_only`, never XP-picked): it gates the
	# General-only promotions (Leadership, Tactics, Medic III) as a prereq.
	var granted: bool = false
	for u in gs.units:
		if u.owner_player_id != player.id or u.id == unit.id:
			continue
		if u.x != unit.x or u.y != unit.y:
			continue
		if gs.db.get_unit(u.unit_type_id).get("classification", "") == "civilian":
			continue
		if not u.has_promotion("leader"):
			u.promotions.append("leader")
		if not u.has_promotion("leadership"):
			u.promotions.append("leadership")
		granted = true
	if not granted:
		return false
	_consume(gs, unit)
	return true

static func _act_build_structure(gs: GameState, unit: Unit, player: Player,
		struct_id: String, params: Dictionary) -> bool:
	if not gs.db.structures.has(struct_id):
		return false
	var s: Settlement = _target_settlement(gs, unit, player, params)
	if s == null or s.has_structure(struct_id):
		return false
	# National wonders are unique per player: refuse if another of the player's
	# settlements already has it.
	var struct: Dictionary = gs.db.get_structure(struct_id)
	if struct.get("is_wonder", false) and str(struct.get("wonder_type", "")) == "national":
		if _player_has_structure(gs, player, struct_id):
			return false
	s.structures.append(struct_id)
	_consume(gs, unit)
	return true
