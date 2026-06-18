# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Specialists
extends Reference

# Specialists subsystem reader (§6.5 / game-data §14.5). Specialists are a
# first-class data table (`data/specialists.json`): each type carries a per-head
# output vector, the great-person points it banks and of which type, and slot
# rules. This module is the single reader of that table — settlement output, the
# Great Person birth path, and the city screen all go through it so output,
# GP-point type, and slot ceilings are data-driven, not hard-coded.
#
# Pure rules: no Node/scene references; reads only DataDB + GameState aggregates.

# The six yield channels a specialist may contribute. The first three mirror the
# settlement's cached output (IDs.Output); science/culture/espionage route into
# the research, culture, and intelligence pipelines respectively.
const CHANNELS := ["food", "production", "commerce", "science", "culture", "espionage"]

# ── Per-type accessors ──────────────────────────────────────────────────────────

static func get_data(db: DataDB, stype: String) -> Dictionary:
	return db.get_specialist(stype)

static func output(db: DataDB, stype: String) -> Dictionary:
	return db.get_specialist(stype).get("output", {})

static func gp_type(db: DataDB, stype: String) -> String:
	return str(db.get_specialist(stype).get("gp_type", ""))

static func gp_points(db: DataDB, stype: String) -> int:
	return int(db.get_specialist(stype).get("gp_points", 0))

# The great-person unit a dominant pool of this specialist type births (§14.3),
# read from the table rather than scanning unit `generated_by` tags.
static func great_person_unit(db: DataDB, stype: String) -> String:
	return str(db.get_specialist(stype).get("great_person_unit", ""))

# ── Settlement output ───────────────────────────────────────────────────────────

# Sum the per-head output vectors of every specialist assigned in `s` into a
# channel→amount dictionary (every CHANNELS key present, zero if unused). Pure;
# the caller routes each channel into the matching pipeline.
static func settlement_output(db: DataDB, s: Settlement) -> Dictionary:
	var totals: Dictionary = {}
	for ch in CHANNELS:
		totals[ch] = 0
	for stype in s.specialists:
		var count: int = int(s.specialists[stype])
		if count <= 0:
			continue
		var vec: Dictionary = output(db, str(stype))
		for ch in vec:
			if totals.has(ch):
				totals[ch] += int(vec[ch]) * count
	return totals

# Convenience: a single channel's total across a settlement's specialists.
static func settlement_channel(db: DataDB, s: Settlement, channel: String) -> int:
	return int(settlement_output(db, s).get(channel, 0))

# Great-person points a settlement banks from its specialists this turn (§14.3),
# weighted by each type's `gp_points` (uniform 1 for working specialists).
static func settlement_gp_points(db: DataDB, s: Settlement) -> int:
	var pts: int = 0
	for stype in s.specialists:
		pts += int(s.specialists[stype]) * gp_points(db, str(stype))
	return pts

# ── Slots ───────────────────────────────────────────────────────────────────────

# Specialist slots of `stype` available in `s` for `player`: the type's
# `default_slots` plus each built structure's `specialist_slots[stype]`. A
# negative default (citizen) or the Caste System civic (`unlimited_specialists`)
# means unlimited, signalled by -1. Used to cap assignment and by the city screen.
static func slots_for(db: DataDB, s: Settlement, player: Player, stype: String) -> int:
	var base: int = int(db.get_specialist(stype).get("default_slots", 0))
	if base < 0:
		return -1
	if player != null and PolicyEffects.has_flag(player, db, "unlimited_specialists"):
		return -1
	var total: int = base
	for sid in s.structures:
		total += int(db.get_structure(sid).get("specialist_slots", {}).get(stype, 0))
	return total

# The working specialist types a player may assign in a city — non-great types
# that bank great-person points (so the GPP-less Citizen and the settled great_*
# super-specialists are excluded), in the table's declared order. This is the
# city screen's offered roster, replacing a hard-coded list.
static func assignable_types(db: DataDB) -> Array:
	var result: Array = []
	for stype in db.get_specialists():
		if stype == "_comment":
			continue
		var rec: Dictionary = db.get_specialists()[stype]
		if bool(rec.get("is_great", false)):
			continue
		if int(rec.get("gp_points", 0)) <= 0:
			continue
		result.append(stype)
	return result
