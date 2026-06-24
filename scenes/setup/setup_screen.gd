# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends Control

# Setup screen shown before the game starts.
# Collects player count, names, world size, seed, pace, difficulty, then
# calls facade.setup() and switches to the main game scene.

var _facade
var _db
var _on_start_callback  # FuncRef(facade, db) called when setup completes

var _player_rows: Array = []
var _world_size_btn: OptionButton
var _world_size_ids: Array = []
var _map_type_btn: OptionButton
var _map_type_ids: Array = []
var _pace_btn: OptionButton
var _difficulty_btn: OptionButton
var _aggressive_wild_check: CheckBox
var _permanent_alliances_check: CheckBox
var _events_check: CheckBox
var _seed_edit: LineEdit
var _player_count_spin: SpinBox
var _error_label: Label
var _player_count_user_set: bool = false
var _building_ui: bool = false

func init(db, on_start) -> void:
	_db = db
	_on_start_callback = on_start
	_building_ui = true
	_build_ui()
	_building_ui = false

func _build_ui() -> void:
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.margin_left = 40
	vbox.margin_top = 40
	vbox.margin_right = -40
	vbox.margin_bottom = -40
	add_child(vbox)

	var title: Label = Label.new()
	title.text = "New Game"
	vbox.add_child(title)

	# Player count — default comes from the initial world size's players_suggested.
	# The value is applied via _apply_player_count() once the player rows exist
	# (see below) so the SpinBox display and the visible rows always agree.
	var count_row: HBoxContainer = HBoxContainer.new()
	var count_lbl: Label = Label.new()
	count_lbl.text = "Players:"
	_player_count_spin = SpinBox.new()
	_player_count_spin.min_value = 2
	_player_count_spin.max_value = 999
	_player_count_spin.connect("value_changed", self, "_on_player_count_changed")
	count_row.add_child(count_lbl)
	count_row.add_child(_player_count_spin)
	vbox.add_child(count_row)

	# Player name + society rows (up to 16 — well beyond any map's suggested count)
	var societies: Dictionary = _db.get_societies()
	var society_ids: Array = societies.keys()
	for i in range(16):
		var row: HBoxContainer = HBoxContainer.new()
		var lbl: Label = Label.new()
		lbl.text = "Player " + str(i + 1) + ":"
		var edit: LineEdit = LineEdit.new()
		edit.text = "Player " + str(i + 1)
		edit.rect_min_size = Vector2(100, 0)
		var society_btn: OptionButton = OptionButton.new()
		society_btn.add_item("— No Society —")
		for sid in society_ids:
			society_btn.add_item(societies[sid].get("name", sid))
		society_btn.connect("item_selected", self, "_on_society_selected", [i])
		# Leader picker — populated from the chosen society's leaders (faction match).
		# Disabled with a placeholder until a society is selected; defaults to the
		# society's own leader so leaving it untouched preserves the old behaviour.
		var leader_btn: OptionButton = OptionButton.new()
		leader_btn.add_item("—")
		leader_btn.disabled = true
		# Per-player computer-control toggle. Player 1 defaults to human; the
		# rest default to AI so a solo player gets opponents out of the box.
		var ai_check: CheckBox = CheckBox.new()
		ai_check.text = "AI"
		ai_check.pressed = i >= 1
		row.add_child(lbl)
		row.add_child(edit)
		row.add_child(society_btn)
		row.add_child(leader_btn)
		row.add_child(ai_check)
		_player_rows.append({"row": row, "name_edit": edit, "society_btn": society_btn,
				"society_ids": society_ids, "leader_btn": leader_btn, "leader_ids": [],
				"ai_check": ai_check})
		vbox.add_child(row)
		# Visibility is synced to the player count by _apply_player_count() below.
		row.visible = false

	# World size — all sizes from world_sizes.json, defaulting to "standard".
	var ws_row: HBoxContainer = HBoxContainer.new()
	var ws_lbl: Label = Label.new()
	ws_lbl.text = "World size:"
	_world_size_btn = OptionButton.new()
	_world_size_ids = _db.world_sizes.keys()
	var ws_default_idx: int = 0
	for wi in range(_world_size_ids.size()):
		var wsid: String = _world_size_ids[wi]
		var ws_data: Dictionary = _db.get_world_size(wsid)
		_world_size_btn.add_item(ws_data.get("name", wsid))
		if wsid == "standard":
			ws_default_idx = wi
	_world_size_btn.select(ws_default_idx)
	_world_size_btn.connect("item_selected", self, "_on_world_size_changed")
	ws_row.add_child(ws_lbl)
	ws_row.add_child(_world_size_btn)
	vbox.add_child(ws_row)
	# Now that both the SpinBox and the player rows exist, apply the default count
	# for the initial world size. This sets the value, refreshes the SpinBox text,
	# and reveals the matching number of player rows — all in one place so the
	# display and the visible rows can never disagree on open.
	_apply_player_count(_default_player_count(_world_size_ids[ws_default_idx]))

	# Map type (data-driven from data/map_types.json)
	var mt_row: HBoxContainer = HBoxContainer.new()
	var mt_lbl: Label = Label.new()
	mt_lbl.text = "Map type:"
	_map_type_btn = OptionButton.new()
	_map_type_ids = _db.get_map_types().keys()
	for mt_id in _map_type_ids:
		_map_type_btn.add_item(_db.get_map_type(mt_id).get("name", mt_id))
	var continents_idx: int = _map_type_ids.find("continents")
	if continents_idx >= 0:
		_map_type_btn.select(continents_idx)
	mt_row.add_child(mt_lbl)
	mt_row.add_child(_map_type_btn)
	vbox.add_child(mt_row)

	# Pace
	var pace_row: HBoxContainer = HBoxContainer.new()
	var pace_lbl: Label = Label.new()
	pace_lbl.text = "Pace:"
	_pace_btn = OptionButton.new()
	for pace_id in ["quick", "normal", "epic"]:
		_pace_btn.add_item(pace_id)
	_pace_btn.select(1)
	pace_row.add_child(pace_lbl)
	pace_row.add_child(_pace_btn)
	vbox.add_child(pace_row)

	# Difficulty
	var diff_row: HBoxContainer = HBoxContainer.new()
	var diff_lbl: Label = Label.new()
	diff_lbl.text = "Difficulty:"
	_difficulty_btn = OptionButton.new()
	for diff_id in ["settler", "warlord", "prince", "emperor"]:
		_difficulty_btn.add_item(diff_id)
	_difficulty_btn.select(1)
	diff_row.add_child(diff_lbl)
	diff_row.add_child(_difficulty_btn)
	vbox.add_child(diff_row)

	# Aggressive wild forces (§9): longer raider waves, shorter cooldowns.
	_aggressive_wild_check = CheckBox.new()
	_aggressive_wild_check.text = "Aggressive raiders"
	_aggressive_wild_check.pressed = false
	vbox.add_child(_aggressive_wild_check)

	# Permanent alliances: players at peace may form permanent alliances via a
	# diplomatic action. Off by default.
	_permanent_alliances_check = CheckBox.new()
	_permanent_alliances_check.text = "Permanent alliances"
	_permanent_alliances_check.pressed = false
	vbox.add_child(_permanent_alliances_check)

	# Random events (§9): the whole random-event system. On by default; unchecking
	# switches it off for the game (multi-turn quests are unaffected).
	_events_check = CheckBox.new()
	_events_check.text = "Random events"
	_events_check.pressed = true
	vbox.add_child(_events_check)

	# Seed
	var seed_row: HBoxContainer = HBoxContainer.new()
	var seed_lbl: Label = Label.new()
	seed_lbl.text = "Seed:"
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(randi())
	_seed_edit.rect_min_size = Vector2(100, 0)
	seed_row.add_child(seed_lbl)
	seed_row.add_child(_seed_edit)
	vbox.add_child(seed_row)

	# Start button
	var start_btn: Button = Button.new()
	start_btn.text = "Start Game"
	start_btn.connect("pressed", self, "_on_start_pressed")
	vbox.add_child(start_btn)

	# Validation error message (hidden until a rule is violated)
	_error_label = Label.new()
	_error_label.modulate = Color(1.0, 0.4, 0.4)
	_error_label.visible = false
	vbox.add_child(_error_label)

