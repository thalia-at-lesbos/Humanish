# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends Node

# Routes all player input to SimFacade commands. Mouse, keyboard, and touch all
# produce Commands.* dicts — no input logic touches GameState directly.

var _facade
var _world_view
var _hotkey_map
var _tooltip_label: Label       # set by main after HUD is available

# Auto-advance: once the active unit can no longer act (moved out of moves, or
# put into a rest stance), automatically select the next idle unit so the player
# flows through their army without re-clicking. On by default.
var auto_advance: bool = true

func init(facade, world_view) -> void:
	_facade = facade
	_world_view = world_view
	_hotkey_map = load("res://scenes/input/hotkey_map.gd").new()
	_hotkey_map.load_bindings()

func set_tooltip_label(label: Label) -> void:
	_tooltip_label = label

func _unhandled_input(event: InputEvent) -> void:
	if _facade == null or _world_view == null:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_keyboard(event)
	elif event is InputEventScreenTouch:
		_handle_touch(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return

	var tile_pos: Vector2 = _world_view.screen_to_tile(event.position)
	var tx: int = int(tile_pos.x)
	var ty: int = int(tile_pos.y)
	var gs = _facade.get_state()

	if event.button_index == BUTTON_LEFT:
		var mode: int = _facade.get_interface_mode()
		if mode != IDs.InterfaceMode.SELECTION:
			# In targeting mode: check validity and dispatch mission
			if _facade.get_mode_tile_validity(tx, ty) > 0:
				_dispatch_targeting_mode(mode, tx, ty)
				_facade.exit_interface_mode()
			return

		_handle_select_click(tx, ty, gs)

	elif event.button_index == BUTTON_RIGHT:
		_handle_move_click(tx, ty, gs)

# Left-click = SELECT ONLY (never moves), so targeting is never ambiguous:
#   • A tile carrying the player's own subject(s) → select / cycle them: units in
#     spawn order, then the city on the tile. This switches to another unit or to
#     a city (incl. a just-founded one sharing its tile with the founding escort)
#     at any time, and cycles a stack on repeated clicks of the same tile.
#   • Any other tile (empty, or holding only foreign subjects) → deselect the
#     current unit and show that tile's terrain readout. Every tile is clickable.
func _handle_select_click(tx: int, ty: int, gs) -> void:
	var sel = _facade.get_selection()
	var subjects: Array = _subjects_at(tx, ty, gs)
	if not subjects.empty():
		_select_subject(_next_subject(subjects, sel))
		return
	_facade.inspect_tile(tx, ty)

# Right-click = MOVE the selected units to the target tile (the unambiguous move
# gesture). The destination may be empty (move), hold an enemy (attack), or hold
# a friendly unit/city (stack up / garrison) — any legal tile is accepted. An
# illegal target (impassable / wrong domain) is ignored, leaving the selection
# intact. With nothing selected there is nothing to move, so it is a no-op.
func _handle_move_click(tx: int, ty: int, gs) -> void:
	var sel = _facade.get_selection()
	var ids: Array = sel.selected_unit_ids
	if ids.empty():
		return
	var head = gs.get_unit(sel.head_unit())
	if head == null or (head.x == tx and head.y == ty):
		return
	if not _facade.can_stack_move(head.x, head.y, tx, ty, ids):
		return
	if ids.size() == 1:
		# A single selected unit moves as a per-unit move command (§3.3).
		_facade.apply_command(Commands.mission_move_to(gs.current_player_id, ids[0], tx, ty))
	else:
		_facade.apply_command(Commands.move_stack(
			gs.current_player_id, head.x, head.y, tx, ty, ids))
	# Issue 14: flash the target tile to confirm the move order.
	if _world_view != null and _world_view.has_method("flash_move_tile"):
		_world_view.flash_move_tile(tx, ty)
	_maybe_auto_advance(gs)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _tooltip_label == null:
		return
	var tile_pos: Vector2 = _world_view.screen_to_tile(event.position)
	var tx: int = int(tile_pos.x)
	var ty: int = int(tile_pos.y)
	var gs = _facade.get_state()
	if gs == null or gs.map == null or not gs.map.is_valid(tx, ty):
		_tooltip_label.visible = false
		return

	# Check for widget at tile
	var sel = _facade.get_selection()
	var head_uid: int = sel.head_unit()
	if head_uid >= 0:
		var u = gs.get_unit(head_uid)
		if u != null and u.x == tx and u.y == ty:
			var widget: Dictionary = {"type": IDs.WidgetType.UNIT_MODEL, "data1": head_uid}
			_tooltip_label.text = _facade.widget_help(widget)
			_tooltip_label.rect_position = event.position + Vector2(12, 12)
			_tooltip_label.visible = true
			return
	_tooltip_label.visible = false

func _handle_keyboard(event: InputEventKey) -> void:
	var ctrl_type: int = _hotkey_map.lookup(event.scancode, event.shift, event.control)
	if ctrl_type < 0:
		return
	if not _facade.can_do_control(ctrl_type):
		return
	var gs = _facade.get_state()
	_facade.apply_command(Commands.do_control(gs.current_player_id, ctrl_type))

func _handle_touch(event: InputEventScreenTouch) -> void:
	if not event.pressed:
		return
	# Single tap behaves like left click
	var fake: InputEventMouseButton = InputEventMouseButton.new()
	fake.button_index = BUTTON_LEFT
	fake.pressed = true
	fake.position = event.position
	_handle_mouse_button(fake)

func _dispatch_targeting_mode(mode: int, tx: int, ty: int) -> void:
	var gs = _facade.get_state()
	var head_uid: int = _facade.get_selection().head_unit()
	if head_uid < 0:
		return
	match mode:
		IDs.InterfaceMode.GO_TO, IDs.InterfaceMode.GO_TO_ALL:
			var u = gs.get_unit(head_uid)
			if u != null:
				_facade.apply_command(
					Commands.move_stack(gs.current_player_id, u.x, u.y, tx, ty))
		IDs.InterfaceMode.AIRLIFT:
			_facade.apply_command(
				Commands.mission_airlift(gs.current_player_id, head_uid, tx, ty))
		IDs.InterfaceMode.AREA_BOMBARD:
			_facade.apply_command(
				Commands.mission_bombard(gs.current_player_id, head_uid, tx, ty))

# ── Helpers ───────────────────────────────────────────────────────────────────

# If the active unit can no longer act, hop to the next idle unit. Mirrors the
# facade's own idle predicate (cycle_idle_units), so a unit that has moved or
# entered a rest stance is considered done.
func _maybe_auto_advance(gs) -> void:
	if not auto_advance:
		return
	var head: int = _facade.get_selection().head_unit()
	if head >= 0:
		var u = gs.get_unit(head)
		if u != null and _unit_can_still_act(u):
			return   # still has moves and no rest stance — keep it selected
	_facade.cycle_idle_units(false)

func _unit_can_still_act(u) -> bool:
	return not (u.has_moved or u.is_fortified or u.is_sentry \
		or u.is_patrolling or u.is_healing)

func _owned_units_at(tx: int, ty: int, gs) -> Array:
	# All units the current player owns on this tile, in stable spawn order so the
	# click-to-cycle ordering is consistent from one click to the next.
	var ids: Array = []
	for u in gs.units:
		if u.x == tx and u.y == ty and u.owner_player_id == gs.current_player_id:
			ids.append(u.id)
	return ids

func _next_in_stack(ids: Array, head_uid: int) -> int:
	# Pick the unit after the currently-selected one, wrapping around. If the
	# selection isn't part of this stack, start at the top of the stack.
	var idx: int = ids.find(head_uid)
	if idx < 0:
		return ids[0]
	return ids[(idx + 1) % ids.size()]

# The player's own selectable subjects on a tile, in click-cycle order: every
# owned unit (stable spawn order) followed by an owned city if one sits here.
# Each entry is {"kind": "unit"|"city", "id": int}.
func _subjects_at(tx: int, ty: int, gs) -> Array:
	var out: Array = []
	for uid in _owned_units_at(tx, ty, gs):
		out.append({"kind": "unit", "id": uid})
	var cid: int = _find_owned_city_at(tx, ty, gs)
	if cid >= 0:
		out.append({"kind": "city", "id": cid})
	return out

# The subject after whatever is currently selected, wrapping around. If nothing
# on this tile is selected, returns the first subject.
func _next_subject(subjects: Array, sel) -> Dictionary:
	var hu: int = sel.head_unit()
	var hc: int = sel.head_city()
	var cur: int = -1
	for i in range(subjects.size()):
		var s: Dictionary = subjects[i]
		if s["kind"] == "unit" and s["id"] == hu:
			cur = i
			break
		if s["kind"] == "city" and s["id"] == hc:
			cur = i
			break
	return subjects[(cur + 1) % subjects.size()]

func _select_subject(subject: Dictionary) -> void:
	if subject["kind"] == "unit":
		_facade.select_unit(int(subject["id"]))
	else:
		_facade.select_city(int(subject["id"]))

func _find_owned_city_at(tx: int, ty: int, gs) -> int:
	for s in gs.settlements:
		if s.x == tx and s.y == ty and s.owner_player_id == gs.current_player_id:
			return s.id
	return -1
