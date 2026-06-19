# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name WildAI

# §9 wild-forces behaviour (provisional). WildForces *spawns* raiders; WildAI makes
# them *act*, once per whole-world step. Owner -2 has no round-robin slot, so this
# runs inside the pipeline (TurnEngine.world_step) rather than as a facade client.
# Like every sim module it is pure: it mutates GameState directly and draws every
# stochastic choice from the shared gs.rng (so a wild turn is deterministic and is
# captured by save/load). Combat is applied through the shared CombatApply module;
# the few things the UI must surface (a fight, a razed city) are pushed onto
# gs.pending_wild_events and drained by SimFacade into signals/notifications,
# exactly as the §4.9 culture-flip phase uses gs.pending_flips.
#
# The loop each world step:
#   1. Refresh wild units' movement (they never see a player_step).
#   2. Act — each wild unit marches toward its raid goal (a mustered wave) or, as a
#      free scout, chases the nearest player it can see; a scout that sees nobody
#      wanders one tile. Stepping into a player unit attacks it; into an undefended
#      player city assaults (and razes) it.
#   3. Detect — a scout that sights a player rouses the nearest idle raider camp,
#      which then musters a wave aimed at the sighted tile.
#   4. Muster — each roused camp spawns one unit per step toward its target for the
#      wave's length, then enters a cooldown before it can be roused again.

static func run(game_state, rng: RNG) -> void:
	# 1. Wild units get no per-player step, so refresh their movement here.
	for u in game_state.units:
		if u.is_wild:
			u.movement_left = u.movement_total
			u.has_moved = false
			u.has_attacked = false

	_act_units(game_state, rng)
	_detect_and_alert(game_state, rng)
	_muster(game_state, rng)

# ── Acting ────────────────────────────────────────────────────────────────────

static func _act_units(game_state, rng: RNG) -> void:
	var db: DataDB = game_state.db
	var sight: int = _scout_sight(game_state, db)

	# Snapshot ids first: combat can remove units (the actor, its target, or stacked
	# bystanders) from game_state.units mid-loop.
	var ids: Array = []
	for u in game_state.units:
		if u.is_wild:
			ids.append(u.id)

	for uid in ids:
		var u: Unit = game_state.get_unit(uid)
		if u == null or not u.is_wild or u.health <= 0:
			continue

		if u.is_animal:
			# Animals hunt weak prey, shun cities and (usually) borders (§9.3).
			_act_animal(game_state, rng, u)
			continue

		if _is_naval(game_state, u):
			# Naval raiders patrol at random, attacking what they bump into (§9.4).
			_act_naval(game_state, rng, u)
			continue

		if u.goto_x >= 0:
			# A mustered raider marching to its wave's target tile.
			_move_along(game_state, rng, u, u.goto_x, u.goto_y)
		else:
			# A free scout: chase the nearest player it can see, else wander.
			var target: Array = _nearest_player_target(game_state, u.x, u.y, sight)
			if not target.empty():
				_move_along(game_state, rng, u, target[0], target[1])
			else:
				_wander(game_state, rng, u)

