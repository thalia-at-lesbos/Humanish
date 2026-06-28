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

# The simple read-only advisor/info screens (§3.1 OPEN_* controls, §11) build
# their text content from real game state without error.

var _SCREENS = [
	"res://scenes/screens/religion_screen.gd",
	"res://scenes/screens/corporation_screen.gd",
	"res://scenes/screens/turn_log_screen.gd",
	"res://scenes/screens/domestic_advisor_screen.gd",
	"res://scenes/screens/victory_progress_screen.gd",
	"res://scenes/screens/options_screen.gd",
	"res://scenes/screens/finance_screen.gd",
	"res://scenes/screens/military_screen.gd",
	"res://scenes/screens/espionage_screen.gd",
	"res://scenes/screens/encyclopedia_screen.gd",
]

func test_info_screens_build_without_error() -> void:
	var facade = setup_facade(91)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	make_settlement(gs, gs.players[0].id, 5, 5, 3)
	make_unit(gs, "warrior", gs.players[0].id, 6, 6)

	for path in _SCREENS:
		var screen = load(path).new()
		add_child_autofree(screen)
		screen.init(facade)
		screen.show_screen()
		assert_true(screen.visible, "Screen %s should be visible after show_screen()" % path)
		assert_true(screen.get_child_count() > 0,
			"Screen %s should build text content from state" % path)

func test_close_screen_hides_info_screen() -> void:
	var facade = setup_facade(93)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	make_settlement(gs, gs.players[0].id, 5, 5, 3)

	for path in _SCREENS:
		var screen = load(path).new()
		add_child_autofree(screen)
		screen.init(facade)
		screen.show_screen()
		assert_true(screen.visible, "Screen %s visible after show_screen()" % path)
		screen.close_screen()
		assert_false(screen.visible, "Screen %s hidden after close_screen()" % path)

func _find_button(node, text):
	for c in node.get_children():
		if c is Button and c.text == text:
			return c
		var found = _find_button(c, text)
		if found != null:
			return found
	return null

func _find_by_text(node, needle: String):
	for c in node.get_children():
		if (c is Label or c is Button) and needle in c.text:
			return c
		var found = _find_by_text(c, needle)
		if found != null:
			return found
	return null

