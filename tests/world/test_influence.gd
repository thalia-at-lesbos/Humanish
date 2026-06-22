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

# Influence (§4.7): the founding claim, per-ring culture spread, and ownership
# resolution (the highest accumulated influence wins a tile).

func _db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

func _grass_map(w, h):
	var m = load("res://src/world/world_map.gd").new()
	m.init(w, h, false, false)
	for tile in m.all_tiles():
		tile.terrain_id = "grassland"
	return m

func test_found_claim_sets_owner() -> void:
	var m = _grass_map(10, 10)
	Influence.found_claim(m, 5, 5, 0, 1, 20)
	assert_eq(m.get_tile(5, 5).owner_player_id, 0, "Center tile owned after founding")

func test_spread_increases_influence() -> void:
	var m = _grass_map(10, 10)
	var tile = m.get_tile(5, 5)
	var before: int = tile.influence.get(0, 0)
	Influence.spread(m, 5, 5, 10, 2, 0, _db())
	assert_gt(tile.influence.get(0, 0), before, "Spreading culture increases influence")

func test_resolve_ownership_max_wins() -> void:
	var m = _grass_map(5, 5)
	var tile = m.get_tile(2, 2)
	tile.influence[0] = 5
	tile.influence[1] = 10
	Influence.resolve_ownership(m)
	assert_eq(tile.owner_player_id, 1, "Player with most influence owns the tile")

func test_wild_owner_claims_tile() -> void:
	# Wild forces (owner -2) own a tile they alone have influence on, so a Raider
	# Camp shows cultural borders just like a civ city does (§4.7).
	var m = _grass_map(5, 5)
	var tile = m.get_tile(2, 2)
	tile.influence[-2] = 7
	Influence.resolve_ownership(m)
	assert_eq(tile.owner_player_id, -2, "Wild forces own a tile they alone influence")

func test_civ_outcultures_wild() -> void:
	# A civ with more influence still wins a contested tile over the wild owner.
	var m = _grass_map(5, 5)
	var tile = m.get_tile(2, 2)
	tile.influence[-2] = 5
	tile.influence[0] = 12
	Influence.resolve_ownership(m)
	assert_eq(tile.owner_player_id, 0, "Civ out-cultures the wild owner")

func test_found_claim_wild_owner() -> void:
	# A wild founding claim paints the camp's ring as owner -2.
	var m = _grass_map(10, 10)
	Influence.found_claim(m, 5, 5, -2, 1, 20)
	assert_eq(m.get_tile(5, 5).owner_player_id, -2, "Wild camp centre owned by -2")
	assert_eq(m.get_tile(5, 6).owner_player_id, -2, "Wild camp ring tile owned by -2")

# ── Culture water-reach cap (§4.7): culture cannot project more than 2 tiles past
# the shoreline, no matter how much influence reaches a far-ocean tile. ──────────

# A coastal map: column x<=2 is land, x>=3 is ocean. Land tiles and ocean tiles up
# to 2 away from land are claimable; ocean tiles 3+ away never are.
func _coast_map(w, h):
	var m = load("res://src/world/world_map.gd").new()
	m.init(w, h, false, false)
	for tile in m.all_tiles():
		tile.terrain_id = "grassland" if tile.x <= 2 else "ocean"
	return m

func test_water_reach_cap_blocks_far_ocean() -> void:
	# Same influence on a near-water tile (1 from land) and a far-ocean tile (3 from
	# land). With db passed, the cap leaves the far tile unowned while near stays owned.
	var db = _db()
	var m = _coast_map(12, 6)
	# (3,3): ocean, one tile from the x=2 land column → within reach (2).
	# (6,3): ocean, four tiles from land → beyond reach.
	m.get_tile(3, 3).influence[0] = 100
	m.get_tile(6, 3).influence[0] = 100
	Influence.resolve_ownership(m, db)
	assert_eq(m.get_tile(3, 3).owner_player_id, 0, "Ocean 1 tile from land is claimable")
	assert_eq(m.get_tile(6, 3).owner_player_id, -1, "Ocean 4 tiles from land cannot be claimed")

func test_water_reach_cap_exact_boundary() -> void:
	# A tile exactly 2 tiles from land is still claimable; 3 is not.
	var db = _db()
	var m = _coast_map(12, 6)
	m.get_tile(4, 3).influence[0] = 100   # 2 from land (x=2) → claimable
	m.get_tile(5, 3).influence[0] = 100   # 3 from land → blocked
	Influence.resolve_ownership(m, db)
	assert_eq(m.get_tile(4, 3).owner_player_id, 0, "Ocean exactly 2 from land is claimable")
	assert_eq(m.get_tile(5, 3).owner_player_id, -1, "Ocean 3 from land cannot be claimed")

func test_water_reach_cap_land_unaffected() -> void:
	# Land tiles are reach 0 and always eligible regardless of the cap.
	var db = _db()
	var m = _coast_map(12, 6)
	m.get_tile(0, 0).influence[0] = 5   # deep inland land tile
	Influence.resolve_ownership(m, db)
	assert_eq(m.get_tile(0, 0).owner_player_id, 0, "Inland land is always claimable")

func test_water_reach_cap_skipped_without_db() -> void:
	# Backward compatibility: with no db (pure unit maps) the cap is inert.
	var m = _coast_map(12, 6)
	m.get_tile(6, 3).influence[0] = 100
	Influence.resolve_ownership(m)   # no db → no cap
	assert_eq(m.get_tile(6, 3).owner_player_id, 0, "Far ocean owned when no db (cap skipped)")
