# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Vassalage
extends Reference

# §7 Team/vassalage parity (Phase 8). Pure static, layered on the existing
# subordination scaffolding (Alliance.is_subordinate_to / tributaries, the
# voluntary SET_SUBORDINATION command, and TurnEngine tribute collection). This
# module adds the war-driven half of the model:
#
#  • Capitulation — a *crushed* alliance (at war with a far stronger enemy, its
#    military power at or below vassal_capitulation_power_pct% of that enemy's)
#    may submit to its conqueror. The actual state change reuses the
#    subordination path; this module only supplies the eligibility gate, which
#    PlayerAI consults (and the diplomacy screen surfaces) before submitting.
#  • Liberation — a vassal whose military power has recovered to at least
#    vassal_liberation_power_pct% of its overlord's breaks free automatically.
#    The dead band between the two percentages (40..70) gives hysteresis, so a
#    freshly-capitulated vassal does not immediately re-liberate.
#  • Shared war & peace — each world step a vassal's external wars are re-synced
#    to its overlord's, so a vassal is dragged into every war the master joins
#    and released from every war the master ends (it cannot make a separate
#    peace). The war with the overlord itself is, of course, already over.
#
# All integer math, no RNG: every outcome is a deterministic function of state.
# Thresholds live in data/constants.json. No new serialized state — the
# relationship persists through Alliance.is_subordinate_to / tributaries, already
# covered by the save/load determinism gate.

# Summed military power of an alliance: each member's land combat units weighted
# by effective strength × current health (the same proxy PlayerAI uses for its
# war-power margin, so capitulation and the AI's attack appetite read one scale).
static func alliance_power(gs, alliance) -> int:
	if alliance == null:
		return 0
	var total: int = 0
	for u in gs.units:
		if u.owner_player_id in alliance.member_player_ids:
			if _is_military_unit(gs.db.get_unit(u.unit_type_id)):
				total += u.effective_strength(gs.db, true, {}, {}, "", false, 0) * u.health
	return total

# A land combat unit (has strength, land domain, not civilian/animal/great person).
# Mirrors PlayerAI._is_military_unit so power proxies agree.
static func _is_military_unit(udata: Dictionary) -> bool:
	var cls: String = str(udata.get("classification", ""))
	if cls == "civilian" or cls == "animal" or cls == "great_person":
		return false
	if str(udata.get("domain", "land")) != "land":
		return false
	return int(udata.get("base_strength", 0)) > 0

# Whether `sub` is being crushed by `overlord`: the two are at war and `sub`'s
# military power is at or below vassal_capitulation_power_pct% of `overlord`'s.
# Used as the gate before a crushed alliance submits (capitulation).
static func is_crushed_by(gs, db, sub, overlord) -> bool:
	if sub == null or overlord == null or sub.id == overlord.id:
		return false
	if not sub.is_at_war_with(overlord.id):
		return false
	var pct: int = db.get_constant("vassal_capitulation_power_pct", 40)
	var sub_power: int = alliance_power(gs, sub)
	var over_power: int = alliance_power(gs, overlord)
	# sub_power / over_power <= pct/100, cross-multiplied to stay integer.
	return sub_power * 100 <= over_power * pct

# The strongest enemy alliance currently crushing `sub` (the natural overlord to
# capitulate to), or null if `sub` is not being crushed by anyone. Ties resolve
# to the lowest alliance id for determinism.
static func crushing_overlord(gs, db, sub):
	if sub == null:
		return null
	var best = null
	var best_power: int = -1
	for enemy_aid in sub.at_war_with:
		var enemy = gs.get_alliance(int(enemy_aid))
		if enemy == null:
			continue
		if not is_crushed_by(gs, db, sub, enemy):
			continue
		var ep: int = alliance_power(gs, enemy)
		if ep > best_power or (ep == best_power and (best == null or enemy.id < best.id)):
			best = enemy
			best_power = ep
	return best

# Whether a subordinate alliance has recovered enough to break free: its military
# power is at least vassal_liberation_power_pct% of its overlord's. An overlord
# with no military can hold no vassals (any positive recovery liberates).
static func can_liberate(gs, db, sub) -> bool:
	if sub == null or sub.is_subordinate_to < 0:
		return false
	var overlord = gs.get_alliance(sub.is_subordinate_to)
	if overlord == null:
		return true
	var pct: int = db.get_constant("vassal_liberation_power_pct", 70)
	var sub_power: int = alliance_power(gs, sub)
	var over_power: int = alliance_power(gs, overlord)
	return sub_power * 100 >= over_power * pct

# Sever the subordination between `sub` and its overlord (liberation / release).
# Clears is_subordinate_to and drops `sub` from the overlord's tributary list.
# Does not touch wars — liberation is a peaceful break, leaving both at peace.
static func liberate(gs, sub) -> void:
	if sub == null or sub.is_subordinate_to < 0:
		return
	var overlord = gs.get_alliance(sub.is_subordinate_to)
	if overlord != null:
		overlord.tributaries.erase(sub.id)
	sub.is_subordinate_to = -1

# Re-sync a vassal's external wars to its overlord's: inherit every war the
# overlord fights against a third party, and drop any third-party war the overlord
# is not in (shared war and shared peace). The overlord/vassal pair is never at war
# with itself, so the overlord's own id is skipped on both sides.
static func sync_vassal_wars(gs, sub) -> void:
	if sub == null or sub.is_subordinate_to < 0:
		return
	var overlord = gs.get_alliance(sub.is_subordinate_to)
	if overlord == null:
		return
	# Inherit the overlord's wars (against third parties).
	for enemy_aid in overlord.at_war_with:
		var eid: int = int(enemy_aid)
		if eid == sub.id:
			continue
		if not (eid in sub.at_war_with):
			sub.at_war_with.append(eid)
		var enemy = gs.get_alliance(eid)
		if enemy != null and not (sub.id in enemy.at_war_with):
			enemy.at_war_with.append(sub.id)
	# Drop third-party wars the overlord does not share (shared peace).
	var drop: Array = []
	for enemy_aid in sub.at_war_with:
		var eid: int = int(enemy_aid)
		if eid == overlord.id:
			continue
		if not (eid in overlord.at_war_with):
			drop.append(eid)
	for eid in drop:
		sub.at_war_with.erase(eid)
		var enemy = gs.get_alliance(eid)
		if enemy != null:
			enemy.at_war_with.erase(sub.id)

# Once-per-world-step vassalage maintenance (§7): keep every vassal's wars in step
# with its overlord, then free any vassal strong enough to break away. Liberation
# notices ride gs.pending_deal_events (the shared diplomacy surfacing queue), so the
# facade turns them into message-log notifications. Deterministic, no RNG; vassals
# are processed in alliance order.
static func world_tick(gs, db) -> void:
	for sub in gs.alliances:
		if sub.is_subordinate_to < 0:
			continue
		sync_vassal_wars(gs, sub)
	# Liberation in a second pass so war-sync is settled first.
	for sub in gs.alliances:
		if sub.is_subordinate_to < 0:
			continue
		if can_liberate(gs, db, sub):
			var overlord_id: int = sub.is_subordinate_to
			liberate(gs, sub)
			gs.pending_deal_events.append({
				"kind": "vassal_liberated",
				"alliance_id": sub.id,
				"overlord_alliance_id": overlord_id
			})
