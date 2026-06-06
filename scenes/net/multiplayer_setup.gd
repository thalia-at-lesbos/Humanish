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

# Client-side lobby for joining a remote game — the "Multiplayer" entry off the
# start menu (the server has no UI; it is launched from the command line, see
# scenes/net/server_runner.gd). Collects host/port/name, opens a NetClient, and
# once the server pushes the first game snapshot, fires its on_connected callback
# so the StartMenu can swap to main.tscn (mirroring the New Game / Load flows).

const NetClient = preload("res://scenes/net/net_client.gd")

var _db
var _on_connected   # FuncRef(facade, db, net_client) — called when the game is ready
var _on_close       # FuncRef() — restore the start menu when this screen goes away
var _net_client

var _host_edit: LineEdit
var _port_edit: LineEdit
var _name_edit: LineEdit
var _status: Label
var _connect_btn: Button

func init(db, on_connected, on_close = null) -> void:
	_db = db
	_on_connected = on_connected
	_on_close = on_close
	_build_ui()

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.3
	vbox.anchor_top = 0.25
	vbox.anchor_right = 0.7
	vbox.anchor_bottom = 0.8
	vbox.add_constant_override("separation", 12)
	add_child(vbox)

	var title := Label.new()
	title.text = "Remote Multiplayer"
	title.align = Label.ALIGN_CENTER
	vbox.add_child(title)

	_host_edit = _add_field(vbox, "Server host:", "127.0.0.1")
	_port_edit = _add_field(vbox, "Port:", "9080")
	_name_edit = _add_field(vbox, "Your name:", "Player")

	_connect_btn = Button.new()
	_connect_btn.text = "Connect"
	_connect_btn.connect("pressed", self, "_on_connect_pressed")
	vbox.add_child(_connect_btn)

	_status = Label.new()
	_status.align = Label.ALIGN_CENTER
	_status.modulate = Color(0.8, 0.8, 0.85)
	vbox.add_child(_status)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.connect("pressed", self, "_on_back_pressed")
	vbox.add_child(back_btn)

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

func _on_connect_pressed() -> void:
	var host: String = _host_edit.text.strip_edges()
	var port: int = int(_port_edit.text) if _port_edit.text.is_valid_integer() else 9080
	var pname: String = _name_edit.text.strip_edges()
	if host == "":
		_set_status("Enter a server host.")
		return
	if pname == "":
		pname = "Player"
	_set_status("Connecting to " + host + ":" + str(port) + " …")
	_connect_btn.disabled = true

	_net_client = NetClient.new()
	_net_client.init(_db)
	add_child(_net_client)   # child so it polls; reparented into main on launch
	_net_client.connect("welcomed", self, "_on_welcomed")
	_net_client.connect("rejected", self, "_on_rejected")
	_net_client.connect("connection_failed", self, "_on_connection_failed")
	_net_client.connect("connection_closed", self, "_on_connection_closed")
	_net_client.connect("game_ready", self, "_on_game_ready")
	if _net_client.connect_to_server(host, port, pname) != OK:
		_set_status("Could not open connection.")
		_reset_connect()

func _on_welcomed(player_id: int, server_name: String) -> void:
	_set_status("Joined " + server_name + " as player " + str(player_id) + ". Waiting for game…")

func _on_rejected(reason: String) -> void:
	_set_status("Rejected: " + reason)
	_reset_connect()

func _on_connection_failed() -> void:
	_set_status("Connection failed.")
	_reset_connect()

func _on_connection_closed() -> void:
	# Only meaningful before the game launches; afterwards main owns the client.
	if _net_client != null and _net_client.get_facade() == null:
		_set_status("Connection closed.")
		_reset_connect()

func _on_game_ready(facade) -> void:
	if _on_connected != null:
		_on_connected.call_func(facade, _db, _net_client)

func _reset_connect() -> void:
	_connect_btn.disabled = false
	if _net_client != null and _net_client.get_facade() == null:
		_net_client.queue_free()
		_net_client = null

func _on_back_pressed() -> void:
	if _net_client != null:
		_net_client.disconnect_from_server()
		_net_client.queue_free()
		_net_client = null
	if _on_close != null:
		_on_close.call_func()
	queue_free()

func _set_status(msg: String) -> void:
	if _status != null:
		_status.text = msg
