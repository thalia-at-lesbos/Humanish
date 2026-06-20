# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Events

# Random-event lifecycle per §9: trigger -> begin(choice) -> apply -> expire.
#
# Triggers (data/event_triggers.json) carry a conjunction of predicates that gate
# WHEN an event (data/events.json) may fire for a player; an armed trigger fires
# at its `probability`. One event fires per player per turn (the §9 player step),
# chosen by weight when several arm at once. An event either applies its begin
# `effects` immediately (no choices) or presents a CHOOSE_EVENT popup (humans) /
# auto-resolves a branch (AI). An event with a positive `duration` persists on
# GameState.active_events and applies its `expire_effects` when the timer runs out.
#
# Determinism: effect magnitudes are fixed integers, so applying a choice draws no
# RNG and is identical whenever the human resolves the popup. The only RNG draws
# are trigger selection (probability rolls for sub-100 triggers, then a weighted
# pick when more than one arms), all in fixed trigger-id order.

# Run the per-player event step (§9): tick down timed events to their expiry, then
# scan triggers and fire at most one new event. Fired/expired descriptors are
# appended to gs.pending_events (drained by the facade) and also returned.
static func process_player_events(player: Player, game_state, rng: RNG) -> Array:
	var produced: Array = tick_active_events(player, game_state)
	var fired: Dictionary = _scan_and_fire(player, game_state, rng)
	if not fired.empty():
		produced.append(fired)
	for d in produced:
		game_state.pending_events.append(d)
	return produced

# Decrement every timed event owned by this player; apply expire_effects and drop
# any that reach zero. Returns the "event_expired" descriptors produced.
static func tick_active_events(player: Player, game_state) -> Array:
	var db: DataDB = game_state.db
	var produced: Array = []
	var kept: Array = []
	for inst in game_state.active_events:
		if int(inst.get("player_id", -1)) != player.id:
			kept.append(inst)
			continue
		var left: int = int(inst.get("turns_left", 0)) - 1
		if left > 0:
			inst["turns_left"] = left
			kept.append(inst)
			continue
		# Expired: commit the expire phase.
		var ev: Dictionary = db.get_event(str(inst.get("event_id", "")))
		apply_effects(ev.get("expire_effects", []), player, game_state)
		produced.append({
			"kind": "event_expired",
			"player_id": player.id,
			"event_id": str(inst.get("event_id", "")),
			"name": str(ev.get("name", inst.get("event_id", "")))
		})
	game_state.active_events = kept
	return produced

# Evaluate triggers for the player and fire one event if any arms. Returns the
# fired descriptor (empty when nothing fires).
static func _scan_and_fire(player: Player, game_state, rng: RNG) -> Dictionary:
	var db: DataDB = game_state.db
	var trigger_ids: Array = []
	for tid in db.get_event_triggers():
		if tid != "_comment":
			trigger_ids.append(tid)
	trigger_ids.sort()  # fixed evaluation order keeps RNG deterministic

	var armed: Array = []
	var weights: Array = []
	for tid in trigger_ids:
		var trig: Dictionary = db.event_triggers[tid]
		if not trigger_holds(trig, player, game_state):
			continue
		var prob: int = int(trig.get("probability", 100))
		# A certain trigger arms without a roll, so a lone prob-100 event fires
		# without perturbing the shared RNG stream.
		if prob < 100 and rng.randi_range(1, 100) > prob:
			continue
		armed.append(trig)
		var w: int = int(trig.get("weight", 1))
		weights.append(w if w > 0 else 1)
	if armed.empty():
		return {}

	var chosen: Dictionary = armed[0]
	if armed.size() > 1:
		var idx: int = rng.rand_weighted(weights)
		if idx >= 0 and idx < armed.size():
			chosen = armed[idx]

	return _fire(chosen, player, game_state)

