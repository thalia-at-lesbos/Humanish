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

# Class-versus-class combat keys (§5.3): a promotion's `vs_<key>` bonus applies
# when the *opponent* has the mapped classification. Data uses the historical key
# names (vs_ships for naval, vs_fighters for air), so we translate here.
const VS_CLASS_KEY: Dictionary = {
	"melee": "vs_melee",
	"mounted": "vs_mounted",
	"gunpowder": "vs_gunpowder",
	"naval": "vs_ships",
	"air": "vs_fighters",
}

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
# Chop/clear order (§4.11): the removable feature the worker is felling on its
# tile; uses build_turns_left for timing, mutually exclusive with a build.
var clearing_feature: String = ""

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
# A wild *animal* (§9.3): a subset of wild units (owner -2, is_wild also true) with
# its own spawning (dark/unrevealed tiles), behaviour (hunts weak units, shuns
# cities and borders), and combat limits (gives capped XP, earns no promotions).
var is_animal: bool = false
# Lifetime XP this unit has banked from killing animals, capped per §9.3 so animal
# hunting can never farm a unit to high levels.
var xp_from_animals: int = 0
# Standing-order stances (§3.3 missions): a unit holds its tile under one of
# these until woken or ordered otherwise. Mutually informative, not exclusive of
# is_fortified, but set independently by the matching mission.
var is_sentry: bool = false
var is_patrolling: bool = false
var is_healing: bool = false
# Asleep: skips its turns (no entrench/defence intent, unlike is_fortified) until
# woken or disturbed. Distinct from fortify so the UI can show the actual order.
var is_sleeping: bool = false
# Heal-until-recovered stances: like is_sleeping/is_fortified but auto-clear on
# full health.  is_sleep_until_healed: pure skip; is_fortify_until_healed: also
# grants the fortify defence bonus while waiting.
var is_sleep_until_healed: bool = false
var is_fortify_until_healed: bool = false
# Explore mission (§3.3): scout/recon unit auto-moves toward unexplored territory.
# Cleared when an enemy is spotted nearby or no new territory is reachable.
var is_exploring: bool = false

func has_promotion(promo_id: String) -> bool:
	return promo_id in promotions

# Effective combat strength (§5.3), accounting for promotions and health fraction.
# Optional context the caller supplies for a
# fight at a settlement: `at_settlement` marks the combat tile as a city (enabling
# the attacker's attack-vs-settlement and the defender's defense-in-settlement
# promotions), `settlement_def_bonus` is the city's structure + cultural defence
# (added to defenders), and `opponent_entrenched` enables vs-fortified bonuses.
func effective_strength(db: DataDB, is_attacker: bool, terrain: Dictionary,
		feature: Dictionary, versus_class: String,
		at_settlement: bool = false, settlement_def_bonus: int = 0,
		opponent_entrenched: bool = false) -> int:
	var bonus_sum: int = 0

	# Class-versus-class key for the opponent's classification (§5.3).
	var vs_key: String = VS_CLASS_KEY.get(versus_class, "")

	# Promotions
	for promo_id in promotions:
		var promo: Dictionary = db.get_promotion(promo_id)
		bonus_sum += int(promo.get("combat_strength_bonus", 0))
		# Class-versus-class and versus-fortified modifiers (apply in either role).
		if vs_key != "":
			bonus_sum += int(promo.get(vs_key, 0))
		if opponent_entrenched:
			bonus_sum += int(promo.get("vs_fortified", 0))
		# Settlement combat: attackers get attack-vs-settlement, defenders get
		# defense-in-settlement (§5.3).
		if at_settlement:
			if is_attacker:
				bonus_sum += int(promo.get("attack_vs_settlement", 0))
			else:
				bonus_sum += int(promo.get("defense_in_settlement", 0))
		# Landform-keyed defence (Guerrilla line on Hills), defender only (§5.3).
		if not is_attacker and str(terrain.get("landform", "")) == "hill":
			bonus_sum += int(promo.get("defense_on_hills", 0))
		var ter_key: String = "combat_in_" + terrain.get("id", "")
		bonus_sum += int(promo.get(ter_key, 0))
		var feat_key: String = "combat_in_" + feature.get("id", "")
		bonus_sum += int(promo.get(feat_key, 0))

	# Terrain defence bonus (defender only)
	if not is_attacker:
		bonus_sum += int(terrain.get("defence_bonus", 0))
		bonus_sum += int(feature.get("defence_bonus", 0))
		# Settlement defensive bonus: walls/castle defence plus cultural defence
		# (§5.3). Computed by the caller from the city's structures.
		bonus_sum += settlement_def_bonus

	# Entrenchment (defender only)
	if not is_attacker:
		bonus_sum += entrenchment

	var effective: int = Fixed.apply_stacked_bonus(base_strength, bonus_sum)
	# Scale by health fraction
	effective = (effective * health) / 100
	return 1 if effective < 1 else effective

# Firepower feeds the §5.4 per-hit damage model, distinct from combat strength.
# For most units firepower equals the effective strength passed in; siege and a
# few special types carry a distinct value via the `firepower` data field (a
# health-scaled flat quantity), so they deal damage decoupled from their odds.
func firepower(db: DataDB, effective_str: int) -> int:
	var data: Dictionary = db.get_unit(unit_type_id)
	if not data.has("firepower"):
		return effective_str
	var fp: int = (int(data["firepower"]) * health) / 100
	return 1 if fp < 1 else fp

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
		"clearing_feature": clearing_feature,
		"goto_x": goto_x, "goto_y": goto_y,
		"has_moved": has_moved, "has_attacked": has_attacked,
		"is_fortified": is_fortified, "is_wild": is_wild,
		"is_animal": is_animal, "xp_from_animals": xp_from_animals,
		"is_sentry": is_sentry, "is_patrolling": is_patrolling,
		"is_healing": is_healing, "is_sleeping": is_sleeping,
		"is_sleep_until_healed": is_sleep_until_healed,
		"is_fortify_until_healed": is_fortify_until_healed,
		"is_exploring": is_exploring
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
	u.clearing_feature = str(d.get("clearing_feature", ""))
	u.goto_x = int(d.get("goto_x", -1))
	u.goto_y = int(d.get("goto_y", -1))
	u.has_moved = bool(d.get("has_moved", false))
	u.has_attacked = bool(d.get("has_attacked", false))
	u.is_fortified = bool(d.get("is_fortified", false))
	u.is_wild = bool(d.get("is_wild", false))
	u.is_animal = bool(d.get("is_animal", false))
	u.xp_from_animals = int(d.get("xp_from_animals", 0))
	u.is_sentry = bool(d.get("is_sentry", false))
	u.is_patrolling = bool(d.get("is_patrolling", false))
	u.is_healing = bool(d.get("is_healing", false))
	u.is_sleeping = bool(d.get("is_sleeping", false))
	u.is_sleep_until_healed = bool(d.get("is_sleep_until_healed", false))
	u.is_fortify_until_healed = bool(d.get("is_fortify_until_healed", false))
	u.is_exploring = bool(d.get("is_exploring", false))
	return u
