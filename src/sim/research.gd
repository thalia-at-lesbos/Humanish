# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Research

# Research graph: prereq resolution, cost calculation with discounts, progress.

# Apply one turn of research for a player. Returns the tech id if completed, else "".
static func advance(player: Player, db: DataDB, known_by_others: Dictionary,
		pace_id: String, difficulty_id: String = "noble",
		world_size_id: String = "standard", team_members: int = 1) -> String:
	if player.current_research_id == "":
		return ""
	var tech: Dictionary = db.get_technology(player.current_research_id)
	if tech.empty():
		return ""

	var cost: int = _effective_cost(player.current_research_id, player, db,
		known_by_others, pace_id, difficulty_id, world_size_id, team_members)

	player.research_store += player.split_commerce(
		_total_commerce(player))[1]  # index 1 = research

	if player.research_store >= cost:
		player.research_store -= cost
		player.technologies.append(player.current_research_id)
		player.current_research_id = ""
		return tech["id"]
	return ""

# Effective cost of a tech for a player (§6.3, game-data §15.4). The canonical
# reference percent chain — base × handicap% × world% × speed% × era% ×
# team-penalty%, floored at 1 — followed by this game's two post-chain discount
# extensions (held prerequisites, factions that already know the tech).
static func _effective_cost(tech_id: String, player: Player, db: DataDB,
		known_by_others: Dictionary, pace_id: String,
		difficulty_id: String = "noble", world_size_id: String = "standard",
		team_members: int = 1) -> int:
	var tech: Dictionary = db.get_technology(tech_id)
	if tech.empty():
		return 999999
	var cost: int = int(tech.get("cost", 100))

	# Difficulty research handicap (§2.2). A player aid: the human pays the level's
	# handicap_research_percent (Settler 60 … Noble 100 … Deity 135). The AI does
	# NOT pay it (its handicap is the separate ai_bonus beaker boost); instead it
	# gets ai_research_per_era — a per-era cost modifier that compounds with its
	# era, applied with the reference sign convention: NEGATIVE means the AI's
	# techs get CHEAPER each era (0 on easy levels, −1…−5 Prince→Deity).
	var diff: Dictionary = db.get_difficulty(difficulty_id)
	if player != null and player.is_ai:
		var per_era: int = int(diff.get("ai_research_per_era", 0))
		if per_era != 0:
			for _i in range(Eras.player_era(player, db)):
				cost = Fixed.scale(cost, 100 + per_era)
	else:
		cost = Fixed.scale(cost, int(diff.get("handicap_research_percent", 100)))
	# World size.
	cost = Fixed.scale(cost, int(db.get_world_size(world_size_id).get("research_percent", 100)))
	# Game speed / pace.
	cost = Fixed.scale(cost, int(db.get_pace(pace_id).get("research_scale", 100)))
	# Advanced-start era (no-op unless ages.json defines research_percent).
	cost = Fixed.scale(cost, Eras.research_scale(Eras.player_era(player, db), db))
	# Team penalty: each extra team member raises the cost (they share research).
	var team_pct: int = int(db.get_constant("tech_cost_extra_team_member_modifier", 30)) \
		* (team_members - 1) + 100
	if team_pct < 0:
		team_pct = 0
	cost = Fixed.scale(cost, team_pct)
	if cost < 1:
		cost = 1

	# ── Post-chain Humanish discounts (intentional extensions, §15.4) ──
	# Prereq discount: 10% per held prerequisite.
	var prereq_discount: int = 0
	for prereq in tech.get("prereqs_all", []):
		if player.has_tech(prereq):
			prereq_discount += 10
	cost = max(1, cost - Fixed.scale(cost, prereq_discount))

	# Trading discount: 5% per other faction that already knows it (capped 25%).
	var others_count: int = int(known_by_others.get(tech_id, 0))
	var others_discount: int = min(others_count * 5, 25)
	cost = max(1, cost - Fixed.scale(cost, others_discount))

	return cost

# Check if a player has all prereqs to research a tech.
static func can_research(tech_id: String, player: Player, db: DataDB) -> bool:
	var tech: Dictionary = db.get_technology(tech_id)
	if tech.empty():
		return false
	if player.has_tech(tech_id):
		return false
	for prereq in tech.get("prereqs_all", []):
		if not player.has_tech(prereq):
			return false
	var any_list: Array = tech.get("prereqs_any", [])
	if not any_list.empty():
		var found: bool = false
		for prereq in any_list:
			if player.has_tech(prereq):
				found = true
				break
		if not found:
			return false
	return true

# Placeholder: total commerce is computed by turn_engine from settlements.
# This provides a default for standalone use.
static func _total_commerce(player: Player) -> int:
	return 0  # overridden by turn_engine