# Whether every predicate on a trigger holds for the player right now (§9). All
# fields are optional and ANDed; absent fields impose no constraint.
static func trigger_holds(trig: Dictionary, player: Player, game_state) -> bool:
	var db: DataDB = game_state.db
	if bool(trig.get("one_shot", false)) and str(trig.get("id", "")) in player.events_fired:
		return false
	# Turn window. min_turn is stretched by the game pace so timers scale with speed.
	var min_turn: int = int(trig.get("min_turn", 0))
	if min_turn > 0:
		var scale: int = int(db.get_pace(game_state.pace_id).get("growth_scale", 100))
		min_turn = (min_turn * scale) / 100
		if game_state.turn_number < min_turn:
			return false
	var max_turn: int = int(trig.get("max_turn", 0))
	if max_turn > 0 and game_state.turn_number > max_turn:
		return false
	var tech_req = trig.get("tech_required", "")
	if tech_req != null and tech_req != "" and not player.has_tech(str(tech_req)):
		return false
	var bld_req = trig.get("building_required", "")
	if bld_req != null and bld_req != "":
		if not _player_has_structure(player.id, str(bld_req), game_state):
			return false
	var terr_req = trig.get("terrain_required", "")
	if terr_req != null and terr_req != "":
		if not _player_has_terrain(player.id, str(terr_req), game_state):
			return false
	if bool(trig.get("at_war", false)) and not _player_at_war(player.id, game_state):
		return false
	if bool(trig.get("at_peace", false)) and _player_at_war(player.id, game_state):
		return false
	# A timed event already running for this player cannot re-fire — otherwise a
	# non-one_shot timed trigger (e.g. the plague) re-arms every turn while still
	# active, stacking overlapping instances that spam begin/expire log entries and
	# stack their health deltas. It becomes eligible again only once it has expired.
	var ev_id: String = str(trig.get("event_id", ""))
	if ev_id != "" and _timed_event_active(ev_id, player.id, game_state):
		return false
	return true

# Whether a timed event instance for `event_id` is already running for the player.
static func _timed_event_active(event_id: String, player_id: int, game_state) -> bool:
	for inst in game_state.active_events:
		if str(inst.get("event_id", "")) == event_id and int(inst.get("player_id", -1)) == player_id:
			return true
	return false

# Fire one armed trigger's event: mark a one-shot trigger spent, then either apply
# the begin phase immediately (no choices), auto-resolve for an AI, or queue a
# pending choice for a human (the facade raises the popup at their turn start).
static func _fire(trig: Dictionary, player: Player, game_state) -> Dictionary:
	var db: DataDB = game_state.db
	if bool(trig.get("one_shot", false)):
		player.events_fired.append(str(trig.get("id", "")))
	var event_id: String = str(trig.get("event_id", ""))
	var ev: Dictionary = db.get_event(event_id)
	var choices: Array = ev.get("choices", [])
	if choices.empty():
		apply_event_begin(ev, player, game_state)
		return {
			"kind": "event_fired", "player_id": player.id, "event_id": event_id,
			"name": str(ev.get("name", event_id)), "text": str(ev.get("text", "")),
			"choice_id": ""
		}
	if player.is_ai:
		var cid: String = ai_choice_id(ev)
		apply_choice(event_id, cid, player, game_state)
		return {
			"kind": "event_fired", "player_id": player.id, "event_id": event_id,
			"name": str(ev.get("name", event_id)), "text": str(ev.get("text", "")),
			"choice_id": cid
		}
	# Human: park the choice on serialized state; the facade raises the popup.
	game_state.pending_event_choices.append({
		"event_id": event_id, "player_id": player.id,
		"trigger_id": str(trig.get("id", ""))
	})
	return {
		"kind": "event_choice_pending", "player_id": player.id, "event_id": event_id,
		"name": str(ev.get("name", event_id)), "text": str(ev.get("text", ""))
	}

# Apply an event's begin phase: commit its `effects` and, when timed, register the
# instance so its expire phase fires later (§9).
static func apply_event_begin(ev: Dictionary, player: Player, game_state) -> void:
	apply_effects(ev.get("effects", []), player, game_state)
	_register_timed(ev, player, game_state)