func _make_espionage_facade(seed_val: int):
	var facade = setup_facade(seed_val, "small",
		[{"name": "Rome",   "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "Greece", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var cost: int = gs.db.get_constant("intel_mission_cost", 100)
	gs.get_player(gs.players[0].id).intel_points = {gs.alliances[1].id: cost + 50}
	return facade

func test_espionage_screen_shows_select_mission_button_when_enough_ep() -> void:
	var facade = _make_espionage_facade(200)
	var screen = load("res://scenes/screens/espionage_screen.gd").new()
	add_child_autofree(screen)
	screen.init(facade)
	screen.show_screen()
	assert_not_null(_find_button(screen, null) if false else _find_by_text(screen, "Select Mission"),
		"Espionage screen must show a 'Select Mission…' button when EP >= cost")

func test_espionage_menu_shows_missions_and_abort() -> void:
	var facade = _make_espionage_facade(201)
	var gs = facade.get_state()
	var target_id: int = gs.alliances[1].id
	var menu = load("res://scenes/screens/espionage_menu.gd").new()
	add_child_autofree(menu)
	menu.init(facade, target_id, null)
	assert_not_null(_find_button(menu, null) if false else _find_by_text(menu, "Steal Tech"),
		"Espionage menu must list Steal Tech")
	assert_not_null(_find_by_text(menu, "Sabotage"),   "Espionage menu must list Sabotage")
	assert_not_null(_find_by_text(menu, "Incite Revolt"), "Espionage menu must list Incite Revolt")
	assert_not_null(_find_button(menu, "Abort"),        "Espionage menu must have an Abort button")

func test_espionage_menu_shows_cost_and_interception() -> void:
	var facade = _make_espionage_facade(202)
	var gs = facade.get_state()
	var target_id: int = gs.alliances[1].id
	var cost: int = facade.get_espionage_mission_cost(target_id)
	var menu = load("res://scenes/screens/espionage_menu.gd").new()
	add_child_autofree(menu)
	menu.init(facade, target_id, null)
	assert_not_null(_find_by_text(menu, "cost"),           "Menu displays EP cost")
	assert_not_null(_find_by_text(menu, "Interception"),   "Menu displays interception chance")
	assert_true(cost > 0, "get_espionage_mission_cost returns a positive cost")

func test_espionage_menu_abort_closes_without_acting() -> void:
	var facade = _make_espionage_facade(203)
	var gs = facade.get_state()
	var target_id: int = gs.alliances[1].id
	var have_before: int = int(gs.get_player(gs.players[0].id).intel_points.get(target_id, 0))
	var menu = load("res://scenes/screens/espionage_menu.gd").new()
	add_child(menu)
	menu.init(facade, target_id, null)
	menu._on_abort()
	yield(get_tree(), "idle_frame")
	var have_after: int = int(gs.get_player(gs.players[0].id).intel_points.get(target_id, 0))
	assert_eq(have_before, have_after, "Aborting the menu must not spend any EP")

func test_espionage_menu_mission_spends_ep() -> void:
	var facade = _make_espionage_facade(204)
	var gs = facade.get_state()
	gs.get_player(gs.players[1].id).technologies = ["mining"]
	var target_id: int = gs.alliances[1].id
	var have_before: int = int(gs.get_player(gs.players[0].id).intel_points.get(target_id, 0))
	var menu = load("res://scenes/screens/espionage_menu.gd").new()
	add_child(menu)
	menu.init(facade, target_id, null)
	menu._on_mission("steal_tech")
	yield(get_tree(), "idle_frame")
	var have_after: int = int(gs.get_player(gs.players[0].id).intel_points.get(target_id, 0))
	assert_true(have_after < have_before, "Launching a mission spends EP")

func test_encyclopedia_new_collectors_return_entries() -> void:
	var facade = setup_facade(95)
	var db = facade._db
	var screen = load("res://scenes/screens/encyclopedia_screen.gd").new()
	add_child_autofree(screen)
	screen.init(facade)
	# Terrain tab: terrain entries + a "Features" header, all data-driven.
	var terrain = screen._collect_terrain(db)
	assert_true(terrain.size() > 0, "Terrain collector returns entries")
	var saw_terrain := false
	var saw_feature := false
	var saw_hills := false
	for it in terrain:
		if it.get("_kind", "") == "terrain":
			saw_terrain = true
		if it.get("_kind", "") == "feature":
			saw_feature = true
		if str(it.get("id", "")) == "hills":
			saw_hills = true
			assert_eq(int(it.get("sight_bonus", 0)), 1, "Hills carry +1 sight bonus")
			assert_true(bool(it.get("blocks_sight", false)), "Hills block line of sight")
	assert_true(saw_terrain, "Terrain collector includes terrain entries")
	assert_true(saw_feature, "Terrain collector includes feature entries")
	assert_true(saw_hills, "Terrain collector includes hills")
	# Improvements tab: mine must be hills-only.
	var imps = screen._collect_improvements(db)
	assert_true(imps.size() > 0, "Improvements collector returns entries")
	var mine_lf := []
	for it in imps:
		if str(it.get("id", "")) == "mine":
			mine_lf = it.get("allowed_landforms", []) as Array
	assert_eq(mine_lf, ["hill"], "Mine is buildable only on hills")

func test_encyclopedia_units_tab_marks_ocean_capability() -> void:
	var facade = setup_facade(96)
	var screen = load("res://scenes/screens/encyclopedia_screen.gd").new()
	add_child_autofree(screen)
	screen.init(facade)
	var db = facade._db
	# Caravel is ocean-going; Galley is coastal-only — the detail must say so.
	var box1 = VBoxContainer.new()
	add_child_autofree(box1)
	screen._detail_unit(box1, db.units["caravel"])
	assert_not_null(_find_by_text(box1, "ocean-going"),
		"Caravel detail labels it ocean-going")
	var box2 = VBoxContainer.new()
	add_child_autofree(box2)
	screen._detail_unit(box2, db.units["galley"])
	assert_not_null(_find_by_text(box2, "coastal only"),
		"Galley detail labels it coastal only")

func test_options_screen_score_toggle_routes_through_facade() -> void:
	var facade = setup_facade(92)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var screen = load("res://scenes/screens/options_screen.gd").new()
	add_child_autofree(screen)
	screen.init(facade)
	screen.show_screen()
	watch_signals(facade)
	screen._on_toggle_score()
	assert_signal_emitted(facade, "screen_requested",
		"Options score toggle should emit screen_requested (TOGGLE_SCORE)")
