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

func test_worker_offers_mine_on_flat_iron() -> void:
	# Regression (tstb7): a worker standing on FLAT (plains/grassland) terrain that
	# carries an iron resource must be offered a "Build Mine" button, even though a
	# bare Mine's allowed_landforms is hills-only. Iron's improvement_required is
	# "mine", so the resource-aware landform gate in can_build_improvement permits
	# it — the panel must delegate to that predicate rather than pre-filtering the
	# candidate list by landform (which previously discarded Mine on flat land).
	var facade = setup_facade(93, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.get_player(pid).technologies = ["mining"]   # reveals & enables the mine
	var tile = gs.map.get_tile(3, 3)
	tile.terrain_id = "plains"             # flat landform (Mine wants hills)
	tile.improvement_id = ""
	tile.feature_id = ""
	tile.resource_id = "iron"
	var worker = make_unit(gs, "worker", pid, 3, 3)

	# Sanity: the authoritative predicate agrees the mine is legal here.
	assert_true(facade.can_build_improvement(pid, worker.id, "mine"),
		"can_build_improvement must permit a Mine on flat iron with Mining")

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(worker.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Build Mine"), 1,
		"A worker on flat iron with Mining is offered Build Mine")

func test_unit_panel_shows_open_city_on_own_city_tile() -> void:
	# Issue 2: when a selected unit shares its tile with the player's own city, the
	# panel surfaces an Open City button (above the on-tile stack list) so the city
	# is reachable directly, not only via left-click cycling.
	var facade = setup_facade(81, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid

	# A city and a (garrisoned) warrior on the same tile.
	make_settlement(gs, pid, 5, 5).name = "Cap"
	var w = make_unit(gs, "warrior", pid, 5, 5)

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(w.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Open City"), 1,
		"A unit sharing a tile with its own city shows an Open City button")
	assert_true(panel.get_child_count() > 0, "The unit panel should still show unit info")

func test_unit_panel_omits_open_city_off_city_tile() -> void:
	# A unit NOT on one of the player's cities shows no Open City button.
	var facade = setup_facade(82, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	# Find a tile with no settlement to stand the unit on (start cities vary by map gen).
	var tx = -1
	var ty = -1
	for cy in range(gs.map.height):
		for cx in range(gs.map.width):
			if gs.get_settlement_at(cx, cy) == null:
				tx = cx; ty = cy
				break
		if tx >= 0:
			break
	var w = make_unit(gs, "warrior", pid, tx, ty)

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(w.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Open City"), 0,
		"A unit not on a city tile shows no Open City button")

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
	panel._on_action_pressed({"kind": "cmd", "action_id": IDs.UnitCmd.FORTIFY})
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

func test_sleeping_unit_shows_wake_action() -> void:
	# Issue 4: a unit that is asleep must offer a Wake button so it can rejoin the
	# idle cycle; pressing it clears the sleep stance.
	var facade = setup_facade(95, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var w = make_unit(gs, "warrior", pid, 8, 8)
	facade.apply_command(Commands.unit_sleep(pid, w.id))
	assert_true(gs.get_unit(w.id).is_sleeping, "Unit is asleep")

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(w.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Wake"), 1,
		"A sleeping unit shows a Wake button")
	assert_eq(_count_buttons_named(panel, "Sleep"), 0,
		"A sleeping unit does not also show a Sleep button")

func test_settler_in_mixed_stack_shows_found_city() -> void:
	# Issue 6: a stack with a settler + warrior must show the SELECTED unit's own
	# actions. Selecting the settler yields Found City; selecting the warrior does not.
	var facade = setup_facade(96, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	# A clear grassland tile far from any starting settlement (min distance 3).
	var fx = -1
	var fy = -1
	for cy in range(gs.map.height):
		for cx in range(gs.map.width):
			var ok = true
			for s in gs.settlements:
				if gs.map.distance(cx, cy, s.x, s.y) < 3:
					ok = false
					break
			if ok:
				fx = cx; fy = cy
				break
		if fx >= 0:
			break
	gs.map.get_tile(fx, fy).terrain_id = "grassland"
	var warrior = make_unit(gs, "warrior", pid, fx, fy)
	var settler = make_unit(gs, "settler", pid, fx, fy)

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)

	# Selecting the warrior: no Found City.
	facade.select_unit(warrior.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Found City"), 0,
		"The warrior shows no Found City action")

	# Selecting the settler: Found City appears.
	facade.select_unit(settler.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Found City"), 1,
		"Selecting the settler in the mixed stack shows its Found City action")

func test_defender_in_city_shows_fortify() -> void:
	# Issue 7: a (e.g. archer) unit garrisoned in a city must still offer Fortify.
	var facade = setup_facade(97, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_settlement(gs, pid, 10, 10).name = "Keep"
	var warrior = make_unit(gs, "warrior", pid, 10, 10)
	var archer = make_unit(gs, "archer", pid, 10, 10)

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(archer.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Fortify"), 1,
		"An archer garrisoned in a city still shows the Fortify action")
	# And the warrior on the same tile likewise.
	facade.select_unit(warrior.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Fortify"), 1,
		"The warrior garrisoned in the same city also shows Fortify")

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

func _has_button_containing(node, needle) -> bool:
	for c in node.get_children():
		if c is Button and needle in c.text:
			return true
	return false

func test_spy_panel_shows_espionage_actions_on_foreign_city() -> void:
	# A spy standing on a foreign city tile with full movement and espionage points
	# shows espionage action buttons (only valid + usable missions, §7.1).
	var facade = setup_facade(77, "small")
	var gs = facade.get_state()
	var p1 = gs.players[0].id
	var p2 = gs.players[1].id
	gs.current_player_id = p1
	make_settlement(gs, p2, 12, 12, 5)
	gs.get_player(p2).treasury = 500
	gs.get_player(p1).intel_points = {gs.get_player(p2).alliance_id: 100000}
	var spy = make_unit(gs, "spy", p1, 12, 12)

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(spy.id)
	panel.rebuild()
	assert_true(_has_label_starting(panel, "Espionage:"),
		"A spy on a foreign city tile shows the Espionage action header")
	assert_true(_has_button_containing(panel, "EP"),
		"...and at least one espionage mission button")

func test_spy_panel_shows_no_espionage_actions_off_city() -> void:
	# The same spy on open ground (no city) shows no espionage actions.
	var facade = setup_facade(78, "small")
	var gs = facade.get_state()
	var p1 = gs.players[0].id
	gs.current_player_id = p1
	gs.get_player(p1).intel_points = {gs.players[1].alliance_id: 100000}
	# A tile with no settlement.
	var tx = -1
	var ty = -1
	for cy in range(gs.map.height):
		for cx in range(gs.map.width):
			if gs.get_settlement_at(cx, cy) == null:
				tx = cx; ty = cy
				break
		if tx >= 0:
			break
	var spy = make_unit(gs, "spy", p1, tx, ty)

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(spy.id)
	panel.rebuild()
	assert_false(_has_label_starting(panel, "Espionage:"),
		"A spy not on a city tile shows no espionage actions")

# Recursive variant of _count_buttons_named: the GP second-column layout nests
# buttons inside an HBox of VBoxes, so top-level iteration cannot see them.
func _count_buttons_named_deep(node, text):
	var n = 0
	for c in node.get_children():
		if c is Button and c.text == text:
			n += 1
		n += _count_buttons_named_deep(c, text)
	return n

func test_gp_unit_shows_second_action_column() -> void:
	# User-directed layout (2026-07-19): a Great Person's action verbs render in a
	# SECOND button column beside the main action column (an HBox of two VBoxes),
	# and a GP button acts immediately — no confirmation step.
	var facade = setup_facade(98, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_settlement(gs, pid, 6, 6).name = "Cap"
	var gp = make_gp(gs, "great_engineer", pid, 6, 6)

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(gp.id)
	panel.rebuild()

	# The GP verbs are present but NOT as direct children (they sit in the
	# second column inside the actions row).
	assert_eq(_count_buttons_named(panel, "Join City"), 0,
		"GP verb buttons are not direct panel children")
	assert_eq(_count_buttons_named_deep(panel, "Join City"), 1,
		"Join City renders in the GP action column")
	assert_eq(_count_buttons_named_deep(panel, "Build Ironworks"), 1,
		"Build Ironworks renders in the GP action column")
	assert_eq(_count_buttons_named_deep(panel, "Golden Age (2 GP)"), 1,
		"Golden Age renders with its GP-cost preview label")
	# The main-column actions moved into the left column of the same row.
	assert_eq(_count_buttons_named_deep(panel, "Skip Turn"), 1,
		"the main action column still holds Skip Turn")

	# Pressing a GP button acts immediately (no confirmation): the Golden Age
	# contribution consumes the Great Person on the spot.
	panel._on_action_pressed({"kind": "gp", "action": "start_golden_age",
		"unit_id": gp.id})
	assert_null(gs.get_unit(gp.id), "the GP action consumed the Great Person")
	assert_eq(gs.get_player(pid).pending_golden_age_gp, 1,
		"the contribution was banked toward the next Golden Age")

func test_executive_panel_shows_spread_button_with_cost() -> void:
	# An executive in an eligible city shows a Spread button whose label carries
	# the computed gold cost; non-GP additions stay in the main (flat) column.
	var facade = setup_facade(99, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var p = gs.get_player(pid)
	p.treasury = 200
	var hq_city = make_settlement(gs, pid, 5, 5, 5)
	make_settlement(gs, pid, 10, 10, 5)
	EconOrgs.found("civilized_jewelers", hq_city, gs)
	# Connect an input resource (gold) for the owner.
	var res = gs.db.get_resource("gold")
	var t = gs.map.get_tile(1, 1)
	t.owner_player_id = pid
	t.resource_id = "gold"
	t.improvement_id = str(res.get("improvement_required", ""))
	var reveal = str(res.get("tech_required", ""))
	if reveal != "" and not p.has_tech(reveal):
		p.technologies.append(reveal)
	var exe = make_unit(gs, "executive", pid, 10, 10)

	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	facade.select_unit(exe.id)
	panel.rebuild()
	assert_eq(_count_buttons_named(panel, "Spread Civilized Jewelers (50 gold)"), 1,
		"the executive's Spread button sits in the main column with its cost label")

func test_open_city_selects_city_under_a_unit() -> void:
	# Regression (bug tstd2): pressing Open City while a non-city unit (a scout) is
	# selected on a city tile must open THAT city. _on_open_city selects the city so
	# the OPEN_CITY_SCREEN handler resolves it via head_city() — before the fix the
	# id was discarded and head_city() was -1, so the advisor never opened.
	var facade = setup_facade(91, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var city = make_settlement(gs, pid, 4, 4, 2)
	var scout = make_unit(gs, "scout", pid, 4, 4)
	facade.select_unit(scout.id)
	var panel = load("res://scenes/hud/selection_panel.gd").new()
	add_child_autofree(panel)
	panel.init(facade, null)
	panel._on_open_city(city.id)
	assert_eq(facade.get_selection().head_city(), city.id,
		"Open City selects the city under the unit so the advisor can resolve it")
