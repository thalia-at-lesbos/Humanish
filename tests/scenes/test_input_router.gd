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

# InputRouter stack handling: clicking a tile cycles through the current player's
# units on it (ignoring enemies) and wraps around.

func _router():
	var ir = load("res://scenes/input/input_router.gd").new()
	add_child_autofree(ir)
	return ir

# Canary: a parse error in the router script still loads (load() returns a broken
# GDScript) but cannot instance; can_instance() reports the compile state without
# throwing, so this fails loudly instead of GUT silently swallowing the error.
func test_input_router_script_compiles() -> void:
	var script = load("res://scenes/input/input_router.gd")
	assert_not_null(script, "input_router.gd loads")
	assert_true(script.can_instance(), "input_router.gd compiles (no parse error)")

# A worker (or other civilian) standing on the same tile as a warrior. After the
# left-click cycle, the active selection can be the civilian — a right-click on an
# adjacent wild/enemy city must still attack with the escorting warrior, not be a
# silent no-op (the reported regression). Routed as the whole owned stack so the
# move command picks the combat-capable unit as the attacker.
func test_right_click_civilian_selected_attacks_wild_city_via_escort() -> void:
	var facade = setup_facade(3434, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(3, 3).terrain_id = "grassland"
	gs.map.get_tile(4, 3).terrain_id = "grassland"
	var worker = make_unit(gs, "worker", pid, 3, 3)
	var warrior = make_warrior(gs, pid, 3, 3)
	make_settlement(gs, -2, 4, 3, 1)   # wild camp (owner -2) adjacent
	facade.select_unit(worker.id)      # the cycle landed on the civilian

	var ir = _router()
	ir._facade = facade
	ir._world_view = _StubView.new()
	ir._handle_move_click(4, 3, gs)
	assert_true(warrior.has_attacked,
		"Right-click on a wild city attacks with the escorting warrior, even though "
		+ "a civilian was the active selection")

# The escort escalation only fires for a hostile target. A civilian selected and
# right-clicking an empty tile moves just that civilian (a normal worker move) —
# it must NOT drag the escorting warrior along (that would be the old whole-tile
# behaviour the per-unit move was meant to fix).
func test_right_click_civilian_selected_empty_tile_moves_only_civilian() -> void:
	var facade = setup_facade(3535, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(3, 3).terrain_id = "grassland"
	gs.map.get_tile(4, 3).terrain_id = "grassland"
	var worker = make_unit(gs, "worker", pid, 3, 3)
	var warrior = make_warrior(gs, pid, 3, 3)
	facade.select_unit(worker.id)

	var ir = _router()
	ir._facade = facade
	ir._world_view = _StubView.new()
	ir._handle_move_click(4, 3, gs)
	assert_eq([worker.x, worker.y], [4, 3], "The selected worker moves onto the empty tile")
	assert_eq([warrior.x, warrior.y], [3, 3],
		"…and the escorting warrior is not dragged along (no hostile escalation)")

# Minimal WorldView double: maps 64px cells to tiles and records pans plus the
# idle-cycle "follow the selection" call (center_on_selection).
class _StubView:
	extends Reference
	var panned = Vector2.ZERO
	var center_calls = 0
	func screen_to_tile(p):
		return Vector2(int(p.x / 64), int(p.y / 64))
	func pan_by(d):
		panned += d
	func flash_move_tile(_a, _b):
		pass
	func center_on_selection():
		center_calls += 1
		return true

# ── Enter ends the turn (data-driven hotkey → END_TURN control) ───────────────

# The hotkey table binds both KEY_ENTER (16777221) and KEY_KP_ENTER (16777222)
# to the END_TURN control (ControlType.END_TURN == 8), the same action the HUD
# End Turn button issues. Verified at the data layer so a future renumber of the
# enum or a typo in hotkeys.json is caught.
func test_enter_keys_bound_to_end_turn_control() -> void:
	var hk = load("res://scenes/input/hotkey_map.gd").new()
	hk.load_bindings()
	assert_eq(hk.lookup(KEY_ENTER, false, false), IDs.ControlType.END_TURN,
		"Enter (main row) ends the turn")
	assert_eq(hk.lookup(KEY_KP_ENTER, false, false), IDs.ControlType.END_TURN,
		"Numpad Enter ends the turn")

func _key(scancode):
	var e = InputEventKey.new()
	e.scancode = scancode
	e.pressed = true
	return e

# Pressing Enter in the main view drives the turn forward through the same
# DO_CONTROL/END_TURN command path the button uses (so the remote-submit seam
# still intercepts it): the turn number advances.
func test_enter_key_advances_turn() -> void:
	var facade = setup_facade(7070, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var before: int = gs.turn_number

	var ir = _router()
	ir._facade = facade
	ir._world_view = _StubView.new()
	ir._hotkey_map = load("res://scenes/input/hotkey_map.gd").new()
	ir._hotkey_map.load_bindings()
	ir._handle_keyboard(_key(KEY_ENTER))

	assert_true(facade.get_state().turn_number > before,
		"Pressing Enter ends the turn and advances the turn counter")

func _mb(idx, pressed, pos):
	var e = InputEventMouseButton.new()
	e.button_index = idx
	e.pressed = pressed
	e.position = pos
	return e

func _mm(pos, mask, rel):
	var e = InputEventMouseMotion.new()
	e.position = pos
	e.button_mask = mask
	e.relative = rel
	return e

# ── Left press-drag pans the map; a plain click still selects ─────────────────

func test_left_press_drag_pans_and_suppresses_select() -> void:
	var facade = setup_facade(3131, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 1, 1)   # under the press point (64,64)
	facade.clear_selection()

	var ir = _router()
	ir._facade = facade
	var stub = _StubView.new()
	ir._world_view = stub
	ir._handle_mouse_button(_mb(BUTTON_LEFT, true, Vector2(64, 64)))
	ir._handle_mouse_motion(_mm(Vector2(104, 64), BUTTON_MASK_LEFT, Vector2(40, 0)))
	ir._handle_mouse_button(_mb(BUTTON_LEFT, false, Vector2(104, 64)))

	assert_true(stub.panned.length() > 0.0, "A left press-drag pans the camera")
	assert_eq(facade.get_selection().head_unit(), -1,
		"A left press-drag must not select — it was a pan, not a click")

func test_left_click_without_drag_selects() -> void:
	var facade = setup_facade(3232, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 1, 1)
	facade.clear_selection()

	var ir = _router()
	ir._facade = facade
	ir._world_view = _StubView.new()
	# Press and release at the same point — no drag.
	ir._handle_mouse_button(_mb(BUTTON_LEFT, true, Vector2(64, 64)))
	ir._handle_mouse_button(_mb(BUTTON_LEFT, false, Vector2(64, 64)))

	assert_eq(facade.get_selection().head_unit(), u.id,
		"A left click with no drag selects the unit under the cursor")

func test_click_cycles_through_stacked_units() -> void:
	var facade = setup_facade(1313, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid

	# Three friendly units sharing one tile, in a known spawn order.
	var ids = []
	for t in ["warrior", "scout", "archer"]:
		ids.append(make_unit(gs, t, pid, 4, 4).id)

	var ir = _router()
	var stack_ids = ir._owned_units_at(4, 4, gs)
	assert_eq(stack_ids, ids, "All owned units on the tile are returned in spawn order")

	# With nothing selected, the first click selects the top of the stack.
	assert_eq(ir._next_in_stack(stack_ids, -1), ids[0], "A fresh click selects the first unit")
	assert_eq(ir._next_in_stack(stack_ids, ids[0]), ids[1], "second click → unit 2")
	assert_eq(ir._next_in_stack(stack_ids, ids[1]), ids[2], "third click → unit 3")
	assert_eq(ir._next_in_stack(stack_ids, ids[2]), ids[0], "fourth click wraps to unit 1")

	# Driving the real selection through the facade cycles the head unit too.
	facade.select_unit(ir._next_in_stack(stack_ids, -1))
	assert_eq(facade.get_selection().head_unit(), ids[0], "head starts at unit 1")
	facade.select_unit(ir._next_in_stack(stack_ids, facade.get_selection().head_unit()))
	assert_eq(facade.get_selection().head_unit(), ids[1], "head advances to unit 2")

func test_owned_units_at_ignores_enemy_units() -> void:
	var facade = setup_facade(1414, "small")
	var gs = facade.get_state()
	var p0 = gs.players[0].id
	var p1 = gs.players[1].id
	gs.current_player_id = p0

	var mine = make_unit(gs, "warrior", p0, 3, 3)
	make_unit(gs, "warrior", p1, 3, 3)

	var ir = _router()
	assert_eq(ir._owned_units_at(3, 3, gs), [mine.id],
		"Only the current player's units are selectable on a shared tile")

func test_auto_advance_selects_next_idle_unit() -> void:
	var facade = setup_facade(1717, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 4, 4)
	var b = make_unit(gs, "scout", pid, 7, 7)
	facade.select_unit(a.id)
	a.has_moved = true   # a has finished acting

	var ir = _router()
	ir._facade = facade
	ir._maybe_auto_advance(gs)
	assert_eq(facade.get_selection().head_unit(), b.id,
		"Once the active unit is done, selection advances to the next idle unit")

func test_no_auto_advance_while_unit_can_still_act() -> void:
	var facade = setup_facade(1818, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 4, 4)
	make_unit(gs, "scout", pid, 7, 7)
	facade.select_unit(a.id)   # a is fresh and idle

	var ir = _router()
	ir._facade = facade
	ir._maybe_auto_advance(gs)
	assert_eq(facade.get_selection().head_unit(), a.id,
		"A unit that can still act stays selected")

func test_auto_advance_can_be_disabled() -> void:
	var facade = setup_facade(1919, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 4, 4)
	make_unit(gs, "scout", pid, 7, 7)
	facade.select_unit(a.id)
	a.has_moved = true

	var ir = _router()
	ir._facade = facade
	ir.auto_advance = false
	ir._maybe_auto_advance(gs)
	assert_eq(facade.get_selection().head_unit(), a.id,
		"With auto-advance off, selection does not move on its own")

# When auto-advance hops to the next idle unit, the world view is asked to centre
# on it (the camera should follow the player through their army).
func test_auto_advance_centers_world_view_on_next_unit() -> void:
	var facade = setup_facade(2727, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 4, 4)
	make_unit(gs, "scout", pid, 7, 7)
	facade.select_unit(a.id)
	a.has_moved = true

	var ir = _router()
	ir._facade = facade
	var stub = _StubView.new()
	ir._world_view = stub
	ir._maybe_auto_advance(gs)
	assert_eq(stub.center_calls, 1,
		"Auto-advancing to the next idle unit centres the world view on it")

# The explicit "next idle unit" hotkey path (KEY_N → NEXT_IDLE_UNIT control)
# also centres the camera on the unit it advances to, so the keyboard cycle and
# the auto-advance behave identically.
func test_next_idle_unit_hotkey_centers_world_view() -> void:
	var facade = setup_facade(3030, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 4, 4)
	make_unit(gs, "scout", pid, 7, 7)
	facade.clear_selection()

	# Sanity: KEY_N is the bound next-idle-unit hotkey (action 6).
	var hk = load("res://scenes/input/hotkey_map.gd").new()
	hk.load_bindings()
	assert_eq(hk.lookup(KEY_N, false, false), IDs.ControlType.NEXT_IDLE_UNIT,
		"KEY_N is bound to the next-idle-unit control")

	var ir = _router()
	ir._facade = facade
	var stub = _StubView.new()
	ir._world_view = stub
	ir._hotkey_map = hk
	ir._handle_keyboard(_key(KEY_N))
	assert_true(facade.get_selection().head_unit() >= 0,
		"The next-idle-unit hotkey selects a unit needing orders")
	assert_eq(stub.center_calls, 1,
		"Pressing the next-idle-unit hotkey centres the world view on the new unit")

# ── Map click releases HUD keyboard focus (issues 1 + 3) ──────────────────────

# After opening an advisor menu, a focused button swallows Enter (bound to End
# Turn) and the arrow keys. A genuine map click must drop that focus. We focus a
# real Button, route a left-click (press+release, no drag) through the router, and
# assert the button no longer holds focus.
func test_left_click_releases_hud_focus() -> void:
	var facade = setup_facade(4040, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	facade.clear_selection()

	# A focusable button standing in for an advisor/HUD control holding focus.
	var btn = Button.new()
	add_child_autofree(btn)
	btn.grab_focus()
	assert_true(btn.has_focus(), "Precondition: the button holds keyboard focus")

	var ir = _router()   # added to the tree, so get_viewport() is live
	ir._facade = facade
	ir._world_view = _StubView.new()
	ir._handle_mouse_button(_mb(BUTTON_LEFT, true, Vector2(64, 64)))
	ir._handle_mouse_button(_mb(BUTTON_LEFT, false, Vector2(64, 64)))

	assert_false(btn.has_focus(),
		"A map click releases HUD keyboard focus so Enter reaches End Turn again")

# A right-click move also releases HUD focus (same Enter-swallowing problem).
func test_right_click_releases_hud_focus() -> void:
	var facade = setup_facade(4141, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	facade.clear_selection()

	var btn = Button.new()
	add_child_autofree(btn)
	btn.grab_focus()
	assert_true(btn.has_focus(), "Precondition: the button holds keyboard focus")

	var ir = _router()
	ir._facade = facade
	ir._world_view = _StubView.new()
	ir._handle_mouse_button(_mb(BUTTON_RIGHT, true, Vector2(64, 64)))

	assert_false(btn.has_focus(),
		"A right-click move also releases HUD keyboard focus")

# A drag-pan (not a click) should NOT touch selection — and the focus path it now
# also runs must not error. (Drag suppresses the select; this guards regressions.)
func test_left_drag_does_not_select_or_error() -> void:
	var facade = setup_facade(4242, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	make_unit(gs, "warrior", gs.players[0].id, 1, 1)   # under the press point
	facade.clear_selection()

	var ir = _router()
	ir._facade = facade
	ir._world_view = _StubView.new()
	ir._handle_mouse_button(_mb(BUTTON_LEFT, true, Vector2(64, 64)))
	ir._handle_mouse_motion(_mm(Vector2(104, 64), BUTTON_MASK_LEFT, Vector2(40, 0)))
	ir._handle_mouse_button(_mb(BUTTON_LEFT, false, Vector2(104, 64)))
	assert_eq(facade.get_selection().head_unit(), -1,
		"A drag is a pan, not a click — it never selects")

# ── Click model: LEFT selects (never moves), RIGHT moves ──────────────────────

func test_right_click_moves_selected_unit_onto_empty_tile() -> void:
	var facade = setup_facade(2020, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(3, 3).terrain_id = "grassland"
	gs.map.get_tile(4, 3).terrain_id = "grassland"
	var mover = make_unit(gs, "warrior", pid, 3, 3)
	facade.select_unit(mover.id)

	var ir = _router()
	ir._facade = facade
	ir._handle_move_click(4, 3, gs)
	assert_eq([mover.x, mover.y], [4, 3],
		"Right-click moves a selected unit onto an adjacent empty tile")

func test_right_click_garrisons_friendly_city() -> void:
	var facade = setup_facade(2121, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(3, 3).terrain_id = "grassland"
	gs.map.get_tile(4, 3).terrain_id = "grassland"
	var mover = make_unit(gs, "warrior", pid, 3, 3)
	make_settlement(gs, pid, 4, 3, 2)   # a friendly city on the target tile
	facade.select_unit(mover.id)

	var ir = _router()
	ir._facade = facade
	ir._handle_move_click(4, 3, gs)
	assert_eq([mover.x, mover.y], [4, 3],
		"Right-click moves onto (garrisons) a friendly city tile")

func test_right_click_with_nothing_selected_is_noop() -> void:
	var facade = setup_facade(2929, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(4, 3).terrain_id = "grassland"
	facade.clear_selection()

	var ir = _router()
	ir._facade = facade
	ir._handle_move_click(4, 3, gs)
	assert_false(facade.get_selection().has_inspected_tile(),
		"Right-click with nothing selected does nothing — no move, no inspect")

func test_right_click_illegal_target_keeps_selection() -> void:
	var facade = setup_facade(2626, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(3, 3).terrain_id = "grassland"
	gs.map.get_tile(4, 3).terrain_id = "ocean"   # land unit cannot enter
	var mover = make_unit(gs, "warrior", pid, 3, 3)
	facade.select_unit(mover.id)

	var ir = _router()
	ir._facade = facade
	ir._handle_move_click(4, 3, gs)
	assert_eq([mover.x, mover.y], [3, 3], "An illegal target does not move the unit")
	assert_eq(facade.get_selection().head_unit(), mover.id,
		"…and the selection is left intact (no accidental deselect on a misclick)")

func test_left_click_friendly_unit_tile_selects_it() -> void:
	var facade = setup_facade(2020, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var mover = make_unit(gs, "warrior", pid, 3, 3)
	var other = make_unit(gs, "scout", pid, 4, 3)   # a friendly unit on the clicked tile
	facade.select_unit(mover.id)

	var ir = _router()
	ir._facade = facade
	ir._handle_select_click(4, 3, gs)
	assert_eq([mover.x, mover.y], [3, 3],
		"Left-click never moves the selected unit")
	assert_eq(facade.get_selection().head_unit(), other.id,
		"…it selects the unit on the clicked tile, so you can switch targets")

func test_left_click_friendly_city_tile_selects_it() -> void:
	var facade = setup_facade(2121, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var mover = make_unit(gs, "warrior", pid, 3, 3)
	var city = make_settlement(gs, pid, 4, 3, 2)   # a friendly city on the clicked tile
	facade.select_unit(mover.id)

	var ir = _router()
	ir._facade = facade
	ir._handle_select_click(4, 3, gs)
	assert_eq(facade.get_selection().head_city(), city.id,
		"Left-clicking a friendly city while a unit is selected selects the city")
	assert_eq([mover.x, mover.y], [3, 3], "…and the unit does not move")

# ── Every tile is clickable; empty/foreign tiles show terrain + deselect ──────

func test_left_click_empty_tile_with_nothing_selected_inspects_terrain() -> void:
	var facade = setup_facade(2525, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(8, 8).terrain_id = "grassland"
	facade.clear_selection()

	var ir = _router()
	ir._facade = facade
	ir._handle_select_click(8, 8, gs)
	assert_true(facade.get_selection().has_inspected_tile(),
		"Left-clicking an empty tile records it for a terrain readout")
	assert_eq([int(facade.get_selection().inspected_tile.x),
		int(facade.get_selection().inspected_tile.y)], [8, 8],
		"…the inspected tile is the one clicked")

func test_left_click_empty_tile_deselects_unit_and_inspects() -> void:
	var facade = setup_facade(2424, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(3, 3).terrain_id = "grassland"
	gs.map.get_tile(7, 7).terrain_id = "grassland"
	var mover = make_unit(gs, "warrior", pid, 3, 3)
	facade.select_unit(mover.id)

	var ir = _router()
	ir._facade = facade
	ir._handle_select_click(7, 7, gs)
	assert_eq(facade.get_selection().head_unit(), -1,
		"Left-clicking an empty tile deselects the current unit")
	assert_true(facade.get_selection().has_inspected_tile(),
		"…and shows that tile's terrain readout")
	assert_eq([mover.x, mover.y], [3, 3], "…without moving the unit")

# ── Bug: a city is selectable the turn it is founded, even sharing its tile ───

func test_city_on_unit_tile_is_reachable_by_cycling() -> void:
	var facade = setup_facade(2727, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var escort = make_unit(gs, "warrior", pid, 5, 5)
	var city = make_settlement(gs, pid, 5, 5, 1)   # city shares the escort's tile
	facade.clear_selection()

	var ir = _router()
	ir._facade = facade
	ir._handle_select_click(5, 5, gs)
	assert_eq(facade.get_selection().head_unit(), escort.id,
		"First click selects the unit on the tile")
	ir._handle_select_click(5, 5, gs)
	assert_eq(facade.get_selection().head_city(), city.id,
		"Cycling the tile reaches the city sharing it with the unit")

# ── Bug: a single member can leave a stack without dragging the rest along ────

func test_move_selected_member_leaves_stack_behind() -> void:
	var facade = setup_facade(2828, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(4, 4).terrain_id = "grassland"
	gs.map.get_tile(5, 4).terrain_id = "grassland"
	var mover = make_unit(gs, "warrior", pid, 4, 4)
	var stayer = make_unit(gs, "scout", pid, 4, 4)
	facade.select_unit(mover.id)   # just one member of the two-unit stack

	var ir = _router()
	ir._facade = facade
	ir._handle_move_click(5, 4, gs)
	assert_eq([mover.x, mover.y], [5, 4], "The selected member moves out (right-click)")
	assert_eq([stayer.x, stayer.y], [4, 4],
		"…the unselected stack member stays put")

func test_left_click_selected_units_own_tile_cycles_stack() -> void:
	var facade = setup_facade(2222, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 3, 3)
	var b = make_unit(gs, "scout", pid, 3, 3)
	facade.select_unit(a.id)

	var ir = _router()
	ir._facade = facade
	ir._handle_select_click(3, 3, gs)   # same tile as the selected unit
	assert_eq(facade.get_selection().head_unit(), b.id,
		"Left-clicking the selected unit's own tile cycles to the next stack member")

func test_left_click_selects_friendly_unit_when_nothing_selected() -> void:
	var facade = setup_facade(2323, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 6, 6)
	facade.clear_selection()

	var ir = _router()
	ir._facade = facade
	ir._handle_select_click(6, 6, gs)
	assert_eq(facade.get_selection().head_unit(), u.id,
		"With nothing selected, left-clicking a friendly unit selects it")

func test_left_click_selects_city_when_nothing_selected() -> void:
	var facade = setup_facade(2424, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var c = make_settlement(gs, pid, 5, 5, 2)
	facade.clear_selection()

	var ir = _router()
	ir._facade = facade
	ir._handle_select_click(5, 5, gs)
	assert_eq(facade.get_selection().head_city(), c.id,
		"With nothing selected, left-clicking a friendly city selects it")