# Move `u` one turn's worth toward (tx, ty), attacking into the target tile if it
# holds a player unit or an enemy city. Mirrors SimFacade's stack-move loop for a
# single wild unit.
static func _move_along(game_state, rng: RNG, u: Unit, tx: int, ty: int) -> void:
	var db: DataDB = game_state.db
	if u.x == tx and u.y == ty:
		u.goto_x = -1; u.goto_y = -1
		return

	var path: Array = Pathfinding.find_path(
		game_state.map, u.x, u.y, tx, ty, u, db, game_state.units, -2, game_state)
	if path.empty():
		return  # unreachable this turn (blocked); try again next step

	var domain: String = db.get_unit(u.unit_type_id).get("domain", "land")
	for step in path:
		if u.movement_left <= 0:
			break
		var sx: int = int(step[0]); var sy: int = int(step[1])

		# A player unit on the next tile is attacked (combat ends the unit's turn).
		var enemy: Unit = Stack.get_defender(game_state.units, sx, sy, -2, game_state)
		if enemy != null:
			var result: Dictionary = Combat.resolve(u, enemy, game_state, game_state.rng)
			# Capture unit identity before CombatApply may remove dead units.
			var atk_type: String = u.unit_type_id
			var def_owner: int = enemy.owner_player_id
			var def_type: String = enemy.unit_type_id
			var def_x: int = enemy.x; var def_y: int = enemy.y
			# Do NOT advance onto a tile that still holds a city: a city tile's garrison
			# must be beaten first, then the city is assaulted separately (mirrors the
			# SimFacade player-move path where advance = enemy_city == null). Without
			# this guard a winning wild unit slides onto the city tile and gets stuck
			# there, unable to assault the city from the inside (Issue 11).
			var city_on_tile: Settlement = _enemy_settlement_at(game_state, sx, sy)
			CombatApply.apply_unit_result(game_state, u, enemy, result,
				city_on_tile == null)
			game_state.pending_wild_events.append({
				"kind": "combat", "result": result,
				"attacker_type_id": atk_type,
				"defender_owner_id": def_owner, "defender_type_id": def_type,
				"defender_x": def_x, "defender_y": def_y
			})
			u.has_attacked = true
			u.movement_left = 0
			u.goto_x = -1; u.goto_y = -1
			return

		# An undefended enemy city is assaulted; wild captors always raze (§4.5).
		var city: Settlement = _enemy_settlement_at(game_state, sx, sy)
		if city != null:
			_assault_city(game_state, u, city)
			u.has_attacked = true
			u.movement_left = 0
			# If the city fell, advance onto its now-empty tile.
			if game_state.get_settlement_at(sx, sy) == null:
				u.x = sx; u.y = sy
				u.stationary_turns = 0
				u.entrenchment = 0
			u.goto_x = -1; u.goto_y = -1
			return

		var cost: int = Pathfinding._move_cost(game_state.map.get_tile(sx, sy), db, domain)
		u.movement_left = u.movement_left - cost if u.movement_left - cost > 0 else 0
		u.x = sx; u.y = sy
		u.has_moved = true
		u.stationary_turns = 0
		u.entrenchment = 0

	# Drop the goal on arrival; keep marching otherwise.
	if u.x == tx and u.y == ty:
		u.goto_x = -1; u.goto_y = -1

# One assault by `lead` on an undefended enemy `city`: lowers its siege HP by the
# attacker's effective strength; at 0 the city is razed (wild forces never hold).
# Exception: wild units can never raze a player's capital (Issue 15). If the
# capital's HP would drop to zero the assault bottoms out at 1 — the city is
# heavily damaged but the civilization survives. The fog-of-war lift reported in
# the bug is a downstream symptom of the ownership/destruction change; preventing
# the destruction here resolves it.
static func _assault_city(game_state, lead: Unit, city: Settlement) -> void:
	var db: DataDB = game_state.db
	# Load TurnEngine rather than name it: TurnEngine references WildAI (it calls
	# run() in the world step), so a class_name reference back would be a cyclic
	# parse dependency (see CLAUDE.md's load()-not-new() note).
	var maxh: int = load("res://src/sim/turn_engine.gd").city_max_health(city, db)
	if city.health < 0 or city.health > maxh:
		city.health = maxh
	var tile: Tile = game_state.map.get_tile(city.x, city.y)
	var ter: Dictionary = db.get_terrain(tile.terrain_id)
	var feat: Dictionary = db.get_feature(tile.feature_id) if tile.feature_id != "" else {}
	var dmg: int = lead.effective_strength(db, true, ter, feat, "", true)
	if dmg < 1:
		dmg = 1
	city.health -= dmg
	if city.health > 0:
		return
	# Wild units cannot raze a player's capital (§4.5 exception): the palace marks
	# the seat of government and must remain with the original owner. Clamp HP to 1
	# so the assault is recorded but the city does not fall.
	if city.has_structure("palace"):
		city.health = 1
		return
	game_state.settlements.erase(city)
	game_state.pending_wild_events.append({
		"kind": "razed", "settlement_id": city.id, "name": city.name})

