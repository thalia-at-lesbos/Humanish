# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name NetConfig

# Parses the command-line switches that put the engine into headless server mode
# (see scenes/net/server_runner.gd). Pure static and side-effect free: it takes a
# raw args array (normally OS.get_cmdline_args()) and returns a config Dictionary,
# so it is fully testable without launching a process.
#
# Recognised switches (both "--flag value" and "--flag=value" forms work):
#   --server                 enable server mode (otherwise {server:false})
#   --port=N                 listen port (default 9080)
#   --name=STR               human-readable server name sent in WELCOME
#   --save=PATH              REQUIRED in server mode: file the server autosaves the
#                            authoritative game to every turn (bare name → under the
#                            user saves dir; contains "/" → used as a full path)
#   --load=PATH              start the authoritative game from a .sav file
#   --new                    start a fresh game (the default when --load is absent)
#   --players=N              total player slots for a new game (default 2)
#   --ai=N                   how many of those slots the server plays itself (default 0)
#   --world=ID               world size id (default "tiny")
#   --map=ID                 map type id (default "continents")
#   --pace=ID                pace id (default "normal")
#   --difficulty=ID          difficulty id (default "warlord")
#   --seed=N                 RNG seed (default: random when launched)
# Unknown switches are ignored so the engine's own args (e.g. --no-window) pass
# through harmlessly.

const DEFAULT_PORT: int = 9080

# Parse an args array into a config Dictionary. `default_seed` lets the caller
# inject a randomised seed (NetConfig stays deterministic and pure itself).
static func parse_args(args: Array, default_seed: int = 0) -> Dictionary:
	var cfg: Dictionary = {
		"server": false,
		"port": DEFAULT_PORT,
		"name": "Humanish Server",
		"save": "",
		"load": "",
		"players": 2,
		"ai": 0,
		"world": "tiny",
		"map": "continents",
		"pace": "normal",
		"difficulty": "warlord",
		"seed": default_seed,
	}
	var i: int = 0
	while i < args.size():
		var raw: String = str(args[i])
		if not raw.begins_with("--"):
			i += 1
			continue
		var key: String = raw.substr(2, raw.length() - 2)
		var value: String = ""
		var have_value: bool = false
		var eq: int = key.find("=")
		if eq >= 0:
			value = key.substr(eq + 1, key.length() - eq - 1)
			key = key.substr(0, eq)
			have_value = true
		elif i + 1 < args.size() and not str(args[i + 1]).begins_with("--"):
			value = str(args[i + 1])
			have_value = true
			i += 1
		match key:
			"server":
				cfg["server"] = true
			"new":
				cfg["load"] = ""
			"port":
				if have_value and value.is_valid_integer():
					cfg["port"] = int(value)
			"name":
				if have_value:
					cfg["name"] = value
			"save":
				if have_value:
					cfg["save"] = value
			"load":
				if have_value:
					cfg["load"] = value
			"players":
				if have_value and value.is_valid_integer():
					cfg["players"] = int(value)
			"ai":
				if have_value and value.is_valid_integer():
					cfg["ai"] = int(value)
			"world":
				if have_value:
					cfg["world"] = value
			"map":
				if have_value:
					cfg["map"] = value
			"pace":
				if have_value:
					cfg["pace"] = value
			"difficulty":
				if have_value:
					cfg["difficulty"] = value
			"seed":
				if have_value and value.is_valid_integer():
					cfg["seed"] = int(value)
		i += 1
	# Clamp the AI count into [0, players] so the server never claims to play more
	# slots than exist (the remainder are the remote-human slots clients fill).
	if cfg["ai"] < 0:
		cfg["ai"] = 0
	if cfg["ai"] > cfg["players"]:
		cfg["ai"] = cfg["players"]
	return cfg

# Validate a parsed server config. Returns "" when good, otherwise a human-
# readable reason the server must not start. A default save file is mandatory in
# server mode so the authoritative game is always persisted (it autosaves every
# turn). Testable without launching anything.
static func server_config_error(cfg: Dictionary) -> String:
	if not bool(cfg.get("server", false)):
		return "not server mode"
	if str(cfg.get("save", "")) == "":
		return "a default save file is required: pass --save=<file>"
	return ""

# True when the args request server mode. Thin helper so launchers don't reparse.
static func is_server_mode(args: Array) -> bool:
	for a in args:
		var s: String = str(a)
		if s == "--server" or s.begins_with("--server="):
			return true
	return false
