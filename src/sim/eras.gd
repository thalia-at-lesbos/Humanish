# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Eras

# §1 Ages/eras. Pure static reader over data/ages.json (loaded into db.ages) and
# the per-tech "era" tag in data/technologies.json. A player's era is *derived*:
# it is the highest era index among the techs they have researched (Ancient/0 when
# they know none). Nothing here holds state — Player.era is only a cache used to
# detect advancement (see Eras.refresh); every mechanic that needs the era reads it
# live through player_era() so it can never go stale.
#
# Eras feed three rule sites today (all provisional, see game-rules.md §17):
#   • growth thresholds scale by the player's era (growth_threshold_scale)
#   • the §4.9 cultural-revolt power term scales by the rival's era number
#   • presentation/AI read the era for display and labelling
# Unit/structure availability is *already* era-gated transitively, because each is
# gated on a tech and every tech carries an era; era_of_tech/era_of_unit expose
# that mapping for labelling without adding a second, divergent gate.

# Era index of a tech via its "era" tag → the matching age's "index" (0 if absent).
static func era_of_tech(tech_id: String, db) -> int:
	var tech: Dictionary = db.get_technology(tech_id)
	if tech.empty():
		return 0
	return _index_of_age(str(tech.get("era", "")), db)

# Era index a unit becomes available in: the era of its required tech (0 if the
# unit needs no tech — e.g. the starting Warrior/Settler).
static func era_of_unit(unit_id: String, db) -> int:
	var u: Dictionary = db.get_unit(unit_id)
	var req = u.get("tech_required", null)
	if req == null or str(req) == "":
		return 0
	return era_of_tech(str(req), db)

# Era index a structure becomes available in: its own "era" tag if present, else
# the era of its required tech.
static func era_of_structure(struct_id: String, db) -> int:
	var s: Dictionary = db.get_structure(struct_id)
	if s.has("era"):
		var by_tag: int = _index_of_age(str(s.get("era", "")), db)
		if by_tag > 0:
			return by_tag
	var req = s.get("tech_required", null)
	if req == null or str(req) == "":
		return 0
	return era_of_tech(str(req), db)

# A player's current era: the highest era index over the techs they know. A player
# with no technologies (or an unknown/wild player) is in the Ancient era (0).
static func player_era(player, db) -> int:
	if player == null:
		return 0
	var best: int = 0
	for tech_id in player.technologies:
		var e: int = era_of_tech(str(tech_id), db)
		if e > best:
			best = e
	return best

# Recompute a player's era and queue an advancement record if it rose. Returns the
# number of era steps gained this call (0 = no change). Idempotent: the notification
# fires once per transition because player.era is bumped to the new value here.
# gs may be null (e.g. one-off setup init) to update the cache without queuing.
static func refresh(player, db, gs = null) -> int:
	if player == null:
		return 0
	var now: int = player_era(player, db)
	var prev: int = int(player.era)
	if now <= prev:
		return 0
	player.era = now
	if gs != null:
		gs.pending_era_advances.append({
			"player_id": player.id, "from": prev, "to": now
		})
	return now - prev

# ── Age-table lookups (data/ages.json) ────────────────────────────────────────

# Name of an era by index ("" if the index has no matching age).
static func era_name(index: int, db) -> String:
	var age: Dictionary = age_at(index, db)
	return str(age.get("name", ""))

# Id of an era by index ("" if none).
static func era_id(index: int, db) -> String:
	var age: Dictionary = age_at(index, db)
	return str(age.get("id", ""))

# growth_threshold_scale for an era index, as an integer percent (default 100 when
# the age is missing the field). Higher → slower growth in later eras.
static func growth_threshold_scale(index: int, db) -> int:
	var age: Dictionary = age_at(index, db)
	return int(age.get("growth_threshold_scale", 100))

# Highest era index defined in data (e.g. 6 for Future in the shipped table).
static func max_index(db) -> int:
	var best: int = 0
	for age_id in db.ages:
		var idx: int = int(db.ages[age_id].get("index", 0))
		if idx > best:
			best = idx
	return best

# The age record at a given index ({} if none).
static func age_at(index: int, db):
	for age_id in db.ages:
		if int(db.ages[age_id].get("index", -1)) == index:
			return db.ages[age_id]
	return {}

# ── Internal ──────────────────────────────────────────────────────────────────

# Index of an age looked up by its id ("ancient" → 0). 0 when the id is unknown so
# an untagged or mistyped era degrades to Ancient rather than erroring.
static func _index_of_age(age_id: String, db) -> int:
	if age_id == "" or not db.ages.has(age_id):
		return 0
	return int(db.ages[age_id].get("index", 0))
