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
# live in data/constants.json, retuned to the §15.7 reference block (C5): unit
# damage 30+rand(50)+rand(50) with a non-combatant death threshold of 60,
# population death 30+rand(20)+rand(20) %, building destruction 40% per
# structure, fallout 50% per blast tile, SDI interception 75%.

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

# True when the strike at (tx, ty) would be shot down before detonating. Two
# interception sources feed ONE chance (§15.7):
#   • an enemy anti-air unit (SAM / Missile Cruiser, the `anti_air` tag) within
#     interception range contributes `nuke_interception_chance`;
#   • the SDI project (per-project `effects.nuke_interception`, reference 75)
#     contributes for any TARGET-side owner — a player, other than the attacker,
#     with a settlement or unit on the target tile.
# The best available chance is rolled ONCE per strike, at this single point in
# the strike sequence (after the launch consumes the weapon, before detonate).
# The rng is only drawn when a source actually exists, so a strike with no
# defence nearby never perturbs the stream.
static func try_intercept(gs, attacker: Unit, tx: int, ty: int, rng: RNG) -> bool:
	var db: DataDB = gs.db
	var reach: int = db.get_constant("nuke_interception_range", 4)
	var chance: int = 0
	for u in gs.units:
		if u.owner_player_id == attacker.owner_player_id:
			continue
		if not ("anti_air" in db.get_unit(u.unit_type_id).get("tags", [])):
			continue
		if u.owner_player_id != -2 and not gs.are_at_war(attacker.owner_player_id, u.owner_player_id):
			continue
		if gs.map.distance(tx, ty, u.x, u.y) <= reach:
			chance = db.get_constant("nuke_interception_chance", 50)
			break
	var sdi: int = _best_sdi_chance(gs, attacker, tx, ty)
	if sdi > chance:
		chance = sdi
	if chance <= 0:
		return false
	return rng.rand_bool_percent(chance)

# The strongest `nuke_interception` project effect (SDI, §15.7) among the
# target's owners: every player other than the attacker's with a settlement or a
# unit on the target tile. 0 when no such player owns the project.
static func _best_sdi_chance(gs, attacker: Unit, tx: int, ty: int) -> int:
	var best: int = 0
	var s = gs.get_settlement_at(tx, ty)
	if s != null and s.owner_player_id != attacker.owner_player_id:
		var v: int = Projects.effect_int(
			gs.get_player(s.owner_player_id), gs.db, "nuke_interception")
		if v > best:
			best = v
	for u in gs.units:
		if u.x != tx or u.y != ty:
			continue
		if u.owner_player_id == attacker.owner_player_id:
			continue
		var uv: int = Projects.effect_int(
			gs.get_player(u.owner_player_id), gs.db, "nuke_interception")
		if uv > best:
			best = uv
	return best

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
	var dmg_base: int = db.get_constant("nuke_unit_damage_base", 30)
	var dmg_r1: int = db.get_constant("nuke_unit_damage_rand1", 50)
	var dmg_r2: int = db.get_constant("nuke_unit_damage_rand2", 50)
	var nc_death: int = db.get_constant("nuke_noncombat_death_threshold", 60)
	var pop_base: int = db.get_constant("nuke_population_death_base", 30)
	var pop_r1: int = db.get_constant("nuke_population_death_rand1", 20)
	var pop_r2: int = db.get_constant("nuke_population_death_rand2", 20)
	var bld_pct: int = db.get_constant("nuke_building_destroy_pct", 40)
	var prod_pct: int = db.get_constant("nuke_production_loss_pct", 50)
	var def_pct: int = db.get_constant("nuke_defence_loss_pct", 50)
	var victims: Dictionary = {}  # alliance_id -> true

	# 1. Units in the blast (all owners, including the attacker's own). Damage is
	#    the reference roll base + rand(r1) + rand(r2) (each 0..n−1, two rng draws
	#    PER UNIT in blast-scan order, §15.7). A combat unit (base strength > 0)
	#    is softened but floored at 1 health; a non-combatant is killed outright
	#    when its roll reaches the death threshold, and untouched otherwise.
	for cell in blast:
		var shelter: int = _shelter_reduction(gs, cell[0], cell[1], db)
		var killed: Array = []
		for u in gs.units:
			if u.x != cell[0] or u.y != cell[1]:
				continue
			var dmg: int = dmg_base + _rand_part(rng, dmg_r1) + _rand_part(rng, dmg_r2)
			dmg -= (dmg * shelter) / 100
			result["units_hit"].append(u.id)
			_note_victim(gs, u.owner_player_id, victims)
			if int(gs.db.get_unit(u.unit_type_id).get("base_strength", 0)) > 0:
				u.health = 1 if u.health - dmg < 1 else u.health - dmg
				u.entrenchment = 0
			elif dmg >= nc_death:
				killed.append(u.id)
		for uid in killed:
			Stack.remove_unit(gs.units, uid)

	# 2. Damage any settlement in the blast (never destroyed by a strike): the
	#    population death roll base + rand(r1) + rand(r2) % (two rng draws per
	#    settlement), then a `nuke_building_destroy_pct` roll per standing
	#    structure in list order (§15.7 reference magnitudes).
	for cell in blast:
		var s: Settlement = gs.get_settlement_at(cell[0], cell[1])
		if s == null:
			continue
		var shelter2: int = _nuke_damage_reduction(s, db)
		var eff_pop: int = pop_base + _rand_part(rng, pop_r1) + _rand_part(rng, pop_r2)
		eff_pop -= (eff_pop * shelter2) / 100
		var loss: int = (s.population * eff_pop) / 100
		s.population = 1 if s.population - loss < 1 else s.population - loss
		if s.peak_population > s.population and s.population < 1:
			s.population = 1
		for sid in s.structures.duplicate():
			if rng.rand_bool_percent(bld_pct):
				s.structures.erase(sid)
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

	# 4. Domestic & world revulsion (§5.7 / §15.8 war weariness): each victim's
	#    alliance accrues hit-by-nuke points against the attacker, and the
	#    attacker's own alliance accrues the far heavier aggressor penalty
	#    against every victim. Both go through the shared CombatApply accruer
	#    (multiplier, forced-war modifier, Golden-Age freeze).
	var ap: Player = gs.get_player(attacker.owner_player_id)
	if ap != null:
		for aid in victims:
			result["victim_alliance_ids"].append(int(aid))
			var victim_pid: int = int(victims[aid])
			CombatApply.accrue_war_fatigue(gs, victim_pid, ap.id,
				"war_weariness_hit_by_nuke")
			CombatApply.accrue_war_fatigue(gs, ap.id, victim_pid,
				"war_weariness_attacked_with_nuke")

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

# One reference-style random part: uniform 0..n−1 (matching the reference's
# rand(n) in the §15.7 damage rows). Draws nothing for n <= 1, so a zeroed
# constant keeps the stream untouched.
static func _rand_part(rng: RNG, n: int) -> int:
	if n <= 1:
		return 0
	return rng.randi_range(0, n - 1)

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

# Record a hit player's alliance as a strike victim. Keyed by alliance id; the
# value keeps the first-noted member player id so the war-weariness accrual (a
# per-player check, §14.4 Golden-Age freeze) has a concrete victim player.
static func _note_victim(gs, owner_player_id: int, victims: Dictionary) -> void:
	if owner_player_id < 0:
		return
	var p: Player = gs.get_player(owner_player_id)
	if p != null and not victims.has(p.alliance_id):
		victims[p.alliance_id] = p.id
