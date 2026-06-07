# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Unit
extends Reference

var id: int = 0
var unit_type_id: String = ""
var owner_player_id: int = -1
var x: int = 0
var y: int = 0

# Combat stats (from data, modified by promotions)
var base_strength: int = 0
var health: int = 100          # 0..100 percent
var experience: int = 0
var experience_level: int = 0
var promotions: Array = []     # Array of promotion IDs

# Movement (fixed-point, see fixed.gd)
var movement_total: int = 200  # Fixed.tiles_to_move(2)
var movement_left: int = 200

# Entrenchment
var entrenchment: int = 0
var stationary_turns: int = 0  # turns without moving

# Transport
var cargo: Array = []          # unit IDs carried (for transport ships)
var transported_by: int = -1   # unit ID of transport, -1 if on land/self

# Worker state
var build_turns_left: int = 0
var building_improvement: String = ""

# Persistent move order (§3.3 go-to mission): when a move cannot reach its target
# this turn, the destination is remembered here so the unit keeps travelling toward
# it on following turns until it arrives or the order is cleared. -1 = no goal.
var goto_x: int = -1
var goto_y: int = -1

# Flags
var has_moved: bool = false
var has_attacked: bool = false
var is_fortified: bool = false
var is_wild: bool = false
# Standing-order stances (§3.3 missions): a unit holds its tile under one of
# these until woken or ordered otherwise. Mutually informative, not exclusive of
# is_fortified, but set independently by the matching mission.
var is_sentry: bool = false
var is_patrolling: bool = false
var is_healing: bool = false
# Asleep: skips its turns (no entrench/defence intent, unlike is_fortified) until
# woken or disturbed. Distinct from fortify so the UI can show the actual order.
var is_sleeping: bool = false

func has_promotion(promo_id: String) -> bool:
	return promo_id in promotions

# Effective strength accounting for promotions and health fraction.
# Returns integer in same scale as base_strength * 1000.
func effective_strength(db: DataDB, is_attacker: bool, terrain: Dictionary,
		feature: Dictionary, versus_class: String) -> int:
	var bonus_sum: int = 0

	# Promotions
	for promo_id in promotions:
		var promo: Dictionary = db.get_promotion(promo_id)
		bonus_sum += int(promo.get("combat_strength_bonus", 0))
		if is_attacker:
			bonus_sum += int(promo.get("attack_vs_settlement", 0)) if terrain.get("is_settlement", false) else 0
		var ter_key: String = "combat_in_" + terrain.get("id", "")
		bonus_sum += int(promo.get(ter_key, 0))
		var feat_key: String = "combat_in_" + feature.get("id", "")
		bonus_sum += int(promo.get(feat_key, 0))

	# Terrain defence bonus (defender only)
	if not is_attacker:
		bonus_sum += int(terrain.get("defence_bonus", 0))
		bonus_sum += int(feature.get("defence_bonus", 0))

	# Entrenchment (defender only)
	if not is_attacker:
		bonus_sum += entrenchment

	var effective: int = Fixed.apply_stacked_bonus(base_strength, bonus_sum)
	# Scale by health fraction
	effective = (effective * health) / 100
	return 1 if effective < 1 else effective

func serialize() -> Dictionary:
	return {
		"id": id, "unit_type_id": unit_type_id,
		"owner_player_id": owner_player_id, "x": x, "y": y,
		"base_strength": base_strength, "health": health,
		"experience": experience, "experience_level": experience_level,
		"promotions": promotions.duplicate(),
		"movement_total": movement_total, "movement_left": movement_left,
		"entrenchment": entrenchment, "stationary_turns": stationary_turns,
		"cargo": cargo.duplicate(), "transported_by": transported_by,
		"build_turns_left": build_turns_left,
		"building_improvement": building_improvement,
		"goto_x": goto_x, "goto_y": goto_y,
		"has_moved": has_moved, "has_attacked": has_attacked,
		"is_fortified": is_fortified, "is_wild": is_wild,
		"is_sentry": is_sentry, "is_patrolling": is_patrolling,
		"is_healing": is_healing, "is_sleeping": is_sleeping
	}

static func deserialize(d: Dictionary):
	var u = load("res://src/sim/unit.gd").new()
	u.id = int(d["id"]); u.unit_type_id = str(d.get("unit_type_id", ""))
	u.owner_player_id = int(d.get("owner_player_id", -1))
	u.x = int(d["x"]); u.y = int(d["y"])
	u.base_strength = int(d.get("base_strength", 0))
	u.health = int(d.get("health", 100))
	u.experience = int(d.get("experience", 0))
	u.experience_level = int(d.get("experience_level", 0))
	u.promotions = d.get("promotions", []).duplicate()
	u.movement_total = int(d.get("movement_total", 200))
	u.movement_left = int(d.get("movement_left", 200))
	u.entrenchment = int(d.get("entrenchment", 0))
	u.stationary_turns = int(d.get("stationary_turns", 0))
	u.cargo = d.get("cargo", []).duplicate()
	u.transported_by = int(d.get("transported_by", -1))
	u.build_turns_left = int(d.get("build_turns_left", 0))
	u.building_improvement = str(d.get("building_improvement", ""))
	u.goto_x = int(d.get("goto_x", -1))
	u.goto_y = int(d.get("goto_y", -1))
	u.has_moved = bool(d.get("has_moved", false))
	u.has_attacked = bool(d.get("has_attacked", false))
	u.is_fortified = bool(d.get("is_fortified", false))
	u.is_wild = bool(d.get("is_wild", false))
	u.is_sentry = bool(d.get("is_sentry", false))
	u.is_patrolling = bool(d.get("is_patrolling", false))
	u.is_healing = bool(d.get("is_healing", false))
	u.is_sleeping = bool(d.get("is_sleeping", false))
	return u
