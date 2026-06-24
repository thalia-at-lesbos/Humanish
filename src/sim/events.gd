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

# Random-event lifecycle per §9 (reworked selection model).
#
# Every event definition (data/events.json) carries its own prereq/obsolete/active/
# weight inline — there is no separate trigger table. Selection per player per turn:
#   1. Grace: nothing fires before event_grace_turns (NOT pace-scaled).
#   2. One era roll: at event_era_chance[player_era] percent, *some* event fires
#      this turn; otherwise none does.
#   3. Eligibility: an event qualifies when it is in this game's roster
#      (GameState.active_event_ids, rolled once at setup from each event's `active`%),
#      every `prereq` predicate holds, it holds no `obsolete` tech, it is not already
#      running as a timed instance, and (if one_shot) has not already fired.
#   4. Weighted pick among the eligible events by `weight`.
# A fired event either auto-applies its begin `effects` or, with `choices`, presents
# a NON-SKIPPABLE popup (humans) / auto-resolves a branch (AI). A positive `duration`
# makes it persist on GameState.active_events, applying `expire_effects` at expiry.
#
# Determinism: random magnitudes (`range`) and probabilistic branches (`chance`) are
# rolled ONCE at fire time, in fixed order, and the concrete results are baked into
# the begin effects / the parked choice's `resolved_choices`. Applying a resolved
# choice therefore draws no RNG, so a human may answer the popup at any point in
# their turn without perturbing the shared stream. The only RNG draws are the per-
# turn era roll, the weighted pick, and the fire-time `range`/`chance` rolls — all in
# fixed event-id / effect order. Tile-targeted verbs resolve their `match` predicate
# at apply time by a deterministic first-match scan (no RNG).

# ── Per-game roster (active inclusion) ───────────────────────────────────────────

# Roll each event's `active` inclusion percent ONCE, in sorted event-id order, to
# decide whether it is in this game at all. Called once after setup; the roster is
# serialized so it is stable across save/load and on the determinism gate.
static func roll_active_events(game_state) -> void:
	var db: DataDB = game_state.db
	var ids: Array = _event_ids(db)
	var roster: Array = []
	for eid in ids:
		var active: int = int(db.get_event(eid).get("active", 100))
		if active >= 100 or game_state.rng.randi_range(1, 100) <= active:
			roster.append(eid)
	game_state.active_event_ids = roster

# ── Per-player event step ────────────────────────────────────────────────────────

# Run the per-player event step (§9): tick down timed events to their expiry, then
# roll and (maybe) fire one new event. Fired/expired descriptors are appended to
# gs.pending_events (drained by the facade) and also returned.
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
		# Expired: commit the expire phase (expire effects are fixed-value).
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

# The era roll + eligibility scan + weighted pick (§9). Returns the fired descriptor
# (empty when nothing fires).
static func _scan_and_fire(player: Player, game_state, rng: RNG) -> Dictionary:
	var db: DataDB = game_state.db
	# Grace period — no events in the opening turns. NOT scaled by game pace.
	if game_state.turn_number < int(db.get_constant("event_grace_turns", 20)):
		return {}
	# One roll: does ANY event fire this turn, at the player's era chance?
	var chance: int = _era_chance(player, db)
	if chance <= 0:
		return {}
	if rng.randi_range(1, 100) > chance:
		return {}
	# Build the weighted list of currently-eligible events (fixed id order).
	var eligible: Array = []
	var weights: Array = []
	for eid in _event_ids(db):
		if not event_eligible(eid, player, game_state):
			continue
		eligible.append(eid)
		var w: int = int(db.get_event(eid).get("weight", 1))
		weights.append(w if w > 0 else 1)
	if eligible.empty():
		return {}
	var idx: int = rng.rand_weighted(weights)
	if idx < 0 or idx >= eligible.size():
		idx = 0
	return fire_event(eligible[idx], player, game_state)

# The percent chance that *some* event fires this turn for the player, by their era.
static func _era_chance(player: Player, db: DataDB) -> int:
	var era: int = Eras.player_era(player, db)
	var table: Array = db.constants.get("event_era_chance", [])
	if table.empty():
		return 0
	if era < 0:
		era = 0
	if era >= table.size():
		era = table.size() - 1
	return int(table[era])

# Sorted list of real event ids (skips the schema `_comment`).
static func _event_ids(db: DataDB) -> Array:
	var ids: Array = []
	for eid in db.get_events():
		if eid != "_comment":
			ids.append(eid)
	ids.sort()
	return ids

# ── Eligibility & prereqs ────────────────────────────────────────────────────────

