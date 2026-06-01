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

# Exploration reward when a unit investigates a discovery site.
# Reward types (weighted): treasury, map, experience, unit, tech, ambush
static func exploration_reward(unit: Unit, game_state, rng: RNG) -> Dictionary:
	var db: DataDB = game_state.db
	var weights: Array = db.constants.get("exploration_reward_weights",
		[30, 20, 20, 15, 10, 5])
	var idx: int = rng.rand_weighted(weights)
	var reward_types := ["treasury", "map", "experience", "unit", "tech", "ambush"]
	var reward_type: String = reward_types[min(idx, reward_types.size() - 1)]

	match reward_type:
		"treasury":
			var amount: int = rng.randi_range(20, 80)
			var player: Player = game_state.get_player(unit.owner_player_id)
			if player != null:
				player.treasury += amount
			return {"type": "treasury", "amount": amount}
		"experience":
			var xp: int = rng.randi_range(5, 15)
			unit.experience += xp
			return {"type": "experience", "amount": xp}
		"ambush":
			return {"type": "ambush", "unit_id": unit.id}
		_:
			return {"type": reward_type}
