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
	elif sel.has_inspected_tile():
		_build_tile_panel(int(sel.inspected_tile.x), int(sel.inspected_tile.y))

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

	# Current activity/stance (fortified, sleeping, moving to a target, building…),
	# so a selected unit's state is visible at a glance. Text comes from the rules
	# layer (TextGen) so it always matches the actual order semantics.
	var state_lbl: Label = Label.new()
	state_lbl.text = "State: " + TextGen.unit_state_text(u)
	add_child(state_lbl)

	# On-tile unit list: every unit the player owns on this tile, so a stack can
	# be inspected and addressed member-by-member. Clicking a row selects just
	# that unit; "Select all" makes subsequent action buttons apply to the whole
	# stack at once.
	var sel = _facade.get_selection()
	var stack: Array = _owned_units_on_tile(u.x, u.y, gs)
	if stack.size() > 1:
		var stack_lbl: Label = Label.new()
		stack_lbl.text = "Stack on tile (" + str(stack.size()) + "):"
		add_child(stack_lbl)
		for su in stack:
			var row: Button = Button.new()
			var mark: String = "▸ " if su.id in sel.selected_unit_ids else "  "
			row.text = mark + su.unit_type_id.capitalize() + "  (HP " + str(su.health) + ")"
			row.connect("pressed", self, "_on_select_stack_member", [su.id])
			add_child(row)
		var all_btn: Button = Button.new()
		all_btn.text = "Select all (" + str(stack.size()) + ")"
		all_btn.connect("pressed", self, "_on_select_all", [u.x, u.y])
		add_child(all_btn)

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

	# Heal-until-recovered buttons (Issue 9): shown when the unit is injured.
	if u.health < 100:
		var db = _facade._db
		var sleep_btn: Button = Button.new()
		sleep_btn.text = "Sleep Until Healed"
		sleep_btn.connect("pressed", self, "_on_sleep_until_healed", [u.id])
		add_child(sleep_btn)

		# Fortify Until Healed: only for non-civilian units.
		var cls: String = str(db.get_unit(u.unit_type_id).get("classification", ""))
		if cls != "civilian":
			var fort_btn: Button = Button.new()
			fort_btn.text = "Fortify Until Healed"
			fort_btn.connect("pressed", self, "_on_fortify_until_healed", [u.id])
			add_child(fort_btn)

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

	# Show revolt status for a recently-conquered city (§4.8).
	if s.revolt_turns > 0:
		var revolt_lbl: Label = Label.new()
		revolt_lbl.text = "In revolt: " + str(s.revolt_turns) + " turn(s)"
		add_child(revolt_lbl)

	# Open city screen button
	var city_btn: Button = Button.new()
	city_btn.text = "Open City"
	city_btn.connect("pressed", self, "_on_open_city", [city_id])
	add_child(city_btn)

	# Disband (raze) — the at-any-time disband, and the "raze" choice for a
	# just-conquered city (§4.8).
	var disband_btn: Button = Button.new()
	disband_btn.text = "Disband City"
	disband_btn.connect("pressed", self, "_on_disband_city", [city_id])
	add_child(disband_btn)

# Terrain readout for an inspected (unoccupied / illegal-target) tile.
func _build_tile_panel(tx: int, ty: int) -> void:
	var text: String = _facade.tile_info_text(tx, ty)
	if text == "":
		return
	var lbl: Label = Label.new()
	lbl.text = text
	add_child(lbl)

func _on_action_pressed(item: Dictionary) -> void:
	# Map flyout item to a command. When a whole stack is selected, per-unit
	# orders (fortify / wake) apply to every selected unit; founding a settlement
	# stays a single-settler action on the head unit.
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
		for id in sel.selected_unit_ids:
			_facade.apply_command(Commands.unit_fortify(pid, id))
	elif aid == IDs.UnitCmd.WAKE:
		for id in sel.selected_unit_ids:
			_facade.apply_command(Commands.mission_skip_turn(pid, id))

func _on_select_stack_member(unit_id: int) -> void:
	_facade.select_unit(unit_id)
	rebuild()

func _on_select_all(tx: int, ty: int) -> void:
	_facade.select_stack(tx, ty)
	rebuild()

# Every unit the current player owns on a tile, in stable spawn order.
func _owned_units_on_tile(tx: int, ty: int, gs) -> Array:
	var out: Array = []
	for u in gs.units:
		if u.x == tx and u.y == ty and u.owner_player_id == gs.current_player_id:
			out.append(u)
	return out

func _on_open_city(_city_id: int) -> void:
	_facade.apply_command(Commands.do_control(
		_facade.get_state().current_player_id, IDs.ControlType.OPEN_CITY_SCREEN))

func _on_disband_city(city_id: int) -> void:
	_facade.apply_command(Commands.disband_city(
		_facade.get_state().current_player_id, city_id))

func _on_sleep_until_healed(unit_id: int) -> void:
	_facade.apply_command(Commands.mission_sleep_until_healed(
		_facade.get_state().current_player_id, unit_id))

func _on_fortify_until_healed(unit_id: int) -> void:
	_facade.apply_command(Commands.mission_fortify_until_healed(
		_facade.get_state().current_player_id, unit_id))

func _clear_children() -> void:
	# Remove from the tree immediately (queue_free alone is deferred, which can
	# leave stale buttons rendered for a frame after the selection changes).
	for child in get_children():
		remove_child(child)
		child.queue_free()
