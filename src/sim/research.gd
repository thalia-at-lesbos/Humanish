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
		pace_id: String) -> String:
	if player.current_research_id == "":
		return ""
	var tech: Dictionary = db.get_technology(player.current_research_id)
	if tech.empty():
		return ""

	var cost: int = _effective_cost(player.current_research_id, player, db,
		known_by_others, pace_id)

	player.research_store += player.split_commerce(
		_total_commerce(player))[1]  # index 1 = research

	if player.research_store >= cost:
		player.research_store -= cost
		player.technologies.append(player.current_research_id)
		player.current_research_id = ""
		return tech["id"]
	return ""

# Effective cost of a tech for a player (discounted).
static func _effective_cost(tech_id: String, player: Player, db: DataDB,
		known_by_others: Dictionary, pace_id: String) -> int:
	var tech: Dictionary = db.get_technology(tech_id)
	if tech.empty():
		return 999999
	var base: int = int(tech.get("cost", 100))
	var pace: Dictionary = db.get_pace(pace_id)
	var scale: int = int(pace.get("research_scale", 100))
	var cost: int = Fixed.scale(base, scale)

	# Prereq discount
	var prereq_discount: int = 0
	for prereq in tech.get("prereqs_all", []):
		if player.has_tech(prereq):
			prereq_discount += 10
	cost = max(1, cost - Fixed.scale(cost, prereq_discount))

	# Discount from others who know it
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
