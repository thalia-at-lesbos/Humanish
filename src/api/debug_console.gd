# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name DebugConsole
extends Reference

# The shared debug console command engine. Like PlayerAI, this is a *client* of
# SimFacade — it is not part of sim/ and holds no Node references, so the same
# engine drives both the terminal reader (scenes/debug/terminal_console.gd) and
# the in-game '~' overlay (scenes/debug/debug_overlay.gd).
#
# Read commands query facade.get_state(); write commands mutate GameState
# directly (that is the whole point of a debug console) and then mark every
# display region dirty so the UI repaints. execute() returns the text result and
# echoes both the command and its output into the shared DebugLog.

var _facade
var _log   # DebugLog (may be null)

func init(facade, log_ref = null) -> void:
	_facade = facade
	_log = log_ref

# Parse and run one command line. Returns the human-readable result text.
func execute(line: String) -> String:
	line = line.strip_edges()
	if line == "":
		return ""
	var parts: Array = line.split(" ", false)
	var cmd: String = String(parts[0]).to_lower()
	var args: Array = []
	for i in range(1, parts.size()):
		args.append(parts[i])

	var out: String = _dispatch(cmd, args)
	if _log != null:
		var turn: int = _turn()
		_log.append("console", "> " + line, turn)
		if out != "":
			for l in out.split("\n", false):
				_log.append("console", l, turn)
	return out

# ── Dispatch ──────────────────────────────────────────────────────────────────

func _dispatch(cmd: String, args: Array) -> String:
	var gs = _facade.get_state() if _facade != null else null
	if gs == null:
		return "no game state"

	match cmd:
		"help", "?":
			return _help()
		"state", "status":
			return _cmd_state(gs)
		"players":
			return _cmd_players(gs)
		"cities":
			return _cmd_cities(gs)
		"units":
			return _cmd_units(gs)
		"log":
			if _log == null:
				return "no log"
			var n: int = int(args[0]) if args.size() >= 1 else 20
			return _log.formatted(n).strip_edges()
		"clearlog":
			if _log != null:
				_log.clear()
			return "log cleared"
		"gold":
			return _cmd_gold(gs, args, false)
		"addgold":
			return _cmd_gold(gs, args, true)
		"tech":
			return _cmd_tech(gs, args)
		"pop":
			return _cmd_pop(gs, args)
		"heal":
			return _cmd_heal(gs, args)
		"kill":
			return _cmd_kill(gs, args)
		"war":
			return _cmd_war(gs, args, true)
		"peace":
			return _cmd_war(gs, args, false)
		"setturn":
			return _cmd_setturn(gs, args)
		"win":
			return _cmd_win(gs, args)
		"hash":
			return "state_hash = " + str(_facade.state_hash())
		"seed":
			if gs.rng == null:
				return "no rng"
			return "rng seed=" + str(gs.rng.get_state().get("seed", "?")) \
				+ " state=" + str(gs.rng.get_state().get("state", "?"))
		"endturn":
			_facade.apply_command(Commands.end_turn(gs.current_player_id))
			return "ended turn for player " + str(gs.current_player_id)
		_:
			return "unknown command: " + cmd + " (try 'help')"

func _help() -> String:
	return \
		"commands:\n" \
		+ "  help                      this list\n" \
		+ "  state                     turn / player / counts summary\n" \
		+ "  players | cities | units  list game objects\n" \
		+ "  log [n]                   show last n log lines (default 20)\n" \
		+ "  clearlog                  empty the log buffer\n" \
		+ "  gold <pid> <amt>          set a player's treasury\n" \
		+ "  addgold <pid> <amt>       add to a player's treasury\n" \
		+ "  tech <pid> <tech_id>      grant a technology\n" \
		+ "  pop <sid> <n>             set a settlement's population\n" \
		+ "  heal <uid|all>            restore unit health to 100\n" \
		+ "  kill <uid>                remove a unit\n" \
		+ "  war <pid> <alliance_id>   declare war on an alliance\n" \
		+ "  peace <pid> <alliance_id> make peace with an alliance\n" \
		+ "  setturn <n>               set the turn counter\n" \
		+ "  win <alliance_id>         force a winning alliance\n" \
		+ "  seed                      show the RNG seed/state\n" \
		+ "  hash                      print the determinism state hash\n" \
		+ "  endturn                   end the current player's turn\n" \
		+ "(the GUI overlay also adds 'reveal' and 'fog' map-view helpers)"

# ── Read commands ───────────────────────────────────────────────────────────────

func _cmd_state(gs) -> String:
	var p = gs.get_player(gs.current_player_id)
	var pname: String = (p.name if p != null else "world")
	return "turn=" + str(gs.turn_number) + "/" + str(gs.max_turns) \
		+ "  current=" + str(gs.current_player_id) + " (" + pname + ")" \
		+ "  players=" + str(gs.players.size()) \
		+ "  cities=" + str(gs.settlements.size()) \
		+ "  units=" + str(gs.units.size()) \
		+ "  winner=" + str(gs.winning_alliance_id)

