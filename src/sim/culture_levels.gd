# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name CultureLevels

# Culture levels (§15.4 / game-data §29.4, D2+C4): the reference geometric
# 5-level progression, per game pace. A settlement's culture LEVEL is how many
# thresholds its accumulated `culture_total` has passed (0 = poor .. 5 =
# legendary); its border ring is `level + 1` (a fresh city reaches ring 1 —
# its own tile plus the immediate neighbours). The per-pace threshold arrays
# live in `data/paces.json` (`culture_level_thresholds`); the per-level city
# defence percentages and the level names live in `data/constants.json`
# (`culture_level_defence`, `culture_level_names`). Pure static; no state.

# The threshold array for a pace, int-coerced (JSON parses numbers as floats).
static func thresholds(db: DataDB, pace_id: String) -> Array:
	var out: Array = []
	for t in db.get_pace(pace_id).get("culture_level_thresholds", []):
		out.append(int(t))
	return out

# Culture level for an accumulated culture total: the number of pace thresholds
# passed (0..thresholds.size()).
static func level_for(db: DataDB, pace_id: String, culture_total: int) -> int:
	var level: int = 0
	for t in thresholds(db, pace_id):
		if culture_total >= t:
			level += 1
		else:
			break
	return level

# Intrinsic city-defence percentage granted by a culture level (§15.4):
# level 0 grants nothing; levels 1..N read `culture_level_defence` (a level
# beyond the table — e.g. a pre-D2 save's ring — clamps to the top entry).
static func defence_pct(db: DataDB, level: int) -> int:
	var arr: Array = db.constants.get("culture_level_defence", [])
	if level <= 0 or arr.empty():
		return 0
	var idx: int = level - 1
	if idx >= arr.size():
		idx = arr.size() - 1
	return int(arr[idx])

# The top (legendary) threshold for a pace — the cultural-victory requirement
# (§15.3 recalibrated by D2: the per-pace column already carries the reference
# speed scaling, so no further stretch applies). 0 when the table is missing.
static func legendary_threshold(db: DataDB, pace_id: String) -> int:
	var arr: Array = thresholds(db, pace_id)
	return arr[arr.size() - 1] if arr.size() > 0 else 0

# Display name for a level ("Poor" .. "Legendary"); clamps out-of-range levels.
static func level_name(db: DataDB, level: int) -> String:
	var names: Array = db.constants.get("culture_level_names", [])
	if names.empty():
		return str(level)
	var idx: int = level
	if idx < 0:
		idx = 0
	if idx >= names.size():
		idx = names.size() - 1
	return str(names[idx])