# Apply the chosen branch of a choice event (begin effects of that choice), then
# register a timed instance if the event persists. Returns true if the choice was
# valid. Deterministic (no RNG): magnitudes are fixed in data.
static func apply_choice(event_id: String, choice_id: String, player: Player, game_state) -> bool:
	var db: DataDB = game_state.db
	var ev: Dictionary = db.get_event(event_id)
	for ch in ev.get("choices", []):
		if str(ch.get("id", "")) == choice_id:
			apply_effects(ch.get("effects", []), player, game_state)
			_register_timed(ev, player, game_state)
			return true
	return false

# The AI's deterministic branch pick for a choice event: the choice carrying an
# explicit `ai_prefer` flag, else the first choice.
static func ai_choice_id(ev: Dictionary) -> String:
	var choices: Array = ev.get("choices", [])
	if choices.empty():
		return ""
	for ch in choices:
		if bool(ch.get("ai_prefer", false)):
			return str(ch.get("id", ""))
	return str(choices[0].get("id", ""))

static func _register_timed(ev: Dictionary, player: Player, game_state) -> void:
	var duration: int = int(ev.get("duration", 0))
	if duration <= 0:
		return
	game_state.active_events.append({
		"event_id": str(ev.get("id", "")),
		"player_id": player.id,
		"turns_left": duration
	})

# Apply a list of effect verbs to the player / their capital (§9).
static func apply_effects(effects: Array, player: Player, game_state) -> void:
	for eff in effects:
		_apply_effect(eff, player, game_state)

static func _apply_effect(eff: Dictionary, player: Player, game_state) -> void:
	var db: DataDB = game_state.db
	match str(eff.get("verb", "")):
		"gold":
			player.treasury += int(eff.get("amount", 0))
		"research":
			var rs: int = player.research_store + int(eff.get("amount", 0))
			player.research_store = rs if rs > 0 else 0
		"culture":
			var cap_c: Settlement = capital_of(player.id, game_state)
			if cap_c != null:
				cap_c.culture_total += int(eff.get("amount", 0))
		"tech":
			var tid: String = str(eff.get("tech_id", ""))
			if tid != "" and not player.has_tech(tid):
				player.technologies.append(tid)
				Eras.refresh(player, db)
			elif tid == "":
				_grant_cheapest_tech(player, game_state, db)
		"unit":
			var cap_u: Settlement = capital_of(player.id, game_state)
			if cap_u != null:
				var count: int = int(eff.get("count", 1))
				for _i in range(count):
					_spawn_unit_at(str(eff.get("unit_type", "warrior")),
						player.id, cap_u.x, cap_u.y, game_state, db)
		"building":
			var cap_b: Settlement = capital_of(player.id, game_state)
			var sid: String = str(eff.get("structure_id", ""))
			if cap_b != null and sid != "" and not cap_b.has_structure(sid):
				cap_b.structures.append(sid)
		"capital_health":
			var cap_h: Settlement = capital_of(player.id, game_state)
			if cap_h != null:
				var mx: int = db.get_constant("max_hp", 100)
				if cap_h.health < 0:
					cap_h.health = mx
				var nh: int = cap_h.health + int(eff.get("amount", 0))
				nh = mx if nh > mx else nh
				cap_h.health = nh if nh > 0 else 0
		"capital_pop":
			# Population delta on the capital (e.g. influenza losses). Floored at 1 so
			# an event never destroys a city outright. The next settlement step
			# normalises worked tiles / specialists to the new size.
			var cap_p: Settlement = capital_of(player.id, game_state)
			if cap_p != null:
				var np: int = cap_p.population + int(eff.get("amount", 0))
				cap_p.population = np if np > 1 else 1
		"nearby_pop":
			# Population delta on every OTHER owned city within `radius` tiles of the
			# capital (the outbreak's epicentre); each floored at 1. Radius is data-
			# driven, falling back to the event_nearby_radius constant.
			var cap_n: Settlement = capital_of(player.id, game_state)
			if cap_n != null:
				var radius: int = int(eff.get("radius",
					db.get_constant("event_nearby_radius", 4)))
				var delta: int = int(eff.get("amount", 0))
				for s in game_state.settlements:
					if s.owner_player_id != player.id or s == cap_n:
						continue
					if game_state.map.distance(cap_n.x, cap_n.y, s.x, s.y) <= radius:
						var sp: int = s.population + delta
						s.population = sp if sp > 1 else 1
		"heal_units":
			var mxh: int = db.get_constant("max_hp", 100)
			for u in game_state.units:
				if u.owner_player_id == player.id:
					u.health = mxh