# Whether an event may fire for this player right now (§9): in the roster, every
# prereq holds, no obsolete tech held, not already running as a timed instance, and
# (if one_shot) not already fired.
static func event_eligible(event_id: String, player: Player, game_state) -> bool:
	var db: DataDB = game_state.db
	var ev: Dictionary = db.get_event(event_id)
	if ev.empty():
		return false
	# Per-game roster. An empty roster means setup has not rolled yet — treat every
	# event as in (so direct unit tests that skip roll_active_events still work).
	if not game_state.active_event_ids.empty() and not (event_id in game_state.active_event_ids):
		return false
	if bool(ev.get("one_shot", false)) and event_id in player.events_fired:
		return false
	for t in ev.get("obsolete", []):
		if player.has_tech(str(t)):
			return false
	if _timed_event_active(event_id, player.id, game_state):
		return false
	return prereq_holds(ev.get("prereq", {}), player, game_state)

# Whether every predicate in a prereq dict holds for the player (all ANDed). Absent
# keys impose no constraint. See the events.json schema comment for the vocabulary.
static func prereq_holds(pr: Dictionary, player: Player, game_state) -> bool:
	var db: DataDB = game_state.db
	if pr.empty():
		return true
	if pr.has("min_era") and Eras.player_era(player, db) < int(pr["min_era"]):
		return false
	if pr.has("max_era") and Eras.player_era(player, db) > int(pr["max_era"]):
		return false
	if bool(pr.get("at_war", false)) and not _player_at_war(player.id, game_state):
		return false
	if bool(pr.get("at_peace", false)) and _player_at_war(player.id, game_state):
		return false
	for t in pr.get("tech_all", []):
		if not player.has_tech(str(t)):
			return false
	if pr.has("tech_any"):
		var any_tech: bool = false
		for t in pr["tech_any"]:
			if player.has_tech(str(t)):
				any_tech = true
				break
		if not any_tech:
			return false
	if pr.has("building") and not _player_has_structure(player.id, str(pr["building"]), game_state):
		return false
	if pr.has("civic") and not _player_has_civic(player, str(pr["civic"])):
		return false
	if bool(pr.get("state_religion", false)) and player.state_religion == "":
		return false
	if pr.has("resource_absent") and _player_owns_resource(player.id, str(pr["resource_absent"]), game_state):
		return false
	if pr.has("min_pop") and not _player_has_city_pop(player.id, game_state, int(pr["min_pop"]), true):
		return false
	if pr.has("max_pop") and not _player_has_city_pop(player.id, game_state, int(pr["max_pop"]), false):
		return false
	if bool(pr.get("coastal", false)) and not _player_has_coastal_city(player.id, game_state):
		return false
	if pr.has("players_tech"):
		var spec: Dictionary = pr["players_tech"]
		if _players_with_tech(game_state, str(spec.get("tech", ""))) < int(spec.get("count", 1)):
			return false
	if pr.has("tile") and _find_owned_tile(player.id, game_state, pr["tile"]) == null:
		return false
	return true

# Whether a timed event instance for `event_id` is already running for the player.
static func _timed_event_active(event_id: String, player_id: int, game_state) -> bool:
	for inst in game_state.active_events:
		if str(inst.get("event_id", "")) == event_id and int(inst.get("player_id", -1)) == player_id:
			return true
	return false

# ── Firing ───────────────────────────────────────────────────────────────────────

# Fire one event for the player: mark a one-shot spent, then either apply the begin
# phase immediately (no choices), auto-resolve for an AI, or park a NON-SKIPPABLE
# choice for a human with its branches pre-rolled. Random magnitudes are rolled here
# (fixed order) so the later apply is RNG-free.
static func fire_event(event_id: String, player: Player, game_state) -> Dictionary:
	var db: DataDB = game_state.db
	var ev: Dictionary = db.get_event(event_id)
	if bool(ev.get("one_shot", false)) and not (event_id in player.events_fired):
		player.events_fired.append(event_id)
	var choices: Array = ev.get("choices", [])
	if choices.empty():
		apply_effects(_resolve_effects(ev.get("effects", []), player, game_state), player, game_state)
		_register_timed(ev, player, game_state)
		return {
			"kind": "event_fired", "player_id": player.id, "event_id": event_id,
			"name": str(ev.get("name", event_id)), "text": str(ev.get("text", "")),
			"choice_id": ""
		}
	# Pre-roll EVERY branch so the human's eventual pick draws no RNG.
	var resolved_choices: Array = []
	for ch in choices:
		resolved_choices.append({
			"id": str(ch.get("id", "")),
			"text": str(ch.get("text", "")),
			"effects": _resolve_effects(ch.get("effects", []), player, game_state)
		})
	if player.is_ai:
		var cid: String = ai_choice_id(ev)
		_apply_resolved_branch(resolved_choices, cid, player, game_state)
		_register_timed(ev, player, game_state)
		return {
			"kind": "event_fired", "player_id": player.id, "event_id": event_id,
			"name": str(ev.get("name", event_id)), "text": str(ev.get("text", "")),
			"choice_id": cid
		}
	# Human: park the pre-rolled choices; the facade raises the popup at turn start
	# and blocks End Turn until it is answered.
	game_state.pending_event_choices.append({
		"event_id": event_id, "player_id": player.id, "trigger_id": "",
		"resolved_choices": resolved_choices
	})
	return {
		"kind": "event_choice_pending", "player_id": player.id, "event_id": event_id,
		"name": str(ev.get("name", event_id)), "text": str(ev.get("text", ""))
	}

