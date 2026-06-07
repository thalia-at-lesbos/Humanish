# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name CultureRevolt

# §4.9 cultural revolt / city flipping (PROVISIONAL — see game-rules.md §4.9).
#
# A settlement may flip to a rival player through cultural pressure rather than
# combat. This is a TurnEngine phase that runs during the owner's player step:
# each of the owner's settlements is tested, and the strongest rival that both
# out-cultures the owner on the city's tile and holds a settlement within
# cultural radius may, on a passed revolt check, accumulate a successful revolt;
# the city flips once enough accumulate.
#
# Pure static and a single-RNG consumer: the revolt check draws from the shared
# gs.rng, so the outcome is deterministic for the seed and captured by save/load.
# It mutates GameState directly (ownership, occupation) like the rest of the
# pipeline; it returns the flip records so the facade can raise notifications and
# the `city_flipped` signal. All math is integer math (§ground rules).

# Test every settlement the active player owns; return an Array of flip records
# {settlement_id, from_player_id, to_player_id} for any that changed hands.
static func process_player(gs, player_id: int, rng, db) -> Array:
	var flips: Array = []
	var chance: int = db.get_constant("revolt_check_chance", 10)
	var shield: bool = db.get_constant("revolt_shield_during_occupation", 1) != 0
	# Snapshot the owner's settlements: a flip mutates ownership mid-loop.
	var own: Array = []
	for s in gs.settlements:
		if s.owner_player_id == player_id:
			own.append(s)

	for s in own:
		# A freshly-conquered city in occupation is (by default) shielded from
		# flipping until its revolt subsides (§4.9).
		if s.revolt_turns > 0 and shield:
			s.revolt_progress = 0
			continue

		var rival: int = _strongest_eligible_rival(gs, s, player_id, db)
		if rival == -999:
			s.revolt_progress = 0   # no rival out-cultures the owner: pressure relieved
			continue

		# A revolt is only *checked* on a fraction of turns (the one stochastic draw).
		if not rng.rand_bool_percent(chance):
			continue

		var power: int = _revolt_power(gs, s, rival, player_id, db)
		var garrison: int = _garrison_strength(gs, s, rival, player_id, db)
		if power <= garrison:
			continue

		# Successful revolt. Barbarian/wild cities flip on the first; a real
		# player's city needs several before it actually changes hands (§4.9).
		var needed: int = 1 if s.owner_player_id == -2 \
			else db.get_constant("revolt_required_successes", 2)
		s.revolt_progress += 1
		if s.revolt_progress >= needed:
			var from_pid: int = s.owner_player_id
			_apply_flip(s, rival, db)
			flips.append({
				"settlement_id": s.id,
				"from_player_id": from_pid,
				"to_player_id": rival
			})
	return flips

# The rival player with the most influence on the settlement's own tile, provided
# that influence exceeds the owner's AND the rival controls a settlement within
# cultural radius of this one. Returns the rival player id, or -999 if none.
static func _strongest_eligible_rival(gs, s, owner_pid: int, db) -> int:
	var tile = gs.map.get_tile(s.x, s.y)
	if tile == null:
		return -999
	var owner_inf: int = int(tile.influence.get(owner_pid, 0))
	var best_pid: int = -999
	var best_inf: int = owner_inf
	for pid in tile.influence:
		if pid == owner_pid:
			continue
		var inf: int = int(tile.influence[pid])
		if inf <= best_inf:
			continue
		if not _rival_has_nearby_city(gs, s, pid):
			continue
		best_inf = inf
		best_pid = pid
	return best_pid

# Does `rival_pid` own a settlement close enough to press its culture on `s`,
# i.e. within that rival settlement's own border reach (its culture_ring)?
static func _rival_has_nearby_city(gs, s, rival_pid: int) -> bool:
	for other in gs.settlements:
		if other.owner_player_id != rival_pid:
			continue
		if gs.map.distance(s.x, s.y, other.x, other.y) <= other.culture_ring:
			return true
	return false

