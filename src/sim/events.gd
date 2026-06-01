class_name Events

# Scripted/random event processing per §9.
# Events are defined in external content data (none loaded yet; stub for Phase 5).

# Process events for the active player.
static func process_player_events(player: Player, game_state, rng: RNG) -> Array:
	# Returns Array of event result Dictionaries (empty until content data added).
	var fired := []
	# TODO: load event definitions from db when content data is added
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
