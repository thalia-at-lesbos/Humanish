# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Combat

# Combat resolution per §5.3–5.4.
# All math is integer. Returns a CombatResult Dictionary.

const COMBAT_SCALE: int = 1000  # odds out of 1000

# Resolve combat between attacker and defender.
# Returns Dictionary: {
#   "attacker_survived": bool, "defender_survived": bool,
#   "attacker_health_after": int, "defender_health_after": int,
#   "attacker_withdrew": bool, "rounds": int,
#   "attacker_xp_gain": int, "defender_xp_gain": int,
#   "spillover_damage": int, "flanking_damage": int
# }
static func resolve(attacker: Unit, defender: Unit,
		game_state, rng: RNG) -> Dictionary:
	var db: DataDB = game_state.db
	var tile: Tile = game_state.map.get_tile(defender.x, defender.y)

	var ter: Dictionary = db.get_terrain(tile.terrain_id)
	var feat: Dictionary = db.get_feature(tile.feature_id) if tile.feature_id != "" else {}

	var a_str: int = attacker.effective_strength(db, true, {}, {}, _unit_class(defender, db))
	var d_str: int = defender.effective_strength(db, false, ter, feat, _unit_class(attacker, db))

	# Free early wins: clamp attacker odds against wild units
	var atk_player: Player = game_state.get_player(attacker.owner_player_id)
	if defender.is_wild and atk_player != null and atk_player.free_early_wins > 0:
		var clamp_val: int = db.get_constant("free_early_wins_clamp", 65)
		# Attacker wins at least clamp_val/1000 of the time
		var natural_odds: int = Fixed.proportion(a_str, a_str + d_str, COMBAT_SCALE)
		if natural_odds < (clamp_val * COMBAT_SCALE / 100):
			a_str = clamp_val
			d_str = 100 - clamp_val

	var a_odds: int = Fixed.proportion(a_str, a_str + d_str, COMBAT_SCALE)
	var d_odds: int = COMBAT_SCALE - a_odds

	# Per-hit damage
	var a_dmg: int = _per_hit_damage(d_str, a_str)  # damage attacker takes per defender hit
	var d_dmg: int = _per_hit_damage(a_str, d_str)  # damage defender takes per attacker hit

	var a_health: int = attacker.health
	var d_health: int = defender.health
	var a_withdrew: bool = false
	var rounds: int = 0
	var max_rounds: int = db.get_constant("combat_max_rounds", 200)

	var a_unit_data: Dictionary = db.get_unit(attacker.unit_type_id)
	var a_first_strikes: int = int(a_unit_data.get("first_strikes", 0))
	var d_unit_data: Dictionary = db.get_unit(defender.unit_type_id)
	var a_combat_limit: int = int(a_unit_data.get("combat_limit", 0))  # 0 = no limit
	var a_withdrawal: int = int(a_unit_data.get("withdrawal_chance", 0))
	# Promotion bonuses
	for promo_id in attacker.promotions:
		var promo: Dictionary = db.get_promotion(promo_id)
		a_withdrawal += int(promo.get("withdrawal_chance_bonus", 0))

	var strikes_used: int = 0

	while a_health > 0 and d_health > 0 and rounds < max_rounds:
		rounds += 1
		var roll: int = rng.randi_range(0, COMBAT_SCALE - 1)

		# First strikes: attacker strikes free before normal exchange
		if strikes_used < a_first_strikes:
			strikes_used += 1
			# Attacker hits regardless of odds (first strike)
			d_health -= d_dmg
			if d_health <= 0:
				break
			continue

		if roll < a_odds:
			# Attacker wins round, defender takes a hit
			# Check combat limit
			if a_combat_limit > 0 and d_health - d_dmg < a_combat_limit:
				d_health = a_combat_limit
				break
			d_health -= d_dmg
		else:
			# Defender wins round, attacker takes a hit
			if a_health - a_dmg <= 0 and a_withdrawal > 0:
				if rng.rand_bool_percent(a_withdrawal):
					# The fatal hit is avoided; the attacker retreats intact rather
					# than taking the blow. (Previous code added and subtracted the
					# same damage, a no-op that left this comment misleading.)
					a_withdrew = true
					break
			a_health -= a_dmg

	a_health = max(0, a_health)
	d_health = max(0, d_health)

	var a_survived: bool = a_health > 0 or a_withdrew
	var d_survived: bool = d_health > 0

	# XP gain
	var min_xp: int = db.get_constant("experience_per_kill_min", 5)
	var max_xp: int = db.get_constant("experience_per_kill_max", 100)
	var wild_cap: int = db.get_constant("experience_vs_wild_cap", 20)

	var a_xp: int = 0
	var d_xp: int = 0
	if not d_survived:
		a_xp = clamp(_xp_from_kill(a_str, d_str), min_xp, max_xp)
		if defender.is_wild:
			a_xp = min(a_xp, wild_cap)
		if atk_player != null and atk_player.free_early_wins > 0 and defender.is_wild:
			atk_player.free_early_wins -= 1
	if not a_survived:
		d_xp = clamp(_xp_from_kill(d_str, a_str), min_xp, max_xp)

	# Spillover damage (siege units hit stack)
	var spillover: int = 0
	if "siege" in a_unit_data.get("tags", []) and not d_survived:
		spillover = d_dmg / 2

	# Flanking damage
	var flanking: int = 0
	if "fast" in a_unit_data.get("tags", []) and not d_survived:
		var flank_frac: int = db.get_constant("flanking_damage_fraction", 25)
		flanking = Fixed.scale(d_str, flank_frac)

	return {
		"attacker_survived": a_survived,
		"defender_survived": d_survived,
		"attacker_health_after": a_health if not a_withdrew else attacker.health,
		"defender_health_after": d_health,
		"attacker_withdrew": a_withdrew,
		"rounds": rounds,
		"attacker_xp_gain": a_xp,
		"defender_xp_gain": d_xp,
		"spillover_damage": spillover,
		"flanking_damage": flanking
	}

static func _per_hit_damage(opponent_fp: int, self_fp: int) -> int:
	# Damage = opponent_fp / self_fp, blended with combined, at least 1
	if self_fp <= 0:
		return 10
	var dmg: int = (opponent_fp * 10) / self_fp
	return 1 if dmg < 1 else dmg

static func _xp_from_kill(winner_str: int, loser_str: int) -> int:
	if winner_str <= 0:
		return 5
	return (loser_str * 10) / winner_str

static func _unit_class(u: Unit, db: DataDB) -> String:
	return db.get_unit(u.unit_type_id).get("classification", "")
