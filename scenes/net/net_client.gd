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

# Remote-multiplayer client. A Node so it polls its WebSocketClient every frame
# via _process. Like the rest of the presentation layer it only talks to the
# engine through SimFacade — it never reaches into sim/world.
#
# Lifecycle:
#   1. multiplayer_setup.gd creates this, calls connect_to_server(...).
#   2. On the socket opening it sends HELLO; the server replies WELCOME.
#   3. The first STATE frame carries the full snapshot — this builds a SimFacade
#      (init_for_load + load_save), installs itself as the facade's remote-submit
#      handler, and emits game_ready(facade) so the lobby can launch main.tscn.
#   4. In game: each STATE re-syncs the facade; ending the turn routes through the
#      facade seam back to submit_turn(), which pushes the post-move snapshot
#      (SUBMIT) and parks the local turn until the next STATE.
# See net_server.gd and docs/design/network-design.md for the matching server.

const NetProtocol = preload("res://src/net/net_protocol.gd")

# Match the server's widened frame buffers so whole-state snapshots fit (KB; the
# engine rounds up to a power of two). See net_server.gd for the rationale.
const BUF_KB: int = 8192
const BUF_PACKETS: int = 16

signal welcomed(player_id, server_name)
signal rejected(reason)
signal connection_failed()
signal connection_closed()
signal game_ready(facade)            # first snapshot received; facade built
signal state_synced(active)          # facade re-synced; active = my turn now
signal waiting_for(player_name)      # someone else is taking their turn
signal game_over(winning_alliance_id)

var _db
var _facade
var _client: WebSocketClient
var _player_id: int = -1
var _requested_id: int = -1
var _player_name: String = "Player"
var _connected: bool = false

# Hand in the loaded DataDB (the menu already has one) so snapshots can be
# deserialized against the same content tables the server used.
func init(db) -> void:
	_db = db

func connect_to_server(host: String, port: int, player_name: String, requested_id: int = -1) -> int:
	_player_name = player_name
	_requested_id = requested_id
	_client = WebSocketClient.new()
	_client.set_buffers(BUF_KB, BUF_PACKETS, BUF_KB, BUF_PACKETS)
	_client.connect("connection_established", self, "_on_connection_established")
	_client.connect("connection_error", self, "_on_connection_error")
	_client.connect("connection_closed", self, "_on_connection_closed")
	_client.connect("server_close_request", self, "_on_server_close_request")
	_client.connect("data_received", self, "_on_data_received")
	var url: String = "ws://" + host + ":" + str(port)
	var err: int = _client.connect_to_url(url, PoolStringArray(), false)
	if err != OK:
		push_error("[net] client connect_to_url failed: " + str(err))
	return err

func get_player_id() -> int:
	return _player_id

func get_facade():
	return _facade

func _process(_delta: float) -> void:
	if _client != null:
		_client.poll()

# ── Transport callbacks ────────────────────────────────────────────────────────

func _on_connection_established(_protocol: String) -> void:
	_connected = true
	_client.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	_send(NetProtocol.HELLO, {"name": _player_name, "player_id": _requested_id})

func _on_connection_error() -> void:
	_connected = false
	emit_signal("connection_failed")

func _on_connection_closed(_was_clean: bool) -> void:
	_connected = false
	emit_signal("connection_closed")

func _on_server_close_request(_code: int, _reason: String) -> void:
	_connected = false

func _on_data_received() -> void:
	var text: String = _client.get_peer(1).get_packet().get_string_from_utf8()
	var frame: Dictionary = NetProtocol.decode(text)
	if frame.empty():
		return
	_handle_frame(frame)

# ── Message handling ───────────────────────────────────────────────────────────

func _handle_frame(frame: Dictionary) -> void:
	var t: String = NetProtocol.type_of(frame)
	var d: Dictionary = NetProtocol.data_of(frame)
	match t:
		NetProtocol.WELCOME:
			_player_id = int(d.get("player_id", -1))
			emit_signal("welcomed", _player_id, str(d.get("server_name", "")))
		NetProtocol.REJECT:
			emit_signal("rejected", str(d.get("reason", "rejected")))
		NetProtocol.STATE:
			_on_state(d)
		NetProtocol.WAIT:
			_on_wait(d)
		NetProtocol.GAME_OVER:
			emit_signal("game_over", int(d.get("winning_alliance_id", -1)))
		NetProtocol.ERROR:
			push_warning("[net] server error: " + str(d.get("message", "")))

func _on_state(d: Dictionary) -> void:
	var snapshot: String = str(d.get("snapshot", ""))
	var active: bool = bool(d.get("active", false))
	if snapshot == "":
		return
	if _facade == null:
		_build_facade(snapshot)
		_facade.set_remote_waiting(not active)
		emit_signal("game_ready", _facade)
	else:
		_facade.load_save(snapshot)
		_facade.get_dirty().mark_all()
		_facade.set_remote_waiting(not active)
	emit_signal("state_synced", active)

func _on_wait(d: Dictionary) -> void:
	if _facade != null:
		_facade.set_remote_waiting(true)
	emit_signal("waiting_for", str(d.get("current_player_name", "")))

func _build_facade(snapshot: String) -> void:
	_facade = load("res://src/api/sim_facade.gd").new()
	_facade.init_for_load(_db)
	_facade.load_save(snapshot)
	# Route this facade's end-of-turn through the network instead of the local
	# pipeline (see SimFacade.set_remote_submit_handler).
	_facade.set_remote_submit_handler(funcref(self, "submit_turn"))

# ── Outbound ───────────────────────────────────────────────────────────────────

# Installed as the facade's remote-submit handler: ship the post-move snapshot to
# the authoritative server. Returns true so the facade records the turn as parked.
func submit_turn() -> bool:
	if _facade == null or not _connected:
		return false
	_send(NetProtocol.SUBMIT, {"snapshot": _facade.save()})
	return true

func disconnect_from_server() -> void:
	if _client != null and _connected:
		_send(NetProtocol.BYE, {})
		_client.disconnect_from_host()
	_connected = false

func _send(msg_type: String, payload: Dictionary) -> void:
	if _client == null:
		return
	var peer = _client.get_peer(1)
	if peer == null:
		return
	peer.set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	peer.put_packet(NetProtocol.encode(msg_type, payload).to_utf8())
