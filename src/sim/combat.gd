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
# Effective first strikes for one battle (§15.5): the unit's guaranteed
# `first_strikes` plus promotion `first_strikes_bonus`es, plus a uniform
# 0..chance roll where chance = unit `chance_first_strikes` + promotion
# `chance_first_strikes_bonus`es. The roll draws from the shared rng ONLY when
# a chance stat is present, so units without one consume no extra draws and
# every pre-§15.5 seeded stream is unchanged.
static func rolled_first_strikes(db: DataDB, unit: Unit, rng: RNG) -> int:
	var udata: Dictionary = db.get_unit(unit.unit_type_id)
	var strikes: int = int(udata.get("first_strikes", 0))
	var chance: int = int(udata.get("chance_first_strikes", 0))
	for promo_id in unit.promotions:
		var promo: Dictionary = db.get_promotion(promo_id)
		strikes += int(promo.get("first_strikes_bonus", 0))
		chance += int(promo.get("chance_first_strikes_bonus", 0))
	if chance > 0:
		strikes += rng.randi_range(0, chance)
	return strikes

static func resolve(attacker: Unit, defender: Unit,
		game_state, rng: RNG) -> Dictionary:
	var db: DataDB = game_state.db
	var tile: Tile = game_state.map.get_tile(defender.x, defender.y)

	var ter: Dictionary = db.get_terrain(tile.terrain_id)
	var feat: Dictionary = db.get_feature(tile.feature_id) if tile.feature_id != "" else {}

	# Settlement context (§5.3): a fight on a city tile gives the attacker the
	# attack-vs-settlement bonus and the defender the in-settlement promotions plus
	# the city's structure + cultural defence.
	var settle: Settlement = game_state.get_settlement_at(defender.x, defender.y)
	var at_settlement: bool = settle != null
	var settle_def: int = settlement_defence(settle, db)
	var a_fortified: bool = defender.entrenchment > 0
	var d_fortified: bool = attacker.entrenchment > 0

	var a_str: int = attacker.effective_strength(db, true, {}, {},
		_unit_class(defender, db), at_settlement, 0, a_fortified)
	var d_str: int = defender.effective_strength(db, false, ter, feat,
		_unit_class(attacker, db), at_settlement, settle_def, d_fortified)

	# River-crossing / amphibious attack penalties (§5.3): an attacker striking
	# across a river border, or from a water tile onto land, fights weakened unless
	# it ignores the penalty (Amphibious promotion / amphibious unit tag).
	var atk_penalty: int = _attack_penalty(attacker, defender, game_state)
	if atk_penalty > 0:
		a_str -= Fixed.scale(a_str, atk_penalty)
		if a_str < 1:
			a_str = 1

	# Firepower (§5.4) feeds the per-hit damage model, captured from the real
	# effective strengths before any odds-only clamps below.
	var a_fp: int = attacker.firepower(db, a_str)
	var d_fp: int = defender.firepower(db, d_str)

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
	# Odds clamp (§5.4): neither side is ever hopeless — win chance is held within
	# 10%..90% of the die (100..900 of 1000). The free-early-wins aid above is
	# applied on top of this (its 65/35 split already sits inside the band).
	var odds_floor: int = COMBAT_SCALE / 10
	var odds_ceil: int = COMBAT_SCALE - odds_floor
	if a_odds < odds_floor:
		a_odds = odds_floor
	elif a_odds > odds_ceil:
		a_odds = odds_ceil
	var d_odds: int = COMBAT_SCALE - a_odds

	# Per-hit damage (§5.4): firepower-blended, scaled by combat_damage.
	var combat_damage: int = db.get_constant("combat_damage", 20)
	var a_dmg: int = _per_hit_damage(a_fp, d_fp, combat_damage)  # damage attacker takes per defender hit
	var d_dmg: int = _per_hit_damage(d_fp, a_fp, combat_damage)  # damage defender takes per attacker hit

	var a_health: int = attacker.health
	var d_health: int = defender.health
	var a_withdrew: bool = false
	var rounds: int = 0
	var max_rounds: int = db.get_constant("combat_max_rounds", 200)

	var a_unit_data: Dictionary = db.get_unit(attacker.unit_type_id)
	# §15.5: guaranteed first strikes + promotion bonuses + a per-battle chance
	# roll, resolved once here before the round loop (the only first-strike rng
	# draw, so battle order stays the documented pipeline order).
	var a_first_strikes: int = rolled_first_strikes(db, attacker, rng)
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

