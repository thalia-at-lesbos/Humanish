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

# CI gate for the live remote-multiplayer socket path. Unlike the rest of the
# net suite (pure protocol/config) this opens real loopback WebSocket connections
# between an in-process NetServer and one or more NetClients, pumps frames via
# GUT yields (a small poller Node drives the server's poll(); clients poll
# themselves in _process), and asserts the end-to-end behaviour.
#
# It exists because two real bugs once slipped past the pure CI suites — see
# docs/design/network-design.md "Testing":
#   • a client joining on another player's turn never left the lobby, and
#   • the host status panel read a freed widget every frame.
# The first is locked down here (test_off_turn_join_still_starts); the second is
# a GUI-only path. Loopback on 127.0.0.1 is reliable headless, so this is gated.

const NetServer = preload("res://scenes/net/net_server.gd")
const NetClient = preload("res://scenes/net/net_client.gd")

# Drives the server's socket each frame (the server is a Reference, not a Node,
# so it needs an external pump — the headless runner uses idle_frame, here a node).
class _ServerPoller:
	extends Node
	var server = null
	func _process(_delta: float) -> void:
		if server != null:
			server.poll()

var _next_port: int = 9311
var _servers: Array = []
var _clients: Array = []
var _pollers: Array = []

# game_ready flags, set by the per-client signal handlers below.
var _c1_ready: bool = false
var _c2_ready: bool = false

func before_each() -> void:
	_c1_ready = false
	_c2_ready = false

func after_each() -> void:
	# Free immediately (not queue_free) so GUT sees no orphaned children/sockets.
	for c in _clients:
		if is_instance_valid(c):
			c.disconnect_from_server()
			c.free()
	for s in _servers:
		if s != null:
			s.stop()
	for p in _pollers:
		if is_instance_valid(p):
			p.free()
	_clients.clear()
	_servers.clear()
	_pollers.clear()

# ── Helpers ────────────────────────────────────────────────────────────────────

# Stand up an authoritative server on a fresh port. `player_configs` get the
# default starting units injected; pass a non-empty save_name to exercise autosave.
func _start_server(player_configs, save_name, seed_val):
	var port: int = _next_port
	_next_port += 1
	var db = make_db()
	var units: Array = db.constants.get("default_starting_units", [])
	for cfg in player_configs:
		if not cfg.has("starting_units"):
			cfg["starting_units"] = units.duplicate()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, seed_val, "tiny", "normal", "warlord", player_configs,
		["last_standing", "time"], "continents")
	var server = NetServer.new()
	server.init(facade, db, "CI")
	if save_name != "":
		var dir := Directory.new()
		if dir.file_exists("user://saves/" + save_name):
			dir.remove("user://saves/" + save_name)
		server.set_save_path(save_name)
	assert_eq(server.listen(port), OK, "server listens on port " + str(port))
	var poller = _ServerPoller.new()
	poller.server = server
	add_child(poller)
	_servers.append(server)
	_pollers.append(poller)
	return {"server": server, "facade": facade, "db": db, "port": port}

func _make_client(db, port, cname, requested_id, ready_method):
	var c = NetClient.new()
	c.init(db)
	add_child(c)
	c.connect("game_ready", self, ready_method)
	c.connect_to_server("127.0.0.1", port, cname, requested_id)
	_clients.append(c)
	return c

func _on_c1_ready(_facade) -> void:
	_c1_ready = true

func _on_c2_ready(_facade) -> void:
	_c2_ready = true

# ── Tests ──────────────────────────────────────────────────────────────────────

# A client joins, ends its turn, and the server runs the authoritative pipeline
# (its own end-turn + the AI player + world_step) and pushes the next turn back.
# Also asserts the server autosaved.
func test_loopback_turn_cycle_and_autosave() -> void:
	var ctx = _start_server([
		{"name": "Human", "is_ai": false},
		{"name": "Bot", "is_ai": true},
	], "ci_mp_turn.sav", 4242)
	var c = _make_client(ctx.db, ctx.port, "Human", -1, "_on_c1_ready")

	for _i in range(40):
		if _c1_ready:
			break
		yield(yield_for(0.1), YIELD)
	assert_true(_c1_ready, "client reached game_ready over the socket")

	var f = c.get_facade()
	assert_not_null(f, "client built a facade from the first snapshot")
	assert_false(f.is_remote_waiting(), "client is active on its own turn")
	var start_turn: int = f.get_state().turn_number

	# End our turn → submit → server runs us + the AI + world_step → new state.
	f.apply_command(Commands.end_turn(f.get_state().current_player_id))
	for _i in range(60):
		if f.get_state().turn_number > start_turn:
			break
		yield(yield_for(0.1), YIELD)

	assert_true(f.get_state().turn_number > start_turn,
		"turn advanced via the authoritative server pipeline")
	assert_true(File.new().file_exists("user://saves/ci_mp_turn.sav"),
		"server autosaved the game")

# Regression: a client connecting while it is NOT its turn must still enter the
# game (parked in the waiting state) rather than stalling in the lobby. The
# server sends every joiner a bootstrap snapshot on hello.
func test_off_turn_join_still_starts() -> void:
	var ctx = _start_server([
		{"name": "P1", "is_ai": false},
		{"name": "P2", "is_ai": false},
	], "", 555)

	var c1 = _make_client(ctx.db, ctx.port, "P1", -1, "_on_c1_ready")
	for _i in range(40):
		if _c1_ready:
			break
		yield(yield_for(0.1), YIELD)
	assert_true(_c1_ready, "first client (the active player) started")

	# Second client joins while it is still player 1's turn.
	var c2 = _make_client(ctx.db, ctx.port, "P2", -1, "_on_c2_ready")
	for _i in range(40):
		if _c2_ready:
			break
		yield(yield_for(0.1), YIELD)

	assert_true(_c2_ready, "off-turn joiner still reached game_ready (bootstrap snapshot)")
	assert_not_null(c2.get_facade(), "off-turn joiner built a facade")
	assert_true(c2.get_facade().is_remote_waiting(), "off-turn joiner is parked waiting")
	assert_false(c1.get_facade().is_remote_waiting(), "the active client is not waiting")
