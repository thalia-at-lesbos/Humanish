# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends SceneTree

# Manual loopback smoke test for remote multiplayer. NOT part of the CI suites
# (it opens real sockets and yields on frames, which would make a headless GUT
# gate flaky) — run it by hand to confirm the NetServer ↔ NetClient turn cycle
# works against the live engine:
#
#   godot3 --no-window -s res://tests/manual/loopback_smoke.gd
#
# It stands up an in-process authoritative server (player 1 remote, player 2 AI),
# connects one NetClient over WebSocket, then repeatedly submits the client's
# end-turn. Each submit must make the server run the human's pipeline + the AI
# turn + world_step and push back a fresh state with an incremented turn number.
# Prints "SMOKE: PASS" and exits 0 on success.

const NetServer = preload("res://scenes/net/net_server.gd")
const NetClient = preload("res://scenes/net/net_client.gd")
const PORT: int = 9099

var _server
var _client
var _facade = null
var _syncs: int = 0

func _init() -> void:
	randomize()
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	var units = db.constants.get("default_starting_units", [])

	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 777, "tiny", "normal", "warlord", [
		{"name": "Human", "leader_id": "", "traits": [], "starting_gold": 100, "starting_units": units, "is_ai": false},
		{"name": "Bot", "leader_id": "", "traits": [], "starting_gold": 100, "starting_units": units, "is_ai": true},
	], ["last_standing", "time"], "continents")

	_server = NetServer.new()
	_server.init(facade, db, "Smoke")
	_server.set_save_path("loopback_smoke.sav")   # exercise per-turn autosave
	_server.listen(PORT)

	_client = NetClient.new()
	_client.init(db)
	get_root().add_child(_client)
	_client.connect("game_ready", self, "_on_ready")
	_client.connect("state_synced", self, "_on_sync")
	_client.connect_to_server("127.0.0.1", PORT, "Human")

	connect("idle_frame", self, "_tick")

func _tick() -> void:
	_server.poll()
	OS.delay_msec(10)

func _on_ready(facade) -> void:
	_facade = facade
	print("SMOKE: game_ready, my player_id=", _client.get_player_id(),
		" turn=", facade.get_state().turn_number)

func _on_sync(active: bool) -> void:
	_syncs += 1
	var gs = _facade.get_state()
	print("SMOKE: state_synced active=", active, " turn=", gs.turn_number)
	if gs.turn_number >= 2:
		var saved := File.new().file_exists("user://saves/loopback_smoke.sav")
		print("SMOKE: autosave file present=", saved)
		print("SMOKE: ", ("PASS" if saved else "FAIL (no autosave)"),
			" — advanced to turn ", gs.turn_number, " over ", _syncs, " syncs")
		quit()
		return
	if active:
		_facade.apply_command(Commands.end_turn(gs.current_player_id))
