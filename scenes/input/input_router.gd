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

		# Selection mode: click tile
		var owned_ids: Array = _owned_units_at(tx, ty, gs)
		var clicked_city_id: int = _find_owned_city_at(tx, ty, gs)
		var head_uid: int = _facade.get_selection().head_unit()

		if not owned_ids.empty():
			# Several units may share a tile. Each click on the stack advances to
			# the next member, so repeated clicks cycle through every unit there.
			_facade.select_unit(_next_in_stack(owned_ids, head_uid))
		elif clicked_city_id >= 0:
			_facade.select_city(clicked_city_id)
		elif head_uid >= 0:
			# Unit selected + click empty/enemy tile → try to move
			var u = gs.get_unit(head_uid)
			if u != null:
				_facade.apply_command(
					Commands.move_stack(gs.current_player_id, u.x, u.y, tx, ty))

	elif event.button_index == BUTTON_RIGHT:
		_show_flyout_menu(tx, ty, event.position)

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

func _show_flyout_menu(tx: int, ty: int, screen_pos: Vector2) -> void:
	var items: Array = _facade.get_flyout_menu(tx, ty)
	if items.empty():
		return
	var popup: PopupMenu = PopupMenu.new()
	add_child(popup)
	for i in range(items.size()):
		popup.add_item(str(items[i].get("label", "?")), i)
	popup.connect("id_pressed", self, "_on_flyout_item", [items, tx, ty])
	popup.popup(Rect2(screen_pos, Vector2.ZERO))

func _on_flyout_item(id: int, items: Array, tx: int, ty: int) -> void:
	if id < 0 or id >= items.size():
		return
	var item: Dictionary = items[id]
	var gs = _facade.get_state()
	var pid: int = gs.current_player_id
	var sel = _facade.get_selection()
	var uid: int = sel.head_unit()
	var aid: int = int(item.get("action_id", -1))

	if aid == IDs.UnitMission.FOUND_SETTLEMENT:
		var settler_id: int = int(item.get("unit_id", uid))
		if settler_id >= 0:
			_facade.apply_command(Commands.found_settlement(pid, settler_id))
	elif aid == IDs.UnitCmd.FORTIFY and uid >= 0:
		_facade.apply_command(Commands.unit_fortify(pid, uid))
	elif aid == IDs.UnitCmd.WAKE and uid >= 0:
		_facade.apply_command(Commands.mission_skip_turn(pid, uid))
	elif aid == IDs.ControlType.OPEN_CITY_SCREEN:
		_facade.apply_command(Commands.do_control(pid, IDs.ControlType.OPEN_CITY_SCREEN))

# ── Helpers ───────────────────────────────────────────────────────────────────

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

func _find_owned_city_at(tx: int, ty: int, gs) -> int:
	for s in gs.settlements:
		if s.x == tx and s.y == ty and s.owner_player_id == gs.current_player_id:
			return s.id
	return -1