# Apply an event's begin phase directly (used by tests / synthetic timed events):
# roll its `effects` and commit, then register a timed instance if it persists.
static func apply_event_begin(ev: Dictionary, player: Player, game_state) -> void:
	apply_effects(_resolve_effects(ev.get("effects", []), player, game_state), player, game_state)
	_register_timed(ev, player, game_state)

# Resolve a human's parked choice: apply the matching pre-rolled branch and register
# a timed instance if the event persists. Returns true if the branch was found.
# Deterministic (no RNG) — the branch effects were already rolled at fire time.
static func apply_choice(event_id: String, choice_id: String, player: Player, game_state) -> bool:
	for pc in game_state.pending_event_choices:
		if int(pc.get("player_id", -1)) != player.id or str(pc.get("event_id", "")) != event_id:
			continue
		if _apply_resolved_branch(pc.get("resolved_choices", []), choice_id, player, game_state):
			_register_timed(game_state.db.get_event(event_id), player, game_state)
			return true
		return false
	return false

# Apply the named branch from a pre-rolled resolved_choices list. Returns false if
# the id is not present.
static func _apply_resolved_branch(resolved_choices: Array, choice_id: String, player: Player, game_state) -> bool:
	for ch in resolved_choices:
		if str(ch.get("id", "")) == choice_id:
			apply_effects(ch.get("effects", []), player, game_state)
			return true
	return false

# The AI's deterministic branch pick: the choice carrying an explicit `ai_prefer`
# flag, else the first choice.
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

# ── Effect rolling (fire time) ───────────────────────────────────────────────────

# Expand a list of effect templates into concrete effects, drawing gs.rng for any
# `range` magnitudes and `chance` branches (in fixed order). The result contains no
# `range`/`chance`, so applying it is RNG-free.
static func _resolve_effects(templates: Array, player: Player, game_state) -> Array:
	var out: Array = []
	for t in templates:
		if str(t.get("verb", "")) == "chance":
			var pct: int = int(t.get("percent", 0))
			if game_state.rng.randi_range(1, 100) <= pct:
				for e in _resolve_effects(t.get("then", []), player, game_state):
					out.append(e)
			continue
		var c: Dictionary = t.duplicate(true)
		if c.has("range"):
			var r: Array = c["range"]
			c["amount"] = game_state.rng.randi_range(int(r[0]), int(r[1]))
			c.erase("range")
		out.append(c)
	return out

# ── Effect application (RNG-free) ────────────────────────────────────────────────

