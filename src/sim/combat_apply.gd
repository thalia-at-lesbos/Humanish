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

	# Non-combat unit capture (§15.21 / M6): a unit carrying a `capture` class
	# that dies while its tile is overrun (the attacker survives AND advances —
	# not a city-tile defence or an air strike) is captured instead of killed:
	# the tile-taker receives a fresh unit of the capture class (settler → worker
	# demotes). Wild forces never capture — the unit simply dies.
	var capture_class: String = ""
	if advance and result["attacker_survived"] and not result["defender_survived"] \
			and attacker.owner_player_id >= 0 \
			and not attacker.is_wild and not attacker.is_animal:
		capture_class = str(gs.db.get_unit(defender.unit_type_id).get("capture", ""))

	# War weariness (§15.8): each side's alliance accrues per-event points
	# against the other when a unit dies — the loser more than the victor, an
	# attacking loss more than a defending one (reference weights, §4.5/§7). A
	# capture swaps in the C8 capture weights (unit captured 2 / captor 1).
	if not result["defender_survived"] and result["attacker_survived"]:
		if capture_class != "":
			accrue_war_fatigue(gs, defender.owner_player_id, attacker.owner_player_id,
				"war_weariness_unit_captured")
			accrue_war_fatigue(gs, attacker.owner_player_id, defender.owner_player_id,
				"war_weariness_captured_unit")
		else:
			accrue_war_fatigue(gs, defender.owner_player_id, attacker.owner_player_id,
				"war_weariness_unit_killed_defending")
			accrue_war_fatigue(gs, attacker.owner_player_id, defender.owner_player_id,
				"war_weariness_killed_unit_attacking")
	elif not result["attacker_survived"] and result["defender_survived"]:
		accrue_war_fatigue(gs, attacker.owner_player_id, defender.owner_player_id,
			"war_weariness_unit_killed_attacking")
		accrue_war_fatigue(gs, defender.owner_player_id, attacker.owner_player_id,
			"war_weariness_killed_unit_defending")

	if not result["attacker_survived"]:
		Stack.remove_unit(gs.units, attacker.id)
	if not result["defender_survived"]:
		Stack.remove_unit(gs.units, defender.id)
		# Attacker may advance (bombard/air strikes pass advance = false)
		if result["attacker_survived"] and advance:
			attacker.x = defender.x
			attacker.y = defender.y

	# Spillover to stacked units (siege attackers). Each stacked unit's summed
	# promotion `collateral_damage_protection` (W5, §29.16: the Drill line, 20
	# each) cuts the spillover it takes.
	if result["spillover_damage"] > 0:
		for u in Stack.at(gs.units, defender.x, defender.y, defender.owner_player_id):
			if u.id != defender.id:
				var spill: int = spillover_taken(gs, u, int(result["spillover_damage"]))
				if spill <= 0:
					continue
				u.health = max(0, u.health - spill)
				if u.health <= 0:
					Stack.remove_unit(gs.units, u.id)

	# Flanking: fast attackers damage part of the defeated defender's stack (§5.4).
	if result["flanking_damage"] > 0:
		for u in Stack.at(gs.units, defender.x, defender.y, defender.owner_player_id):
			if u.id != defender.id:
				u.health = max(0, u.health - int(result["flanking_damage"]))
				if u.health <= 0:
					Stack.remove_unit(gs.units, u.id)

	# Missiles cannot defend (§15.7 / D3): a victorious attacker advancing onto
	# the defender's tile destroys any hostile missiles stranded there without a
	# surviving defender.
	if advance and result["attacker_survived"] and not result["defender_survived"]:
		destroy_stranded_missiles(gs, attacker.x, attacker.y, attacker.owner_player_id)

	# §15.21 (M6): hand the tile-taker the captured unit — fresh (full health,
	# no XP/promotions carried), spent for this turn, on the overrun tile. The
	# result dict carries the id so the facade can surface it (unit_created).
	if capture_class != "":
		var cdata: Dictionary = gs.db.get_unit(capture_class)
		var cu := Unit.new()
		cu.id = gs.next_unit_id()
		cu.unit_type_id = capture_class
		cu.owner_player_id = attacker.owner_player_id
		cu.x = defender.x
		cu.y = defender.y
		cu.base_strength = int(cdata.get("base_strength", 0))
		cu.movement_total = int(cdata.get("movement", 120))
		cu.movement_left = 0
		cu.has_moved = true
		gs.units.append(cu)
		result["captured_unit_id"] = cu.id
		result["captured_unit_type"] = capture_class

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

