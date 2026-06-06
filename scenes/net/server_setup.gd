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

# Host-side lobby — the start menu's "Multiplayer Server" entry. It runs an
# authoritative NetServer *in this process* (the desktop app acts as the server;
# remote players join with the "Multiplayer" client menu). The host either:
#   • configures a New Game (reusing the normal SetupScreen for players/world/…), or
#   • loads a previously saved state,
# then names a save file the server autosaves to every turn. Once started, the
# screen becomes a status panel (connected players, current turn) with a Stop
# button. The server has no game board here — it only holds/relays state.
#
# See net_server.gd and docs/design/network-design.md.

const NetServer = preload("res://scenes/net/net_server.gd")
const SaveLoadScreen = preload("res://scenes/screens/save_load_screen.gd")
const DEFAULT_SAVE := "mp_server.sav"

var _db
var _on_close            # FuncRef() — restore the start menu when we go away
var _setup_screen        # SetupScreen instance during new-game config
var _server              # running NetServer (null until started)
var _facade              # authoritative facade (kept for the status display)
var _server_port: int = 9080
var _server_name: String = ""   # captured before the config widgets are freed
var _status_accum: float = 0.0

# Config-phase widgets
var _config_box: VBoxContainer
var _port_edit: LineEdit
var _name_edit: LineEdit
var _save_edit: LineEdit
var _load_list: VBoxContainer
var _error_label: Label

# Status-phase widgets
var _status_box: VBoxContainer
var _status_label: Label

func init(db, on_close) -> void:
	_db = db
	_on_close = on_close
	_build_config_ui()

# ── Config phase ───────────────────────────────────────────────────────────────

func _build_config_ui() -> void:
	_config_box = VBoxContainer.new()
	_config_box.anchor_left = 0.3
	_config_box.anchor_top = 0.2
	_config_box.anchor_right = 0.7
	_config_box.anchor_bottom = 0.85
	_config_box.add_constant_override("separation", 12)
	add_child(_config_box)

	var title := Label.new()
	title.text = "Host Multiplayer Server"
	title.align = Label.ALIGN_CENTER
	_config_box.add_child(title)

	_port_edit = _add_field(_config_box, "Port:", "9080")
	_name_edit = _add_field(_config_box, "Server name:", "Humanish Server")
	# The server autosaves here every turn — mandatory, mirrors the CLI --save.
	_save_edit = _add_field(_config_box, "Save file:", DEFAULT_SAVE)

	var new_btn := Button.new()
	new_btn.text = "New Game…"
	new_btn.connect("pressed", self, "_on_new_game_pressed")
	_config_box.add_child(new_btn)

	var load_btn := Button.new()
	load_btn.text = "Load Saved Game…"
	load_btn.connect("pressed", self, "_on_load_pressed")
	_config_box.add_child(load_btn)

	_load_list = VBoxContainer.new()
	_config_box.add_child(_load_list)

	_error_label = Label.new()
	_error_label.modulate = Color(1.0, 0.4, 0.4)
	_error_label.visible = false
	_config_box.add_child(_error_label)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.connect("pressed", self, "_on_back_pressed")
	_config_box.add_child(back_btn)

func _add_field(parent: VBoxContainer, label_text: String, default_value: String) -> LineEdit:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.rect_min_size = Vector2(110, 0)
	var edit := LineEdit.new()
	edit.text = default_value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(edit)
	parent.add_child(row)
	return edit

# New game: reuse the normal SetupScreen (player/society/world/map/…). Its start
# callback hands us a ready facade; the server-only fields we already collected
# (port/name/save) stay live on this still-mounted screen.
func _on_new_game_pressed() -> void:
	if str(_save_edit.text).strip_edges() == "":
		_show_error("Enter a save file name first.")
		return
	_config_box.visible = false
	_setup_screen = load("res://scenes/setup/setup_screen.gd").new()
	_setup_screen.anchor_right = 1.0
	_setup_screen.anchor_bottom = 1.0
	add_child(_setup_screen)
	_setup_screen.init(_db, funcref(self, "_on_facade_ready"))

# Load: list saved games; picking one builds the authoritative facade.
func _on_load_pressed() -> void:
	if str(_save_edit.text).strip_edges() == "":
		_show_error("Enter a save file name first.")
		return
	for child in _load_list.get_children():
		child.queue_free()
	var saves := _list_saves()
	if saves.empty():
		var none_lbl := Label.new()
		none_lbl.text = "(no saved games found)"
		_load_list.add_child(none_lbl)
		return
	for filename in saves:
		var btn := Button.new()
		btn.text = filename
		btn.connect("pressed", self, "_on_load_file", [filename])
		_load_list.add_child(btn)