# Apply a list of (already-resolved) effect verbs to the player / their cities (§9).
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
		"research_pct_remaining":
			_research_pct(player, db, int(eff.get("percent", 0)), true)
		"research_pct_loss":
			_research_pct(player, db, int(eff.get("percent", 0)), false)
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
			# Population delta on the capital, floored at 1 so an event never razes a
			# city. The next settlement step normalises worked tiles / specialists.
			var cap_p: Settlement = capital_of(player.id, game_state)
			if cap_p != null:
				var np: int = cap_p.population + int(eff.get("amount", 0))
				cap_p.population = np if np > 1 else 1
		"nearby_pop":
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
		"food_store":
			var cap_f: Settlement = capital_of(player.id, game_state)
			if cap_f != null:
				if eff.has("pct"):
					cap_f.food_store -= Fixed.scale(cap_f.food_store, int(eff["pct"]))
				else:
					cap_f.food_store += int(eff.get("amount", 0))
				if cap_f.food_store < 0:
					cap_f.food_store = 0
		"golden_age":
			GreatPeople.start_free_golden_age(game_state, player)
		"attitude":
			_apply_attitude(eff, player, game_state)
		"grant_promotion":
			_grant_promotion(eff, player, game_state, db)
		"city_happy_timed":
			_apply_city_happy_timed(eff, player, game_state)
		"place_resource":
			_apply_place_resource(eff, player, game_state)
		"tile_yield":
			var ty_tile: Tile = _find_owned_tile(player.id, game_state, eff.get("match", {}))
			if ty_tile != null:
				ty_tile.event_food += int(eff.get("food", 0))
				ty_tile.event_production += int(eff.get("production", 0))
				ty_tile.event_commerce += int(eff.get("commerce", 0))
		"remove_feature":
			var rf_tile: Tile = _find_owned_tile(player.id, game_state, eff.get("match", {}))
			if rf_tile != null:
				rf_tile.feature_id = ""
		"remove_improvement":
			var ri_tile: Tile = _find_owned_tile(player.id, game_state, eff.get("match", {}))
			if ri_tile != null:
				ri_tile.improvement_id = ""
				ri_tile.improvement_age = 0
		"remove_route":
			var rr_tile: Tile = _find_owned_tile(player.id, game_state, eff.get("match", {}))
			if rr_tile != null:
				if rr_tile.transport_id == "road" or rr_tile.transport_id == "railroad":
					rr_tile.transport_id = ""
				elif rr_tile.improvement_id == "road" or rr_tile.improvement_id == "railroad":
					rr_tile.improvement_id = ""
		"spawn_wild":
			_apply_spawn_wild(eff, player, game_state)
		"structure_yield":
			_apply_structure_yield(eff, player, game_state)
		"specialist":
			_apply_specialist(eff, player, game_state)
		"settle_great_person":
			_apply_settle_great_person(eff, player, game_state)
		"spread_religion":
			_apply_spread_religion(eff, player, game_state)
		"destroy_building":
			_apply_destroy_building(eff, player, game_state)
		"pillage":
			_apply_pillage(eff, player, game_state)
		"revolt":
			_apply_revolt(eff, player, game_state)
		"make_peace":
			_apply_make_peace(eff, player, game_state)
		"declare_war":
			_apply_declare_war(eff, player, game_state)
		"espionage":
			_apply_espionage(eff, player, game_state)

# DESTROY_BLDG (§9): remove up to `count` standing structures from the scoped city
# (default the capital), filtered by hammer cost — `cost` is "cheap" (<=
# event_building_cheap_max), "expensive" (above it), or "any" (default). Wonders and
# the palace are never destroyed (the palace would orphan the capital). Deterministic:
# the cheapest-then-id matching structures are removed first.
static func _apply_destroy_building(eff: Dictionary, player: Player, game_state) -> void:
	var db: DataDB = game_state.db
	var count: int = int(eff.get("count", 1))
	if count <= 0:
		return
	var cost_filter: String = str(eff.get("cost", "any"))
	var cheap_max: int = db.get_constant("event_building_cheap_max", 100)
	for s in _scoped_settlements(str(eff.get("scope", "capital")), player, game_state):
		# Candidate structures: real (non-wonder, non-palace) buildings matching the
		# cost band, ordered cheapest-then-id so removal is deterministic.
		var cands: Array = []
		for sid in s.structures:
			if sid == "palace":
				continue
			var sd: Dictionary = db.get_structure(sid)
			if sd.empty() or bool(sd.get("is_wonder", false)):
				continue
			var c: int = int(sd.get("cost", 0))
			if cost_filter == "cheap" and c > cheap_max:
				continue
			if cost_filter == "expensive" and c <= cheap_max:
				continue
			cands.append({"id": sid, "cost": c})
		cands.sort_custom(load("res://src/sim/events.gd"), "_cmp_building_cost")
		var removed: int = 0
		for cand in cands:
			if removed >= count:
				break
			s.structures.erase(str(cand["id"]))
			removed += 1

# Cheapest-then-id ascending comparator for deterministic building destruction.
static func _cmp_building_cost(a, b) -> bool:
	if int(a["cost"]) != int(b["cost"]):
		return int(a["cost"]) < int(b["cost"])
	return str(a["id"]) < str(b["id"])

