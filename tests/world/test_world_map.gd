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

# WorldMap geometry (§1.1/§1.2): Chebyshev distance, axis wrapping, neighbour
# queries, range/ring helpers, and serialization round-trip.

func _map(w, h, wrap_x = true, wrap_y = false):
	var m = load("res://src/world/world_map.gd").new()
	m.init(w, h, wrap_x, wrap_y)
	return m

# ── Distance & wrapping ──────────────────────────────────────────────────────

func test_distance_no_wrap() -> void:
	var m = _map(20, 20, false, false)
	assert_eq(m.distance(0, 0, 3, 4), 4, "Chebyshev max(3,4)=4")
	assert_eq(m.distance(5, 5, 5, 5), 0, "same tile = 0")
	assert_eq(m.distance(0, 0, 2, 2), 2, "diagonal 2 = 2")

func test_distance_wrap_x() -> void:
	var m = _map(10, 10, true, false)
	assert_eq(m.distance(0, 0, 9, 0), 1, "wrap-x: shorter path is 1")

func test_distance_no_wrap_y() -> void:
	var m = _map(10, 10, false, false)
	assert_eq(m.distance(0, 0, 0, 9), 9, "no wrap-y: direct = 9")

func test_get_tile_wraps_x() -> void:
	var m = _map(10, 10, true, false)
	assert_eq(m.get_tile(0, 0), m.get_tile(10, 0), "get_tile wraps x correctly")

func test_get_tile_out_of_bounds_no_wrap() -> void:
	var m = _map(10, 10, false, false)
	assert_null(m.get_tile(15, 0), "Out of bounds without wrap returns null")

# ── Neighbours, ranges, rings ──────────────────────────────────────────────────

func test_neighbours4_count_interior() -> void:
	var m = _map(10, 10, false, false)
	assert_eq(m.neighbours4(5, 5).size(), 4, "Interior tile has 4 cardinal neighbours")

func test_neighbours4_count_corner_no_wrap() -> void:
	var m = _map(10, 10, false, false)
	assert_eq(m.neighbours4(0, 0).size(), 2, "Corner without wrap has 2 neighbours")

func test_neighbours8_count_interior() -> void:
	var m = _map(10, 10, false, false)
	assert_eq(m.neighbours8(5, 5).size(), 8, "Interior tile has 8 neighbours")

func test_tiles_in_range() -> void:
	var m = _map(20, 20, false, false)
	assert_eq(m.tiles_in_range(5, 5, 2).size(), 25, "Range 2 = 25 tiles (5x5)")

func test_ring_at_distance_0() -> void:
	var m = _map(10, 10, false, false)
	assert_eq(m.ring_at_distance(5, 5, 0).size(), 1, "Ring at distance 0 = 1 tile (center)")

func test_ring_at_distance_1() -> void:
	var m = _map(10, 10, false, false)
	assert_eq(m.ring_at_distance(5, 5, 1).size(), 8, "Ring at distance 1 = 8 tiles")

# ── Wrap: neighbours at east/west seam ──────────────────────────────────────

func test_neighbours4_wrap_x_right_edge() -> void:
	var m = _map(10, 10, true, false)
	# Right edge tile (9,5): with wrap_x, the east neighbour is (0,5)
	var nbs = m.neighbours4(9, 5)
	assert_eq(nbs.size(), 4, "Right-edge tile with wrap_x has 4 cardinal neighbours")
	var xs = []
	for nb in nbs:
		xs.append(nb.x)
	assert_true(xs.has(0), "East neighbour of right-edge tile wraps to column 0")

func test_neighbours8_wrap_x_right_edge() -> void:
	var m = _map(10, 10, true, false)
	var nbs = m.neighbours8(9, 5)
	assert_eq(nbs.size(), 8, "Right-edge interior tile with wrap_x has 8 diagonal neighbours")

func test_neighbours4_no_wrap_right_edge() -> void:
	var m = _map(10, 10, false, false)
	var nbs = m.neighbours4(9, 5)
	assert_eq(nbs.size(), 3, "Right-edge tile without wrap_x has 3 cardinal neighbours")

func test_normalize_wraps_x() -> void:
	var m = _map(10, 10, true, false)
	var norm = m.normalize(10, 3)  # x == width → 0
	assert_eq(int(norm[0]), 0, "normalize wraps x==width to 0")
	assert_eq(int(norm[1]), 3, "y unchanged by x-wrap")
	var norm2 = m.normalize(-1, 3)  # x == -1 → 9
	assert_eq(int(norm2[0]), 9, "normalize wraps x==-1 to width-1")

# ── Serialization ────────────────────────────────────────────────────────────

func test_serialize_roundtrip() -> void:
	var m = _map(8, 6, true, false)
	m.get_tile(3, 2).terrain_id = "hills"
	m.get_tile(3, 2).feature_id = "forest"
	var m2 = load("res://src/world/world_map.gd").deserialize(m.serialize())
	assert_eq(m2.width, 8, "Width preserved")
	assert_eq(m2.height, 6, "Height preserved")
	assert_eq(m2.get_tile(3, 2).terrain_id, "hills", "Terrain preserved")
	assert_eq(m2.get_tile(3, 2).feature_id, "forest", "Feature preserved")
