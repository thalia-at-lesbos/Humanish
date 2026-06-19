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

# The HUD selection panel renders a selected unit's own actions but must not show
# an Open City button when only a unit (not a city) is selected — even on a city
# tile, where the right-click flyout still offers Open City.

func _count_buttons_named(node, text):
	var n = 0
	for c in node.get_children():
		if c is Button and c.text == text:
			n += 1
	return n

func test_panel_script_loads_and_instances() -> void:
	# Canary: a parse error anywhere in selection_panel.gd makes load().new()
	# return null, which leaves the live SelectionPanel node scriptless — it then
	# renders nothing (no unit/city info, no action buttons) even though the rules
	# layer is fine. GUT does not fail a suite on a script load error, so without
	# this explicit assertion the breakage stays green. Guards that regression.
	# Use can_instance() rather than new(): a script with a parse error still loads
	# as a (broken) GDScript object, and calling new() on it raises an engine error
	# that GUT swallows AND aborts the test before any later assert. can_instance()
	# reports the compile state without throwing, so it actually fails the suite.
	var script = load("res://scenes/hud/selection_panel.gd")
	assert_not_null(script, "selection_panel.gd must load")
	assert_true(script.can_instance(),
		"selection_panel.gd must compile with no parse error")

func test_worker_shows_build_action_buttons() -> void:
	# Exercises the worker-improvement path (_add_worker_buttons), the code that
	# carried the parse error. A worker on a flat tile with Agriculture should
	# offer a "Build Farm" action.
	var facade = setup_facade(91, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.get_player(pid).technologies = ["agriculture"]
	var tile = gs.map.get_tile(3, 3)
	tile.terrain_id = "grassland"          # flat landform
	tile.improvement_id = ""
	tile.feature_id = ""
	var worker = make_unit(gs, "worker", pid, 3, 3)

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(worker.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Build Farm"), 1,
		"A worker on a flat tile with Agriculture offers Build Farm")

func test_unit_panel_omits_open_city_button() -> void:
	var facade = setup_facade(81, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid

	# A city and a (garrisoned) warrior on the same tile.
	make_settlement(gs, pid, 5, 5).name = "Cap"
	var w = make_unit(gs, "warrior", pid, 5, 5)

	# Sanity: the (right-click) flyout still offers Open City on that tile.
	var has_open = false
	for it in facade.get_flyout_menu(5, 5):
		if int(it.get("action_id", -1)) == IDs.ControlType.OPEN_CITY_SCREEN:
			has_open = true
	assert_true(has_open, "Flyout should still offer Open City on a city tile")

	# But the unit selection panel must not render an Open City button.
	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(w.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Open City"), 0,
		"A selected unit must not show an Open City button (no city is selected)")
	assert_true(panel.get_child_count() > 0, "The unit panel should still show unit info")

func test_capital_panel_hides_disband_button() -> void:
	# The capital (the city holding the Palace) cannot be disbanded, so its panel
	# must not offer a Disband button; a non-capital city still does.
	var facade = setup_facade(92, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid

	var capital = make_settlement(gs, pid, 7, 7)
	capital.name = "Capital"
	capital.structures.append("palace")
	var other = make_settlement(gs, pid, 9, 9)
	other.name = "Town"

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)

	facade.select_city(capital.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Disband City"), 0,
		"The capital must not show a Disband City button")

	facade.select_city(other.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Disband City"), 1,
		"A non-capital city still shows a Disband City button")

func _has_label_starting(node, prefix) -> bool:
	for c in node.get_children():
		if c is Label and c.text.begins_with(prefix):
			return true
	return false

func test_unit_panel_shows_current_state() -> void:
	var facade = setup_facade(89, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var w = make_unit(gs, "warrior", pid, 6, 6)
	gs.get_unit(w.id).is_fortified = true

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(w.id)
	panel.rebuild()
	assert_true(_has_label_starting(panel, "State: Fortified"),
		"The unit panel shows the unit's current state")

func test_stack_panel_lists_members_and_select_all() -> void:
	var facade = setup_facade(85, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 4, 4)
	make_unit(gs, "scout", pid, 4, 4)
	make_unit(gs, "archer", pid, 4, 4)

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(a.id)
	panel.rebuild()

	assert_true(_count_buttons_named(panel, "Select all (3)") == 1,
		"A multi-unit tile shows a Select-all button")

	# Selecting all then a fortify action fortifies every unit in the stack.
	panel._on_select_all(4, 4)
	assert_eq(facade.get_selection().selected_unit_ids.size(), 3,
		"Select all selects the whole stack")
	panel._on_action_pressed({"action_id": IDs.UnitCmd.FORTIFY})
	for u in gs.units:
		if u.x == 4 and u.y == 4:
			assert_true(u.is_fortified, "Fortify-all should fortify every unit in the stack")

func _has_label_containing(node, needle) -> bool:
	for c in node.get_children():
		if c is Label and needle in c.text:
			return true
	return false

func test_unit_panel_shows_tile_terrain() -> void:
	# A selected unit must also show the underlying tile's terrain readout, using
	# the same facade tile-info text as the empty-tile panel.
	var facade = setup_facade(93, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var w = make_unit(gs, "warrior", pid, 3, 3)
	var expected = facade.tile_info_text(3, 3)

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(w.id)
	panel.rebuild()
	assert_true(_has_label_containing(panel, expected),
		"A selected unit's panel includes the tile terrain readout")

func test_city_panel_shows_tile_terrain() -> void:
	# A selected city must also show the underlying tile's terrain readout.
	var facade = setup_facade(94, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var city = make_settlement(gs, pid, 6, 6)
	city.name = "Town"
	var expected = facade.tile_info_text(6, 6)

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_city(city.id)
	panel.rebuild()
	assert_true(_has_label_containing(panel, expected),
		"A selected city's panel includes the tile terrain readout")

func test_single_unit_panel_has_no_stack_list() -> void:
	var facade = setup_facade(86, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var solo = make_unit(gs, "warrior", pid, 2, 2)
	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(solo.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Select all (1)"), 0,
		"A lone unit shows no Select-all button")
