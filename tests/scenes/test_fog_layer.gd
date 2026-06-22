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

# Canary for the fog-of-war overlay. It now drives the shared Visibility helper
# (terrain-aware sight) instead of an inline Manhattan loop; this guards against a
# parse/compile error in the refactored script that GUT would otherwise swallow.

func test_fog_layer_script_compiles() -> void:
	assert_true(load("res://scenes/world/fog_layer.gd").can_instance(),
		"fog_layer.gd must compile (terrain-aware sight refactor)")

func test_visibility_helper_compiles() -> void:
	assert_true(load("res://src/world/visibility.gd").can_instance(),
		"Visibility helper must compile")

# The three fog states must stay clearly distinct and correctly ordered:
# in-sight (no veil) brightest > explored (translucent veil) > unexplored (opaque
# black). The explored veil is also kept light enough (alpha well under the old
# 0.55) that remembered terrain reads clearly above pure black.
func test_fog_state_brightness_ordering() -> void:
	var fog = load("res://scenes/world/fog_layer.gd").new()
	# Unexplored is fully opaque black; remembered is a partial veil; in-sight has none.
	assert_eq(fog.FOG_COLOR.a, 1.0, "Unexplored fog is fully opaque black")
	assert_true(fog.REMEMBERED_COLOR.a < fog.FOG_COLOR.a,
		"Explored veil is lighter than unexplored black")
	assert_true(fog.REMEMBERED_COLOR.a > 0.0,
		"Explored veil is still a visible dim (darker than in-sight)")
	assert_true(fog.REMEMBERED_COLOR.a <= 0.45,
		"Explored veil is light enough that remembered terrain reads through")
	fog.free()

# After the border-vision refactor the fog layer reads its current-visible set
# straight from SimFacade.player_visible_tiles, so an owned cultural-border tile
# (with no unit/city nearby) now lifts the fog.
func _mini_facade_with_owned_tile():
	var gs = load("res://src/sim/game_state.gd").new()
	gs.db = load("res://src/core/data_db.gd").new()
	gs.db.load_all()
	gs.rng = load("res://src/core/rng.gd").new()
	gs.rng.init(1)
	gs.map = load("res://src/world/world_map.gd").new()
	gs.map.init(20, 20, false, false)
	for t in gs.map.all_tiles():
		t.terrain_id = "grassland"
	var p = load("res://src/sim/player.gd").new()
	p.id = 1
	p.alliance_id = 1
	gs.players.append(p)
	gs.map.get_tile(10, 10).owner_player_id = 1
	var f = load("res://src/api/sim_facade.gd").new()
	f._gs = gs
	f._db = gs.db
	f._dirty = load("res://src/api/dirty_flags.gd").new()
	f._hooks = load("res://src/sim/hooks.gd").new()
	return f

func test_fog_rebuild_reflects_owned_territory() -> void:
	var f = _mini_facade_with_owned_tile()
	var fog = load("res://scenes/world/fog_layer.gd").new()
	fog.init(f)
	fog.rebuild(1)
	var seen = fog.get_visible_tiles()
	assert_true(seen.has("10,10"), "Fog lifts over an owned cultural-border tile")
	assert_true(seen.has("11,10"), "…and over the one-ring fringe beyond it")
	assert_false(seen.has("13,10"), "…but not two rings beyond the border")
	fog.free()