# PILLAGE (§9): clear the improvement on up to `count` tiles. By default targets the
# acting player's own improved tiles; match.owner "rival" targets a rival's improved
# tiles within event_city_radius of one of the player's cities (the "looters raid the
# neighbour" case). Deterministic first-match map scan; combine with the `match` tile
# predicate keys (terrain/feature/improvement/resource).
static func _apply_pillage(eff: Dictionary, player: Player, game_state) -> void:
	var db: DataDB = game_state.db
	var count: int = int(eff.get("count", 1))
	if count <= 0:
		return
	var spec: Dictionary = eff.get("match", {})
	var want_rival: bool = str(spec.get("owner", "own")) == "rival"
	var pillaged: int = 0
	for t in game_state.map.all_tiles():
		if pillaged >= count:
			break
		if t.improvement_id == "":
			continue
		if want_rival:
			if t.owner_player_id == player.id or t.owner_player_id < 0:
				continue
			if not _tile_in_city_radius(player.id, t, game_state, db):
				continue
		else:
			if t.owner_player_id != player.id:
				continue
		if spec.has("terrain") and t.terrain_id != str(spec["terrain"]):
			continue
		if spec.has("feature") and t.feature_id != str(spec["feature"]):
			continue
		if spec.has("improvement") and t.improvement_id != str(spec["improvement"]):
			continue
		if spec.has("resource") and t.resource_id != str(spec["resource"]):
			continue
		t.improvement_id = ""
		t.improvement_age = 0
		pillaged += 1

# REVOLT (§9): throw the scoped city (default the capital) into `turns` turns of
# disorder — it produces nothing until the occupation counter ticks out (§4.8, the
# same machinery a freshly-conquered city uses). No-op for turns <= 0.
static func _apply_revolt(eff: Dictionary, player: Player, game_state) -> void:
	var turns: int = int(eff.get("turns", 0))
	if turns <= 0:
		return
	for s in _scoped_settlements(str(eff.get("scope", "capital")), player, game_state):
		s.revolt_turns = turns
		s.in_disorder = true

# PEACE (§9): end the war between the player's alliance and a rival's, optionally
# warming the rival's attitude. The rival is the lowest-id living rival; a positive
# `attitude` bumps the player's event-memory toward them.
static func _apply_make_peace(eff: Dictionary, player: Player, game_state) -> void:
	var rid: int = _pick_rival(player, game_state)
	if rid < 0:
		return
	var rival: Player = game_state.get_player(rid)
	if rival == null:
		return
	var mine: Alliance = game_state.get_alliance(player.alliance_id)
	var theirs: Alliance = game_state.get_alliance(rival.alliance_id)
	if mine == null or theirs == null or mine.id == theirs.id:
		return
	mine.at_war_with.erase(theirs.id)
	theirs.at_war_with.erase(mine.id)
	var att: int = int(eff.get("attitude", 0))
	if att != 0:
		_adjust_memory(player, rid, att, game_state)

# WAR (§9): declare war on a rival's alliance (offer-or-declare collapses to a
# declaration here — the §7 layer's offer flow is presentation-side). Records the war
# on both alliances and, with a signed `attitude`, the diplomatic memory.
static func _apply_declare_war(eff: Dictionary, player: Player, game_state) -> void:
	var rid: int = _pick_rival(player, game_state)
	if rid < 0:
		return
	var rival: Player = game_state.get_player(rid)
	if rival == null:
		return
	var mine: Alliance = game_state.get_alliance(player.alliance_id)
	var theirs: Alliance = game_state.get_alliance(rival.alliance_id)
	if mine == null or theirs == null or mine.id == theirs.id:
		return
	if not (theirs.id in mine.at_war_with):
		mine.at_war_with.append(theirs.id)
	if not (mine.id in theirs.at_war_with):
		theirs.at_war_with.append(mine.id)
	var att: int = int(eff.get("attitude", 0))
	if att != 0:
		_adjust_memory(player, rid, att, game_state)

# ESP (§9): grant or drain `amount` espionage points against a rival's alliance.
# `Player.intel_points` is the per-alliance EP ledger; the rival is the lowest-id
# living rival (the reference treats EP as a pool, so a single rival suffices).
# Floored at zero — an event never drives the ledger negative.
static func _apply_espionage(eff: Dictionary, player: Player, game_state) -> void:
	var amount: int = int(eff.get("amount", 0))
	if amount == 0:
		return
	var rid: int = _pick_rival(player, game_state)
	if rid < 0:
		return
	var rival: Player = game_state.get_player(rid)
	if rival == null or rival.alliance_id == player.alliance_id:
		return
	var aid: int = rival.alliance_id
	var v: int = int(player.intel_points.get(aid, 0)) + amount
	player.intel_points[aid] = v if v > 0 else 0