static func _per_hit_damage(our_fp: int, their_fp: int, combat_damage: int) -> int:
	# §5.4 firepower blend: damage one side takes per hit, proportional to the
	# opponent's firepower relative to one's own, blended with a combined-firepower
	# factor and scaled by combat_damage, floored at one point.
	#   strengthFactor = (ourFP + theirFP + 1) / 2
	#   ourDamage      = max(1, combat_damage * (theirFP + strengthFactor)
	#                                          / (ourFP   + strengthFactor))
	if our_fp <= 0:
		return combat_damage
	var strength_factor: int = (our_fp + their_fp + 1) / 2
	var denom: int = our_fp + strength_factor
	if denom <= 0:
		return combat_damage
	var dmg: int = (combat_damage * (their_fp + strength_factor)) / denom
	return 1 if dmg < 1 else dmg

static func _xp_from_kill(winner_str: int, loser_str: int) -> int:
	if winner_str <= 0:
		return 5
	return (loser_str * 10) / winner_str

# Percentage strength penalty an attacker suffers for the way it reaches the
# defender (§5.3): an amphibious assault (attacking off a water tile onto land) or
# a river crossing (attacking across a river border). Waived for units that ignore
# amphibious penalties (the Amphibious promotion's `no_amphibious_penalty`, or the
# `amphibious` unit tag — Marines / Navy SEALs). The two situations are mutually
# exclusive (a unit on water cannot also be crossing a land river), so the larger
# applicable penalty is returned, never their sum.
static func _attack_penalty(attacker: Unit, defender: Unit, game_state) -> int:
	var db: DataDB = game_state.db
	if _ignores_amphibious(attacker, db):
		return 0
	var atk_tile: Tile = game_state.map.get_tile(attacker.x, attacker.y)
	var def_tile: Tile = game_state.map.get_tile(defender.x, defender.y)
	if atk_tile == null or def_tile == null:
		return 0
	var atk_land: String = str(db.get_terrain(atk_tile.terrain_id).get("landform", ""))
	var def_land: String = str(db.get_terrain(def_tile.terrain_id).get("landform", ""))
	var atk_on_water: bool = atk_land == "water" or atk_land == "deep_water"
	var def_on_land: bool = def_land != "water" and def_land != "deep_water"
	if atk_on_water and def_on_land:
		return db.get_constant("amphibious_attack_penalty", 50)
	if _river_between(game_state.map, attacker.x, attacker.y, defender.x, defender.y):
		return db.get_constant("river_crossing_attack_penalty", 25)
	return 0

# True when a unit ignores amphibious/river attack penalties.
static func _ignores_amphibious(u: Unit, db: DataDB) -> bool:
	if "amphibious" in db.get_unit(u.unit_type_id).get("tags", []):
		return true
	for pid in u.promotions:
		if bool(db.get_promotion(pid).get("no_amphibious_penalty", false)):
			return true
	return false

# True when a river runs along the shared border between two orthogonally adjacent
# tiles. Rivers are stored on a tile's north/west edges (see Tile); a south edge is
# the tile-below's north, an east edge the tile-to-the-right's west. Only direct
# (non-wrapped) orthogonal adjacency is considered.
static func _river_between(map, ax: int, ay: int, bx: int, by: int) -> bool:
	var dx: int = bx - ax
	var dy: int = by - ay
	var adx: int = dx if dx >= 0 else -dx
	var ady: int = dy if dy >= 0 else -dy
	if adx + ady != 1:
		return false
	if dy == -1:  # defender to the north: attacker's own north edge
		var n: Tile = map.get_tile(ax, ay)
		return n != null and n.river_n
	if dy == 1:   # defender to the south: that tile's north edge
		var s: Tile = map.get_tile(ax, ay + 1)
		return s != null and s.river_n
	if dx == -1:  # defender to the west: attacker's own west edge
		var w: Tile = map.get_tile(ax, ay)
		return w != null and w.river_w
	if dx == 1:   # defender to the east: that tile's west edge
		var e: Tile = map.get_tile(ax + 1, ay)
		return e != null and e.river_w
	return false

static func _unit_class(u: Unit, db: DataDB) -> String:
	return db.get_unit(u.unit_type_id).get("classification", "")

# Total defensive bonus a settlement grants its garrison (§5.3): each built
# structure's defence_bonus plus its cultural_defence_bonus (walls, castle, …).
# Public so the facade's city-intel readout (§25.6) shows the same number the
# combat resolver uses.
static func settlement_defence(settle, db: DataDB) -> int:
	if settle == null:
		return 0
	var total: int = 0
	for sid in settle.structures:
		var st: Dictionary = db.get_structure(sid)
		total += int(st.get("defence_bonus", 0))
		total += int(st.get("cultural_defence_bonus", 0))
	return total
