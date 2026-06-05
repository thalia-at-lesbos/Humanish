# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://addons/gut/test.gd"

# Regions: domain-connectivity flood fill (land vs sea regions) and same-owner
# transport-linked supply groups.

func _db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

func _map(w, h):
	var m = load("res://src/world/world_map.gd").new()
	m.init(w, h, false, false)
	return m

func _distinct_ids(region_map):
	var ids := {}
	for k in region_map:
		ids[region_map[k]] = true
	return ids.size()

# ── Region labelling ─────────────────────────────────────────────────────────

func test_single_landmass_is_one_region() -> void:
	var m = _map(5, 5)
	for tile in m.all_tiles():
		tile.terrain_id = "grassland"
	assert_eq(_distinct_ids(Regions.compute_regions(m, _db())), 1,
		"All grassland tiles form one region")

func test_land_and_sea_are_separate_regions() -> void:
	var m = _map(4, 2)
	for x in range(4):
		m.get_tile(x, 0).terrain_id = "grassland"
		m.get_tile(x, 1).terrain_id = "coast"
	assert_eq(_distinct_ids(Regions.compute_regions(m, _db())), 2,
		"Land and sea form 2 separate regions")

# ── Supply groups ────────────────────────────────────────────────────────────

func test_supply_group_links_owned_road_tiles() -> void:
	var m = _map(5, 5)
	for tile in m.all_tiles():
		tile.terrain_id = "grassland"
	# A contiguous owned road from (1,2) to (3,2) forms one supply group.
	for x in range(1, 4):
		var t = m.get_tile(x, 2)
		t.owner_player_id = 1
		t.improvement_id = "road"
	var groups: Dictionary = Regions.compute_supply_groups(m, _db())
	assert_eq(groups.size(), 3, "All three connected road tiles are grouped")
	var gid = groups.get("1,2", -1)
	assert_eq(groups.get("3,2", -2), gid, "Both ends share the same supply group id")

func test_supply_group_excludes_untransported_tiles() -> void:
	var m = _map(5, 5)
	for tile in m.all_tiles():
		tile.terrain_id = "grassland"
	# Owned but with no road/transport — not part of any supply group.
	var plain = m.get_tile(2, 2)
	plain.owner_player_id = 1
	var groups: Dictionary = Regions.compute_supply_groups(m, _db())
	assert_false(groups.has("2,2"),
		"An owned tile without road/transport joins no supply group")

func test_supply_group_split_by_ownership() -> void:
	var m = _map(6, 3)
	for tile in m.all_tiles():
		tile.terrain_id = "grassland"
	# Two roads of different owners, adjacent but not connected across the border.
	m.get_tile(1, 1).owner_player_id = 1; m.get_tile(1, 1).improvement_id = "road"
	m.get_tile(2, 1).owner_player_id = 1; m.get_tile(2, 1).improvement_id = "road"
	m.get_tile(3, 1).owner_player_id = 2; m.get_tile(3, 1).improvement_id = "road"
	m.get_tile(4, 1).owner_player_id = 2; m.get_tile(4, 1).improvement_id = "road"
	var groups: Dictionary = Regions.compute_supply_groups(m, _db())
	assert_ne(groups.get("2,1", -1), groups.get("3,1", -2),
		"Adjacent roads owned by different players are different supply groups")