# Bank percent% of the current research's remaining cost (gain=true) or shave
# percent% of its full cost off the store (gain=false). No-op without a current tech.
static func _research_pct(player: Player, db: DataDB, percent: int, gain: bool) -> void:
	var tid: String = player.current_research_id
	if tid == "":
		return
	var cost: int = int(db.get_technology(tid).get("cost", 0))
	if cost <= 0:
		return
	if gain:
		var remaining: int = cost - player.research_store
		if remaining < 0:
			remaining = 0
		player.research_store += Fixed.scale(remaining, percent)
	else:
		player.research_store -= Fixed.scale(cost, percent)
		if player.research_store < 0:
			player.research_store = 0

# Adjust diplomatic memory toward a rival (or every rival, target="all_met") by a
# signed `amount`, capped by memory_cap. Stored under the "event" memory kind so the
# normal §7 decay erodes it over time.
static func _apply_attitude(eff: Dictionary, player: Player, game_state) -> void:
	var amount: int = int(eff.get("amount", 0))
	if amount == 0:
		return
	if str(eff.get("target", "rival")) == "all_met":
		for o in game_state.players:
			if o.id != player.id and not o.is_eliminated:
				_adjust_memory(player, o.id, amount, game_state)
	else:
		var r: int = _pick_rival(player, game_state)
		if r >= 0:
			_adjust_memory(player, r, amount, game_state)

static func _adjust_memory(from_p: Player, to_id: int, amount: int, game_state) -> void:
	var cap: int = int(game_state.db.get_diplomacy().get("memory_cap", 120))
	if not from_p.diplo_memory.has(to_id):
		from_p.diplo_memory[to_id] = {}
	var kinds: Dictionary = from_p.diplo_memory[to_id]
	var v: int = int(kinds.get("event", 0)) + amount
	v = cap if v > cap else v
	v = -cap if v < -cap else v
	kinds["event"] = v

# The lowest-id living rival, or -1 if the player has none.
static func _pick_rival(player: Player, game_state) -> int:
	var best: int = -1
	for o in game_state.players:
		if o.id == player.id or o.is_eliminated:
			continue
		if best < 0 or o.id < best:
			best = o.id
	return best

# Grant a promotion to every owned unit matching the effect's filter (classification
# / domain / unit_types), skipping units that already hold it.
static func _grant_promotion(eff: Dictionary, player: Player, game_state, db: DataDB) -> void:
	var promo: String = str(eff.get("promotion", ""))
	if promo == "":
		return
	var want_class: String = str(eff.get("classification", ""))
	var want_domain: String = str(eff.get("domain", ""))
	var want_types: Array = eff.get("unit_types", [])
	for u in game_state.units:
		if u.owner_player_id != player.id or u.has_promotion(promo):
			continue
		var ud: Dictionary = db.get_unit(u.unit_type_id)
		if want_class != "" and str(ud.get("classification", "")) != want_class:
			continue
		if want_domain != "" and str(ud.get("domain", "")) != want_domain:
			continue
		if not want_types.empty() and not (u.unit_type_id in want_types):
			continue
		u.promotions.append(promo)

# Append a timed happiness modifier to the scoped cities (capital / all owned /
# all owned holding the state religion).
static func _apply_city_happy_timed(eff: Dictionary, player: Player, game_state) -> void:
	var amount: int = int(eff.get("amount", 0))
	var turns: int = int(eff.get("turns", 0))
	if turns <= 0:
		return
	var scope: String = str(eff.get("scope", "capital"))
	var targets: Array = []
	if scope == "capital":
		var cap: Settlement = capital_of(player.id, game_state)
		if cap != null:
			targets.append(cap)
	else:
		for s in game_state.settlements:
			if s.owner_player_id != player.id:
				continue
			if scope == "all_state_religion" and s.belief_id != player.state_religion:
				continue
			targets.append(s)
	for s in targets:
		s.timed_happiness.append({"amount": amount, "turns_left": turns})

# The owned settlements an event verb targets, by scope: "capital" (the one city,
# default), "all" (every owned city), or "all_state_religion" (owned cities holding
# the player's adopted state religion). Shared by the §9 cluster verbs.
static func _scoped_settlements(scope: String, player: Player, game_state) -> Array:
	var targets: Array = []
	if scope == "capital":
		var cap: Settlement = capital_of(player.id, game_state)
		if cap != null:
			targets.append(cap)
	else:
		for s in game_state.settlements:
			if s.owner_player_id != player.id:
				continue
			if scope == "all_state_religion" and s.belief_id != player.state_religion:
				continue
			targets.append(s)
	return targets

