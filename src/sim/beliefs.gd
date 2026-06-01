class_name Beliefs

# Belief founding, spread, and per-turn processing.

# Try to found a new belief. Returns the belief_id if founded, else "".
# Called during the per-player turn when a founding condition is first met.
static func try_found(player_id: int, game_state, rng: RNG) -> String:
	var db: DataDB = game_state.db
	var eligible := []
	for belief_id in db.beliefs:
		if game_state.founded_beliefs.has(belief_id):
			continue
		var belief: Dictionary = db.beliefs[belief_id]
		var tech_req = belief.get("founding_tech", null)
		var player: Player = game_state.get_player(player_id)
		if tech_req != null and tech_req != "" and not player.has_tech(tech_req):
			continue
		eligible.append(belief_id)
	if eligible.empty():
		return ""
	# Randomly choose among eligible (tie-break via RNG for determinism)
	var idx: int = rng.randi_range(0, eligible.size() - 1)
	var chosen: String = eligible[idx]
	game_state.founded_beliefs[chosen] = player_id
	# Find a settlement of this player to host the principal site
	for s in game_state.settlements:
		if s.owner_player_id == player_id and s.belief_id == "":
			s.belief_id = chosen
			break
	return chosen

# Spread beliefs to adjacent settlements each turn.
static func spread_all(game_state, rng: RNG) -> void:
	var db: DataDB = game_state.db
	for belief_id in game_state.founded_beliefs:
		var belief: Dictionary = db.beliefs.get(belief_id, {})
		var spread_chance: int = int(belief.get("spread_chance_base", 20))
		for s in game_state.settlements:
			if s.belief_id == belief_id:
				continue
			# Check adjacency to a settlement with this belief
			for other in game_state.settlements:
				if other.belief_id != belief_id:
					continue
				var dist: int = game_state.map.distance(s.x, s.y, other.x, other.y)
				if dist <= 3:
					if rng.rand_bool_percent(max(1, spread_chance - dist * 5)):
						if s.belief_id == "":
							s.belief_id = belief_id
						break
