# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Projects

# §15.7 non-spaceship projects (C5): SDI and The Internet. Pure static reader of
# data/projects.json — the single place per-project `effects` are aggregated,
# mirroring PolicyEffects for civics. A project entry either carries
# `win_condition: "endgame_project"` (a spaceship stage, counted per alliance in
# gs.endgame_project_parts — counted per part type since M4, §15.16) or is an
# **effects project**: once built it is recorded on `Player.projects` and its
# `effects` dictionary applies to that player for the rest of the game.
#
# Instance limits come from the entry's `instances` field:
#   "player" — one per player (the default; SDI),
#   "world"  — one per game (The Internet).
# `requires_wonder_any: <structure_id>` gates buildability on that wonder having
# been completed by ANY player (SDI needs the Manhattan Project built by anyone).

# True when this projects.json entry is a spaceship stage (the endgame model).
static func is_endgame(proj: Dictionary) -> bool:
	return str(proj.get("win_condition", "")) == "endgame_project"

# ── §15.16 spaceship parts (M4) ───────────────────────────────────────────────
# The space race counts parts PER TYPE (gs.endgame_project_parts:
# alliance_id -> {project_id: count}); each type is capped at its data
# `count_needed` (casing ×5, thrusters ×5, engines ×2, four single-instance
# parts — 16 at full build), so duplicate parts of a filled type no longer
# advance the race. One of every type launches the ship (the reference minimum
# threshold is 1 for all seven types); WinConditions runs the arrival countdown.

# Full instances the race counts for this part type (§29.14 Full-count column).
static func count_needed(proj: Dictionary) -> int:
	var n: int = int(proj.get("count_needed", 1))
	return n if n > 0 else 1

# Every endgame (spaceship) project id in ascending `stage` order — the
# deterministic iteration order for launch/delay/arrival math. (Sorted via an
# explicit int key list: Godot 3's Array-of-Array sort() is not lexicographic.)
static func endgame_ids(db: DataDB) -> Array:
	var by_stage: Dictionary = {}
	for pid in db.projects:
		var proj: Dictionary = db.projects[pid]
		if is_endgame(proj):
			var st: int = int(proj.get("stage", 0))
			if not by_stage.has(st):
				by_stage[st] = []
			by_stage[st].append(str(pid))
	var stages: Array = by_stage.keys()
	stages.sort()
	var out: Array = []
	for st in stages:
		for pid in by_stage[st]:
			out.append(pid)
	return out

# The alliance's per-type part tally ({} when it has built nothing).
static func parts_tally(gs, alliance_id: int) -> Dictionary:
	return gs.endgame_project_parts.get(alliance_id, {})

# Count of `pid` parts the tally holds, capped at the type's full count.
static func parts_of(db: DataDB, tally: Dictionary, pid: String) -> int:
	var have: int = int(tally.get(pid, 0))
	var need: int = count_needed(db.projects.get(pid, {}))
	return have if have < need else need

# Launch readiness (§15.16): every part type at its minimum threshold of one.
static func launch_ready(db: DataDB, tally: Dictionary) -> bool:
	var ids: Array = endgame_ids(db)
	if ids.empty():
		return false
	for pid in ids:
		if int(tally.get(pid, 0)) < 1:
			return false
	return true

# True when `player` has completed the effects project `proj_id`.
static func has_project(player, proj_id: String) -> bool:
	return player != null and (proj_id in player.projects)

# True when any player has completed the effects project `proj_id`.
static func completed_by_anyone(gs, proj_id: String) -> bool:
	for p in gs.players:
		if proj_id in p.projects:
			return true
	return false

# Sum of an integer effect key over the player's completed effects projects —
# the single read path for project effects (like PolicyEffects.sum_int for
# civics). 0 for a player with no projects.
static func effect_int(player, db: DataDB, key: String) -> int:
	if player == null:
		return 0
	var total: int = 0
	for pid in player.projects:
		total += int(db.projects.get(pid, {}).get("effects", {}).get(key, 0))
	return total

# Whether `player` may queue/complete the effects project `proj_id` right now:
# the entry must exist, its tech must be researched, its instance limit must not
# be exhausted (per-player: not already owned; per-world: not owned by anyone),
# and any `requires_wonder_any` wonder must stand somewhere in the world.
# Endgame (spaceship) projects are NOT judged here — they keep their own model.
static func can_build(gs, player, proj_id: String) -> bool:
	var proj: Dictionary = gs.db.projects.get(proj_id, {})
	if proj.empty() or is_endgame(proj) or player == null:
		return false
	var tech = proj.get("tech_required", null)
	if tech != null and str(tech) != "" and not player.has_tech(str(tech)):
		return false
	if not grantable(gs, player, proj_id):
		return false
	var wonder: String = str(proj.get("requires_wonder_any", ""))
	if wonder != "" and not _wonder_built_by_anyone(gs, wonder):
		return false
	return true

# Instance-limit check alone: whether completing `proj_id` now would still grant
# it to `player`. Used at completion time so a world-unique project finished a
# turn after a rival's grants nothing (the hammers are lost, as in the reference).
static func grantable(gs, player, proj_id: String) -> bool:
	if has_project(player, proj_id):
		return false
	var proj: Dictionary = gs.db.projects.get(proj_id, {})
	if str(proj.get("instances", "player")) == "world" \
			and completed_by_anyone(gs, proj_id):
		return false
	return true

static func _wonder_built_by_anyone(gs, structure_id: String) -> bool:
	for s in gs.settlements:
		if s.has_structure(structure_id):
			return true
	return false
