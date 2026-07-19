# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name WinConditions

# Win condition evaluation per §10.
# Returns the winning alliance_id (int) if any condition is met, else -1.

static func check_all(game_state) -> int:
	var db: DataDB = game_state.db
	var enabled: Array = game_state.enabled_win_conditions

	for wc_id in enabled:
		var wc: Dictionary = db.win_conditions.get(wc_id, {})
		if wc.empty():
			continue
		var winner: int = _check_one(wc, game_state)
		if winner >= 0:
			return winner
	return -1

static func _check_one(wc: Dictionary, game_state) -> int:
	var wtype: String = wc.get("type", "")
	match wtype:
		"last_standing":
			return _last_standing(game_state)
		"dominance":
			return _dominance(wc, game_state)
		"endgame_project":
			return _endgame_project(wc, game_state)
		"cultural":
			return _cultural(wc, game_state)
		"diplomatic":
			# Diplomatic victory is delivered *solely* by the world assembly's
			# supreme-leadership election: Assembly.apply_effect("diplomatic_victory")
			# sets winning_alliance_id directly once the institution passes the motion
			# at the body-dependent threshold (UN 60% / Apostolic Palace 75%), the
			# candidate clears the path-specific gate (UN Mass Media / AP belief held
			# by every civ), and the candidate's alliance is not itself "too big"
			# (>= 75% of the vote). See game-rules.md §7.2 and Assembly. This periodic
			# check therefore never awards on its own.
			return -1
		"score":
			return _score(wc, game_state)
		"time":
			return _time(game_state)
	return -1

static func _last_standing(game_state) -> int:
	var living_alliances := {}
	for s in game_state.settlements:
		if s.owner_player_id >= 0:
			var p: Player = game_state.get_player(s.owner_player_id)
			if p != null:
				living_alliances[p.alliance_id] = true
	for u in game_state.units:
		if u.owner_player_id >= 0:
			var p: Player = game_state.get_player(u.owner_player_id)
			if p != null:
				living_alliances[p.alliance_id] = true
	if living_alliances.size() == 1:
		return living_alliances.keys()[0]
	return -1

static func _dominance(wc: Dictionary, game_state) -> int:
	var land_req: int = int(wc.get("land_share_required", 60))
	var pop_req: int  = int(wc.get("population_share_required", 60))
	var total_land: int = 0
	var total_pop: int  = 0
	var land_by_alliance := {}
	var pop_by_alliance  := {}

	for tile in game_state.map.all_tiles():
		if tile.owner_player_id >= 0:
			var p: Player = game_state.get_player(tile.owner_player_id)
			if p != null:
				var aid: int = p.alliance_id
				land_by_alliance[aid] = land_by_alliance.get(aid, 0) + 1
		total_land += 1

	for s in game_state.settlements:
		if s.owner_player_id >= 0:
			var p: Player = game_state.get_player(s.owner_player_id)
			if p != null:
				var aid: int = p.alliance_id
				pop_by_alliance[aid] = pop_by_alliance.get(aid, 0) + s.population
		total_pop += s.population

	for aid in land_by_alliance:
		if total_land == 0 or total_pop == 0:
			continue
		var land_pct: int = (land_by_alliance[aid] * 100) / total_land
		var pop_pct: int  = (pop_by_alliance.get(aid, 0) * 100) / total_pop
		if land_pct >= land_req and pop_pct >= pop_req:
			return aid
	return -1

# Space race (§15.16 / M4): parts tally PER TYPE (Projects/`count_needed`).
# One of every part type launches the ship, starting an arrival countdown of
# `victory_delay_turns` (10) × the pace `victory_delay_scale` % (67/100/150/300),
# stretched by each optional part type still short of its full threshold
# (`delay_percent` × missing / count_needed percent — engines +25% per missing,
# thrusters +20%). The countdown ticks −1 per world step; at 0 an arrival roll
# fires — success chance 100 − `success_rate` (20) × missing casings. Success
# wins; failure loses the launch (parts remain; the ship auto-relaunches on the
# next check). Integer truncation throughout. A chance of 100 skips the rng
# draw (pure function of state, so seeded streams gain no draw), as does 0.
# Losing the capital cancels the countdown (spaceship_capital_lost below).
static func _endgame_project(wc: Dictionary, game_state) -> int:
	var db: DataDB = game_state.db
	# Deterministic alliance order: sorted int ids across tallies + countdowns.
	var aid_set := {}
	for k in game_state.endgame_project_parts:
		aid_set[int(k)] = true
	for k in game_state.spaceship_countdown:
		aid_set[int(k)] = true
	var order: Array = aid_set.keys()
	order.sort()
	for aid in order:
		var tally: Dictionary = Projects.parts_tally(game_state, aid)
		if game_state.spaceship_countdown.has(aid):
			var left: int = int(game_state.spaceship_countdown[aid]) - 1
			if left > 0:
				game_state.spaceship_countdown[aid] = left
				continue
			# Arrival: the launch is spent either way.
			game_state.spaceship_countdown.erase(aid)
			var chance: int = arrival_chance(db, tally)
			if chance >= 100 \
					or (chance > 0 and game_state.rng.rand_bool_percent(chance)):
				return aid
			# Failure: parts remain; a re-launch starts on the next check.
		elif Projects.launch_ready(db, tally):
			game_state.spaceship_countdown[aid] = launch_delay(game_state, wc, tally)
	return -1