func _default_player_count(size_id: String) -> int:
	var ws: Dictionary = _db.get_world_size(size_id)
	var suggested: int = ws.get("players_suggested", 4)
	return suggested if suggested >= 2 else 2

# Sets the player count programmatically (not a user edit): updates the SpinBox
# value, force-refreshes its visible text (Godot 3's SpinBox does not always
# repaint its line edit when set_value runs before the node is in the tree, and
# assigning the same value fires no signal at all), and reveals the matching
# rows — without flagging the count as user-set.
func _apply_player_count(count: int) -> void:
	var was_user_set: bool = _player_count_user_set
	_player_count_spin.value = count
	_player_count_user_set = was_user_set
	var line_edit: LineEdit = _player_count_spin.get_line_edit()
	if line_edit != null:
		line_edit.text = str(count)
	_sync_player_rows(count)

func _sync_player_rows(count: int) -> void:
	for i in range(_player_rows.size()):
		_player_rows[i]["row"].visible = i < count

func _on_player_count_changed(value: float) -> void:
	if not _building_ui:
		_player_count_user_set = true
	_sync_player_rows(int(value))

func _on_world_size_changed(idx: int) -> void:
	if not _player_count_user_set and idx >= 0 and idx < _world_size_ids.size():
		# Auto-update the player count to match the new world size (programmatic,
		# so this must not mark the count as user-set).
		_apply_player_count(_default_player_count(_world_size_ids[idx]))

# Returns the 1-based player numbers that have no society selected (index 0 of the
# option button is the "— No Society —" placeholder). Empty = all valid.
func _players_missing_society(count: int) -> Array:
	var missing: Array = []
	for i in range(count):
		if _player_rows[i]["society_btn"].selected <= 0:
			missing.append(i + 1)
	return missing

