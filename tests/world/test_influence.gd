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
