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
# a settlement), fog-of-war that tracks movement and is fully opaque, and
# zoom-toward-cursor behaviour (Issue 8).

func _world_view(facade):
	var wv = load("res://scenes/world/world_view.tscn").instance()
	add_child_autofree(wv)
	wv.init(facade)
	return wv

# ── Canary ─────────────────────────────────────────────────────────────────────

# Guard against a parse error silently hiding the whole script (GUT swallows load
# failures and still reports green). can_instance() reports compile state safely.
func test_world_view_script_compiles() -> void:
	assert_true(load("res://scenes/world/world_view.gd").can_instance(),
		"world_view.gd must compile (no parse error)")

# ── Wild/raider border colour ────────────────────────────────────────────────────

func test_wild_owner_maps_to_wild_color() -> void:
	# A Raider Camp's tiles (owner -2) hatch in the dedicated charcoal wild colour,
	# distinct from any civ slot and from the unowned grey fallback.
	var facade = setup_facade(2020, "standard",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var wv = _world_view(facade)
	assert_eq(wv._player_color(wv.WILD_OWNER_ID, gs), wv.WILD_COLOR,
		"Wild owner (-2) maps to the wild border colour")
	assert_ne(wv._player_color(gs.players[0].id, gs), wv.WILD_COLOR,
		"A real player does not share the wild colour")

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

# The idle-unit cycle centres on whatever unit the facade selection now points
# at; center_on_selection() pans the camera onto that unit's tile.
func test_center_on_selection_pans_to_selected_unit() -> void:
	var facade = setup_facade(2626, "standard",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 3, 4)
	var u = make_unit(gs, "scout", pid, 11, 6)
	facade.select_unit(u.id)

	var wv = _world_view(facade)
	assert_true(wv.center_on_selection(),
		"center_on_selection reports it found a selected unit to centre on")
	var t = wv.screen_to_tile(wv.get_viewport_rect().size * 0.5)
	assert_eq([int(t.x), int(t.y)], [11, 6],
		"The camera is centred on the selected unit's tile, not the first unit")

# With nothing selected the cycle wrapped to nothing — center_on_selection must
# be a no-op (return false, no camera move) so it never yanks the view.
func test_center_on_selection_noop_when_nothing_selected() -> void:
	var facade = setup_facade(2727, "standard",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	make_unit(gs, "warrior", gs.players[0].id, 4, 4)
	facade.clear_selection()

	var wv = _world_view(facade)
	wv.pan_to_tile(9, 9)
	var before = wv.screen_to_tile(wv.get_viewport_rect().size * 0.5)
	assert_false(wv.center_on_selection(),
		"With no selected unit, center_on_selection reports false")
	var after = wv.screen_to_tile(wv.get_viewport_rect().size * 0.5)
	assert_eq([int(after.x), int(after.y)], [int(before.x), int(before.y)],
		"…and does not move the camera")

# Issue 5: opening a turn, the view jumps to a unit that still needs orders. With
# an idle unit present, center_on_idle_or_player selects it and centres on it,
# even though a busy (fortified) unit sits first in the unit list.
func test_center_on_idle_or_player_focuses_idle_unit() -> void:
	var facade = setup_facade(2828, "standard",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var busy = make_unit(gs, "warrior", pid, 3, 4)
	busy.is_fortified = true            # first in the list, but not awaiting orders
	var idle = make_unit(gs, "scout", pid, 13, 7)
	facade.select_unit(busy.id)         # a stale selection on the busy unit

	var wv = _world_view(facade)
	assert_true(wv.center_on_idle_or_player(pid),
		"center_on_idle_or_player finds the idle unit to centre on")
	assert_eq(facade.get_selection().head_unit(), idle.id,
		"…and the idle unit (not the fortified one) becomes the selection")
	var t = wv.screen_to_tile(wv.get_viewport_rect().size * 0.5)
	assert_eq([int(t.x), int(t.y)], [13, 7],
		"…and the camera is centred on the idle unit's tile")

# When no unit is idle (all fortified/asleep), it still opens the turn on
# something the player owns by falling back to center_on_player.
func test_center_on_idle_or_player_falls_back_when_none_idle() -> void:
	var facade = setup_facade(2929, "standard",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var only = make_unit(gs, "warrior", pid, 8, 5)
	only.is_fortified = true            # nothing is idle
	facade.clear_selection()

	var wv = _world_view(facade)
	assert_true(wv.center_on_idle_or_player(pid),
		"With nothing idle it still centres on an owned unit (fallback)")
	var t = wv.screen_to_tile(wv.get_viewport_rect().size * 0.5)
	assert_eq([int(t.x), int(t.y)], [8, 5],
		"…the fallback centres on the player's (busy) unit")

func test_pan_by_shifts_the_camera() -> void:
	var facade = setup_facade(1818, "standard",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var wv = _world_view(facade)
	var center = wv.get_viewport_rect().size * 0.5
	var before = wv.screen_to_tile(center)
	# Drag the map left: the tile under a fixed screen point shifts right.
	wv.pan_by(Vector2(-256, 0))
	var after = wv.screen_to_tile(center)
	assert_true(after.x > before.x,
		"pan_by shifts which tile sits under a fixed screen point")

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

func test_fog_explored_set_is_read_from_facade_memory() -> void:
	# The fog layer's explored set now derives from the facade's serialized fog
	# memory (SimFacade.get_seen_memory), so committed tiles count as explored even
	# with no live unit currently standing there.
	var facade = setup_facade(96, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 5, 5)
	# Commit "what player saw" via a real end-of-turn so the memory is on gs.
	facade.apply_command(Commands.end_turn(pid))
	assert_true(facade.get_seen_memory(pid).has("5,5"),
		"Sanity: the facade now reports (5,5) in fog memory")

	var wv = _world_view(facade)
	var fog = wv.get_node_or_null("FogLayer")
	fog.init(facade)
	# A different active player id with no live unit on (5,5): explored must still
	# include (5,5) purely from the facade-backed memory.
	fog.rebuild(pid)
	assert_true(fog.get_explored_tiles().has("5,5"),
		"Explored set is seeded from the facade's persistent fog memory")

func test_fog_memory_persists_across_save_load() -> void:
	# Revealed fog survives a save/load round-trip: a tile seen before saving is
	# still explored after the facade reloads the state.
	var facade = setup_facade(97, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 5, 5)
	facade.apply_command(Commands.end_turn(pid))
	var json = facade.save()

	# Fresh facade, load the save.
	var f2 = load("res://src/api/sim_facade.gd").new()
	f2.init_for_load(make_db())
	f2.load_save(json)
	assert_true(f2.get_seen_memory(pid).has("5,5"),
		"Fog memory survives save/load on a fresh facade")

	var wv = _world_view(f2)
	var fog = wv.get_node_or_null("FogLayer")
	fog.init(f2)
	fog.rebuild(pid)
	assert_true(fog.get_explored_tiles().has("5,5"),
		"Reloaded game still remembers the previously-explored tile")

func test_fog_color_is_fully_opaque() -> void:
	var fog = load("res://scenes/world/fog_layer.gd").new()
	add_child_autofree(fog)
	assert_eq(fog.FOG_COLOR.a, 1.0,
		"Fog of war must be fully opaque so hidden terrain never shows through")

# ── Wrap-x fog of war ──────────────────────────────────────────────────────

func test_fog_wraps_sight_across_east_west_seam() -> void:
	# A unit at the right edge of a wrap_x map must reveal tiles on the left edge.
	var facade = setup_facade(9901, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	# Place a unit one tile from the right edge; with sight_radius >= 2 it should
	# see column 0 through the wrap seam.
	var w: int = gs.map.width
	assert_true(gs.map.wrap_x, "small map must have wrap_x enabled")
	make_unit(gs, "warrior", pid, w - 1, gs.map.height / 2)

	var wv = _world_view(facade)
	var fog = wv.get_node_or_null("FogLayer")
	assert_not_null(fog, "FogLayer must exist")
	fog.init(facade)
	fog.rebuild(pid)

	# The tile at column 0, same row, must be visible through the east-west wrap.
	assert_true(fog.get_visible_tiles().has("0," + str(gs.map.height / 2)),
		"Wrap-x: sight from right-edge unit must reveal column 0 across the seam")

# ── Zoom toward cursor (Issue 8) ──────────────────────────────────────────────

func test_zoom_toward_cursor_keeps_world_point_fixed() -> void:
	# After zooming, the world point that was under the cursor must remain at the
	# same screen position. The _zoom_toward_cursor helper encodes this invariant.
	var facade = setup_facade(8001, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var wv = _world_view(facade)

	# Start with a known pan so the offset is non-zero, making the test meaningful.
	wv.pan_to_tile(5, 5)

	# Pick an arbitrary cursor position and record the world point under it.
	var cursor: Vector2 = Vector2(120.0, 80.0)
	var world_before: Vector2 = (cursor - wv._offset) / wv._zoom

	# Zoom in; the helper must adjust the offset to keep world_before fixed.
	wv._zoom_toward_cursor(wv._zoom * 1.1, cursor)

	var world_after: Vector2 = (cursor - wv._offset) / wv._zoom
	assert_true(abs(world_after.x - world_before.x) < 0.5,
		"Zoom-toward-cursor: world x under cursor must not drift")
	assert_true(abs(world_after.y - world_before.y) < 0.5,
		"Zoom-toward-cursor: world y under cursor must not drift")
