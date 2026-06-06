# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends Reference

# Authoritative multiplayer server. Like PlayerAI and the in-game UI, this is a
# *client* of SimFacade — it only ever reads get_state() or mutates through
# apply_command()/load_save(), and it draws no randomness of its own. It is NOT
# part of src/sim or src/world and the rule code never references it.
#
# Transport is a WebSocketServer in raw mode (TCP, one listen port). WebSocket is
# the simplest stack that ships with Godot 3 and is transparent across the public
# internet: clients make ordinary outbound TCP connections, so no UDP, NAT-hole-
# punching, or client-side firewall rules are needed — only the server's single
# port must be reachable (the one routing concession, same as any web service).
#
# Turn model — full-state handoff, round robin (see docs/design/network-design.md):
#   • The server owns the one authoritative GameState (its own SimFacade).
#   • When the current player is an AI slot, the server plays it itself.
#   • When the current player is a remote human, the server pushes the whole
#     serialized state to that client (STATE) and tells everyone else to WAIT.
#   • The client makes its moves locally, then pushes its post-move snapshot back
#     (SUBMIT); the server adopts it, runs the end-of-turn pipeline, and advances.
# Simultaneous turns are a future extension: collect every active client's SUBMIT
# before resolving, instead of advancing on each one (the round-robin loop in
# _drive() is the single place that policy lives).

const NetProtocol = preload("res://src/net/net_protocol.gd")

# Where bare save filenames land (shared with the in-game save/load screen so the
# two never drift). A save path containing "/" is treated as a full path instead.
const SAVE_DIR: String = "user://saves/"

# Full-state snapshots (a whole serialized GameState) are large — far bigger than
# the WebSocket default frame buffers — so we widen them before listening. Sizes
# are in KB; the engine rounds each up to a power of two. 8 MB comfortably holds a
# standard-map snapshot with room to spare.
const BUF_KB: int = 8192
const BUF_PACKETS: int = 16

var _db
var _facade
var _server_name: String = "Humanish Server"
var _save_path: String = ""   # autosave target; empty = disabled (see set_save_path)

var _ws: WebSocketServer
var _listening: bool = false

# peer_id (int) → { "player_id": int, "name": String }
var _peers: Dictionary = {}
# player_id (int) → peer_id (int) for currently-claimed remote slots
var _player_peer: Dictionary = {}
# player_ids that a remote client must fill (the non-AI human slots)
var _remote_player_ids: Array = []

func init(facade, db, server_name: String = "Humanish Server") -> void:
	_facade = facade
	_db = db
	_server_name = server_name

# Set the file the authoritative game is autosaved to after every turn. A bare
# filename (no "/") is placed under SAVE_DIR; anything with a slash is treated as
# a full path. Empty disables autosave.
func set_save_path(path: String) -> void:
	_save_path = path

func get_save_path() -> String:
	return _save_path

# Begin listening on `port`. Returns OK or a Godot error code. The facade must
# already hold a set-up (or loaded) game before this is called.
func listen(port: int) -> int:
	_remote_player_ids = []
	var gs = _facade.get_state()
	for p in gs.players:
		if not p.is_ai:
			_remote_player_ids.append(p.id)

	_ws = WebSocketServer.new()
	# Widen frame buffers so whole-state snapshots fit (see BUF_KB note above).
	_ws.set_buffers(BUF_KB, BUF_PACKETS, BUF_KB, BUF_PACKETS)
	_ws.connect("client_connected", self, "_on_client_connected")
	_ws.connect("client_disconnected", self, "_on_client_disconnected")
	_ws.connect("data_received", self, "_on_data_received")
	var err: int = _ws.listen(port)
	_listening = (err == OK)
	if _listening:
		print("[net] server '", _server_name, "' listening on port ", port,
			" — remote slots: ", _remote_player_ids,
			" total players: ", gs.players.size())
		if _save_path != "":
			print("[net] autosaving every turn to ", _resolved_save_path())
		# Autosave after every player's turn ends (player_turn_started fires once
		# per turn transition, from both human submits and the AI turns the server
		# plays), so a completed turn is never lost to a crash.
		_facade.connect("player_turn_started", self, "_on_turn_advanced")
		# Persist the opening state immediately so the save file always exists.
		_save_to_disk()
		# Drive once so any AI players that lead the round robin play immediately,
		# parking on the first remote slot (which waits for its client to connect).
		_drive()
	else:
		push_error("[net] server failed to listen on port " + str(port) + " (err " + str(err) + ")")
	return err

