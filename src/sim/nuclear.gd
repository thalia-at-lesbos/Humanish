# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Nuclear

# Nuclear weapons & radioactive fallout (§5.7, provisional). Pure static mutation
# of GameState — no signals, no scene/Node references — so SimFacade (the launch
# command) and TurnEngine (the meltdown world-tick) share one source of truth.
#
# A nuclear strike is a one-use **area effect**, distinct from the round-by-round
# duel of §5.4: it detonates over a target tile and damages everything in a blast
# radius (friend and foe alike), softens any settlement there, strips the ground,
# then contaminates tiles with the Fallout feature. Every stochastic step draws
# from the shared `gs.rng` in a fixed tile order so replays reproduce the craters.
#
# All quantities are integer math; chances are integer percentages. The magnitudes
# live in data/constants.json and are placeholders to be tuned (see §5.7).

# True when this unit is a nuclear weapon (carries the `nuke` tag).
static func is_nuke(db: DataDB, u: Unit) -> bool:
	return "nuke" in db.get_unit(u.unit_type_id).get("tags", [])

# Nukes are usable once any player has completed a wonder granting
# `enable_nukes_global` (the Manhattan Project) — it enables nukes for everyone.
static func nukes_enabled(gs) -> bool:
	for s in gs.settlements:
		for sid in s.structures:
			if gs.db.get_structure(sid).get("effects", {}).get("enable_nukes_global", false):
				return true
	return false

# Blast radius (Chebyshev) for this weapon: data `blast_radius`, defaulting to 1
# for a `global_range` weapon (ICBM) and 0 (point strike) otherwise.
static func blast_radius(db: DataDB, u: Unit) -> int:
	var ud: Dictionary = db.get_unit(u.unit_type_id)
	if ud.has("blast_radius"):
		return int(ud["blast_radius"])
	return 1 if "global_range" in ud.get("tags", []) else 0

# True when the strike at (tx, ty) would be shot down before detonating: an enemy
# anti-air unit (SAM / Missile Cruiser, the `anti_air` tag) within interception
# range rolls the interception chance. The rng is only drawn when an interceptor
# actually exists, so a strike with no defender nearby never perturbs the stream.
static func try_intercept(gs, attacker: Unit, tx: int, ty: int, rng: RNG) -> bool:
	var db: DataDB = gs.db
	var reach: int = db.get_constant("nuke_interception_range", 4)
	var has_interceptor: bool = false
	for u in gs.units:
		if u.owner_player_id == attacker.owner_player_id:
			continue
		if not ("anti_air" in db.get_unit(u.unit_type_id).get("tags", [])):
			continue
		if u.owner_player_id != -2 and not gs.are_at_war(attacker.owner_player_id, u.owner_player_id):
			continue
		if gs.map.distance(tx, ty, u.x, u.y) <= reach:
			has_interceptor = true
			break
	if not has_interceptor:
		return false
	return rng.rand_bool_percent(db.get_constant("nuke_interception_chance", 50))

# Detonate a strike centred on (tx, ty), mutating GameState, and return a result
# dict for the caller to surface:
#   {attacker_player_id, target_x, target_y, radius,
#    units_hit:[unit_id], settlements_hit:[settlement_id],
#    fallout_tiles:[[x,y]], victim_alliance_ids:[int]}
# Units are softened (floored at 1 health), settlements lose population / stored
# production / siege integrity (never destroyed outright), tiles are stripped, and
# fallout may settle on the blast and a one-tile ring around it.
static func detonate(gs, attacker: Unit, tx: int, ty: int, rng: RNG) -> Dictionary:
	var db: DataDB = gs.db
	var radius: int = blast_radius(db, attacker)
	var result: Dictionary = {
		"attacker_player_id": attacker.owner_player_id,
		"target_x": tx, "target_y": ty, "radius": radius,
		"units_hit": [], "settlements_hit": [],
		"fallout_tiles": [], "victim_alliance_ids": []
	}
	# §11 Global warming: every detonation feeds the running nuke tally.
	gs.nukes_exploded += 1

	var blast: Array = _area_tiles(gs, tx, ty, radius)
	var dmg_pct: int = db.get_constant("nuke_blast_unit_damage_pct", 60)
	var pop_pct: int = db.get_constant("nuke_population_loss_pct", 50)
	var prod_pct: int = db.get_constant("nuke_production_loss_pct", 50)
	var def_pct: int = db.get_constant("nuke_defence_loss_pct", 50)
	var victims: Dictionary = {}  # alliance_id -> true

	# 1. Soften every unit in the blast (all owners, including the attacker's own).
	for cell in blast:
		var shelter: int = _shelter_reduction(gs, cell[0], cell[1], db)
		var dmg: int = dmg_pct - (dmg_pct * shelter) / 100
		for u in gs.units:
			if u.x != cell[0] or u.y != cell[1]:
				continue
			u.health = 1 if u.health - dmg < 1 else u.health - dmg
			u.entrenchment = 0
			result["units_hit"].append(u.id)
			_note_victim(gs, u.owner_player_id, victims)

	# 2. Damage any settlement in the blast (never destroyed by a strike).
	for cell in blast:
		var s: Settlement = gs.get_settlement_at(cell[0], cell[1])
		if s == null:
			continue
		var shelter2: int = _nuke_damage_reduction(s, db)
		var eff_pop: int = pop_pct - (pop_pct * shelter2) / 100
		var loss: int = (s.population * eff_pop) / 100
		s.population = 1 if s.population - loss < 1 else s.population - loss
		if s.peak_population > s.population and s.population < 1:
			s.population = 1
		s.production_store -= (s.production_store * prod_pct) / 100
		if s.production_store < 0:
			s.production_store = 0
		if s.health > 0:
			s.health -= (s.health * def_pct) / 100
		s.garrison_turns = 0
		result["settlements_hit"].append(s.id)
		_note_victim(gs, s.owner_player_id, victims)

	# 3. Strip improvements & vegetation, then contaminate (blast + a one-tile ring).
	var blast_chance: int = db.get_constant("nuke_fallout_chance", 50)
	var ring_chance: int = db.get_constant("nuke_fallout_ring_chance", 25)
	for cell in blast:
		var t: Tile = gs.map.get_tile(cell[0], cell[1])
		if t == null:
			continue
		t.improvement_id = ""
		t.feature_id = ""
		if rng.rand_bool_percent(blast_chance) and _can_contaminate(db, t):
			t.feature_id = "fallout"
			result["fallout_tiles"].append([cell[0], cell[1]])
	for cell in _ring_tiles(gs, tx, ty, radius):
		var rt: Tile = gs.map.get_tile(cell[0], cell[1])
		if rt == null:
			continue
		if rng.rand_bool_percent(ring_chance) and _can_contaminate(db, rt):
			rt.feature_id = "fallout"
			result["fallout_tiles"].append([cell[0], cell[1]])

	# 4. Domestic & world revulsion: the attacker's alliance accrues heavy
	#    war-fatigue against every victim (§5.7 diplomatic consequences).
	var ap: Player = gs.get_player(attacker.owner_player_id)
	if ap != null:
		var aa: Alliance = gs.get_alliance(ap.alliance_id)
		if aa != null:
			var fatigue: int = db.get_constant("nuke_war_fatigue", 50)
			if victims.empty():
				aa.war_fatigue[ap.alliance_id] = int(aa.war_fatigue.get(ap.alliance_id, 0)) + fatigue
			for aid in victims:
				aa.war_fatigue[aid] = int(aa.war_fatigue.get(aid, 0)) + fatigue
				result["victim_alliance_ids"].append(aid)

	return result

