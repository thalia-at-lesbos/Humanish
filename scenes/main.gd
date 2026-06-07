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

# Root scene. Wires all child systems and routes SimFacade signals.
# Call init_with_facade(facade, db) before adding to the tree to supply a
# pre-configured game; otherwise _ready() falls back to a default 2-player game.

var _facade
var _db
var _dbg_log   # DebugLog (advanced debugging; only active in interactive debug builds)
var _extra_screens = {}   # ControlType -> simple read-only info screen node
var _net_client = null     # NetClient (remote multiplayer); null in solo/hotseat play
var _turn_prompts = null   # TurnPrompts node (start-of-turn chooser prompts)

func init_with_facade(facade, db) -> void:
	_facade = facade
	_db = db

# Attach a live NetClient before the scene is added to the tree (remote play).
# Wiring happens in _ready() once the world/HUD nodes exist.
func set_net_client(net_client) -> void:
	_net_client = net_client

func _ready() -> void:
	if _facade == null:
		_db = load("res://src/core/data_db.gd").new()
		if not _db.load_all():
			push_error("DataDB load failed: " + str(_db.get_errors()))
			return
		_facade = load("res://src/api/sim_facade.gd").new()
		var default_units = _db.starting_units_for_techs(_db.constants.get("starting_techs", []))
		_facade.setup(_db, randi(), "tiny", "normal", "warlord",
			[
				{"name": "Player 1", "leader_id": "", "traits": [], "starting_gold": 100,
					"starting_units": default_units},
				{"name": "Player 2", "leader_id": "", "traits": [], "starting_gold": 100,
					"starting_units": default_units}
			],
			["last_standing", "dominance", "time"])

	_facade.connect("game_won", self, "_on_game_won")
	_facade.connect("player_turn_started", self, "_on_player_turn_started")
	_facade.connect("screen_requested", self, "_on_screen_requested")

	var world_view = get_node_or_null("WorldView")
	if world_view != null:
		world_view.init(_facade)
		var fog = world_view.get_node_or_null("FogLayer")
		if fog != null:
			fog.init(_facade)

	# Wire HUD child panels
	var hud = get_node_or_null("HUD")
	if hud != null:
		if hud.has_method("init"):
			hud.init(_facade)
		_init_node("HUD/VBox/MenuBar", [_facade])
		_init_node("HUD/VBox/TurnScoreBar", [_facade])
		_init_node("HUD/VBox/ResearchBar", [_facade])
		_init_node("HUD/VBox/SliderPanel", [_facade])
		_init_node("HUD/VBox/SelectionPanel", [_facade, world_view])
		_init_node("HUD/VBox/MessageLog", [_facade])
		_init_node("HUD/VBox/EndTurnButton", [_facade])

	# Wire full-screen overlays (city / tech / policy / save-load)
	var screens = get_node_or_null("Screens")
	if screens != null:
		for sname in ["CityScreen", "TechChooser", "PolicyScreen", "DiplomacyScreen", "SaveLoadScreen", "PauseMenu"]:
			var sc = screens.get_node_or_null(sname)
			if sc != null and sc.has_method("init"):
				sc.init(_facade)
		# The pause menu delegates Save/Load to the shared SaveLoadScreen.
		var pause = screens.get_node_or_null("PauseMenu")
		var save_load = screens.get_node_or_null("SaveLoadScreen")
		if pause != null and save_load != null and pause.has_method("set_save_load_screen"):
			pause.set_save_load_screen(save_load)
		# Stand up the simple read-only advisor/info screens (§3.1) programmatically
		# so they need no .tscn nodes; each is keyed by the control that opens it.
		_init_extra_screens(screens)
		# Start-of-turn prompts (ask what to research / what to produce). Solo and
		# hotseat only — remote turns are server-driven, not via player_turn_started.
		if _net_client == null:
			_turn_prompts = load("res://scenes/hud/turn_prompts.gd").new()
			_turn_prompts.name = "TurnPrompts"
			add_child(_turn_prompts)
			_turn_prompts.init(_facade,
				screens.get_node_or_null("TechChooser"),
				screens.get_node_or_null("CityScreen"))

	# Wire input router
	var input_router = get_node_or_null("InputRouter")
	if input_router != null:
		input_router.init(_facade, world_view)

	# Wire hotseat manager
	var hsm = get_node_or_null("HotseatManager")
	var pass_screen = get_node_or_null("PassDeviceScreen")
	if hsm != null:
		hsm.init(_facade, world_view)
		if pass_screen != null:
			# The overlay self-wires its OK button and manages its own pause/
			# visibility; we only hand it the facade.
			if pass_screen.has_method("init"):
				pass_screen.init(_facade)
			hsm.set_pass_screen(pass_screen)

	# Wire the advanced debugging subsystem (logging + '~' overlay + terminal
	# console). Inert in release builds and under the headless test runner.
	_wire_debug(world_view)

	# Build fog for the opening player so the map starts hidden (only their own
	# surroundings are revealed) rather than showing the whole world up front.
	if world_view != null:
		var start_fog = world_view.get_node_or_null("FogLayer")
		if start_fog != null:
			start_fog.rebuild(_facade.get_state().current_player_id)
		# player_turn_started is not emitted for the opening player, so center the
		# map on one of their units here at game start.
		if world_view.has_method("center_on_player"):
			world_view.center_on_player(_facade.get_state().current_player_id)

	# Remote multiplayer: refresh the view whenever the server pushes new state.
	_wire_net_client(world_view)

	# Kick off the opening turn. In solo/hotseat play this drives an AI opener so
	# a game that starts on an AI slot does not hang (its first turn is never
	# announced via player_turn_started). In remote play the server owns turn
	# policy, so the client never drives turns locally.
	if _net_client == null and hsm != null:
		hsm.begin()

