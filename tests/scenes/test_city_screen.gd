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

# CityScreen builds its content from a real settlement and queues production via
# its build buttons.

func _screen(facade):
	var screen = load("res://scenes/screens/city_screen.gd").new()
	add_child_autofree(screen)
	screen.init(facade)
	return screen

# Canary: the script must compile so a parse error cannot hide behind a green run.
func test_city_screen_script_compiles() -> void:
	assert_true(load("res://scenes/screens/city_screen.gd").can_instance(),
		"city_screen.gd must compile cleanly")

func test_city_view_builds_from_settlement() -> void:
	var facade = setup_facade(71, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid

	var s = make_settlement(gs, pid, 5, 5, 3)
	s.name = "Testopolis"
	s.output_food = 4; s.output_production = 3; s.output_commerce = 6
	s.structures = ["granary"]
	s.production_queue = [{"type": "unit", "id": "warrior"}]
	s.worked_tiles = [[5, 5], [5, 6]]
	gs.map.get_tile(5, 6).terrain_id = "grassland"

	var screen = _screen(facade)
	# Call _build directly to bypass rebuild()'s idle-frame yield.
	screen._city_id = s.id
	screen.visible = true
	screen._build()
	assert_true(screen.get_child_count() > 0,
		"City screen must build content (background + info) from the settlement")

# Prev/Next navigation cycles the displayed city across the player's own cities.
func test_city_screen_cycles_owned_cities() -> void:
	var facade = setup_facade(73, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s1 = make_settlement(gs, pid, 5, 5, 1)
	s1.name = "First"
	var s2 = make_settlement(gs, pid, 12, 12, 1)
	s2.name = "Second"

	var screen = _screen(facade)
	screen._city_id = s1.id
	screen.visible = true
	# Owned-id ordering follows settlement (founding) order.
	assert_eq(screen._owned_city_ids(gs, pid), [s1.id, s2.id],
		"Owned city ids list both settlements in founding order")
	# Cycle forward → Second; forward again wraps → First; backward → Second.
	screen._on_cycle_city(1)
	assert_eq(screen._city_id, s2.id, "Next moves to the second city")
	screen._on_cycle_city(1)
	assert_eq(screen._city_id, s1.id, "Next wraps back to the first city")
	screen._on_cycle_city(-1)
	assert_eq(screen._city_id, s2.id, "Prev wraps to the last city")

# Recursively collect the text of every Label/Button under a node.
func _all_text(node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += str(node.text) + "\n"
	for c in node.get_children():
		out += _all_text(c)
	return out

func test_city_screen_shows_health_and_growth() -> void:
	var facade = setup_facade(75, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 3)
	s.name = "Healthville"
	# The Growth line reads LIVE output now, so stage a real food surplus: four
	# worked grassland tiles (2 food each = 8) less 3-pop consumption (6) → +2.
	s.manage_citizens_auto = false
	for pair in [[5, 5], [6, 5], [4, 5], [5, 6]]:
		gs.map.get_tile(pair[0], pair[1]).terrain_id = "grassland"
	s.worked_tiles = [[5, 5], [6, 5], [4, 5], [5, 6]]
	s.wellbeing_deficit = 0
	s.health = 5            # below max → "recovering"
	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._build()
	var text := _all_text(screen)
	assert_true("Health:" in text, "City screen must show a Health line")
	assert_true("Growth:" in text, "City screen must show a Growth line")
	assert_true("growing" in text,
		"A city with a positive food surplus must report it is growing")

# Collect every Button in a subtree (for asserting enabled/offered state).
func _all_buttons(node, acc) -> void:
	if node is Button:
		acc.append(node)
	for c in node.get_children():
		_all_buttons(c, acc)

func test_output_line_shows_live_not_stale_totals() -> void:
	# The Output section must reflect the LIVE recomputed output for the current
	# worked tiles, not the stale s.output_* left by last turn's pipeline.
	var facade = setup_facade(77, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 1)
	s.manage_citizens_auto = false
	gs.map.get_tile(5, 5).terrain_id = "grassland"
	s.worked_tiles = [[5, 5]]           # centre only → a small, known live food
	s.output_food = 999                 # bogus stale value must NOT be shown
	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._build()
	var text := _all_text(screen)
	assert_false("Food +999" in text, "the stale s.output_food must not be displayed")
	var live = facade.settlement_output(s.id)
	assert_true(("Food +" + str(live[0])) in text,
		"the Output line shows the live recomputed food total")

func test_output_line_live_updates_when_a_tile_is_deselected() -> void:
	# ISSUE 1 (screen level): deselecting a worked tile must immediately change the
	# Output line — no auto-backfill masks the change.
	var facade = setup_facade(79, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 3)
	s.discontented = 0
	s.manage_citizens_auto = false
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			gs.map.get_tile(5 + dx, 5 + dy).terrain_id = "grassland"
	s.worked_tiles = [[5, 5], [6, 5], [4, 5], [5, 6]]   # centre + 3
	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._build()
	var food_before: int = facade.settlement_output(s.id)[0]
	assert_true(("Food +" + str(food_before)) in _all_text(screen),
		"the Output line shows the live food total before the deselect")
	# Deselect one worked grassland tile through the same command the grid issues.
	facade.apply_command(Commands.set_tile_worked(pid, s.id, 6, 5, false))
	screen._build()
	var food_after: int = facade.settlement_output(s.id)[0]
	assert_true(food_after < food_before,
		"deselecting a worked food tile drops the live food total")
	assert_true(("Food +" + str(food_after)) in _all_text(screen),
		"the rebuilt Output line shows the new, lower food total")

func test_hurry_gold_button_not_offered_without_queue() -> void:
	# With nothing queued there is nothing to gold-rush, so the Hurry (Gold) button
	# is not offered at all (§15.2 gold hurry is otherwise ungated by civic).
	var facade = setup_facade(78, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 2)
	s.production_queue = []              # nothing to rush
	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._build()
	var btns := []
	_all_buttons(screen, btns)
	for b in btns:
		assert_false("Hurry (Gold" in str(b.text),
			"no Hurry (Gold) button when there is nothing to rush")

func test_work_boat_offered_only_when_coastal_and_teched() -> void:
	var facade = setup_facade(76, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var owner = gs.get_player(pid)
	owner.technologies = ["fishing"]  # the work_boat prerequisite

	# Inland city surrounded by land: no water neighbour → not coastal.
	for t in gs.map.all_tiles():
		t.terrain_id = "grassland"
	var inland = make_settlement(gs, pid, 5, 5, 2)
	var screen = _screen(facade)
	screen._city_id = inland.id
	screen.visible = true
	screen._build()
	assert_false("+ work_boat" in _all_text(screen),
		"An inland city must not offer a sea unit even with the tech")
	screen.queue_free()

	# Coastal city: one adjacent water tile makes it coastal.
	var coastal = make_settlement(gs, pid, 10, 10, 2)
	gs.map.get_tile(11, 10).terrain_id = "coast"
	var screen2 = _screen(facade)
	screen2._city_id = coastal.id
	screen2.visible = true
	screen2._build()
	assert_true("+ work_boat" in _all_text(screen2),
		"A coastal city with the fishing tech must offer the work_boat")

func test_work_boat_hidden_without_tech() -> void:
	var facade = setup_facade(77, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.get_player(pid).technologies = []  # no fishing tech
	var coastal = make_settlement(gs, pid, 10, 10, 2)
	gs.map.get_tile(11, 10).terrain_id = "coast"
	var screen = _screen(facade)
	screen._city_id = coastal.id
	screen.visible = true
	screen._build()
	assert_false("+ work_boat" in _all_text(screen),
		"A coastal city without the fishing tech must not offer the work_boat")

func test_base_units_offered_regardless_of_tech() -> void:
	# Warrior/Settler/Worker have "tech_required": null. The chooser must offer
	# them even to a player with no techs at all — str(null) is "Null" in Godot 3,
	# so a naive tech check used to filter these base units out entirely.
	var facade = setup_facade(78, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.get_player(pid).technologies = []  # no research at all
	var s = make_settlement(gs, pid, 5, 5, 2)

	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._build()
	var text := _all_text(screen)
	assert_true("+ warrior" in text, "Warrior must be offered with no tech")
	assert_true("+ settler" in text, "Settler must be offered with no tech")
	assert_true("+ worker" in text, "Worker must be offered with no tech")

func test_city_view_add_to_production_queues_item() -> void:
	var facade = setup_facade(72, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 4, 4, 2)
	s.name = "Buildtown"

	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._on_build("structure", "granary")
	assert_eq(s.production_queue.size(), 1, "Build button should queue one item")
	assert_eq(str(s.production_queue[0].get("id", "")), "granary",
		"The queued item should be the chosen structure")

func _has_pair(arr, x, y) -> bool:
	for p in arr:
		if int(p[0]) == x and int(p[1]) == y:
			return true
	return false

func test_city_screen_toggle_tile_locks_it() -> void:
	var facade = setup_facade(73, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 2)

	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._on_toggle_tile(6, 5, true)
	assert_true(_has_pair(s.locked_tiles, 6, 5), "Toggling a tile on locks it")
	assert_true(_has_pair(s.worked_tiles, 6, 5), "…and it becomes worked immediately")
	screen._on_toggle_tile(6, 5, false)
	assert_false(_has_pair(s.locked_tiles, 6, 5), "Toggling it again removes the lock")

func test_city_screen_toggle_automation() -> void:
	var facade = setup_facade(74, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 2)
	assert_true(s.manage_citizens_auto, "Cities start auto-managed")

	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._on_toggle_automation(false)
	assert_false(s.manage_citizens_auto, "Automation toggle turns management manual")

func test_city_screen_assign_specialist() -> void:
	var facade = setup_facade(75, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 3)

	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._on_specialist("scientist", 1)
	assert_eq(int(s.specialists.get("scientist", 0)), 1, "Adding a specialist sets its count")
	screen._on_specialist("scientist", 0)
	assert_eq(int(s.specialists.get("scientist", 0)), 0, "Removing it clears the count")

func test_city_screen_dequeue_removes_item() -> void:
	var facade = setup_facade(76, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 2)
	s.production_queue = [
		{"type": "unit", "id": "warrior"},
		{"type": "structure", "id": "granary"}
	]

	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._on_dequeue(0)
	assert_eq(s.production_queue.size(), 1, "Clicking index 0 removes the first queue item")
	assert_eq(str(s.production_queue[0].get("id", "")), "granary",
		"The second item shifts to the front")

# ── Part B: production queue duplicate classification ───────────────────────────

func test_can_queue_more_unit_repeatable() -> void:
	var facade = setup_facade(80, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var screen = _screen(facade)
	# A unit already in the queue can still be queued again (repeatable).
	var queue = [{"type": "unit", "id": "warrior"}]
	assert_true(screen._can_queue_more("unit", "warrior", [], queue),
		"A unit already queued must remain addable (queue multiple warriors)")
	assert_true(screen._can_queue_more("unit", "warrior", [], []),
		"A unit not yet queued is addable")

func test_can_queue_more_building_blocked_when_queued() -> void:
	var facade = setup_facade(81, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var screen = _screen(facade)
	var queue = [{"type": "structure", "id": "granary"}]
	assert_false(screen._can_queue_more("structure", "granary", [], queue),
		"A building already in the queue must not be queueable twice")
	assert_true(screen._can_queue_more("structure", "library", [], queue),
		"A different building is still addable")

func test_can_queue_more_building_blocked_when_built() -> void:
	var facade = setup_facade(82, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var screen = _screen(facade)
	assert_false(screen._can_queue_more("structure", "granary", ["granary"], []),
		"A building already built in the city must not be queueable")

func test_on_build_allows_duplicate_units() -> void:
	var facade = setup_facade(83, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 2)
	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._on_build("unit", "warrior")
	screen._on_build("unit", "warrior")
	screen._on_build("unit", "warrior")
	assert_eq(s.production_queue.size(), 3,
		"Building the same unit three times queues three copies")

func test_on_build_rejects_duplicate_building() -> void:
	var facade = setup_facade(84, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 2)
	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._on_build("structure", "granary")
	screen._on_build("structure", "granary")
	assert_eq(s.production_queue.size(), 1,
		"A building cannot be queued twice in one city")

# ── Part A: work-grid worked/blank/dot markers ──────────────────────────────────

func test_grid_marker_worked_carries_hash() -> void:
	var facade = setup_facade(85, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var screen = _screen(facade)
	# Worked but not the centre, not locked → the # worked marker.
	assert_true("#" in screen._tile_grid_marker(false, true, false),
		"A worked tile must carry the # worked marker")
	# Workable but not worked, not locked → no # marker.
	assert_false("#" in screen._tile_grid_marker(false, false, false),
		"An unworked-but-workable tile must NOT carry the # marker")

func test_grid_marker_center_glyph() -> void:
	var facade = setup_facade(86, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var screen = _screen(facade)
	# The city centre is always worked and shows its ⌂ glyph plus the # worked
	# marker (it is always a worked tile).
	var center: String = screen._tile_grid_marker(true, true, false)
	assert_true("⌂" in center, "The city centre must show its ⌂ glyph")
	assert_true("#" in center,
		"The always-worked city centre must also carry the # worked marker")

func test_grid_marker_locked() -> void:
	var facade = setup_facade(87, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var screen = _screen(facade)
	assert_true("★" in screen._tile_grid_marker(false, true, true),
		"A locked+worked tile shows ★")
	assert_true("☆" in screen._tile_grid_marker(false, false, true),
		"A locked but idle tile shows ☆")

func test_work_grid_is_always_5x5() -> void:
	# The work grid is a FIXED 5×5 (25-cell) shell even for a small (culture_ring
	# 1) city — every slot is a Button, and tiles outside the real work radius are
	# blank (no-text) buttons.
	var facade = setup_facade(88, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	for t in gs.map.all_tiles():
		t.terrain_id = "grassland"
		t.owner_player_id = -1
	var s = make_settlement(gs, pid, 8, 8, 2)
	s.culture_ring = 1  # small city — yet the grid is still the full 5×5
	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._build()
	var wgrid = _work_grid(screen)
	assert_ne(wgrid, null, "The work grid must be present")
	assert_eq(wgrid.columns, 5, "The work grid has 5 columns")
	assert_eq(wgrid.get_child_count(), 25,
		"The work grid is always a fixed 5×5 = 25 cells, even for a culture_ring-1 city")
	# Every cell is a Button (usable ones carry text; unavailable ones are blank).
	var blanks := 0
	for cell in wgrid.get_children():
		assert_true(cell is Button, "Every work-grid cell is a Button (blank or labelled)")
		if str(cell.text) == "":
			blanks += 1
	# A culture_ring-1 city works only the 3×3 inner ring (9 tiles) within the
	# 5×5 shell, so the outer band (16 tiles) must be blank.
	assert_true(blanks >= 16,
		"Tiles outside the real work radius render as blank (no-text) buttons")

func test_work_grid_usable_text_and_hash_marker() -> void:
	# A currently-usable tile shows text; a worked tile carries the # marker while
	# an unworked-but-usable tile does not.
	var facade = setup_facade(89, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	var other = gs.players[1].id
	gs.current_player_id = pid
	for t in gs.map.all_tiles():
		t.terrain_id = "grassland"
		t.owner_player_id = -1
	var s = make_settlement(gs, pid, 8, 8, 2)
	s.culture_ring = 1
	# A foreign-owned in-radius tile → not usable → blank.
	gs.map.get_tile(9, 8).owner_player_id = other
	# Work one usable tile so a # appears; leave (8,9) usable but unworked.
	s.worked_tiles = [[7, 8]]
	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._build()
	var wgrid = _work_grid(screen)
	assert_ne(wgrid, null, "The work grid must be present")
	# Collect cell text by which tile each cell maps to (row-major, dx/dy -2..+2).
	var by_tile := {}
	var idx := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			by_tile[str(s.x + dx) + "," + str(s.y + dy)] = str(wgrid.get_children()[idx].text)
			idx += 1
	# The worked (7,8) tile shows text including the # marker.
	var worked_text: String = by_tile["7,8"]
	assert_true(worked_text != "", "A usable worked tile shows its text/label")
	assert_true("#" in worked_text, "A worked tile carries the # worked marker")
	# An unworked but usable tile (8,9) shows text but no # marker.
	var idle_text: String = by_tile["8,9"]
	assert_true(idle_text != "", "An unworked but usable tile still shows text")
	assert_false("#" in idle_text,
		"An unworked usable tile must NOT carry the # worked marker")
	# The foreign-owned (9,8) tile is a blank (no-text) button.
	assert_eq(by_tile["9,8"], "",
		"A foreign-owned in-radius tile renders as a blank (no-text) button")

# Find the citizen-management work grid: the 5-column GridContainer whose cells
# include the city-centre ⌂ marker.
func _work_grid(node):
	if node is GridContainer and node.columns == 5:
		for c in node.get_children():
			if c is Button and "⌂" in str(c.text):
				return node
	for child in node.get_children():
		var found = _work_grid(child)
		if found != null:
			return found
	return null

func test_city_screen_dequeue_last_item_empties_queue() -> void:
	var facade = setup_facade(77, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 2)
	s.production_queue = [{"type": "unit", "id": "archer"}]

	var screen = _screen(facade)
	screen._city_id = s.id
	screen.visible = true
	screen._on_dequeue(0)
	assert_true(s.production_queue.empty(), "Removing the only queue item leaves the queue empty")