# STRUCT_YIELD (§9): grant a persistent per-structure yield/culture/research/happy
# bonus to the scoped cities that hold the named structure (e.g. "+1 production for
# the city's forge"). The bonus rides on Settlement.structure_bonuses and is folded
# into the output/culture/research/contentment sites only while the structure stands.
static func _apply_structure_yield(eff: Dictionary, player: Player, game_state) -> void:
	var struct_id: String = str(eff.get("structure_id", ""))
	if struct_id == "":
		return
	var channels: Array = ["food", "production", "commerce", "culture", "research", "happiness"]
	for s in _scoped_settlements(str(eff.get("scope", "capital")), player, game_state):
		if not s.has_structure(struct_id):
			continue
		for ch in channels:
			var amt: int = int(eff.get(ch, 0))
			if amt != 0:
				s.add_structure_bonus(struct_id, ch, amt)

# SPEC (§9): grant `count` free specialists of `specialist_type` in the scoped
# cities (default the capital). The next settlement step normalises worked tiles.
static func _apply_specialist(eff: Dictionary, player: Player, game_state) -> void:
	var stype: String = str(eff.get("specialist_type", ""))
	if stype == "":
		return
	var count: int = int(eff.get("count", 1))
	if count <= 0:
		return
	for s in _scoped_settlements(str(eff.get("scope", "capital")), player, game_state):
		s.specialists[stype] = int(s.specialists.get(stype, 0)) + count

# SGP (§9): settle a free Great Person of `gp_type` (general/prophet/merchant/
# artist/scientist/spy) in the capital — modelled as a permanent super-specialist of
# the great person's underlying specialist type, exactly as GreatPeople join_city
# does (§14.1). No unit is spawned; the GP arrives already settled.
static func _apply_settle_great_person(eff: Dictionary, player: Player, game_state) -> void:
	var cap: Settlement = capital_of(player.id, game_state)
	if cap == null:
		return
	var stype: String = _settled_gp_specialist(str(eff.get("gp_type", "")))
	if stype == "":
		return
	var add: int = int(game_state.db.get_constant("gp_super_specialist_count", 1))
	cap.specialists[stype] = int(cap.specialists.get(stype, 0)) + add

# Map a Great Person type onto the specialist type a settled one works as (§14.1):
# a settled General works as an engineer (production); the rest map by name.
static func _settled_gp_specialist(gp_type: String) -> String:
	match gp_type:
		"general", "engineer":
			return "engineer"
		"prophet", "priest":
			return "priest"
		"artist":
			return "artist"
		"scientist":
			return "scientist"
		"merchant":
			return "merchant"
		"spy":
			return "spy"
	return ""

# SPREAD (§9): spread a religion to up to `count` cities. `belief` names the religion
# (default the player's state religion); `scope` selects "own" (default), "foreign",
# or "any" cities. Only converts a city that does not already hold `belief`; honours
# the optional `max_other_religions` filter (the reference's "≤1 other religion" gate:
# a city already holding a *different* religion is skipped when max_other_religions
# is 0). Deterministic city-id scan order.
static func _apply_spread_religion(eff: Dictionary, player: Player, game_state) -> void:
	var belief: String = str(eff.get("belief", ""))
	if belief == "":
		belief = player.state_religion
	if belief == "":
		return
	var count: int = int(eff.get("count", 1))
	if count <= 0:
		return
	var scope: String = str(eff.get("scope", "own"))
	var allow_other: bool = not eff.has("max_other_religions") \
		or int(eff.get("max_other_religions", 1)) >= 1
	# Deterministic order: lowest settlement id first.
	var ordered: Array = game_state.settlements.duplicate()
	ordered.sort_custom(load("res://src/sim/events.gd"), "_cmp_settlement_id")
	var spread: int = 0
	for s in ordered:
		if spread >= count:
			break
		if scope == "own" and s.owner_player_id != player.id:
			continue
		if scope == "foreign" and s.owner_player_id == player.id:
			continue
		if s.belief_id == belief:
			continue
		if s.belief_id != "" and not allow_other:
			continue
		s.belief_id = belief
		spread += 1

# Settlement-id ascending comparator for deterministic spread order.
static func _cmp_settlement_id(a, b) -> bool:
	return a.id < b.id

# Place a resource on a matching owned tile, optionally clearing its feature and
# laying an improvement / route (e.g. cultivating spices into a plantation).
static func _apply_place_resource(eff: Dictionary, player: Player, game_state) -> void:
	var tile: Tile = _find_owned_tile(player.id, game_state, eff.get("match", {}))
	if tile == null:
		return
	tile.resource_id = str(eff.get("resource", ""))
	if bool(eff.get("remove_feature", false)):
		tile.feature_id = ""
	if eff.has("add_improvement"):
		tile.improvement_id = str(eff["add_improvement"])
		tile.improvement_age = 0
	if eff.has("add_route"):
		tile.transport_id = str(eff["add_route"])