# Collateral/spillover damage a stacked unit actually takes (W5, §29.16 / 0j
# cross-check): the unit's promotions' `collateral_damage_protection` values SUM
# (Drill II/III/IV carry 20 each, so a Drill IV unit holds 60) and cut the
# damage taken — damage × (100 − protection) / 100, truncating; a sum of 100 or
# more is full immunity. Integer math only.
static func spillover_taken(gs, u: Unit, damage: int) -> int:
	var protection: int = 0
	for pid in u.promotions:
		protection += int(gs.db.get_promotion(pid).get("collateral_damage_protection", 0))
	if protection <= 0:
		return damage
	if protection >= 100:
		return 0
	return damage * (100 - protection) / 100

# Missiles cannot defend (§15.7 / D3), so a missile left with no surviving
# defender on a tile taken by an enemy — a captured/razed city, or open ground an
# attacker advanced onto — is destroyed, not captured. Hostile means at war with
# the captor (or either side wild). No-op while any combat defender still stands
# there. Returns the removed unit ids so callers can surface them.
static func destroy_stranded_missiles(gs, x: int, y: int, captor_pid: int) -> Array:
	var removed: Array = []
	if Stack.get_defender(gs.units, x, y, captor_pid, gs) != null:
		return removed
	for u in Stack.at(gs.units, x, y):
		if u.owner_player_id == captor_pid:
			continue
		if str(gs.db.get_unit(u.unit_type_id).get("classification", "")) != "missile":
			continue
		if u.owner_player_id != -2 and captor_pid != -2 \
				and not gs.are_at_war(captor_pid, u.owner_player_id):
			continue
		removed.append(u.id)
	for uid in removed:
		Stack.remove_unit(gs.units, uid)
	return removed

# Grant promotions for each experience level newly reached (§5.5). Levels are the
# data-defined experience_thresholds; each new level awards one eligible promotion.
# XP actually awarded to `unit` for this fight. Against an **animal** (§9.3) the
# gain is clamped so the unit's *lifetime* animal XP never exceeds the cap — beyond
# it, hunting animals yields nothing. Non-animal fights award the full gain.
static func _award_xp(gs, unit: Unit, opponent: Unit, gain: int) -> int:
	if gain <= 0 or not opponent.is_animal:
		return gain if gain > 0 else 0
	var cap: int = gs.db.get_constant("animal_xp_lifetime_cap", 5)
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
			and u.experience >= _xp_needed(gs, u, int(thresholds[u.experience_level + 1])):
		u.experience_level += 1
		var promo: String = pick_promotion(gs, u)
		if promo == "":
			break  # nothing eligible left; stop awarding
		u.promotions.append(promo)

# XP needed to reach the next level for `u`: the data threshold reduced by the
# owner's trait `promotion_xp_reduction` percentages (Charismatic: the reference
# "-25% XP needed for next promotion" model, A9). Summed across traits, clamped
# to 100; integer math (truncating scale, like every percent in the engine).
static func _xp_needed(gs, u: Unit, base: int) -> int:
	var player = gs.get_player(u.owner_player_id)
	if player == null:
		return base
	var reduction: int = 0
	for trait_id in player.traits:
		reduction += int(gs.db.get_trait(trait_id).get("promotion_xp_reduction", 0))
	if reduction <= 0:
		return base
	if reduction > 100:
		reduction = 100
	return Fixed.scale(base, 100 - reduction)

