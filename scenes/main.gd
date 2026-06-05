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

func init_with_facade(facade, db) -> void:
	_facade = facade
	_db = db

func _ready() -> void:
	if _facade == null:
		_db = load("res://src/core/data_db.gd").new()
		if not _db.load_all():
			push_error("DataDB load failed: " + str(_db.get_errors()))
			return
		_facade = load("res://src/api/sim_facade.gd").new()
		var default_units = _db.constants.get("default_starting_units", [])
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
		_init_node("HUD/VBox/TurnScoreBar", [_facade])
		_init_node("HUD/VBox/ResearchBar", [_facade])
		_init_node("HUD/VBox/SliderPanel", [_facade])
		_init_node("HUD/VBox/SelectionPanel", [_facade, world_view])
		_init_node("HUD/VBox/MessageLog", [_facade])
		_init_node("HUD/VBox/EndTurnButton", [_facade])

	# Wire full-screen overlays (city / tech / policy / save-load)
	var screens = get_node_or_null("Screens")
	if screens != null:
		for sname in ["CityScreen", "TechChooser", "PolicyScreen", "SaveLoadScreen", "PauseMenu"]:
			var sc = screens.get_node_or_null(sname)
			if sc != null and sc.has_method("init"):
				sc.init(_facade)
		# The pause menu delegates Save/Load to the shared SaveLoadScreen.
		var pause = screens.get_node_or_null("PauseMenu")
		var save_load = screens.get_node_or_null("SaveLoadScreen")
		if pause != null and save_load != null and pause.has_method("set_save_load_screen"):
			pause.set_save_load_screen(save_load)

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

func _init_node(path: String, args: Array) -> void:
	var node = get_node_or_null(path)
	if node != null and node.has_method("init"):
		node.callv("init", args)

func get_facade():
	return _facade

func _on_game_won(alliance_id: int) -> void:
	print("Game won by alliance: ", alliance_id)

func _on_player_turn_started(player_id: int) -> void:
	var gs = _facade.get_state()
	var p = gs.get_player(player_id)
	print("Turn started: ", p.name if p != null else str(player_id))

func _on_screen_requested(screen_id: int) -> void:
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
			var diplo = get_node_or_null("DiplomacyScreen")
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
			if pause != null:
				pause.toggle()
		-1:  # close current screen
			pass
