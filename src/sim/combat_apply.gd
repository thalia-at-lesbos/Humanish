# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name CombatApply

# Pure application of a resolved unit-vs-unit combat (§5) to GameState.
#
# Combat.resolve() computes the outcome; this module writes it back: healths, XP,
# auto-promotions, removing the dead, advancing a victorious attacker, spillover
# and flanking damage, war-fatigue, and Great-General accrual. It is pure data
# mutation — no signals, no scene/Node references — so both SimFacade (the human/AI
# command path) and WildAI (the world-step raider path) share one source of truth.
# Callers that surface combat to the UI emit their own signals afterwards from the
# returned `result` dictionary.

# Apply a resolved attacker-vs-defender result. `advance` walks a surviving
# attacker onto the defender's tile when the defender dies (false for bombard/air
# strikes that hit without moving).
static func apply_unit_result(gs, attacker: Unit, defender: Unit,
		result: Dictionary, advance: bool = true) -> void:
	attacker.health = int(result["attacker_health_after"])
	defender.health = int(result["defender_health_after"])

	attacker.experience += _award_xp(gs, attacker, defender, int(result["attacker_xp_gain"]))
	defender.experience += _award_xp(gs, defender, attacker, int(result["defender_xp_gain"]))

	# Auto-promote survivors that crossed an experience threshold (§5.5).
	if result["attacker_survived"]:
		award_promotions(gs, attacker)
	if result["defender_survived"]:
		award_promotions(gs, defender)

	# War-fatigue: the losing side's alliance accrues fatigue (§4.5, §7).
	if not result["defender_survived"] and result["attacker_survived"]:
		accrue_war_fatigue(gs, defender, attacker)
	elif not result["attacker_survived"] and result["defender_survived"]:
		accrue_war_fatigue(gs, attacker, defender)

	if not result["attacker_survived"]:
		Stack.remove_unit(gs.units, attacker.id)
	if not result["defender_survived"]:
		Stack.remove_unit(gs.units, defender.id)
		# Attacker may advance (bombard/air strikes pass advance = false)
		if result["attacker_survived"] and advance:
			attacker.x = defender.x
			attacker.y = defender.y

	# Spillover to stacked units (siege attackers)
	if result["spillover_damage"] > 0:
		for u in Stack.at(gs.units, defender.x, defender.y, defender.owner_player_id):
			if u.id != defender.id:
				u.health = max(0, u.health - int(result["spillover_damage"]))
				if u.health <= 0:
					Stack.remove_unit(gs.units, u.id)

	# Flanking: fast attackers damage part of the defeated defender's stack (§5.4).
	if result["flanking_damage"] > 0:
		for u in Stack.at(gs.units, defender.x, defender.y, defender.owner_player_id):
			if u.id != defender.id:
				u.health = max(0, u.health - int(result["flanking_damage"]))
				if u.health <= 0:
					Stack.remove_unit(gs.units, u.id)

	# Great General accrues from combat victories (§14.2): the surviving victor's
	# owner gains points and may produce a Great General in the field.
	if result["attacker_survived"] != result["defender_survived"]:
		if result["attacker_survived"]:
			GreatPeople.award_combat_points(gs,
				gs.get_player(attacker.owner_player_id),
				attacker.x, attacker.y, int(result["attacker_xp_gain"]))
		else:
			GreatPeople.award_combat_points(gs,
				gs.get_player(defender.owner_player_id),
				defender.x, defender.y, int(result["defender_xp_gain"]))

# Grant promotions for each experience level newly reached (§5.5). Levels are the
# data-defined experience_thresholds; each new level awards one eligible promotion.
# XP actually awarded to `unit` for this fight. Against an **animal** (§9.3) the
# gain is clamped so the unit's *lifetime* animal XP never exceeds the cap — beyond
# it, hunting animals yields nothing. Non-animal fights award the full gain.
static func _award_xp(gs, unit: Unit, opponent: Unit, gain: int) -> int:
	if gain <= 0 or not opponent.is_animal:
		return gain if gain > 0 else 0
	var cap: int = gs.db.get_constant("animal_xp_lifetime_cap", 10)
	var remaining: int = cap - unit.xp_from_animals
	if remaining <= 0:
		return 0
	var granted: int = gain if gain < remaining else remaining
	unit.xp_from_animals += granted
	return granted

static func award_promotions(gs, u: Unit) -> void:
	# Animals never earn promotions from combat (§9.3).
	if u.is_animal:
		return
	var thresholds: Array = gs.db.constants.get("experience_thresholds", [])
	while u.experience_level + 1 < thresholds.size() \
			and u.experience >= int(thresholds[u.experience_level + 1]):
		u.experience_level += 1
		var promo: String = pick_promotion(gs, u)
		if promo == "":
			break  # nothing eligible left; stop awarding
		u.promotions.append(promo)

# First promotion (in data order) whose prereqs are met, that applies to this
# unit's class/domain, and that it does not already hold. "" if none qualifies.
static func pick_promotion(gs, u: Unit) -> String:
	var db: DataDB = gs.db
	var udata: Dictionary = db.get_unit(u.unit_type_id)
	var cls: String = str(udata.get("classification", ""))
	var dom: String = str(udata.get("domain", "land"))
	for pid in db.promotions:
		if pid in u.promotions:
			continue
		var promo: Dictionary = db.promotions[pid]
		var applies: String = str(promo.get("applies_to", "all"))
		if applies != "all" and applies != cls and applies != dom:
			continue
		var ok: bool = true
		for pr in promo.get("prereqs", []):
			if not (pr in u.promotions):
				ok = false
				break
		if ok:
			return pid
	return ""

# The defeated unit's alliance accumulates war-fatigue against the victor's
# alliance. Wild forces (no player/alliance) are skipped.
static func accrue_war_fatigue(gs, loser: Unit, winner: Unit) -> void:
	var lp: Player = gs.get_player(loser.owner_player_id)
	var wp: Player = gs.get_player(winner.owner_player_id)
	if lp == null or wp == null:
		return
	var la: Alliance = gs.get_alliance(lp.alliance_id)
	if la == null:
		return
	# War Weariness does not increase for a player enjoying a Golden Age (§14.4).
	if GreatPeople.is_in_golden_age(lp):
		return
	var amt: int = gs.db.get_constant("war_fatigue_per_loss", 5)
	la.war_fatigue[wp.alliance_id] = int(la.war_fatigue.get(wp.alliance_id, 0)) + amt
