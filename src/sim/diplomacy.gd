# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Diplomacy
extends Reference

# §7 AI diplomatic attitude & memory (Phase 7). Pure static: a player's attitude
# toward a rival is a neutral base plus live relational factors plus a decaying
# memory of the rival's past acts, clamped 0..100 and bucketed into five levels
# (furious → friendly). The attitude gates AI deal acceptance, war declaration, and
# assembly votes (PlayerAI / Assembly). All integer math; every magnitude lives in
# data/diplomacy.json. No RNG: attitude is a deterministic function of state.
#
# Memory lives on Player.diplo_memory: rival_player_id -> {kind: signed points}.
# record() accrues a kind's data value when the rival acts; decay() shrinks every
# entry toward zero each turn. memory is held by the *rememberer* about the rival.

# Attitude levels (indices into data attitude_levels).
const FURIOUS := 0
const ANNOYED := 1
const CAUTIOUS := 2
const PLEASED := 3
const FRIENDLY := 4

# ── Attitude ───────────────────────────────────────────────────────────────────

# The 0..100 attitude score `from_id` holds toward `to_id`: neutral base + live
# factors + decaying memory total, clamped.
static func attitude_score(gs, db, from_id: int, to_id: int) -> int:
	var dip: Dictionary = db.get_diplomacy()
	var score: int = int(dip.get("attitude_base", 50))
	score += _factor_score(gs, db, from_id, to_id)
	var from_p = gs.get_player(from_id)
	if from_p != null:
		score += memory_total(from_p, to_id)
	if score < 0:
		return 0
	if score > 100:
		return 100
	return score

# The attitude *level* (0=furious .. 4=friendly) `from_id` holds toward `to_id`.
# A score at or above attitude_thresholds[i-1] reaches level i; below the first
# threshold is the lowest level.
static func attitude_level(gs, db, from_id: int, to_id: int) -> int:
	var score: int = attitude_score(gs, db, from_id, to_id)
	var thresholds: Array = db.get_diplomacy().get("attitude_thresholds", [])
	var level: int = 0
	for i in range(thresholds.size()):
		if score >= int(thresholds[i]):
			level = i + 1
	return level

# The display name of an attitude level (e.g. "pleased"); "" for an out-of-range index.
static func level_name(db, level: int) -> String:
	var levels: Array = db.get_diplomacy().get("attitude_levels", [])
	if level < 0 or level >= levels.size():
		return ""
	return str(levels[level])

# Live relational factors (current war/peace, shared enemies, permanent alliance,
# an active deal, shared/clashing state religion). Independent of memory.
static func _factor_score(gs, db, from_id: int, to_id: int) -> int:
	var f: Dictionary = db.get_diplomacy().get("factors", {})
	var from_p = gs.get_player(from_id)
	var to_p = gs.get_player(to_id)
	if from_p == null or to_p == null:
		return 0
	var score: int = 0
	var fa = gs.get_alliance(from_p.alliance_id)
	var ta = gs.get_alliance(to_p.alliance_id)
	if fa != null and ta != null and fa.id != ta.id:
		if fa.is_at_war_with(ta.id):
			score += int(f.get("at_war", 0))
		else:
			# Shared war: a common third alliance both are fighting.
			for enemy in fa.at_war_with:
				if enemy != ta.id and enemy in ta.at_war_with:
					score += int(f.get("shared_war", 0))
					break
		if ta.id in fa.permanent_allies:
			score += int(f.get("permanent_ally", 0))
	# An active standing deal between the two alliances warms relations.
	if _have_active_deal(gs, from_p.alliance_id, to_p.alliance_id):
		score += int(f.get("active_deal", 0))
	# State religion: shared faith warms, clashing faith cools (both must have one).
	if from_p.state_religion != "" and to_p.state_religion != "":
		if from_p.state_religion == to_p.state_religion:
			score += int(f.get("shared_religion", 0))
		else:
			score += int(f.get("different_religion", 0))
	return score

static func _have_active_deal(gs, alliance_a: int, alliance_b: int) -> bool:
	for d in gs.deals:
		var x: int = int(d.get("a_alliance", -1))
		var y: int = int(d.get("b_alliance", -1))
		if (x == alliance_a and y == alliance_b) or (x == alliance_b and y == alliance_a):
			return true
	return false

# ── Memory ─────────────────────────────────────────────────────────────────────

# The signed sum of every remembered act `player` holds about `rival_id`.
static func memory_total(player, rival_id: int) -> int:
	var kinds: Dictionary = player.diplo_memory.get(rival_id, {})
	var total: int = 0
	for k in kinds:
		total += int(kinds[k])
	return total

# Accrue one act: player `from_id` remembers `to_id` doing `kind`. Adds the kind's
# data `value` (signed), capped in magnitude by memory_cap so a single relationship
# cannot dominate forever. Unknown kinds are ignored.
static func record(gs, db, from_id: int, to_id: int, kind: String) -> void:
	if from_id == to_id:
		return
	var spec: Dictionary = db.get_diplomacy().get("memory_kinds", {}).get(kind, {})
	if spec.empty():
		return
	var from_p = gs.get_player(from_id)
	if from_p == null:
		return
	if not from_p.diplo_memory.has(to_id):
		from_p.diplo_memory[to_id] = {}
	var kinds: Dictionary = from_p.diplo_memory[to_id]
	var cap: int = int(db.get_diplomacy().get("memory_cap", 120))
	var v: int = int(kinds.get(kind, 0)) + int(spec.get("value", 0))
	if v > cap:
		v = cap
	if v < -cap:
		v = -cap
	kinds[kind] = v

# Record the same act on every member of `to_alliance`, remembered by every member
# of `from_alliance` — used when an act is taken at the alliance level (declaring
# war, making peace). `to_alliance`'s members remember `from_alliance`'s actor(s).
static func record_alliance(gs, db, rememberers: Array, actors: Array, kind: String) -> void:
	for r in rememberers:
		for a in actors:
			record(gs, db, int(r), int(a), kind)

# Decay every player's memory toward zero by each kind's `decay` per turn; drop a
# kind once it reaches zero, and an empty rival entry with it. Called once per turn.
static func decay(gs, db) -> void:
	var mem_kinds: Dictionary = db.get_diplomacy().get("memory_kinds", {})
	for p in gs.players:
		var dead_rivals: Array = []
		for rival_id in p.diplo_memory:
			var kinds: Dictionary = p.diplo_memory[rival_id]
			var dead_kinds: Array = []
			for k in kinds:
				var step: int = int(mem_kinds.get(k, {}).get("decay", 1))
				var v: int = int(kinds[k])
				if v > 0:
					v = v - step if v - step > 0 else 0
				elif v < 0:
					v = v + step if v + step < 0 else 0
				if v == 0:
					dead_kinds.append(k)
				else:
					kinds[k] = v
			for k in dead_kinds:
				kinds.erase(k)
			if kinds.empty():
				dead_rivals.append(rival_id)
		for r in dead_rivals:
			p.diplo_memory.erase(r)