# Post-launch travel turns (§15.16): base `victory_delay_turns` × the pace's
# `victory_delay_scale` / 100, then × (100 + Σ per-type delay_percent × missing
# / count_needed) / 100. Truncating integer math at each step.
static func launch_delay(game_state, wc: Dictionary, tally: Dictionary) -> int:
	var db: DataDB = game_state.db
	var scale: int = int(db.get_pace(game_state.pace_id).get("victory_delay_scale", 100))
	var turns: int = int(wc.get("victory_delay_turns", 10)) * scale / 100
	var stretch: int = 100
	for pid in Projects.endgame_ids(db):
		var proj: Dictionary = db.projects[pid]
		var dpct: int = int(proj.get("delay_percent", 0))
		if dpct <= 0:
			continue
		var need: int = Projects.count_needed(proj)
		var missing: int = need - Projects.parts_of(db, tally, pid)
		if missing > 0:
			stretch += dpct * missing / need
	return turns * stretch / 100

# Arrival success chance (§15.16): 100 − Σ per-type `success_rate` × missing
# instances (casings carry 20 → −20% per missing casing). Clamped to 0..100.
static func arrival_chance(db: DataDB, tally: Dictionary) -> int:
	var chance: int = 100
	for pid in Projects.endgame_ids(db):
		var proj: Dictionary = db.projects[pid]
		var rate: int = int(proj.get("success_rate", 0))
		if rate <= 0:
			continue
		var missing: int = Projects.count_needed(proj) - Projects.parts_of(db, tally, pid)
		if missing > 0:
			chance -= rate * missing
	if chance < 0:
		chance = 0
	return chance

# §15.16: losing the capital cancels the arrival countdown — the spaceship is
# lost and must re-launch (which the auto-launch check restarts from scratch).
# Called by the conquest paths (SimFacade._city_falls, WildAI's raze) with the
# city about to fall; a non-capital city, or an owner alliance with no launch
# in flight, is a no-op. Returns true when a countdown was cancelled so the
# caller can surface it.
static func spaceship_capital_lost(game_state, city) -> bool:
	if city == null or not city.has_structure("palace"):
		return false
	var p: Player = game_state.get_player(city.owner_player_id)
	if p == null or not game_state.spaceship_countdown.has(p.alliance_id):
		return false
	game_state.spaceship_countdown.erase(p.alliance_id)
	return true

# Cultural victory: `cities_at_max_culture` settlements must each accumulate the
# legendary-culture threshold — the top entry of the pace's
# `culture_level_thresholds` column (§15.4 / D2: 25000/50000/75000/150000 on
# quick/normal/epic/marathon). The per-pace columns already carry the reference
# speed scaling, so no `victory_delay_scale` stretch applies any more (the C3-era
# formula scaled the old near-linear top ring of 550; D2 replaced that curve).
static func _cultural(wc: Dictionary, game_state) -> int:
	var cities_req: int = int(wc.get("cities_at_max_culture", 5))
	var need_culture: int = CultureLevels.legendary_threshold(
		game_state.db, game_state.pace_id)
	if need_culture <= 0:
		return -1
	var by_alliance := {}
	for s in game_state.settlements:
		if s.culture_total >= need_culture:
			var p: Player = game_state.get_player(s.owner_player_id)
			if p != null:
				var aid: int = p.alliance_id
				by_alliance[aid] = by_alliance.get(aid, 0) + 1
	for aid in by_alliance:
		if by_alliance[aid] >= cities_req:
			return aid
	return -1

# Time victory: highest score once the turn limit arrives. The turn threshold is
# already pace-stretched — `max_turns` comes from the per-pace column in paces.json
# (330/500/750/1500, matching the reference totals) — so victory_delay_scale is NOT
# applied again here (§15.3).
static func _time(game_state) -> int:
	if game_state.turn_number < game_state.max_turns:
		return -1
	# Return highest-scoring alliance
	return Scoring.highest_scoring_alliance(game_state)

# Score victory (§10): the first alliance whose summed score reaches the
# configured absolute threshold wins immediately — distinct from Time, which
# only awards the highest score at the turn limit. Ties resolve to the lowest
# alliance id for determinism.
static func _score(wc: Dictionary, game_state) -> int:
	var threshold: int = int(wc.get("score_threshold", 0))
	if threshold <= 0:
		return -1
	var totals: Dictionary = Scoring.score_by_alliance(game_state)
	var winner: int = -1
	for aid in totals:
		if totals[aid] >= threshold and (winner < 0 or aid < winner):
			winner = aid
	return winner