# ── Remote multiplayer ─────────────────────────────────────────────────────────

# In a remote game the server (not a local pipeline) drives turns: each STATE
# frame re-syncs the facade, so we repaint and re-fog for *our* player here. No
# HotseatManager pass-device flow runs — player_turn_started never fires on the
# client — so this is the client's equivalent "your turn begins" hook.
func _wire_net_client(world_view) -> void:
	if _net_client == null:
		return
	_net_client.connect("state_synced", self, "_on_net_state_synced", [world_view])
	_net_client.connect("game_over", self, "_on_net_game_over")

func _on_net_state_synced(active: bool, world_view) -> void:
	var my_id: int = _net_client.get_player_id()
	if world_view != null:
		var fog = world_view.get_node_or_null("FogLayer")
		if fog != null:
			fog.rebuild(my_id)
		if active and world_view.has_method("center_on_player"):
			world_view.center_on_player(my_id)
	_facade.get_dirty().mark_all()

func _on_net_game_over(alliance_id: int) -> void:
	print("Remote game over — winning alliance: ", alliance_id)

func _init_extra_screens(screens) -> void:
	var defs = {
		IDs.ControlType.OPEN_RELIGION: "res://scenes/screens/religion_screen.gd",
		IDs.ControlType.OPEN_CORPORATION: "res://scenes/screens/corporation_screen.gd",
		IDs.ControlType.OPEN_TURN_LOG: "res://scenes/screens/turn_log_screen.gd",
		IDs.ControlType.OPEN_DOMESTIC_ADVISOR: "res://scenes/screens/domestic_advisor_screen.gd",
		IDs.ControlType.OPEN_VICTORY_PROGRESS: "res://scenes/screens/victory_progress_screen.gd",
		IDs.ControlType.OPEN_OPTIONS: "res://scenes/screens/options_screen.gd",
		IDs.ControlType.OPEN_FINANCE: "res://scenes/screens/finance_screen.gd",
		IDs.ControlType.OPEN_MILITARY: "res://scenes/screens/military_screen.gd",
		IDs.ControlType.OPEN_ESPIONAGE: "res://scenes/screens/espionage_screen.gd",
		IDs.ControlType.OPEN_ENCYCLOPEDIA: "res://scenes/screens/encyclopedia_screen.gd",
	}
	for ctrl in defs:
		var sc = load(defs[ctrl]).new()
		sc.name = "InfoScreen_" + str(ctrl)
		screens.add_child(sc)
		sc.init(_facade)
		_extra_screens[ctrl] = sc