# A random passable neighbouring land tile with no unit and no settlement on it.
static func _wander(game_state, rng: RNG, u: Unit) -> void:
	if u.movement_left <= 0:
		return
	var db: DataDB = game_state.db
	var open: Array = []
	for nb in game_state.map.neighbours8(u.x, u.y):
		var ter: Dictionary = db.get_terrain(nb.terrain_id)
		if ter.get("domain", "land") != "land" or ter.get("impassable", false):
			continue
		if not Stack.at(game_state.units, nb.x, nb.y).empty():
			continue
		if game_state.get_settlement_at(nb.x, nb.y) != null:
			continue
		open.append(nb)
	if open.empty():
		return
	var pick = open[rng.randi_range(0, open.size() - 1)]
	var cost: int = Pathfinding._move_cost(pick, db,
		db.get_unit(u.unit_type_id).get("domain", "land"))
	u.movement_left = u.movement_left - cost if u.movement_left - cost > 0 else 0
	u.x = pick.x; u.y = pick.y
	u.has_moved = true
	u.stationary_turns = 0

# ── Animal behaviour (§9.3, provisional) ───────────────────────────────────────

# An animal hunts the nearest weak prey it can reach; with none in range it wanders.
# Unlike raiders it never attacks cities and (on most difficulties) never enters
# player borders.
static func _act_animal(game_state, rng: RNG, u: Unit) -> void:
	var db: DataDB = game_state.db
	var radius: int = db.get_constant("animal_detect_radius", 2)
	var allow_borders: bool = bool(
		db.get_difficulty(game_state.difficulty_id).get("animals_enter_borders", false))
	var prey: Array = _nearest_prey(game_state, u, radius, allow_borders)
	if not prey.empty():
		_animal_move(game_state, rng, u, prey[0], prey[1], allow_borders)
	else:
		_animal_wander(game_state, rng, u, allow_borders)

# Nearest huntable player unit within `radius`: a **civilian or unfortified** unit
# that is **not standing in a city** (animals leave garrisons/cities alone). When the
# animal cannot cross borders, prey on owned tiles is unreachable and skipped.
# Returns [x, y] of the prey's tile, or [] if none.
static func _nearest_prey(game_state, u: Unit, radius: int, allow_borders: bool) -> Array:
	var best: Array = []
	var best_d: int = radius + 1
	for pu in game_state.units:
		if pu.owner_player_id < 0:
			continue  # -1 unowned / -2 wild
		if game_state.get_settlement_at(pu.x, pu.y) != null:
			continue  # protected inside a city
		var weak: bool = pu.base_strength <= 0 or not pu.is_fortified
		if not weak:
			continue
		var tile: Tile = game_state.map.get_tile(pu.x, pu.y)
		if not allow_borders and tile != null and tile.owner_player_id >= 0:
			continue  # cannot enter borders to reach it
		var d: int = game_state.map.distance(u.x, u.y, pu.x, pu.y)
		if d <= radius and d < best_d:
			best_d = d
			best = [pu.x, pu.y]
	return best

# Move an animal one turn toward (tx, ty): attacks a player unit it steps into, but
# never enters a city tile and never crosses into borders unless `allow_borders`.
static func _animal_move(game_state, rng: RNG, u: Unit, tx: int, ty: int,
		allow_borders: bool) -> void:
	var db: DataDB = game_state.db
	var path: Array = Pathfinding.find_path(
		game_state.map, u.x, u.y, tx, ty, u, db, game_state.units, -2, game_state)
	if path.empty():
		return
	for step in path:
		if u.movement_left <= 0:
			break
		var sx: int = int(step[0]); var sy: int = int(step[1])
		if game_state.get_settlement_at(sx, sy) != null:
			break  # animals leave cities alone
		var stile: Tile = game_state.map.get_tile(sx, sy)
		if not allow_borders and stile != null and stile.owner_player_id >= 0:
			break  # stop at the border

		var enemy: Unit = Stack.get_defender(game_state.units, sx, sy, -2, game_state)
		if enemy != null:
			var result: Dictionary = Combat.resolve(u, enemy, game_state, game_state.rng)
			# Capture unit identity before CombatApply may remove dead units.
			var atk_type2: String = u.unit_type_id
			var def_owner2: int = enemy.owner_player_id
			var def_type2: String = enemy.unit_type_id
			var def_x2: int = enemy.x; var def_y2: int = enemy.y
			CombatApply.apply_unit_result(game_state, u, enemy, result, true)
			game_state.pending_wild_events.append({
				"kind": "combat", "result": result,
				"attacker_type_id": atk_type2,
				"defender_owner_id": def_owner2, "defender_type_id": def_type2,
				"defender_x": def_x2, "defender_y": def_y2
			})
			u.has_attacked = true
			u.movement_left = 0
			return

		var cost: int = Pathfinding._move_cost(stile, db, "land")
		u.movement_left = u.movement_left - cost if u.movement_left - cost > 0 else 0
		u.x = sx; u.y = sy
		u.has_moved = true
		u.stationary_turns = 0
		u.entrenchment = 0

