# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://tests/support/sim_fixture.gd"

# WorldView presentation: turn-start centering on the current player's units (or
# a settlement), and fog-of-war that tracks movement and is fully opaque.

func _world_view(facade):
	var wv = load("res://scenes/world/world_view.tscn").instance()
	add_child_autofree(wv)
	wv.init(facade)
	return wv

# ── Centering ────────────────────────────────────────────────────────────────

func test_centers_on_current_players_unit() -> void:
	var facade = setup_facade(1515, "standard",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 12, 9)

	var wv = _world_view(facade)
	assert_true(wv.center_on_player(pid), "Centering should find the player's unit")
	var t = wv.screen_to_tile(wv.get_viewport_rect().size * 0.5)
	assert_eq([int(t.x), int(t.y)], [12, 9],
		"The camera should be centred on the current player's unit tile")

func test_centers_on_settlement_when_no_units() -> void:
	var facade = setup_facade(1616, "standard",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_settlement(gs, pid, 7, 8)

	var wv = _world_view(facade)
	assert_true(wv.center_on_player(pid), "With no units, centering falls back to a settlement")
	var t = wv.screen_to_tile(wv.get_viewport_rect().size * 0.5)
	assert_eq([int(t.x), int(t.y)], [7, 8], "The camera should fall back to the player's city")

func test_center_on_player_false_with_nothing_owned() -> void:
	var facade = setup_facade(1717, "standard",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var wv = _world_view(facade)
	assert_false(wv.center_on_player(facade.get_state().players[0].id),
		"Centering reports false when the player owns nothing to look at")

# ── Fog of war ───────────────────────────────────────────────────────────────

func test_fog_updates_when_world_changes() -> void:
	var facade = setup_facade(91, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 5, 5)

	var wv = _world_view(facade)
	var fog = wv.get_node_or_null("FogLayer")
	assert_not_null(fog, "world view should have a fog layer")
	fog.init(facade)  # main.gd initialises the fog layer separately

	facade.get_dirty().set_dirty(IDs.DirtyRegion.WORLD)
	wv._process(0.0)
	assert_true(fog.get_visible_tiles().has("5,5"), "Fog should reveal the tile the unit stands on")

	u.x = 12; u.y = 9
	facade.get_dirty().set_dirty(IDs.DirtyRegion.WORLD)
	wv._process(0.0)
	assert_true(fog.get_visible_tiles().has("12,9"),
		"Fog should reveal the unit's new location after it moves")
	assert_false(fog.get_visible_tiles().has("5,5"),
		"The tile left behind should no longer be in current sight")

func test_fog_remembers_explored_tiles_after_unit_leaves() -> void:
	var facade = setup_facade(94, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 5, 5)

	var wv = _world_view(facade)
	var fog = wv.get_node_or_null("FogLayer")
	fog.init(facade)

	fog.rebuild(pid)
	assert_true(fog.get_explored_tiles().has("5,5"), "Standing tile should be explored")

	u.x = 12; u.y = 9
	fog.rebuild(pid)
	assert_false(fog.get_visible_tiles().has("5,5"),
		"The vacated tile leaves current sight")
	assert_true(fog.get_explored_tiles().has("5,5"),
		"…but stays in explored memory until vision says otherwise")
	assert_true(fog.get_explored_tiles().has("12,9"),
		"The new location is also remembered")

func test_fog_memory_resets_on_player_handoff() -> void:
	var facade = setup_facade(95, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var a = gs.players[0].id
	var b = gs.players[1].id
	make_unit(gs, "warrior", a, 5, 5)
	make_unit(gs, "warrior", b, 14, 11)

	var wv = _world_view(facade)
	var fog = wv.get_node_or_null("FogLayer")
	fog.init(facade)

	fog.rebuild(a)
	assert_true(fog.get_explored_tiles().has("5,5"), "Player A remembers their surroundings")
	fog.rebuild(b)
	assert_false(fog.get_explored_tiles().has("5,5"),
		"Handing off to player B must not leak A's discoveries")
	assert_true(fog.get_explored_tiles().has("14,11"), "B remembers their own surroundings")

func test_fog_color_is_fully_opaque() -> void:
	var fog = load("res://scenes/world/fog_layer.gd").new()
	add_child_autofree(fog)
	assert_eq(fog.FOG_COLOR.a, 1.0,
		"Fog of war must be fully opaque so hidden terrain never shows through")
