class_name Scoring

# Score calculation per §10.
# Score = weighted sum of (population, land, technologies, wonders) / normalization.

static func compute_all(game_state) -> void:
	var total_land: int = game_state.map.all_tiles().size()
	var total_pop: int = 0
	for s in game_state.settlements:
		total_pop += s.population

	var score_by_player := {}
	for p in game_state.players:
		if p.is_eliminated:
			score_by_player[p.id] = 0
			continue
		var land: int = _count_land(p.id, game_state)
		var pop: int  = _count_pop(p.id, game_state)
		var techs: int = p.technologies.size()
		var wonders: int = _count_wonders(p.id, game_state)
		var land_score: int = (land * 100) / max(1, total_land)
		var pop_score: int  = (pop * 100) / max(1, max(1, total_pop))
		var tech_score: int = techs * 2
		var wonder_score: int = wonders * game_state.db.get_constant("score_weight_wonder", 5)
		score_by_player[p.id] = land_score + pop_score + tech_score + wonder_score

	# Write back
	for p in game_state.players:
		p.score = score_by_player.get(p.id, 0)

static func highest_scoring_alliance(game_state) -> int:
	compute_all(game_state)
	var best_aid: int = -1
	var best_score: int = -1
	var score_by_alliance := {}
	for p in game_state.players:
		if p.alliance_id < 0:
			continue
		score_by_alliance[p.alliance_id] = score_by_alliance.get(p.alliance_id, 0) + p.score
	for aid in score_by_alliance:
		if score_by_alliance[aid] > best_score:
			best_score = score_by_alliance[aid]
			best_aid = aid
	return best_aid

static func _count_land(player_id: int, game_state) -> int:
	var count: int = 0
	for tile in game_state.map.all_tiles():
		if tile.owner_player_id == player_id:
			count += 1
	return count

static func _count_pop(player_id: int, game_state) -> int:
	var total: int = 0
	for s in game_state.settlements:
		if s.owner_player_id == player_id:
			total += s.population
	return total

# Count wonders the player owns. A structure is a wonder when its data entry
# carries "is_wonder": true, keeping the rule data-driven (§12).
static func _count_wonders(player_id: int, game_state) -> int:
	var db = game_state.db
	var count: int = 0
	for s in game_state.settlements:
		if s.owner_player_id != player_id:
			continue
		for struct_id in s.structures:
			if db.get_structure(struct_id).get("is_wonder", false):
				count += 1
	return count