func _cmd_players(gs) -> String:
	var out: String = ""
	for p in gs.players:
		out += "#" + str(p.id) + " " + p.name + "  gold=" + str(p.treasury) \
			+ "  techs=" + str(p.technologies.size()) \
			+ "  alliance=" + str(p.alliance_id) \
			+ ("  [AI]" if p.is_ai else "") + "\n"
	return out.strip_edges()

func _cmd_cities(gs) -> String:
	var out: String = ""
	for s in gs.settlements:
		out += "#" + str(s.id) + " " + s.name + "  owner=" + str(s.owner_player_id) \
			+ "  pop=" + str(s.population) + "  (" + str(s.x) + "," + str(s.y) + ")\n"
	if out == "":
		return "(no settlements)"
	return out.strip_edges()

func _cmd_units(gs) -> String:
	var out: String = ""
	for u in gs.units:
		out += "#" + str(u.id) + " " + u.unit_type_id + "  owner=" + str(u.owner_player_id) \
			+ "  hp=" + str(u.health) + "  (" + str(u.x) + "," + str(u.y) + ")\n"
	if out == "":
		return "(no units)"
	return out.strip_edges()

# ── Write commands ──────────────────────────────────────────────────────────────

func _cmd_gold(gs, args: Array, add: bool) -> String:
	if args.size() < 2:
		return "usage: " + ("addgold" if add else "gold") + " <pid> <amt>"
	var p = gs.get_player(int(args[0]))
	if p == null:
		return "no such player: " + str(args[0])
	var amt: int = int(args[1])
	p.treasury = (p.treasury + amt) if add else amt
	_refresh()
	return p.name + " treasury = " + str(p.treasury)

func _cmd_tech(gs, args: Array) -> String:
	if args.size() < 2:
		return "usage: tech <pid> <tech_id>"
	var p = gs.get_player(int(args[0]))
	if p == null:
		return "no such player: " + str(args[0])
	var tech_id: String = String(args[1])
	if gs.db != null and gs.db.get_technology(tech_id).empty():
		return "no such tech: " + tech_id
	if p.has_tech(tech_id):
		return p.name + " already has " + tech_id
	p.technologies.append(tech_id)
	_refresh()
	return "granted " + tech_id + " to " + p.name

func _cmd_pop(gs, args: Array) -> String:
	if args.size() < 2:
		return "usage: pop <sid> <n>"
	var s = gs.get_settlement(int(args[0]))
	if s == null:
		return "no such settlement: " + str(args[0])
	var n: int = int(args[1])
	s.population = n if n >= 1 else 1
	_refresh()
	return s.name + " population = " + str(s.population)

func _cmd_heal(gs, args: Array) -> String:
	if args.size() < 1:
		return "usage: heal <uid|all>"
	if String(args[0]).to_lower() == "all":
		var count: int = 0
		for u in gs.units:
			if u.owner_player_id == gs.current_player_id:
				u.health = 100
				count += 1
		_refresh()
		return "healed " + str(count) + " units"
	var unit = gs.get_unit(int(args[0]))
	if unit == null:
		return "no such unit: " + str(args[0])
	unit.health = 100
	_refresh()
	return "healed unit #" + str(unit.id)

func _cmd_kill(gs, args: Array) -> String:
	if args.size() < 1:
		return "usage: kill <uid>"
	var uid: int = int(args[0])
	if gs.get_unit(uid) == null:
		return "no such unit: " + str(uid)
	Stack.remove_unit(gs.units, uid)
	_refresh()
	return "removed unit #" + str(uid)

func _cmd_war(gs, args: Array, declare: bool) -> String:
	if args.size() < 2:
		return "usage: " + ("war" if declare else "peace") + " <pid> <alliance_id>"
	var cmd: Dictionary
	if declare:
		cmd = Commands.declare_war(int(args[0]), int(args[1]))
	else:
		cmd = Commands.make_peace(int(args[0]), int(args[1]))
	var ok: bool = _facade.apply_command(cmd)
	_refresh()
	return ("ok" if ok else "rejected") + ": " \
		+ ("war on" if declare else "peace with") + " alliance " + str(args[1])

func _cmd_setturn(gs, args: Array) -> String:
	if args.size() < 1:
		return "usage: setturn <n>"
	gs.turn_number = int(args[0])
	_refresh()
	return "turn_number = " + str(gs.turn_number)

func _cmd_win(gs, args: Array) -> String:
	if args.size() < 1:
		return "usage: win <alliance_id>"
	gs.winning_alliance_id = int(args[0])
	_refresh()
	return "winning_alliance_id = " + str(gs.winning_alliance_id)

# ── Helpers ─────────────────────────────────────────────────────────────────────

func _turn() -> int:
	var gs = _facade.get_state() if _facade != null else null
	return gs.turn_number if gs != null else -1

# Repaint the whole UI after a direct state mutation.
func _refresh() -> void:
	if _facade != null and _facade.get_dirty() != null:
		_facade.get_dirty().mark_all()