func is_listening() -> bool:
	return _listening

# Pump the socket. Called every frame/iteration by the headless runner.
func poll() -> void:
	if _ws != null and _listening:
		_ws.poll()

func stop() -> void:
	if _ws != null and _listening:
		_ws.stop()
	_listening = false

# ── Transport callbacks ────────────────────────────────────────────────────────

func _on_client_connected(peer_id: int, _protocol: String) -> void:
	# WebSocket peers default to binary frames; send UTF-8 JSON as text frames.
	var peer = _ws.get_peer(peer_id)
	if peer != null:
		peer.set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	print("[net] peer ", peer_id, " connected")

func _on_client_disconnected(peer_id: int, _was_clean: bool) -> void:
	_release_peer(peer_id)
	print("[net] peer ", peer_id, " disconnected")

func _on_data_received(peer_id: int) -> void:
	var peer = _ws.get_peer(peer_id)
	if peer == null:
		return
	var text: String = peer.get_packet().get_string_from_utf8()
	var frame: Dictionary = NetProtocol.decode(text)
	if frame.empty():
		return
	_handle_frame(peer_id, frame)

# ── Message handling ───────────────────────────────────────────────────────────

func _handle_frame(peer_id: int, frame: Dictionary) -> void:
	var t: String = NetProtocol.type_of(frame)
	var d: Dictionary = NetProtocol.data_of(frame)
	match t:
		NetProtocol.HELLO:
			_handle_hello(peer_id, d)
		NetProtocol.SUBMIT:
			_handle_submit(peer_id, d)
		NetProtocol.BYE:
			_release_peer(peer_id)

func _handle_hello(peer_id: int, d: Dictionary) -> void:
	var requested: int = int(d.get("player_id", -1))
	var slot: int = _claim_slot(requested)
	if slot < 0:
		_send(peer_id, NetProtocol.REJECT, {"reason": "no free player slot"})
		return
	_peers[peer_id] = {"player_id": slot, "name": str(d.get("name", "Player"))}
	_player_peer[slot] = peer_id
	# Adopt the chosen name onto the player so all clients see it.
	var p = _facade.get_state().get_player(slot)
	if p != null and str(d.get("name", "")) != "":
		p.name = str(d.get("name"))
	_send(peer_id, NetProtocol.WELCOME, {
		"player_id": slot,
		"server_name": _server_name,
		"turn_number": _facade.get_state().turn_number,
		"players": _player_summaries(),
	})
	print("[net] peer ", peer_id, " joined as player ", slot)
	# Bootstrap: every joiner needs a snapshot to build its world and actually
	# start the game, even when it is not its turn yet. _drive() only pushes state
	# to the *active* player, so a client joining on someone else's turn would
	# otherwise get only a WAIT frame and never leave the lobby. Send it the
	# current state here (inactive); _drive() then handles the active player.
	if slot != _facade.get_state().current_player_id:
		_send_state(peer_id, false)
	_drive()

func _handle_submit(peer_id: int, d: Dictionary) -> void:
	if not _peers.has(peer_id):
		return
	var player_id: int = int(_peers[peer_id]["player_id"])
	var gs = _facade.get_state()
	if player_id != gs.current_player_id:
		_send(peer_id, NetProtocol.ERROR, {"message": "not your turn"})
		return
	var snapshot: String = str(d.get("snapshot", ""))
	if snapshot == "" or not _facade.load_save(snapshot):
		_send(peer_id, NetProtocol.ERROR, {"message": "snapshot rejected"})
		# Re-push the authoritative state so the client recovers from its bad push.
		_send_state(peer_id, true)
		return
	_facade.get_dirty().mark_all()
	# Run the authoritative end-of-turn pipeline for the submitting player.
	_facade.apply_command({"type": IDs.CommandType.END_TURN, "player_id": player_id})
	_drive()

# ── Round-robin turn driver ────────────────────────────────────────────────────

