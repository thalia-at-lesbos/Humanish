# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://addons/gut/test.gd"

# Unit tests for the headless server command-line parser (src/net/net_config.gd).

func test_defaults_when_no_args() -> void:
	var cfg: Dictionary = NetConfig.parse_args([])
	assert_false(cfg["server"], "server off by default")
	assert_eq(int(cfg["port"]), NetConfig.DEFAULT_PORT, "default port")
	assert_eq(int(cfg["players"]), 2, "default players")
	assert_eq(int(cfg["ai"]), 0, "default ai")
	assert_eq(str(cfg["world"]), "tiny", "default world")
	assert_eq(str(cfg["map"]), "continents", "default map")

func test_equals_form() -> void:
	var cfg: Dictionary = NetConfig.parse_args(
		["--server", "--port=9000", "--players=4", "--ai=2", "--map=pangaea"])
	assert_true(cfg["server"], "server flag set")
	assert_eq(int(cfg["port"]), 9000, "port parsed")
	assert_eq(int(cfg["players"]), 4, "players parsed")
	assert_eq(int(cfg["ai"]), 2, "ai parsed")
	assert_eq(str(cfg["map"]), "pangaea", "map parsed")

func test_space_separated_form() -> void:
	var cfg: Dictionary = NetConfig.parse_args(
		["--server", "--port", "9001", "--world", "small"])
	assert_eq(int(cfg["port"]), 9001, "space-separated port")
	assert_eq(str(cfg["world"]), "small", "space-separated world")

func test_ai_clamped_to_player_count() -> void:
	var cfg: Dictionary = NetConfig.parse_args(["--players=2", "--ai=5"])
	assert_eq(int(cfg["ai"]), 2, "ai clamped down to players")
	var cfg2: Dictionary = NetConfig.parse_args(["--players=3", "--ai=-1"])
	assert_eq(int(cfg2["ai"]), 0, "negative ai clamped up to 0")

func test_default_seed_injected() -> void:
	var cfg: Dictionary = NetConfig.parse_args([], 4242)
	assert_eq(int(cfg["seed"]), 4242, "injected default seed used when none given")
	var cfg2: Dictionary = NetConfig.parse_args(["--seed=7"], 4242)
	assert_eq(int(cfg2["seed"]), 7, "explicit seed overrides default")

func test_load_path_and_ignores_unknown() -> void:
	var cfg: Dictionary = NetConfig.parse_args(
		["--no-window", "--server", "--load=/tmp/game.sav", "--bogus=1"])
	assert_eq(str(cfg["load"]), "/tmp/game.sav", "load path parsed")
	assert_true(cfg["server"], "unknown flags do not disturb known ones")

func test_save_path_parsed_and_defaults_empty() -> void:
	assert_eq(str(NetConfig.parse_args([])["save"]), "", "save empty by default")
	var cfg: Dictionary = NetConfig.parse_args(["--save=mp_server.sav"])
	assert_eq(str(cfg["save"]), "mp_server.sav", "save name parsed")

func test_server_requires_save_file() -> void:
	# Server mode without --save is rejected.
	var no_save: Dictionary = NetConfig.parse_args(["--server", "--port=9080"])
	assert_ne(NetConfig.server_config_error(no_save), "",
		"server without --save reports an error")
	# With --save it validates clean.
	var ok: Dictionary = NetConfig.parse_args(["--server", "--save=game.sav"])
	assert_eq(NetConfig.server_config_error(ok), "",
		"server with --save validates")
	# Not server mode at all is also an error for this validator.
	var off: Dictionary = NetConfig.parse_args(["--save=game.sav"])
	assert_ne(NetConfig.server_config_error(off), "",
		"non-server config is flagged")

func test_is_server_mode() -> void:
	assert_true(NetConfig.is_server_mode(["--no-window", "--server"]), "detects --server")
	assert_false(NetConfig.is_server_mode(["--no-window"]), "absent → false")
