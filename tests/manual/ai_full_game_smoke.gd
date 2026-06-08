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

# Run a full game to win condition (or 10-minute wall-clock timeout) with all
# AI opponents. PlayerAI drives each player's turn; DebugConsole provides
# periodic state snapshots. All facade signals are captured inline so the log
# is chronologically synchronized with the game's event stream.
#
# Usage:
#   godot3 --no-window -s res://tests/manual/ai_full_game_smoke.gd
#   godot3 --no-window -s res://tests/manual/ai_full_game_smoke.gd -- \
#       --players=4 --seed=99 --map=islands --size=standard --log=/tmp/run.log
#
# Exit 0: win reached with zero errors.
# Exit 1: timeout, no win condition, or at least one error recorded.

const TIMEOUT_MS    : int = 600_000   # 10 minutes wall clock
const SNAP_EVERY    : int = 25        # debug-console dump interval (world turns)

var _facade = null
var _dlog    : DebugLog    = null
var _console : DebugConsole = null
var _file    : File        = null
var _start_ms: int         = 0
var _errors  : int         = 0
var _events  : int         = 0
var _won     : bool        = false
var _won_id  : int         = -1


# ── Entry ──────────────────────────────────────────────────────────────────────

func _init() -> void:
	_start_ms = OS.get_ticks_msec()

	# -- Optional CLI overrides (pass after the " -- " separator) ---------------
	var num_players : int    = 3
	var seed_val    : int    = 42
	var map_type    : String = "continents"
	var world_size  : String = "small"
	var log_path    : String = ""

	for arg in OS.get_cmdline_args():
		var kv: PoolStringArray = arg.split("=", false, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"--players": num_players = int(kv[1])
			"--seed"   : seed_val    = int(kv[1])
			"--map"    : map_type    = kv[1]
			"--size"   : world_size  = kv[1]
			"--log"    : log_path    = kv[1]

	if log_path == "":
		var dt: Dictionary = OS.get_datetime()
		log_path = "user://ai_game_%04d%02d%02d_%02d%02d%02d.log" % [
			int(dt["year"]),   int(dt["month"]),  int(dt["day"]),
			int(dt["hour"]),   int(dt["minute"]), int(dt["second"]),
		]

	# -- Open log file ----------------------------------------------------------
	_file = File.new()
	if _file.open(log_path, File.WRITE) != OK:
		print("FATAL: cannot open log: ", log_path)
		quit(1)
		return

	_w("# Humanish — AI Full-Game Smoke Run")
	_w("# Log:       " + log_path)
	_w("# Config:    players=%d  seed=%d  map=%s  size=%s" % [
		num_players, seed_val, map_type, world_size])
	_w("# Timeout:   %d s" % (TIMEOUT_MS / 1000))
	_w("# Started:   " + _utc())
	_w("")

	# -- Load game data ---------------------------------------------------------
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()

	# -- DebugLog: ring buffer, mirrored to stdout; console appends to it -------
	_dlog = DebugLog.new()
	_dlog.enabled = true

	# -- All-AI player configs (society data fills leader/traits when available) -
	num_players = int(clamp(num_players, 2, 6))
	var societies  : Dictionary = db.get_societies()
	var soc_list   : Array      = societies.values()
	var start_units: Array      = db.starting_units_for_techs(
			db.constants.get("starting_techs", []))
	var player_configs : Array  = []

	for i in range(num_players):
		var cfg : Dictionary = {
			"name"          : "AI%d" % (i + 1),
			"leader_id"     : "",
			"traits"        : [],
			"starting_gold" : 100,
			"starting_units": start_units,
			"is_ai"         : true,
		}
		if i < soc_list.size():
			var soc : Dictionary = soc_list[i]
			cfg["name"]          = str(soc.get("leader_name", "AI%d" % (i + 1)))
			cfg["leader_id"]     = str(soc.get("leader_id",   ""))
			cfg["traits"]        = soc.get("traits", [])
			cfg["starting_gold"] = int(soc.get("starting_gold", 100))
		player_configs.append(cfg)

	# -- Facade setup -----------------------------------------------------------
	_facade = load("res://src/api/sim_facade.gd").new()
	_facade.setup(db, seed_val, world_size, "normal", "warlord", player_configs,
			["last_standing", "dominance", "cultural", "diplomatic", "time"],
			map_type, false)

	# -- DebugConsole: drives periodic state snapshots, feeds _dlog -------------
	_console = DebugConsole.new()
	_console.init(_facade, _dlog)

	# -- Connect every facade signal so the log is fully synchronized -----------
	_facade.connect("game_won",             self, "_sig_won")
	_facade.connect("turn_advanced",        self, "_sig_turn")
	_facade.connect("player_turn_started",  self, "_sig_player_start")
	_facade.connect("unit_created",         self, "_sig_unit_created")
	_facade.connect("settlement_founded",   self, "_sig_founded")
	_facade.connect("city_conquered",       self, "_sig_conquered")
	_facade.connect("city_razed",           self, "_sig_razed")
	_facade.connect("city_flipped",         self, "_sig_flipped")
	_facade.connect("technology_completed", self, "_sig_tech")
	_facade.connect("era_advanced",         self, "_sig_era")
	_facade.connect("combat_resolved",      self, "_sig_combat")
	_facade.connect("event_emitted",        self, "_sig_event")
	_facade.connect("assembly_event",       self, "_sig_assembly")
	_facade.connect("nuclear_detonated",    self, "_sig_nuke")

	# -- Initial state snapshot via debug console -------------------------------
	_w("## INITIAL STATE")
	_snap("state")
	_snap("players")
	_w("")
	_w("## EVENT LOG")
	_w("# Format: T{turn} +{elapsed_s}s [{category}] {detail}")
	_w("")

	# ── Main game loop (all work is synchronous; signals fire during commands) ──

	var last_pid : int = -1
	var stall    : int = 0

	while true:
		var elapsed_ms : int = OS.get_ticks_msec() - _start_ms
		if elapsed_ms >= TIMEOUT_MS:
			_note("TIMEOUT: %ds elapsed — no win condition reached" % (elapsed_ms / 1000))
			break

		var gs = _facade.get_state()
		if gs.winning_alliance_id >= 0:
			break

		var pid : int = gs.current_player_id
		if pid < 0:
			_err("current_player_id=-1 at T%d — game loop cannot continue" % gs.turn_number)
			break

		# Stall guard: if the same player is still active across 3 loop
		# iterations the end_turn pipeline has not advanced — abort cleanly.
		if pid == last_pid:
			stall += 1
			if stall >= 3:
				_err("stall: player %d still active after %d iterations at T%d" % [
					pid, stall, gs.turn_number])
				break
		else:
			last_pid = pid
			stall    = 0

		_do_ai_turn(pid)

		# Periodic snapshot every SNAP_EVERY world turns (fires when turn_number
		# crosses a multiple of SNAP_EVERY after a full round completes).
		var gs2 = _facade.get_state()
		if gs2.turn_number != gs.turn_number and (gs2.turn_number % SNAP_EVERY) == 0:
			_w("")
			_w("### SNAPSHOT T%d" % gs2.turn_number)
			_snap("state")
			_snap("players")
			_snap("cities")
			_snap("units")
			_snap("log 30")
			_w("")

	# ── End-of-run report ─────────────────────────────────────────────────────

	var elapsed_s : float = (OS.get_ticks_msec() - _start_ms) / 1000.0
	var final_gs  = _facade.get_state()

	_w("")
	_w("## FINAL SNAPSHOT")
	_snap("state")
	_snap("players")
	_snap("cities")
	_snap("units")

	# The DebugLog holds every line the console wrote during snapshot commands —
	# dump it here as the synchronized debug-console session record.
	_w("")
	_w("## DEBUG CONSOLE SESSION LOG")
	var dlog_text := _dlog.formatted(0)
	if dlog_text == "":
		_w("(no debug console output captured)")
	else:
		_w(dlog_text)

	_w("")
	_w("## SUMMARY")
	if _won:
		var a = final_gs.get_alliance(_won_id)
		var members := ""
		if a:
			for mid in a.member_player_ids:
				var mp = final_gs.get_player(mid)
				if mp:
					members += " " + str(mp.name)
		_w("RESULT  WIN     alliance=%d (%s)  turn=%d" % [
			_won_id, members.strip_edges(), final_gs.turn_number])
	else:
		_w("RESULT  NO-WIN  turn=%d" % final_gs.turn_number)
	_w("Events  %d" % _events)
	_w("Errors  %d" % _errors)
	_w("Time    %.1f s" % elapsed_s)
	_w("Turns   %d" % final_gs.turn_number)

	_file.close()
	print("ai_full_game_smoke: done  errors=%d  won=%s  log=%s" % [
		_errors, str(_won), log_path])
	quit(0 if (_won and _errors == 0) else 1)


# ── AI turn driver ─────────────────────────────────────────────────────────────

func _do_ai_turn(pid: int) -> void:
	var gs     = _facade.get_state()
	var player = gs.get_player(pid)
	if player == null:
		_err("no player record for id=%d at T%d" % [pid, gs.turn_number])
		return
	if player.is_eliminated:
		# PlayerAI guards this too, but belt-and-suspenders: log and force advance.
		_err("eliminated player %d (%s) is still scheduled at T%d — forcing end_turn" % [
			pid, str(player.name), gs.turn_number])
		_facade.apply_command(Commands.end_turn(pid))
		return

	var pid_before  : int = gs.current_player_id
	var turn_before : int = gs.turn_number

	PlayerAI.take_turn(_facade, pid)

	# If end_turn inside PlayerAI failed to advance state, record a diagnostic.
	var gs2 = _facade.get_state()
	if gs2.current_player_id == pid_before and gs2.turn_number == turn_before:
		_err("AI turn for player %d (%s) did not advance state at T%d" % [
			pid, str(player.name), turn_before])


# ── Signal handlers ────────────────────────────────────────────────────────────

func _sig_won(alliance_id: int) -> void:
	_won    = true
	_won_id = alliance_id
	_ev("game_won", "alliance=%d" % alliance_id)

func _sig_turn(turn_number: int) -> void:
	_ev("turn_advanced", "T%d" % turn_number)

func _sig_player_start(player_id: int) -> void:
	var gs  = _facade.get_state()
	var p   = gs.get_player(player_id)
	var pn  := str(p.name) if p else "?"
	_ev("player_turn", "player=%d (%s) T%d" % [player_id, pn, gs.turn_number])

func _sig_unit_created(unit_id: int) -> void:
	var gs = _facade.get_state()
	var u  = gs.get_unit(unit_id)
	if u:
		_ev("unit_created", "id=%d type=%s owner=%d pos=(%d,%d)" % [
			unit_id, str(u.unit_type_id), u.owner_player_id, u.x, u.y])
	else:
		_ev("unit_created", "id=%d" % unit_id)

func _sig_founded(settlement_id: int) -> void:
	var gs = _facade.get_state()
	var s  = gs.get_settlement(settlement_id)
	if s:
		_ev("city_founded", "id=%d name=%s owner=%d pos=(%d,%d)" % [
			settlement_id, str(s.name), s.owner_player_id, s.x, s.y])
	else:
		_ev("city_founded", "id=%d" % settlement_id)

func _sig_conquered(settlement_id: int, captor_player_id: int) -> void:
	var gs   = _facade.get_state()
	var s    = gs.get_settlement(settlement_id)
	var sn   := str(s.name) if s else "?"
	_ev("city_conquered", "city=%d (%s) captor=%d" % [
		settlement_id, sn, captor_player_id])

func _sig_razed(settlement_id: int, by_player_id: int) -> void:
	_ev("city_razed", "city=%d by_player=%d" % [settlement_id, by_player_id])

func _sig_flipped(settlement_id: int, from_pid: int, to_pid: int) -> void:
	var gs  = _facade.get_state()
	var s   = gs.get_settlement(settlement_id)
	var sn  := str(s.name) if s else "?"
	_ev("city_flipped", "city=%d (%s) from=%d to=%d" % [
		settlement_id, sn, from_pid, to_pid])

func _sig_tech(player_id: int, tech_id: String) -> void:
	var gs  = _facade.get_state()
	var p   = gs.get_player(player_id)
	var pn  := str(p.name) if p else "?"
	_ev("tech_completed", "player=%d (%s) tech=%s" % [player_id, pn, tech_id])

func _sig_era(player_id: int, from_era, to_era) -> void:
	var gs  = _facade.get_state()
	var p   = gs.get_player(player_id)
	var pn  := str(p.name) if p else "?"
	_ev("era_advanced", "player=%d (%s) %s → %s" % [
		player_id, pn, str(from_era), str(to_era)])

func _sig_combat(result: Dictionary) -> void:
	# Combat fires very frequently; log only the critical outcome fields to keep
	# the log readable. Full result dict is available via DebugConsole "log".
	var att  := str(result.get("attacker_id",    "?"))
	var def  := str(result.get("defender_id",    "?"))
	var a_ok := str(result.get("attacker_alive", "?"))
	var d_ok := str(result.get("defender_alive", "?"))
	_ev("combat", "att=%s def=%s att_alive=%s def_alive=%s" % [att, def, a_ok, d_ok])

func _sig_event(event: Dictionary) -> void:
	_ev("event", str(event))

func _sig_assembly(event: Dictionary) -> void:
	_ev("assembly", str(event))

func _sig_nuke(result: Dictionary) -> void:
	_ev("NUCLEAR", str(result))


# ── Helpers ────────────────────────────────────────────────────────────────────

# Write one line to the log file and mirror it to stdout.
func _w(line: String) -> void:
	_file.store_line(line)
	print(line)

# Timestamp prefix: "T{turn} +{elapsed_s}s ".
func _ts(turn: int) -> String:
	var s : int = (OS.get_ticks_msec() - _start_ms) / 1000
	return "T%d +%ds " % [turn, s]

# Log a game event (increments counter).
func _ev(category: String, text: String) -> void:
	_events += 1
	var turn: int = _facade.get_state().turn_number if _facade else 0
	_w(_ts(turn) + "[%s] %s" % [category, text])

# Log a contextual note (no counter — observer/diagnostic, not a game event).
func _note(text: String) -> void:
	var turn: int = _facade.get_state().turn_number if _facade else 0
	_w(_ts(turn) + "[NOTE] " + text)

# Log an error and increment the error counter.
func _err(text: String) -> void:
	_errors += 1
	var turn: int = _facade.get_state().turn_number if _facade else 0
	_w(_ts(turn) + "[ERROR] " + text)

# Execute a debug-console command and write its output to the log.
func _snap(cmd: String) -> void:
	var out: String = _console.execute(cmd)
	if out != "":
		_w(out)

# ISO-8601-ish UTC string for the run header.
func _utc() -> String:
	var dt: Dictionary = OS.get_datetime()
	return "%04d-%02d-%02d %02d:%02d:%02d UTC" % [
		int(dt["year"]),   int(dt["month"]),  int(dt["day"]),
		int(dt["hour"]),   int(dt["minute"]), int(dt["second"]),
	]
