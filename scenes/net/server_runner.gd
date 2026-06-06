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

# Headless multiplayer-server entry point. Run it as the engine main loop with -s:
#
#   godot3 --no-window -s res://scenes/net/server_runner.gd -- --server --port=9080 \
#       --players=3 --ai=1 --world=tiny --map=continents --pace=normal --difficulty=warlord
#
#   # or resume an authoritative save:
#   godot3 --no-window -s res://scenes/net/server_runner.gd -- --server --load=/path/to/game.sav
#
# This never loads the menu or any scene: it builds DataDB + a SimFacade, stands
# up the WebSocket NetServer (scenes/net/net_server.gd), and polls the socket on
# every idle frame. The same engine runs windowless, so a server and a desktop
# client share one codebase. See run_server.sh and docs/design/network-design.md.

const NetConfig = preload("res://src/net/net_config.gd")
const NetServer = preload("res://scenes/net/net_server.gd")

var _server
var _frame_budget_msec: int = 10   # ~100 Hz socket poll; keeps a server core idle

func _init() -> void:
	randomize()
	var args: Array = OS.get_cmdline_args()
	var cfg: Dictionary = NetConfig.parse_args(args, randi())

	if not cfg["server"]:
		# Defensive: this script is only meaningful in server mode. Bail cleanly
		# rather than spin up a serverless main loop.
		push_error("[net] server_runner started without --server; quitting")
		quit()
		return

	# A default save file is mandatory: the server autosaves the authoritative
	# game every turn, so it must know where.
	var cfg_err: String = NetConfig.server_config_error(cfg)
	if cfg_err != "":
		push_error("[net] " + cfg_err)
		print("[net] usage: --server --save=<file> [--port=N] [--players=N --ai=N | --load=PATH] …")
		quit()
		return

	var db = load("res://src/core/data_db.gd").new()
	if not db.load_all():
		push_error("[net] DataDB load failed: " + str(db.get_errors()))
		quit()
		return

	var facade = load("res://src/api/sim_facade.gd").new()
	if str(cfg["load"]) != "":
		if not _setup_from_save(facade, db, str(cfg["load"])):
			quit()
			return
	else:
		_setup_new_game(facade, db, cfg)

	_server = NetServer.new()
	_server.init(facade, db, str(cfg["name"]))
	_server.set_save_path(str(cfg["save"]))
	if _server.listen(int(cfg["port"])) != OK:
		quit()
		return

	# Poll the socket every idle frame. SceneTree emits idle_frame even headless,
	# so no scene/node tree is needed; a short sleep keeps CPU use sane.
	connect("idle_frame", self, "_on_idle_frame")

func _on_idle_frame() -> void:
	if _server != null:
		_server.poll()
	OS.delay_msec(_frame_budget_msec)

func _finalize() -> void:
	if _server != null:
		_server.stop()

# Build a fresh authoritative game. The first (players - ai) slots are remote
# human slots that clients fill; the remainder are AI slots the server plays.
func _setup_new_game(facade, db, cfg: Dictionary) -> void:
	var total: int = int(cfg["players"])
	var ai_count: int = int(cfg["ai"])
	var humans: int = total - ai_count
	var default_units: Array = db.constants.get("default_starting_units", [])
	var configs: Array = []
	for i in range(total):
		var is_ai: bool = i >= humans
		var label: String = ("AI " if is_ai else "Player ") + str(i + 1)
		configs.append({
			"name": label,
			"leader_id": "",
			"traits": [],
			"starting_gold": 100,
			"starting_units": default_units.duplicate(),
			"is_ai": is_ai,
		})
	facade.setup(db, int(cfg["seed"]), str(cfg["world"]), str(cfg["pace"]),
		str(cfg["difficulty"]), configs,
		["last_standing", "dominance", "time"], str(cfg["map"]))
	print("[net] new game: ", total, " players (", humans, " remote, ", ai_count, " AI), seed ", cfg["seed"])

func _setup_from_save(facade, db, path: String) -> bool:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		push_error("[net] could not open save: " + path)
		return false
	var json_str := file.get_as_text()
	file.close()
	facade.init_for_load(db)
	if not facade.load_save(json_str):
		push_error("[net] failed to load save: " + path)
		return false
	print("[net] resumed authoritative game from ", path)
	return true