# First promotion (in data order) whose prereqs are met, that applies to this
# unit's class/domain, and that it does not already hold. "" if none qualifies.
# A `granted_only` promotion (the reference Great-General `leader` marker) is
# never picked from XP — it is only appended by an effect (§14.1 attach).
static func pick_promotion(gs, u: Unit) -> String:
	var db: DataDB = gs.db
	var udata: Dictionary = db.get_unit(u.unit_type_id)
	var cls: String = str(udata.get("classification", ""))
	var dom: String = str(udata.get("domain", "land"))
	for pid in db.promotions:
		if pid in u.promotions:
			continue
		var promo: Dictionary = db.promotions[pid]
		if bool(promo.get("granted_only", false)):
			continue
		if not promo_applies(promo, cls, dom):
			continue
		var ok: bool = true
		for pr in promo.get("prereqs", []):
			if not (pr in u.promotions):
				ok = false
				break
		if ok:
			return pid
	return ""

# Whether a promotion's `applies_to` covers a unit of classification `cls` /
# domain `dom`. Accepts the single-string form ("all" / one class / one domain)
# and the list form (any listed class or domain matches), so multi-class
# reference promotions (Ambush, Charge, Mobility) can carry their real rosters.
static func promo_applies(promo: Dictionary, cls: String, dom: String) -> bool:
	var applies = promo.get("applies_to", "all")
	if typeof(applies) == TYPE_ARRAY:
		return (cls in applies) or (dom in applies)
	var a: String = str(applies)
	return a == "all" or a == cls or a == dom

# §15.8 war weariness: `side_pid`'s alliance accrues the data-defined per-event
# weight `key` (× `war_weariness_multiplier`) against `enemy_pid`'s alliance.
# Reduced by the forced-war modifier (−50%) when the war was declared on `side`
# (alliance.forced_wars). Shared by every event site — unit combat (both the
# facade and WildAI paths route through apply_unit_result above), city conquest
# (SimFacade._city_falls) and nuclear strikes (Nuclear.detonate) — so all paths
# write state identically. Wild forces (no player/alliance) are skipped, as is
# a side enjoying a Golden Age (§14.4: weariness is frozen).
static func accrue_war_fatigue(gs, side_pid: int, enemy_pid: int, key: String) -> void:
	var sp: Player = gs.get_player(side_pid)
	var ep: Player = gs.get_player(enemy_pid)
	if sp == null or ep == null or sp.alliance_id == ep.alliance_id:
		return
	var sa: Alliance = gs.get_alliance(sp.alliance_id)
	if sa == null:
		return
	# War Weariness does not increase for a player enjoying a Golden Age (§14.4).
	if GreatPeople.is_in_golden_age(sp):
		return
	var amt: int = gs.db.get_constant(key, 0) \
		* gs.db.get_constant("war_weariness_multiplier", 2)
	if ep.alliance_id in sa.forced_wars:
		amt = amt * (100 + gs.db.get_constant("war_weariness_forced_modifier", -50)) / 100
	# Enemy-side amplification (§15: `enemy_war_weariness`, Statue of Zeus +100%):
	# standing structures in the ENEMY's cities raise this side's accrual against
	# them by the summed percentage while the war lasts (a captured or razed
	# wonder stops counting because the scan follows city ownership). Truncates.
	var enemy_pct: int = 0
	for es in gs.settlements:
		if es.owner_player_id != ep.id:
			continue
		for e_struct_id in es.structures:
			if ep.structure_obsolete(gs.db, e_struct_id):
				continue  # an obsolete wonder stops amplifying (§15.17)
			enemy_pct += int(gs.db.get_structure(e_struct_id).get("effects", {}) \
				.get("enemy_war_weariness", 0))
	if enemy_pct > 0:
		amt = amt * (100 + enemy_pct) / 100
	if amt <= 0:
		return
	sa.war_fatigue[ep.alliance_id] = int(sa.war_fatigue.get(ep.alliance_id, 0)) + amt
