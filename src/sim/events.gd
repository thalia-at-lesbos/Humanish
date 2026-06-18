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

# Scripted/random event processing per §9.
# Events are defined in external content data (none loaded yet; stub for Phase 5).

# Process scripted events for the active player. Each event in data/events.json
# fires once per player when its `min_turn` is reached and any prereq tech is
# held, applying simple effects (treasury). Returns the fired event Dictionaries.
static func process_player_events(player: Player, game_state, rng: RNG) -> Array:
	var db: DataDB = game_state.db
	var fired := []
	for event_id in db.events:
		if event_id in player.events_fired:
			continue
		var ev: Dictionary = db.events[event_id]
		if game_state.turn_number < int(ev.get("min_turn", 0)):
			continue
		var tech_req = ev.get("tech_required", null)
		if tech_req != null and tech_req != "" and not player.has_tech(tech_req):
			continue
		player.events_fired.append(event_id)
		player.treasury += int(ev.get("treasury", 0))
		fired.append(ev)
	return fired

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