# Like _wander, but an animal also refuses to step into borders (unless allowed).
static func _animal_wander(game_state, rng: RNG, u: Unit, allow_borders: bool) -> void:
	if u.movement_left <= 0:
		return
	var db: DataDB = game_state.db
	var open: Array = []
	for nb in game_state.map.neighbours8(u.x, u.y):
		var ter: Dictionary = db.get_terrain(nb.terrain_id)
		if ter.get("domain", "land") != "land" or ter.get("impassable", false):
			continue
		if not allow_borders and nb.owner_player_id >= 0:
			continue
		if not Stack.at(game_state.units, nb.x, nb.y).empty():
			continue
		if game_state.get_settlement_at(nb.x, nb.y) != null:
			continue
		open.append(nb)
	if open.empty():
		return
	var pick = open[rng.randi_range(0, open.size() - 1)]
	var cost: int = Pathfinding._move_cost(pick, db, "land")
	u.movement_left = u.movement_left - cost if u.movement_left - cost > 0 else 0
	u.x = pick.x; u.y = pick.y
	u.has_moved = true
	u.stationary_turns = 0

# ── Naval raider behaviour (§9.4, provisional) ─────────────────────────────────
#
# INCOMPLETE PLACEHOLDER. This is a deliberately minimal first cut, not finished
# behaviour: a naval raider only random-walks and hits whatever it happens to bump
# into. It does NOT yet seek targets, threaten coasts, bombard or raid cities,
# disembark, retreat when hurt, or coordinate — all of which §9.4 calls for. Treat
# it as a stub to be replaced, on par with the land WildAI's own provisional state.
# Kept intentionally simple so the spawn/AI plumbing can be exercised end to end.

static func _is_naval(game_state, u: Unit) -> bool:
	return game_state.db.get_unit(u.unit_type_id).get("domain", "land") == "sea"