# Society dropdown changed for a player row → refresh that row's leader picker.
func _on_society_selected(_society_idx: int, row_idx: int) -> void:
	_populate_leaders(row_idx)

# Fill a row's leader picker with the leaders of its selected society (faction
# match), defaulting to the society's own leader. With no society selected the
# picker is disabled and shows a placeholder.
func _populate_leaders(row_idx: int) -> void:
	var row_data: Dictionary = _player_rows[row_idx]
	var leader_btn: OptionButton = row_data["leader_btn"]
	leader_btn.clear()
	var society_idx: int = row_data["society_btn"].selected - 1  # 0 = "No Society"
	if society_idx < 0:
		leader_btn.add_item("—")
		leader_btn.disabled = true
		row_data["leader_ids"] = []
		return
	var sid: String = row_data["society_ids"][society_idx]
	var leader_ids: Array = _db.get_society_leaders(sid)
	row_data["leader_ids"] = leader_ids
	leader_btn.disabled = leader_ids.empty()
	var default_leader: String = str(_db.get_society(sid).get("leader_id", ""))
	var default_idx: int = 0
	for j in range(leader_ids.size()):
		var leader: Dictionary = _db.get_leader(leader_ids[j])
		leader_btn.add_item(leader.get("name", leader_ids[j]))
		if leader_ids[j] == default_leader:
			default_idx = j
	if not leader_ids.empty():
		leader_btn.select(default_idx)

func _on_start_pressed() -> void:
	var count: int = int(_player_count_spin.value)
	if count > _player_rows.size():
		count = _player_rows.size()

	# Bug 1: every player must pick a society before the game can start.
	var missing: Array = _players_missing_society(count)
	if not missing.empty():
		var who: String = ""
		for n in missing:
			who += ("" if who == "" else ", ") + str(n)
		_show_error("Select a society for player(s): " + who)
		return
	_clear_error()

	var player_configs: Array = []
	for i in range(count):
		var row_data: Dictionary = _player_rows[i]
		var society_btn: OptionButton = row_data["society_btn"]
		var society_idx: int = society_btn.selected - 1  # 0 = "No Society"
		var leader_id: String = ""
		var society_id: String = ""
		var traits: Array = []
		var starting_gold: int = 100
		var starting_techs: Array = _db.constants.get("starting_techs", []).duplicate()
		if society_idx >= 0:
			var sid: String = row_data["society_ids"][society_idx]
			society_id = sid
			var society: Dictionary = _db.get_society(sid)
			leader_id = society.get("leader_id", "")
			traits = society.get("traits", []).duplicate()
			starting_gold = int(society.get("starting_gold", 100))
			starting_techs = society.get("starting_techs", starting_techs).duplicate()
			# Use the player's chosen leader (and its traits) when the picker has been
			# populated for this society; otherwise fall back to the society default.
			var leader_ids: Array = row_data["leader_ids"]
			var leader_sel: int = row_data["leader_btn"].selected
			if leader_sel >= 0 and leader_sel < leader_ids.size():
				leader_id = leader_ids[leader_sel]
			var leader: Dictionary = _db.get_leader(leader_id)
			if not leader.empty():
				traits = leader.get("traits", traits).duplicate()
		# Opening units are derived from the starting techs (settler + warrior, or a
		# scout when Hunting is known); see DataDB.starting_units_for_techs.
		player_configs.append({
			"name": row_data["name_edit"].text,
			"leader_id": leader_id,
			"society_id": society_id,
			"traits": traits,
			"starting_gold": starting_gold,
			"starting_techs": starting_techs,
			"starting_units": _db.starting_units_for_techs(starting_techs),
			"is_ai": row_data["ai_check"].pressed
		})

	var world_size_id: String = "standard"
	if _world_size_btn.selected >= 0 and _world_size_btn.selected < _world_size_ids.size():
		world_size_id = _world_size_ids[_world_size_btn.selected]
	var map_type_id: String = "continents"
	if _map_type_btn.selected >= 0 and _map_type_btn.selected < _map_type_ids.size():
		map_type_id = _map_type_ids[_map_type_btn.selected]
	var pace_id: String = _pace_btn.get_item_text(_pace_btn.selected)
	var difficulty_id: String = _difficulty_btn.get_item_text(_difficulty_btn.selected)
	var seed_val: int = int(_seed_edit.text) if _seed_edit.text.is_valid_integer() else randi()

	_facade = load("res://src/api/sim_facade.gd").new()
	_facade.setup(_db, seed_val, world_size_id, pace_id, difficulty_id,
		player_configs, ["last_standing", "dominance", "cultural", "score", "time"], map_type_id,
		_aggressive_wild_check.pressed,
		_permanent_alliances_check.pressed,
		_events_check.pressed)

	if _on_start_callback != null:
		_on_start_callback.call_func(_facade, _db)

func _show_error(msg: String) -> void:
	if _error_label != null:
		_error_label.text = msg
		_error_label.visible = true

func _clear_error() -> void:
	if _error_label != null:
		_error_label.visible = false