# The player's capital (the Palace city), else their lowest-id settlement; null if
# they hold none. Event effects that need a city target route through here.
static func capital_of(player_id: int, game_state) -> Settlement:
	var fallback: Settlement = null
	for s in game_state.settlements:
		if s.owner_player_id != player_id:
			continue
		if s.has_structure("palace"):
			return s
		if fallback == null or s.id < fallback.id:
			fallback = s
	return fallback

static func _player_has_structure(player_id: int, struct_id: String, game_state) -> bool:
	for s in game_state.settlements:
		if s.owner_player_id == player_id and s.has_structure(struct_id):
			return true
	return false

static func _player_has_terrain(player_id: int, terrain_id: String, game_state) -> bool:
	for s in game_state.settlements:
		if s.owner_player_id != player_id:
			continue
		var t = game_state.map.get_tile(s.x, s.y)
		if t != null and t.terrain_id == terrain_id:
			return true
	return false

static func _player_at_war(player_id: int, game_state) -> bool:
	for other in game_state.players:
		if other.id != player_id and game_state.are_at_war(player_id, other.id):
			return true
	return false

# Grant the cheapest currently-researchable tech for free (deterministic: lowest
# base cost, ties by tech id). No-op when nothing is researchable.
static func _grant_cheapest_tech(player: Player, game_state, db: DataDB) -> void:
	var best: String = ""
	var best_cost: int = 1 << 30
	for tech_id in db.technologies:
		if not Research.can_research(tech_id, player, db):
			continue
		var cost: int = int(db.get_technology(tech_id).get("cost", 0))
		if cost < best_cost or (cost == best_cost and tech_id < best):
			best_cost = cost
			best = tech_id
	if best != "":
		player.technologies.append(best)
		Eras.refresh(player, db)

# Spawn a free unit for `player_id` on (x, y), stats from data/units.json.
static func _spawn_unit_at(unit_type: String, player_id: int, x: int, y: int, game_state, db: DataDB) -> int:
	var udata: Dictionary = db.get_unit(unit_type)
	if udata.empty():
		return -1
	var u = load("res://src/sim/unit.gd").new()
	u.id = game_state.next_unit_id()
	u.unit_type_id = unit_type
	u.owner_player_id = player_id
	u.x = x
	u.y = y
	u.base_strength = int(udata.get("base_strength", 0))
	u.movement_total = int(udata.get("movement", 120))
	u.movement_left = u.movement_total
	game_state.units.append(u)
	return u.id

# Reward when a unit enters a goody hut / discovery site (§9). The goody table
# (data/goodies.json) supplies the weighted list of rewards and their magnitudes;
# a difficulty may bias the weights via difficulties.json `goody_weights`
# (id -> weight). One reward is rolled from gs.rng and applied to pure game state
# here, so the result is deterministic and survives save/load. Returns a
# descriptor; the facade surfaces it (notification + signals) and, when a unit was
# spawned, emits unit_created for the returned `unit_id`.
static func exploration_reward(unit: Unit, game_state, rng: RNG) -> Dictionary:
	var db: DataDB = game_state.db
	var goodies: Array = db.get_goodies()
	if goodies.empty():
		return {"type": "none"}

	# Per-difficulty weight overrides (default to each goody's base weight).
	var diff: Dictionary = db.get_difficulty(game_state.difficulty_id)
	var overrides: Dictionary = diff.get("goody_weights", {})
	var weights: Array = []
	for g in goodies:
		var w: int = int(overrides.get(str(g.get("id", "")), g.get("weight", 0)))
		weights.append(w if w > 0 else 0)

	var idx: int = rng.rand_weighted(weights)
	if idx < 0 or idx >= goodies.size():
		idx = 0
	var goody: Dictionary = goodies[idx]
	return _apply_goody(goody, unit, game_state, rng)

