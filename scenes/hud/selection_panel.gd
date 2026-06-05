# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends VBoxContainer

# Shows info about the currently selected unit or city.
# Action buttons are built dynamically from facade.get_flyout_menu().

var _facade
var _world_view

func init(facade, world_view) -> void:
	_facade = facade
	_world_view = world_view

func rebuild() -> void:
	if _facade == null:
		return
	_clear_children()

	var sel = _facade.get_selection()
	var gs = _facade.get_state()
	var head_uid: int = sel.head_unit()
	var head_cid: int = sel.head_city()

	if head_uid >= 0:
		_build_unit_panel(head_uid, gs)
	elif head_cid >= 0:
		_build_city_panel(head_cid, gs)

func _build_unit_panel(unit_id: int, gs) -> void:
	var u = gs.get_unit(unit_id)
	if u == null:
		return
	var udata = _facade._db.get_unit(u.unit_type_id)

	var name_lbl: Label = Label.new()
	name_lbl.text = u.unit_type_id.capitalize()
	add_child(name_lbl)

	var health_lbl: Label = Label.new()
	health_lbl.text = "HP: " + str(u.health) + "/100"
	add_child(health_lbl)

	var move_lbl: Label = Label.new()
	move_lbl.text = "MP: " + str(u.movement_left) + "/" + str(u.movement_total)
	add_child(move_lbl)

	# Action buttons from flyout menu. Skip the "Open City" action: that belongs
	# to a selected city, not a unit that merely shares the tile with one —
	# otherwise it lingers on screen with no city actually selected.
	var menu: Array = _facade.get_flyout_menu(u.x, u.y)
	for item in menu:
		if int(item.get("action_id", -1)) == IDs.ControlType.OPEN_CITY_SCREEN:
			continue
		var btn: Button = Button.new()
		btn.text = str(item.get("label", ""))
		btn.connect("pressed", self, "_on_action_pressed", [item])
		add_child(btn)

func _build_city_panel(city_id: int, gs) -> void:
	var s = gs.get_settlement(city_id)
	if s == null:
		return

	var name_lbl: Label = Label.new()
	name_lbl.text = s.name
	add_child(name_lbl)

	var pop_lbl: Label = Label.new()
	pop_lbl.text = "Pop: " + str(s.population)
	add_child(pop_lbl)

	var prod_lbl: Label = Label.new()
	if not s.production_queue.empty():
		prod_lbl.text = "Building: " + str(s.production_queue[0].get("id", "?"))
	else:
		prod_lbl.text = "Building: (none)"
	add_child(prod_lbl)

	# Open city screen button
	var city_btn: Button = Button.new()
	city_btn.text = "Open City"
	city_btn.connect("pressed", self, "_on_open_city", [city_id])
	add_child(city_btn)

func _on_action_pressed(item: Dictionary) -> void:
	# Map flyout item to a command — minimal mapping for Phase 6
	var gs = _facade.get_state()
	var sel = _facade.get_selection()
	var uid: int = sel.head_unit()
	if uid < 0:
		return
	var pid: int = gs.current_player_id
	var aid: int = int(item.get("action_id", -1))
	if aid == IDs.UnitMission.FOUND_SETTLEMENT:
		_facade.apply_command(Commands.found_settlement(pid, int(item.get("unit_id", uid))))
	elif aid == IDs.UnitCmd.FORTIFY:
		_facade.apply_command(Commands.unit_fortify(pid, uid))
	elif aid == IDs.UnitCmd.WAKE:
		_facade.apply_command(Commands.mission_skip_turn(pid, uid))

func _on_open_city(_city_id: int) -> void:
	_facade.apply_command(Commands.do_control(
		_facade.get_state().current_player_id, IDs.ControlType.OPEN_CITY_SCREEN))

func _clear_children() -> void:
	# Remove from the tree immediately (queue_free alone is deferred, which can
	# leave stale buttons rendered for a frame after the selection changes).
	for child in get_children():
		remove_child(child)
		child.queue_free()