# PLACEHOLDER (see section header): a naval raider patrols at random over the water.
# Each step it picks a random adjacent passable-sea tile; if that tile holds a player
# unit it attacks (the unit it "lands on"), otherwise it sails there. Friendly-occupied
# tiles are not chosen, so it never stalls against its own kind. No goal-seeking,
# coastal raiding, or retreat yet — to be built out.
static func _act_naval(game_state, rng: RNG, u: Unit) -> void:
	var db: DataDB = game_state.db
	while u.movement_left > 0:
		# Candidate moves: empty sea tiles, or sea tiles holding an attackable enemy.
		var opts: Array = []
		for nb in game_state.map.neighbours8(u.x, u.y):
			var ter: Dictionary = db.get_terrain(nb.terrain_id)
			if ter.get("domain", "land") != "sea" or ter.get("impassable", false):
				continue
			var stack: Array = Stack.at(game_state.units, nb.x, nb.y)
			if stack.empty():
				opts.append([nb, null])
			else:
				var enemy: Unit = Stack.get_defender(
					game_state.units, nb.x, nb.y, -2, game_state)
				if enemy != null:
					opts.append([nb, enemy])
		if opts.empty():
			return  # land-locked this step
		var pick: Array = opts[rng.randi_range(0, opts.size() - 1)]
		var dest = pick[0]
		var foe: Unit = pick[1]
		if foe != null:
			var result: Dictionary = Combat.resolve(u, foe, game_state, game_state.rng)
			# Capture unit identity before CombatApply may remove dead units.
			var atk_type3: String = u.unit_type_id
			var def_owner3: int = foe.owner_player_id
			var def_type3: String = foe.unit_type_id
			var def_x3: int = foe.x; var def_y3: int = foe.y
			CombatApply.apply_unit_result(game_state, u, foe, result, true)
			game_state.pending_wild_events.append({
				"kind": "combat", "result": result,
				"attacker_type_id": atk_type3,
				"defender_owner_id": def_owner3, "defender_type_id": def_type3,
				"defender_x": def_x3, "defender_y": def_y3
			})
			u.has_attacked = true
			u.movement_left = 0
			return
		var cost: int = Pathfinding._move_cost(dest, db, "sea")
		if cost < 1:
			cost = 1  # guard against a zero-cost loop
		u.movement_left = u.movement_left - cost if u.movement_left - cost > 0 else 0
		u.x = dest.x; u.y = dest.y
		u.has_moved = true
		u.stationary_turns = 0

# ── Detection and alerting ────────────────────────────────────────────────────

static func _detect_and_alert(game_state, rng: RNG) -> void:
	var db: DataDB = game_state.db
	var camps: Array = []
	for s in game_state.settlements:
		if s.owner_player_id == -2:
			camps.append(s)
	if camps.empty():
		return  # waves muster from camps; no camp, no wave (design gap 4)

	var sight: int = _scout_sight(game_state, db)
	for u in game_state.units:
		if not u.is_wild or u.is_animal or _is_naval(game_state, u):
			continue  # animals/naval raiders are lone; they do not rouse land camps
		var target: Array = _nearest_player_target(game_state, u.x, u.y, sight)
		if target.empty():
			continue
		var camp: Settlement = _nearest_idle_camp(game_state, camps, u.x, u.y)
		if camp == null:
			continue  # every camp already mustering or cooling down
		var wave: int = db.get_constant("wild_wave_length", 4)
		if game_state.wild_aggressive:
			wave += db.get_constant("wild_aggression_wave_bonus", 3)
		camp.alert_turns = wave
		camp.alert_target_x = target[0]
		camp.alert_target_y = target[1]

# ── Mustering waves ───────────────────────────────────────────────────────────

static func _muster(game_state, rng: RNG) -> void:
	var db: DataDB = game_state.db
	var wave_type: String = _strongest_wild_unit_type(game_state)

	# Soft population ceiling: the normal wild cap plus wave headroom, so an alert
	# can mass a strike force without permanently flooding the map.
	var land_tiles: int = 0
	for tile in game_state.map.all_tiles():
		var ter: Dictionary = db.get_terrain(tile.terrain_id)
		if ter.get("domain", "land") == "land" and not ter.get("impassable", false):
			land_tiles += 1
	var per_unit: int = db.get_constant("wild_land_per_unit", 80)
	if per_unit < 1:
		per_unit = 1
	var cap: int = land_tiles / per_unit + db.get_constant("wild_wave_unit_bonus", 6)
	var wild_count: int = 0
	for u in game_state.units:
		if u.is_wild:
			wild_count += 1

	var cooldown: int = db.get_constant("wild_alert_cooldown", 8)
	if game_state.wild_aggressive:
		cooldown -= db.get_constant("wild_aggression_cooldown_cut", 4)
		if cooldown < 1:
			cooldown = 1

	for camp in game_state.settlements:
		if camp.owner_player_id != -2:
			continue
		if camp.alert_cooldown > 0:
			camp.alert_cooldown -= 1
		if camp.alert_turns <= 0:
			continue
		if wild_count < cap:
			_spawn_wave_unit(game_state, camp, wave_type)
			wild_count += 1
		camp.alert_turns -= 1
		if camp.alert_turns <= 0:
			camp.alert_cooldown = cooldown
			camp.alert_target_x = -1
			camp.alert_target_y = -1