func _init_node(path: String, args: Array) -> void:
	var node = get_node_or_null(path)
	if node != null and node.has_method("init"):
		node.callv("init", args)

# Close the topmost open screen and return true, or return false if nothing
# was visible. Priority: extra info screens → major screens → pause submenus.
# The pause menu itself is not closed here — callers toggle it separately.
func _try_close_open_screen(pause) -> bool:
	for sc in _extra_screens.values():
		if sc != null and sc.visible:
			sc.close_screen()
			return true
	for path in ["Screens/CityScreen", "Screens/TechChooser", "Screens/PolicyScreen",
			"Screens/DiplomacyScreen", "Screens/SaveLoadScreen"]:
		var sc = get_node_or_null(path)
		if sc != null and sc.visible:
			sc.close_screen()
			return true
	if pause != null and pause.visible and pause.has_method("try_close_submenu"):
		if pause.try_close_submenu():
			return true
	return false

func get_facade():
	return _facade

func _on_game_won(alliance_id: int) -> void:
	print("Game won by alliance: ", alliance_id)

func _on_player_turn_started(player_id: int) -> void:
	var gs = _facade.get_state()
	var p = gs.get_player(player_id)
	print("Turn started: ", p.name if p != null else str(player_id))

func _on_screen_requested(screen_id: int) -> void:
	# Score toggle: pure presentation — flip the score bar's visibility.
	if screen_id == IDs.ControlType.TOGGLE_SCORE:
		var score_bar = get_node_or_null("HUD/VBox/TurnScoreBar")
		if score_bar != null:
			score_bar.visible = not score_bar.visible
		return
	# Simple read-only advisor/info screens opened programmatically.
	if _extra_screens.has(screen_id):
		_extra_screens[screen_id].show_screen()
		return
	match screen_id:
		IDs.ControlType.OPEN_CITY_SCREEN:
			var city_screen = get_node_or_null("Screens/CityScreen")
			if city_screen != null:
				var sel = _facade.get_selection()
				city_screen.show_city(sel.head_city())
		IDs.ControlType.OPEN_TECH:
			var tech = get_node_or_null("Screens/TechChooser")
			if tech != null:
				tech.show_screen()
		IDs.ControlType.OPEN_POLICY:
			var policy = get_node_or_null("Screens/PolicyScreen")
			if policy != null:
				policy.show_screen()
		IDs.ControlType.OPEN_DIPLOMACY:
			var diplo = get_node_or_null("Screens/DiplomacyScreen")
			if diplo != null:
				diplo.show_screen()
		IDs.ControlType.OPEN_SAVE_LOAD:
			var sl = get_node_or_null("Screens/SaveLoadScreen")
			if sl != null:
				sl.show_screen()
		IDs.ControlType.QUICK_SAVE:
			var sl = get_node_or_null("Screens/SaveLoadScreen")
			if sl != null:
				sl.quick_save()
		IDs.ControlType.QUICK_LOAD:
			var sl = get_node_or_null("Screens/SaveLoadScreen")
			if sl != null:
				sl.quick_load()
		IDs.ControlType.OPEN_MENU:
			var pause = get_node_or_null("Screens/PauseMenu")
			if not _try_close_open_screen(pause):
				if pause != null:
					pause.toggle()
		-1:  # close current screen
			var pause = get_node_or_null("Screens/PauseMenu")
			_try_close_open_screen(pause)

# ── Advanced debugging ─────────────────────────────────────────────────────────

