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
	s.output_food = 10      # net food: 10 - 0 - 3*2 = +4 → growing
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