# A small per-turn chance that each Nuclear Plant melts down, contaminating the
# tiles around its settlement with fallout (§5.7, provisional). Returns the list
# of newly contaminated tiles for the caller to surface. Draws one rng roll per
# plant in settlement order.
static func meltdown_tick(gs, rng: RNG) -> Array:
	var db: DataDB = gs.db
	var chance: int = db.get_constant("nuclear_meltdown_chance", 1)
	var contaminated: Array = []
	if chance <= 0:
		return contaminated
	for s in gs.settlements:
		if not _has_meltdown_plant(s, db):
			continue
		if not rng.rand_bool_percent(chance):
			continue
		# §11 Global warming: a meltdown counts as a nuclear explosion.
		gs.nukes_exploded += 1
		# Contaminate the plant's tile and the ring around it.
		for cell in _area_tiles(gs, s.x, s.y, 1):
			var t: Tile = gs.map.get_tile(cell[0], cell[1])
			if t == null or t.feature_id == "fallout":
				continue
			if _can_contaminate(db, t):
				t.feature_id = "fallout"
				contaminated.append([cell[0], cell[1]])
	return contaminated

# ── Helpers ───────────────────────────────────────────────────────────────────

# Chebyshev-radius tiles around (cx, cy), in a fixed scan order, on the map.
static func _area_tiles(gs, cx: int, cy: int, radius: int) -> Array:
	var out: Array = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var nx: int = cx + dx
			var ny: int = cy + dy
			if gs.map.is_valid(nx, ny):
				out.append([nx, ny])
	return out

# The one-tile ring just outside the blast (Chebyshev distance == radius + 1),
# in a fixed scan order.
static func _ring_tiles(gs, cx: int, cy: int, radius: int) -> Array:
	var out: Array = []
	var r: int = radius + 1
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if (dx if dx >= 0 else -dx) != r and (dy if dy >= 0 else -dy) != r:
				continue
			var nx: int = cx + dx
			var ny: int = cy + dy
			if gs.map.is_valid(nx, ny):
				out.append([nx, ny])
	return out

# Bomb-Shelter style reduction (%) for a unit standing on tile (x, y): only a
# settlement on that tile shelters it.
static func _shelter_reduction(gs, x: int, y: int, db: DataDB) -> int:
	var s: Settlement = gs.get_settlement_at(x, y)
	return _nuke_damage_reduction(s, db) if s != null else 0

# The strongest `nuke_damage_reduction` (%) among a settlement's structures.
static func _nuke_damage_reduction(s, db: DataDB) -> int:
	if s == null:
		return 0
	var best: int = 0
	for sid in s.structures:
		var red: int = int(db.get_structure(sid).get("effects", {}).get("nuke_damage_reduction", 0))
		if red > best:
			best = red
	return best

# Fallout only settles on landforms the feature allows (flat/hill per features.json).
static func _can_contaminate(db: DataDB, t: Tile) -> bool:
	var fallout: Dictionary = db.get_feature("fallout")
	var allowed: Array = fallout.get("allowed_landforms", [])
	if allowed.empty():
		return true
	var landform: String = str(db.get_terrain(t.terrain_id).get("landform", ""))
	return landform in allowed

static func _has_meltdown_plant(s, db: DataDB) -> bool:
	for sid in s.structures:
		if db.get_structure(sid).get("effects", {}).get("provides_power", false):
			# Nuclear plants provide power and consume uranium; treat power plants
			# that require fission as meltdown-prone.
			if str(db.get_structure(sid).get("tech_required", "")) == "fission":
				return true
	return false

static func _note_victim(gs, owner_player_id: int, victims: Dictionary) -> void:
	if owner_player_id < 0:
		return
	var p: Player = gs.get_player(owner_player_id)
	if p != null:
		victims[p.alliance_id] = true