func _on_load_file(filename: String) -> void:
	var file := File.new()
	if file.open(SaveLoadScreen.SAVE_DIR + filename, File.READ) != OK:
		_show_error("Could not open save: " + filename)
		return
	var json_str := file.get_as_text()
	file.close()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.init_for_load(_db)
	if not facade.load_save(json_str):
		_show_error("Failed to load save: " + filename)
		return
	# Default the autosave target to the loaded file unless the host changed it.
	if str(_save_edit.text).strip_edges() == DEFAULT_SAVE:
		_save_edit.text = filename
	_on_facade_ready(facade, _db)

func _list_saves() -> Array:
	var files: Array = []
	var dir := Directory.new()
	if dir.open(SaveLoadScreen.SAVE_DIR) == OK:
		dir.list_dir_begin(true, true)
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".sav"):
				files.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()
	files.sort()
	return files

# ── Start the server ───────────────────────────────────────────────────────────

func _on_facade_ready(facade, db) -> void:
	_facade = facade
	# Capture the config-field values into plain vars now: the status panel reads
	# them every refresh, but the LineEdits are freed with _config_box below.
	_server_port = int(_port_edit.text) if _port_edit.text.is_valid_integer() else 9080
	_server_name = str(_name_edit.text)
	var save_name: String = str(_save_edit.text).strip_edges()
	if save_name == "":
		save_name = DEFAULT_SAVE

	if _setup_screen != null:
		_setup_screen.queue_free()
		_setup_screen = null

	_server = NetServer.new()
	_server.init(facade, db, _server_name)
	_server.set_save_path(save_name)
	if _server.listen(_server_port) != OK:
		_server = null
		_config_box.visible = true
		_show_error("Could not listen on port " + str(_server_port) + " (already in use?).")
		return

	_build_status_ui()

# ── Status phase ───────────────────────────────────────────────────────────────

func _build_status_ui() -> void:
	if _config_box != null:
		_config_box.queue_free()
		_config_box = null

	_status_box = VBoxContainer.new()
	_status_box.anchor_left = 0.25
	_status_box.anchor_top = 0.25
	_status_box.anchor_right = 0.75
	_status_box.anchor_bottom = 0.8
	_status_box.add_constant_override("separation", 12)
	add_child(_status_box)

	var title := Label.new()
	title.text = "Server Running"
	title.align = Label.ALIGN_CENTER
	_status_box.add_child(title)

	_status_label = Label.new()
	_status_box.add_child(_status_label)

	var stop_btn := Button.new()
	stop_btn.text = "Stop Server"
	stop_btn.connect("pressed", self, "_on_stop_pressed")
	_status_box.add_child(stop_btn)

	_refresh_status()

func _process(delta: float) -> void:
	if _server == null:
		return
	_server.poll()
	_status_accum += delta
	if _status_accum >= 0.5:
		_status_accum = 0.0
		_refresh_status()

func _refresh_status() -> void:
	if _status_label == null or _server == null:
		return
	var gs = _facade.get_state()
	var lines: Array = []
	lines.append("Name: " + _server_name)
	lines.append("Listening on port " + str(_server_port))
	lines.append("Autosaving to: " + _server.get_save_path())
	lines.append("Turn: " + str(gs.turn_number))
	lines.append("Players:")
	for p in _server.get_players():
		var tag: String = "AI" if bool(p.get("is_ai", false)) \
			else ("connected" if bool(p.get("claimed", false)) else "waiting…")
		var marker: String = " ◀ current" if int(p.get("id", -1)) == gs.current_player_id else ""
		lines.append("  • " + str(p.get("name", "?")) + " [" + tag + "]" + marker)
	_status_label.text = PoolStringArray(lines).join("\n")

func _on_stop_pressed() -> void:
	_shutdown()
	_close()

# ── Teardown ───────────────────────────────────────────────────────────────────

func _on_back_pressed() -> void:
	_close()

func _shutdown() -> void:
	if _server != null:
		_server.stop()
		_server = null

func _close() -> void:
	_shutdown()
	if _on_close != null:
		_on_close.call_func()
	queue_free()

func _show_error(msg: String) -> void:
	if _error_label != null:
		_error_label.text = msg
		_error_label.visible = true