# Revolt power of the challenging rival (§4.9):
#   base   = 1 + per_pop * peak_population + adjacent_rival_tiles * era
#   ratio  = 1 + (rival_culture - owner_culture) / rival_culture   (clamped 1..2)
#   power  = base * ratio, then ×/÷ by the belief amplifier/dampener
static func _revolt_power(gs, s, rival_pid: int, owner_pid: int, db) -> int:
	var tile = gs.map.get_tile(s.x, s.y)
	var owner_inf: int = int(tile.influence.get(owner_pid, 0))
	var rival_inf: int = int(tile.influence.get(rival_pid, 0))

	# Adjacent tiles the rival controls, scaled by the rival's era number.
	var adj: int = 0
	for nb in gs.map.neighbours8(s.x, s.y):
		if nb.owner_player_id == rival_pid:
			adj += 1
	var era: int = _era_number(gs, rival_pid, db)

	var base: int = 1 + db.get_constant("revolt_base_per_pop", 2) * s.peak_population \
		+ adj * era

	# Culture ratio as integer percent in [100, 200]. rival_inf > owner_inf and
	# rival_inf > 0 here (the rival was the strongest eligible challenger).
	var ratio_pct: int = 100
	if rival_inf > 0:
		var extra: int = ((rival_inf - owner_inf) * 100) / rival_inf
		extra = 0 if extra < 0 else (100 if extra > 100 else extra)
		ratio_pct = 100 + extra

	var power: int = base * ratio_pct / 100

	# Belief acts as a cultural amplifier/dampener (§4.9): a rival pressing a
	# foreign belief amplifies the revolt; the owner's own belief dampens it.
	var bmult: int = db.get_constant("revolt_state_belief_multiplier", 2)
	if bmult > 0:
		var rival_belief: String = _rival_source_belief(gs, s, rival_pid)
		if rival_belief != "" and rival_belief != s.belief_id:
			power *= bmult
		if s.belief_id != "":
			power = power / bmult

	return 1 if power < 1 else power

# Garrison strength defending against a flip (§4.9): a base plus the combat
# strength of every non-civilian unit the owner has stationed in the city,
# doubled while the owner is at war with the rival's alliance.
static func _garrison_strength(gs, s, rival_pid: int, owner_pid: int, db) -> int:
	var total: int = db.get_constant("revolt_garrison_base", 1)
	for u in gs.units:
		if u.owner_player_id != owner_pid or u.x != s.x or u.y != s.y:
			continue
		if db.get_unit(u.unit_type_id).get("classification", "") == "civilian":
			continue
		total += int(db.get_unit(u.unit_type_id).get("base_strength", 0))

	var owner_alliance = gs.get_player_alliance(owner_pid)
	var rival_player = gs.get_player(rival_pid)
	if owner_alliance != null and rival_player != null \
			and owner_alliance.is_at_war_with(rival_player.alliance_id):
		total *= db.get_constant("revolt_war_garrison_multiplier", 2)
	return total

# Era number of a player for the revolt-power term (§4.9): the real era (§1, the
# highest era among the rival's researched techs), floored at 1 so even an Ancient
# rival exerts adjacency pressure. Wild/unknown players are era 1.
static func _era_number(gs, player_id: int, db) -> int:
	var p = gs.get_player(player_id)
	if p == null:
		return 1
	var era: int = Eras.player_era(p, db)
	return 1 if era < 1 else era

# The belief carried by the rival's nearest pressing settlement (used as its
# "state belief" for the amplifier); "" if it has none.
static func _rival_source_belief(gs, s, rival_pid: int) -> String:
	var best = null
	var best_dist: int = 0
	for other in gs.settlements:
		if other.owner_player_id != rival_pid:
			continue
		var d: int = gs.map.distance(s.x, s.y, other.x, other.y)
		if best == null or d < best_dist:
			best = other
			best_dist = d
	return "" if best == null else best.belief_id

# Transfer a flipped settlement to its captor. Mirrors the kept-capture transform
# in SimFacade._capture_city (§4.8): the queue/specialists/worked tiles are
# cleared, the Palace is stripped, siege HP is restored (the -1 "full" sentinel,
# normalised on next use), and the city enters occupation/revolt — but with no
# combat or attacking stack involved.
static func _apply_flip(s, captor_pid: int, db) -> void:
	s.owner_player_id = captor_pid
	s.structures.erase("palace")
	s.production_queue = []
	s.production_store = 0
	s.specialists = {}
	s.worked_tiles = []
	s.locked_tiles = []
	s.revolt_turns = db.get_constant("revolt_base_turns", 3) + s.population / 2
	s.revolt_progress = 0
	s.health = -1
	s.in_disorder = true
	s.garrison_turns = 0