static func _spawn_wave_unit(game_state, camp: Settlement, unit_type_id: String) -> void:
	var db: DataDB = game_state.db
	var ud: Dictionary = db.get_unit(unit_type_id)
	var u := Unit.new()
	u.id = game_state.next_unit_id()
	u.unit_type_id = unit_type_id
	u.owner_player_id = -2
	u.x = camp.x; u.y = camp.y
	u.base_strength = int(ud.get("base_strength", 5))
	u.movement_total = int(ud.get("movement", 120))
	u.movement_left = 0  # spawned this step; marches from next world step
	u.is_wild = true
	u.goto_x = camp.alert_target_x
	u.goto_y = camp.alert_target_y
	game_state.units.append(u)

# ── Helpers ───────────────────────────────────────────────────────────────────

# The strongest land military unit the most-advanced player has unlocked, used for
# every wave so raiders scale with the game (gap 3: global, not per-target). Tech
# prerequisites are honoured; resource requirements are deliberately ignored
# (gap 2) so raiders are never gated on copper/iron/horse they do not own.
static func _strongest_wild_unit_type(game_state) -> String:
	var db: DataDB = game_state.db
	var leader: Player = null
	for p in game_state.players:
		if leader == null or p.technologies.size() > leader.technologies.size():
			leader = p

	var best_id: String = "warrior"
	var best_str: int = -1
	for uid in db.units:
		var ud: Dictionary = db.units[uid]
		if ud.get("domain", "land") != "land":
			continue
		if ud.get("classification", "") == "animal":
			continue  # wildlife is never raider stock (§9.3)
		if str(ud.get("unique_to", "")) != "":
			continue  # society-specific uniques are not generic raider stock
		var bs: int = int(ud.get("base_strength", 0))
		if bs <= 0:
			continue  # civilians / non-combatants
		var tech_req = ud.get("tech_required", null)
		if leader != null and tech_req != null and str(tech_req) != "" \
				and not leader.has_tech(str(tech_req)):
			continue
		if leader == null and tech_req != null and str(tech_req) != "":
			continue  # no players (headless): only tech-free units
		if bs > best_str:
			best_str = bs
			best_id = str(uid)
	return best_id

# Nearest player-owned unit or settlement within `radius` of (x, y). Returns
# [tx, ty] of the closest, or [] if none in range.
static func _nearest_player_target(game_state, x: int, y: int, radius: int) -> Array:
	var best: Array = []
	var best_d: int = radius + 1
	for u in game_state.units:
		if u.owner_player_id < 0:
			continue  # -2 wild, -1 unowned
		var d: int = game_state.map.distance(x, y, u.x, u.y)
		if d <= radius and d < best_d:
			best_d = d
			best = [u.x, u.y]
	for s in game_state.settlements:
		if s.owner_player_id < 0:
			continue
		var d: int = game_state.map.distance(x, y, s.x, s.y)
		if d <= radius and d < best_d:
			best_d = d
			best = [s.x, s.y]
	return best

# Nearest camp that is neither mustering (alert_turns > 0) nor cooling down.
static func _nearest_idle_camp(game_state, camps: Array, x: int, y: int) -> Settlement:
	var best: Settlement = null
	var best_d: int = 999999
	for c in camps:
		if c.alert_turns > 0 or c.alert_cooldown > 0:
			continue
		var d: int = game_state.map.distance(x, y, c.x, c.y)
		if d < best_d:
			best_d = d
			best = c
	return best

# An enemy settlement on (x, y) from a wild unit's view: any settlement not owned
# by the wild faction. null if the tile holds none.
static func _enemy_settlement_at(game_state, x: int, y: int) -> Settlement:
	var s: Settlement = game_state.get_settlement_at(x, y)
	if s == null or s.owner_player_id == -2:
		return null
	return s

static func _scout_sight(game_state, db: DataDB) -> int:
	var r: int = db.get_constant("wild_detect_radius", 4)
	if game_state.wild_aggressive:
		r += db.get_constant("wild_aggression_detect_bonus", 2)
	return r