# Apply one rolled goody's effect to game state and return its descriptor.
static func _apply_goody(goody: Dictionary, unit: Unit, game_state, rng: RNG) -> Dictionary:
	var db: DataDB = game_state.db
	var gtype: String = str(goody.get("type", ""))
	match gtype:
		"treasury":
			var amount: int = rng.randi_range(
				int(goody.get("min", 20)), int(goody.get("max", 80)))
			var player: Player = game_state.get_player(unit.owner_player_id)
			if player != null:
				player.treasury += amount
			return {"type": "treasury", "amount": amount}
		"experience":
			var xp: int = rng.randi_range(
				int(goody.get("min", 5)), int(goody.get("max", 15)))
			unit.experience += xp
			return {"type": "experience", "amount": xp}
		"heal":
			unit.health = db.get_constant("max_hp", 100)
			return {"type": "heal"}
		"map":
			# Presentation-only reveal around the discoverer; no sim state changes.
			return {"type": "map", "x": unit.x, "y": unit.y,
				"radius": int(goody.get("radius", 4))}
		"unit":
			var new_id: int = _spawn_reward_unit(
				str(goody.get("unit_type", "warrior")), unit, game_state, db)
			return {"type": "unit", "unit_id": new_id,
				"unit_type": str(goody.get("unit_type", "warrior"))}
		"tech":
			var tech_id: String = _grant_free_tech(unit, game_state, db)
			return {"type": "tech", "tech_id": tech_id}
		"ambush":
			# The discoverer is hurt (never killed by a goody — that would orphan the
			# in-flight move). A floor of 1 health keeps the unit alive.
			var dmg: int = int(goody.get("damage", 50))
			var floored: int = unit.health - dmg
			unit.health = floored if floored > 1 else 1
			return {"type": "ambush", "damage": dmg, "unit_id": unit.id}
		_:
			return {"type": gtype}

# Spawn a free unit of `unit_type` for the discoverer on its tile. Mirrors the
# facade's spawn so stats come from data/units.json. Returns the new unit id, or
# -1 if the type is unknown.
static func _spawn_reward_unit(unit_type: String, finder: Unit, game_state, db: DataDB) -> int:
	var udata: Dictionary = db.get_unit(unit_type)
	if udata.empty():
		return -1
	var u = load("res://src/sim/unit.gd").new()
	u.id = game_state.next_unit_id()
	u.unit_type_id = unit_type
	u.owner_player_id = finder.owner_player_id
	u.x = finder.x
	u.y = finder.y
	u.base_strength = int(udata.get("base_strength", 0))
	u.movement_total = int(udata.get("movement", 120))
	u.movement_left = u.movement_total
	game_state.units.append(u)
	return u.id

# Grant the cheapest tech the discoverer's owner can currently research (free), if
# any. Deterministic: lowest base cost, ties broken by tech id. Returns "" when
# nothing is researchable.
static func _grant_free_tech(unit: Unit, game_state, db: DataDB) -> String:
	var player: Player = game_state.get_player(unit.owner_player_id)
	if player == null:
		return ""
	var best: String = ""
	var best_cost: int = 1 << 30
	for tech_id in db.technologies:
		if not Research.can_research(tech_id, player, db):
			continue
		var cost: int = int(db.get_technology(tech_id).get("cost", 0))
		if cost < best_cost or (cost == best_cost and tech_id < best):
			best_cost = cost
			best = tech_id
	if best == "":
		return ""
	player.technologies.append(best)
	Eras.refresh(player, db)
	return best