# Stand up the debug subsystem: a shared DebugLog + DebugConsole drive both the
# '~' overlay and the terminal reader, and the facade's signals are mirrored into
# the log as "extra logging". All of it is silent unless this is an interactive
# windowed debug build (release builds and headless/GUT runs skip it).
func _wire_debug(world_view) -> void:
	var active: bool = _debug_active()

	_dbg_log = DebugLog.new()
	_dbg_log.enabled = active

	var console = DebugConsole.new()
	console.init(_facade, _dbg_log)

	if active:
		# Extra logging: every meaningful facade event becomes a log line.
		_facade.connect("turn_advanced", self, "_dbg_on_turn_advanced")
		_facade.connect("player_turn_started", self, "_dbg_on_player_turn_started")
		_facade.connect("combat_resolved", self, "_dbg_on_combat_resolved")
		_facade.connect("unit_created", self, "_dbg_on_unit_created")
		_facade.connect("settlement_founded", self, "_dbg_on_settlement_founded")
		_facade.connect("technology_completed", self, "_dbg_on_technology_completed")
		_facade.connect("event_emitted", self, "_dbg_on_event_emitted")
		_facade.connect("game_won", self, "_dbg_on_game_won")
		_dbg_log.append("debug", "advanced debugging active (debug build)")

	var fog = null
	if world_view != null:
		fog = world_view.get_node_or_null("FogLayer")

	var overlay = get_node_or_null("Screens/DebugOverlay")
	if overlay != null and overlay.has_method("init"):
		overlay.init(_facade, console, _dbg_log, fog)

	var terminal = get_node_or_null("DebugConsoleTerminal")
	if terminal != null and terminal.has_method("init"):
		terminal.init(console)
		terminal.start_console()   # no-op unless interactive debug build

# Interactive windowed debug build? Excludes release exports and the headless
# GUT runner (so tests stay silent and never read script-mode stdin).
func _debug_active() -> bool:
	if not OS.is_debug_build():
		return false
	for arg in OS.get_cmdline_args():
		if arg == "--no-window" or arg.find("gut_cmdln") != -1:
			return false
	return true

func _dbg_on_turn_advanced(turn_number: int) -> void:
	if _dbg_log != null:
		_dbg_log.append("turn", "turn advanced -> " + str(turn_number), turn_number)

func _dbg_on_player_turn_started(player_id: int) -> void:
	if _dbg_log == null:
		return
	var gs = _facade.get_state()
	var p = gs.get_player(player_id) if gs != null else null
	var pname: String = (p.name if p != null else str(player_id))
	_dbg_log.append("turn", "player turn started: #" + str(player_id) + " " + pname,
		gs.turn_number if gs != null else -1)

func _dbg_on_combat_resolved(result: Dictionary) -> void:
	if _dbg_log != null:
		_dbg_log.append("combat",
			"atk_hp=" + str(result.get("attacker_health_after", "?"))
			+ " def_hp=" + str(result.get("defender_health_after", "?"))
			+ " atk_survived=" + str(result.get("attacker_survived", "?")))

func _dbg_on_unit_created(unit_id: int) -> void:
	if _dbg_log != null:
		_dbg_log.append("unit", "unit created #" + str(unit_id))

func _dbg_on_settlement_founded(settlement_id: int) -> void:
	if _dbg_log != null:
		_dbg_log.append("city", "settlement founded #" + str(settlement_id))

func _dbg_on_technology_completed(player_id: int, tech_id: String) -> void:
	if _dbg_log != null:
		_dbg_log.append("research",
			"player #" + str(player_id) + " completed " + str(tech_id))

func _dbg_on_event_emitted(event_dict: Dictionary) -> void:
	if _dbg_log != null:
		_dbg_log.append("event", str(event_dict.get("type", event_dict)))

func _dbg_on_game_won(alliance_id: int) -> void:
	if _dbg_log != null:
		_dbg_log.append("game", "game won by alliance " + str(alliance_id))