# Advance through AI players the server owns until the current player is a remote
# human, then push state to that human and park. Idempotent: safe to call after
# any state change (connect, submit, startup).
func _drive() -> void:
	while true:
		var gs = _facade.get_state()
		if gs.winning_alliance_id >= 0:
			_broadcast(NetProtocol.GAME_OVER, {"winning_alliance_id": gs.winning_alliance_id})
			return
		var cur: int = gs.current_player_id
		var player = gs.get_player(cur)
		if player == null:
			return
		if player.is_ai:
			# The server plays its own AI slot; take_turn ends the turn and
			# advances current_player_id, so the loop re-evaluates the next one.
			PlayerAI.take_turn(_facade, cur)
			continue
		# Remote human's turn.
		var peer_id: int = int(_player_peer.get(cur, -1))
		if peer_id < 0:
			# Slot not yet claimed — hold the game and let connected clients know.
			_broadcast_wait(cur)
			return
		_send_state(peer_id, true)
		_broadcast_wait(cur, peer_id)
		return

# ── Slot / peer bookkeeping ────────────────────────────────────────────────────

# Pick an unclaimed remote slot. Honours a specific request when free; otherwise
# returns the first free remote slot. -1 when the game is full.
func _claim_slot(requested: int) -> int:
	if requested >= 0 and requested in _remote_player_ids and not _player_peer.has(requested):
		return requested
	for pid in _remote_player_ids:
		if not _player_peer.has(pid):
			return pid
	return -1

func _release_peer(peer_id: int) -> void:
	if not _peers.has(peer_id):
		return
	var player_id: int = int(_peers[peer_id]["player_id"])
	_peers.erase(peer_id)
	if int(_player_peer.get(player_id, -1)) == peer_id:
		_player_peer.erase(player_id)

# ── Autosave ───────────────────────────────────────────────────────────────────

func _on_turn_advanced(_player_id: int) -> void:
	_save_to_disk()

# Resolve the configured save target to a concrete path: a bare filename goes
# under SAVE_DIR, a path with a slash is used verbatim.
func _resolved_save_path() -> String:
	if _save_path.find("/") >= 0:
		return _save_path
	return SAVE_DIR + _save_path

func _save_to_disk() -> void:
	if _save_path == "" or _facade == null:
		return
	var path: String = _resolved_save_path()
	# Ensure the saves dir exists for bare-filename targets.
	if not (_save_path.find("/") >= 0):
		var dir := Directory.new()
		if not dir.dir_exists(SAVE_DIR):
			dir.make_dir_recursive(SAVE_DIR)
	var file := File.new()
	if file.open(path, File.WRITE) != OK:
		push_error("[net] autosave failed to open " + path)
		return
	file.store_string(_facade.save())
	file.close()

# Public view of the player roster (for a host status display).
func get_players() -> Array:
	return _player_summaries()

func _player_summaries() -> Array:
	var out: Array = []
	for p in _facade.get_state().players:
		out.append({
			"id": p.id,
			"name": p.name,
			"is_ai": p.is_ai,
			"claimed": _player_peer.has(p.id),
		})
	return out

# ── Outbound helpers ───────────────────────────────────────────────────────────

func _send_state(peer_id: int, active: bool) -> void:
	var gs = _facade.get_state()
	_send(peer_id, NetProtocol.STATE, {
		"snapshot": _facade.save(),
		"current_player_id": gs.current_player_id,
		"turn_number": gs.turn_number,
		"active": active,
	})

func _broadcast_wait(current_player_id: int, except_peer: int = -1) -> void:
	var gs = _facade.get_state()
	var p = gs.get_player(current_player_id)
	var payload: Dictionary = {
		"current_player_id": current_player_id,
		"current_player_name": (p.name if p != null else str(current_player_id)),
		"turn_number": gs.turn_number,
	}
	for peer_id in _peers.keys():
		if peer_id != except_peer:
			_send(peer_id, NetProtocol.WAIT, payload)

func _broadcast(msg_type: String, payload: Dictionary) -> void:
	for peer_id in _peers.keys():
		_send(peer_id, msg_type, payload)

func _send(peer_id: int, msg_type: String, payload: Dictionary) -> void:
	if _ws == null:
		return
	var peer = _ws.get_peer(peer_id)
	if peer == null or not peer.is_connected_to_host():
		return
	peer.set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	peer.put_packet(NetProtocol.encode(msg_type, payload).to_utf8())
