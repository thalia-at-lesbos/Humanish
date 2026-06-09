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
			# UN election: Assembly.apply_effect("diplomatic_victory") sets
			# winning_alliance_id directly once the institution passes the motion
			# (gated on "diplomatic" being enabled). The old crude population-share
			# tally was removed — it awarded the game to whoever momentarily
			# governed a 67% population majority, which one early city trivially
			# does. This periodic check therefore never awards on its own. The full
			# diplomatic condition is slated for a follow-up rework.
			return -1
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

static func _endgame_project(wc: Dictionary, game_state) -> int:
	var stages_req: int = int(wc.get("stages_required", 3))
	for aid in game_state.endgame_project_stages:
		if game_state.endgame_project_stages[aid] >= stages_req:
			return aid
	return -1

static func _cultural(wc: Dictionary, game_state) -> int:
	var cities_req: int = int(wc.get("cities_at_max_culture", 5))
	var max_ring: int = game_state.db.constants.get("culture_ring_thresholds", []).size()
	var by_alliance := {}
	for s in game_state.settlements:
		if s.culture_ring >= max_ring:
			var p: Player = game_state.get_player(s.owner_player_id)
			if p != null:
				var aid: int = p.alliance_id
				by_alliance[aid] = by_alliance.get(aid, 0) + 1
	for aid in by_alliance:
		if by_alliance[aid] >= cities_req:
			return aid
	return -1

static func _time(game_state) -> int:
	if game_state.turn_number < game_state.max_turns:
		return -1
	# Return highest-scoring alliance
	return Scoring.highest_scoring_alliance(game_state)
