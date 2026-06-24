# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Tile
extends Reference

var x: int = 0
var y: int = 0

# Data table IDs
var terrain_id: String = ""
var feature_id: String = ""
var resource_id: String = ""
var improvement_id: String = ""
var transport_id: String = ""

# Rivers run *along tile borders*, not on the tile itself (§4.6). Each tile stores
# only its north and west edges; a tile's south edge is the north edge of the tile
# below it, and its east edge is the west edge of the tile to its right. So the
# full set of river borders on the map is covered without double-counting.
var river_n: bool = false   # river along this tile's northern border
var river_w: bool = false   # river along this tile's western border

# Cultural influence: player_id (int) -> accumulated influence (int)
var influence: Dictionary = {}

# Derived from influence by influence.gd
var owner_player_id: int = -1  # -1 = unowned

# Exploration: an undiscovered site that yields a reward when first entered (§9)
var has_discovery: bool = false

# Improvement construction progress (turns remaining)
var improvement_turns_left: int = 0

# Cottage-line growth (§8): turns the current improvement has been worked, used to
# advance cottage → hamlet → village → town once it reaches the improvement's
# `upgrade_turns`. Reset on upgrade or when the improvement changes.
var improvement_age: int = 0

# Entrenchment per-unit is on the unit; this tracks tile-level fortification count
# (not part of base spec but used for improvement tracking)

func _init(px: int = 0, py: int = 0) -> void:
	x = px
	y = py

func serialize() -> Dictionary:
	return {
		"x": x, "y": y,
		"terrain_id": terrain_id,
		"feature_id": feature_id,
		"resource_id": resource_id,
		"improvement_id": improvement_id,
		"transport_id": transport_id,
		"river_n": river_n,
		"river_w": river_w,
		"influence": influence.duplicate(),
		"owner_player_id": owner_player_id,
		"improvement_turns_left": improvement_turns_left,
		"improvement_age": improvement_age,
		"has_discovery": has_discovery
	}

static func deserialize(d: Dictionary):
	var t = load("res://src/world/tile.gd").new(int(d["x"]), int(d["y"]))
	t.terrain_id = str(d.get("terrain_id", ""))
	t.feature_id = str(d.get("feature_id", ""))
	t.resource_id = str(d.get("resource_id", ""))
	t.improvement_id = str(d.get("improvement_id", ""))
	t.transport_id = str(d.get("transport_id", ""))
	t.river_n = bool(d.get("river_n", false))
	t.river_w = bool(d.get("river_w", false))
	var inf = d.get("influence", {})
	for k in inf:
		t.influence[int(k)] = int(inf[k])
	t.owner_player_id = int(d.get("owner_player_id", -1))
	t.improvement_turns_left = int(d.get("improvement_turns_left", 0))
	t.improvement_age = int(d.get("improvement_age", 0))
	t.has_discovery = bool(d.get("has_discovery", false))
	return t