# Spawn `count` wild raiders near the player's capital (§9, e.g. The Huns). Units are
# owned by -2 (wild) and placed on passable land tiles adjacent to the capital,
# falling back to the capital tile itself.
static func _apply_spawn_wild(eff: Dictionary, player: Player, game_state) -> void:
	var cap: Settlement = capital_of(player.id, game_state)
	if cap == null:
		return
	var unit_type: String = str(eff.get("unit_type", "warrior"))
	var count: int = int(eff.get("count", 1))
	var db: DataDB = game_state.db
	var spots: Array = _wild_spawn_tiles(cap, count, game_state, db)
	for i in range(count):
		var spot: Array = spots[i % spots.size()] if not spots.empty() else [cap.x, cap.y]
		WildForces._spawn_wild_unit(int(spot[0]), int(spot[1]), game_state, unit_type)

# Passable land tiles around a city for wild spawns (deterministic ring scan),
# capped at `count`. Falls back to the city tile when no ring tile is passable.
static func _wild_spawn_tiles(cap: Settlement, count: int, game_state, db: DataDB) -> Array:
	var spots: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var t: Tile = game_state.map.get_tile(cap.x + dx, cap.y + dy)
			if t == null:
				continue
			var ter: Dictionary = db.get_terrain(t.terrain_id)
			if str(ter.get("domain", "land")) != "land" or bool(ter.get("impassable", false)):
				continue
			spots.append([t.x, t.y])
			if spots.size() >= count:
				return spots
	if spots.empty():
		spots.append([cap.x, cap.y])
	return spots

# ── Tile / player query helpers ──────────────────────────────────────────────────

# The first owned tile matching a tile predicate (deterministic map scan order), or
# null. Keys: terrain, feature, improvement, resource, route(bool), in_city_radius
# (bool — within event_city_radius of one of the player's cities).
static func _find_owned_tile(player_id: int, game_state, spec: Dictionary) -> Tile:
	var db: DataDB = game_state.db
	for t in game_state.map.all_tiles():
		if t.owner_player_id != player_id:
			continue
		if spec.has("terrain") and t.terrain_id != str(spec["terrain"]):
			continue
		if spec.has("feature") and t.feature_id != str(spec["feature"]):
			continue
		if spec.has("improvement") and t.improvement_id != str(spec["improvement"]):
			continue
		if spec.has("resource") and t.resource_id != str(spec["resource"]):
			continue
		if bool(spec.get("route", false)) and not _tile_has_route(t):
			continue
		if bool(spec.get("in_city_radius", false)) and not _tile_in_city_radius(player_id, t, game_state, db):
			continue
		return t
	return null

static func _tile_has_route(t: Tile) -> bool:
	return t.transport_id == "road" or t.transport_id == "railroad" \
		or t.improvement_id == "road" or t.improvement_id == "railroad"

static func _tile_in_city_radius(player_id: int, t: Tile, game_state, db: DataDB) -> bool:
	var radius: int = db.get_constant("event_city_radius", 2)
	for s in game_state.settlements:
		if s.owner_player_id == player_id and game_state.map.distance(s.x, s.y, t.x, t.y) <= radius:
			return true
	return false

static func _player_has_civic(player: Player, civic_id: String) -> bool:
	for cat in player.policies:
		if str(player.policies[cat]) == civic_id:
			return true
	return false

static func _player_owns_resource(player_id: int, resource_id: String, game_state) -> bool:
	for t in game_state.map.all_tiles():
		if t.owner_player_id == player_id and t.resource_id == resource_id:
			return true
	return false

static func _player_has_city_pop(player_id: int, game_state, threshold: int, at_least: bool) -> bool:
	for s in game_state.settlements:
		if s.owner_player_id != player_id:
			continue
		if at_least and s.population >= threshold:
			return true
		if not at_least and s.population <= threshold:
			return true
	return false

static func _player_has_coastal_city(player_id: int, game_state) -> bool:
	var db: DataDB = game_state.db
	for s in game_state.settlements:
		if s.owner_player_id != player_id:
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var t: Tile = game_state.map.get_tile(s.x + dx, s.y + dy)
				if t != null and str(db.get_terrain(t.terrain_id).get("domain", "land")) == "sea":
					return true
	return false

static func _players_with_tech(game_state, tech_id: String) -> int:
	if tech_id == "":
		return 0
	var n: int = 0
	for p in game_state.players:
		if p.has_tech(tech_id):
			n += 1
	return n

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
