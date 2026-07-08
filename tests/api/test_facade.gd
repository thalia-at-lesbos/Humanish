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

# SimFacade command routing: founding settlements (and the min-distance rule),
# setting research, class-bounded moves, friendly stacking, and the settler's
# Found City action surfaced through the flyout.

func _settler(facade, player_id, x, y):
	var gs = facade.get_state()
	# Found-settlement legality now requires foundable land (not water/peak); make
	# the settler's tile grassland so these palace/founding tests stay terrain-agnostic.
	var tile = gs.map.get_tile(x, y)
	if tile != null:
		tile.terrain_id = "grassland"
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id(); u.unit_type_id = "settler"
	u.owner_player_id = player_id; u.x = x; u.y = y
	u.base_strength = 0; u.health = 100
	u.movement_total = 200; u.movement_left = 200
	gs.units.append(u)
	return u.id

# ── Found settlement ─────────────────────────────────────────────────────────

func test_found_settlement_creates_settlement() -> void:
	var facade = setup_facade(100)
	var gs = facade.get_state()
	var uid: int = _settler(facade, gs.players[0].id, 5, 5)
	gs.current_player_id = gs.players[0].id
	assert_true(facade.apply_command(Commands.found_settlement(gs.players[0].id, uid, "Alpha")),
		"Found settlement command should succeed")
	assert_eq(gs.settlements.size(), 1, "One settlement should exist")
	assert_eq(gs.settlements[0].name, "Alpha", "Settlement name set correctly")

# A nameless founding draws the next unused historical name from the player's
# society list: capital (index 0) first, then index 1, then a name skipped because
# it already names an existing settlement is jumped over.
func test_found_settlement_uses_historical_society_names() -> void:
	var gs = make_gs(1)
	gs.current_player_id = gs.players[0].id
	var p = gs.players[0]
	p.society_id = "roman"
	var facade = bare_facade(gs)
	var cnames: Array = gs.db.get_city_names("roman")
	var capital: String = str(cnames[0])
	var second: String = str(cnames[1])
	var third: String = str(cnames[2])

	# First city → capital.
	var u0: int = _settler(facade, p.id, 5, 5)
	assert_true(facade.apply_command(Commands.found_settlement(p.id, u0)),
		"Nameless first founding succeeds")
	assert_eq(gs.settlements[0].name, capital, "First city gets the society capital")

	# Second city → next name (index 1).
	var u1: int = _settler(facade, p.id, 10, 10)
	assert_true(facade.apply_command(Commands.found_settlement(p.id, u1)),
		"Nameless second founding succeeds")
	assert_eq(gs.settlements[1].name, second, "Second city gets the next name")

	# Manually rename the next settlement-to-be's name onto an existing city so it
	# is "in use"; the following founding must SKIP it and take index 3.
	gs.settlements[1].name = third
	var u2: int = _settler(facade, p.id, 15, 15)
	assert_true(facade.apply_command(Commands.found_settlement(p.id, u2)),
		"Nameless third founding succeeds")
	assert_eq(gs.settlements[2].name, str(cnames[3]),
		"A name already in use by an existing settlement is skipped")

# With no society (or an unknown one) the founding falls back to "City N".
func test_found_settlement_falls_back_without_society() -> void:
	var gs = make_gs(1)
	gs.current_player_id = gs.players[0].id
	var facade = bare_facade(gs)  # player society_id is ""
	var u0: int = _settler(facade, gs.players[0].id, 5, 5)
	assert_true(facade.apply_command(Commands.found_settlement(gs.players[0].id, u0)),
		"Nameless founding without a society still succeeds")
	assert_true(gs.settlements[0].name.begins_with("City "),
		"Without a society the name falls back to 'City N'")

func test_first_contact_surfaces_notification_and_signal() -> void:
	# When two players newly meet, the facade must drain the first-contact queue
	# into a player-facing notification (naming the rival) and a first_contact
	# signal, and must not re-surface an already-met pair.
	var gs = make_gs(2)
	make_unit(gs, "warrior", 1, 5, 5)
	make_unit(gs, "warrior", 2, 6, 5)
	gs.get_player(1).name = "Alice"
	gs.get_player(2).name = "Bob"
	var facade = bare_facade(gs)
	watch_signals(facade)

	TurnEngine._detect_sight_contact(gs)
	facade._drain_first_contacts()

	assert_signal_emit_count(facade, "first_contact", 2,
		"One first_contact signal per met player")
	var notes: Array = facade.get_notification_queue()
	var contact_notes: Array = []
	for n in notes:
		if str(n.get("text", "")).find("made contact") != -1:
			contact_notes.append(str(n["text"]))
	assert_eq(contact_notes.size(), 2, "One contact notification per player")
	var joined: String = PoolStringArray(contact_notes).join(" | ")
	assert_true(joined.find("Alice") != -1, "Bob's notification names Alice")
	assert_true(joined.find("Bob") != -1, "Alice's notification names Bob")
	assert_true(gs.pending_first_contacts.empty(), "Queue cleared after draining")

	# A second sweep with no new meetings surfaces nothing more.
	TurnEngine._detect_sight_contact(gs)
	facade._drain_first_contacts()
	assert_eq(facade.get_notification_queue().size(), notes.size(),
		"Already-met pair adds no further notifications")

func test_found_settlement_too_close_fails() -> void:
	var facade = setup_facade(200)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var uid1: int = _settler(facade, gs.players[0].id, 5, 5)
	facade.apply_command(Commands.found_settlement(gs.players[0].id, uid1, "A"))
	var uid2: int = _settler(facade, gs.players[0].id, 6, 5)
	assert_false(facade.apply_command(Commands.found_settlement(gs.players[0].id, uid2, "B")),
		"Cannot found within min distance")

func test_first_city_is_founded_with_a_palace() -> void:
	var facade = setup_facade(101)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var uid: int = _settler(facade, gs.players[0].id, 5, 5)
	facade.apply_command(Commands.found_settlement(gs.players[0].id, uid, "Capital"))
	assert_true(gs.settlements[0].has_structure("palace"),
		"A player's first city (its capital) is founded with the Palace")

func test_only_the_first_city_gets_a_palace() -> void:
	var facade = setup_facade(102)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var uid1: int = _settler(facade, gs.players[0].id, 5, 5)
	facade.apply_command(Commands.found_settlement(gs.players[0].id, uid1, "Capital"))
	# A second city, far enough away to clear the minimum-distance check.
	var uid2: int = _settler(facade, gs.players[0].id, 20, 20)
	facade.apply_command(Commands.found_settlement(gs.players[0].id, uid2, "Second"))
	assert_eq(gs.settlements.size(), 2, "Both cities are founded")
	assert_true(gs.get_settlement(gs.settlements[0].id).has_structure("palace"),
		"The capital keeps its Palace")
	assert_false(gs.get_settlement(gs.settlements[1].id).has_structure("palace"),
		"A later city is not given a Palace")

func test_each_players_first_city_gets_its_own_palace() -> void:
	var facade = setup_facade(103, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var p0 = gs.players[0].id
	var p1 = gs.players[1].id

	gs.current_player_id = p0
	var u0: int = _settler(facade, p0, 5, 5)
	facade.apply_command(Commands.found_settlement(p0, u0, "ACity"))

	gs.current_player_id = p1
	var u1: int = _settler(facade, p1, 20, 20)
	facade.apply_command(Commands.found_settlement(p1, u1, "BCity"))

	for s in gs.settlements:
		assert_true(s.has_structure("palace"),
			"Every society's first city has its own Palace (" + s.name + ")")

func test_found_city_action_offered_and_works() -> void:
	var facade = setup_facade(31, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(6, 6).terrain_id = "grassland"
	var u = make_unit(gs, "settler", pid, 6, 6)

	var found_item = {}
	for it in facade.get_flyout_menu(6, 6):
		if int(it.get("action_id", -1)) == IDs.UnitMission.FOUND_SETTLEMENT:
			found_item = it
			break
	assert_false(found_item.empty(), "Flyout should offer Found City for a settler")

	var before = gs.settlements.size()
	assert_true(facade.apply_command(Commands.found_settlement(pid, int(found_item.get("unit_id", u.id)))),
		"Found settlement command should succeed")
	assert_eq(gs.settlements.size(), before + 1, "A new settlement should exist")
	assert_null(gs.get_unit(u.id), "The founding settler should be consumed")

func test_can_found_settlement_at_true_on_valid_tile() -> void:
	var facade = setup_facade(40, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	# A grassland tile far from every existing settlement.
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
	var u = make_unit(gs, "settler", pid, fx, fy)
	assert_true(facade.can_found_settlement_at(u.id),
		"A settler on foundable land far from settlements can found")

func test_can_found_settlement_at_false_too_close() -> void:
	var facade = setup_facade(41, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var city = make_settlement(gs, pid, 10, 10)
	gs.map.get_tile(11, 10).terrain_id = "grassland"   # distance 1 < min 3
	var u = make_unit(gs, "settler", pid, 11, 10)
	assert_false(facade.can_found_settlement_at(u.id),
		"A settler within the minimum distance of a settlement cannot found")

func test_can_found_settlement_at_false_on_water() -> void:
	var facade = setup_facade(42, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	# Place far from any settlement but on coast (sea domain) — not foundable.
	gs.map.get_tile(14, 14).terrain_id = "coast"
	var u = make_unit(gs, "settler", pid, 14, 14)
	# Make sure distance is not the blocker here.
	var blocked_by_distance = false
	for s in gs.settlements:
		if gs.map.distance(14, 14, s.x, s.y) < 3:
			blocked_by_distance = true
	assert_false(blocked_by_distance, "test tile must be far enough to isolate the terrain check")
	assert_false(facade.can_found_settlement_at(u.id),
		"A settler on a water tile cannot found a city")

func test_can_found_settlement_at_false_for_warrior() -> void:
	var facade = setup_facade(43, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(16, 16).terrain_id = "grassland"
	var u = make_unit(gs, "warrior", pid, 16, 16)
	assert_false(facade.can_found_settlement_at(u.id),
		"A non-settler cannot found a settlement")

func test_get_unit_actions_settler_includes_found_warrior_excludes() -> void:
	# The selected-unit action list reflects the SELECTED unit even in a mixed stack.
	var facade = setup_facade(44, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
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

	var settler_labels := []
	for it in facade.get_unit_actions(settler.id):
		settler_labels.append(str(it.get("label", "")))
	assert_true("Found City" in settler_labels,
		"The settler's own action list includes Found City")

	var warrior_labels := []
	for it in facade.get_unit_actions(warrior.id):
		warrior_labels.append(str(it.get("label", "")))
	assert_false("Found City" in warrior_labels,
		"The warrior's own action list excludes Found City")
	assert_true("Fortify" in warrior_labels,
		"The warrior's action list includes Fortify")

func test_get_unit_actions_fortify_in_city() -> void:
	# A unit garrisoned in a city still offers Fortify (Issue 7).
	var facade = setup_facade(45, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_settlement(gs, pid, 12, 12)
	var archer = make_unit(gs, "archer", pid, 12, 12)
	var labels := []
	for it in facade.get_unit_actions(archer.id):
		labels.append(str(it.get("label", "")))
	assert_true("Fortify" in labels,
		"An archer garrisoned in a city offers Fortify")

func test_get_unit_actions_sleeping_unit_offers_wake() -> void:
	# A sleeping unit's action list offers Wake (and not Sleep); applying it clears
	# the sleep flag (Issue 4).
	var facade = setup_facade(46, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 9, 9)
	facade.apply_command(Commands.unit_sleep(pid, u.id))
	var labels := []
	for it in facade.get_unit_actions(u.id):
		labels.append(str(it.get("label", "")))
	assert_true("Wake" in labels, "A sleeping unit's actions include Wake")
	assert_false("Sleep" in labels, "A sleeping unit's actions exclude Sleep")
	assert_true(facade.apply_command(Commands.unit_wake(pid, u.id)), "wake accepted")
	assert_false(gs.get_unit(u.id).is_sleeping, "Wake clears the sleep flag")

func test_found_city_not_offered_for_warrior() -> void:
	var facade = setup_facade(32, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 7, 7)
	for it in facade.get_flyout_menu(7, 7):
		assert_true(int(it.get("action_id", -1)) != IDs.UnitMission.FOUND_SETTLEMENT,
			"A warrior must not be offered Found City")

# ── Research command ───────────────────────────────────────────────────────────

func test_set_research_command() -> void:
	var facade = setup_facade(300)
	var gs = facade.get_state()
	var p = gs.players[0]
	gs.current_player_id = p.id
	assert_true(facade.apply_command(Commands.set_research(p.id, "mining")),
		"Set research should succeed")
	assert_eq(p.current_research_id, "mining", "Research target set")

# ── Movement & stacking via commands ───────────────────────────────────────────

func test_move_stack_command_succeeds_on_open_map() -> void:
	var facade = setup_facade(123, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 2, 2)
	assert_true(facade.apply_command(Commands.move_stack(pid, 2, 2, 3, 2)),
		"Moving a unit one tile on open land should succeed")

func test_friendly_units_may_stack_on_one_tile() -> void:
	var facade = setup_facade(1212, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_warrior(gs, pid, 5, 5)  # already on the target tile
	var b = make_unit(gs, "scout", pid, 6, 5)

	assert_true(facade.apply_command(Commands.move_stack(pid, 6, 5, 5, 5)),
		"A unit must be able to move onto a friendly-occupied tile")
	assert_eq([gs.get_unit(b.id).x, gs.get_unit(b.id).y], [5, 5],
		"The moving unit ends up on the shared tile")
	assert_eq(Stack.at(gs.units, 5, 5, pid).size(), 2, "Both friendly units now occupy the same tile")

# ── move_stack unit_ids subset: peel a single member off a stack ──────────────

func test_move_stack_moves_only_listed_units() -> void:
	var facade = setup_facade(135, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 4, 4)
	var b = make_unit(gs, "scout", pid, 4, 4)
	assert_true(facade.apply_command(Commands.move_stack(pid, 4, 4, 5, 4, [a.id])),
		"Moving a single listed member should succeed")
	assert_eq([gs.get_unit(a.id).x, gs.get_unit(a.id).y], [5, 4], "The listed unit moves")
	assert_eq([gs.get_unit(b.id).x, gs.get_unit(b.id).y], [4, 4],
		"The unlisted stack member stays behind")

# ── Multi-turn go-to (§3.3) ─────────────────────────────────────────────────────

func test_move_to_far_tile_sets_goto_and_continues() -> void:
	var facade = setup_facade(321, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 5, 5)

	# Destination six tiles east — well beyond one turn of movement.
	assert_true(facade.apply_command(Commands.move_stack(pid, 5, 5, 11, 5)),
		"Issuing a far move should succeed")
	assert_true(gs.get_unit(u.id).x < 11, "It does not reach the far tile in one turn")
	assert_eq(gs.get_unit(u.id).goto_x, 11, "It remembers the destination (x)")
	assert_eq(gs.get_unit(u.id).goto_y, 5, "It remembers the destination (y)")

	# Simulate the start of later turns: refresh movement and resume the order.
	for _i in range(6):
		if gs.get_unit(u.id).x == 11:
			break
		gs.get_unit(u.id).movement_left = gs.get_unit(u.id).movement_total
		facade._resume_goto(pid)
	assert_eq([gs.get_unit(u.id).x, gs.get_unit(u.id).y], [11, 5],
		"The unit travels to the destination over several turns")
	assert_eq(gs.get_unit(u.id).goto_x, -1, "The go-to goal clears on arrival")

func test_adjacent_move_clears_goto() -> void:
	var facade = setup_facade(322, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 3, 3)
	facade.apply_command(Commands.move_stack(pid, 3, 3, 4, 3))
	assert_eq(gs.get_unit(u.id).goto_x, -1,
		"A move that reaches its target leaves no standing go-to order")

func test_goto_survives_save_load() -> void:
	var facade = setup_facade(323, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 5, 5)
	facade.apply_command(Commands.move_stack(pid, 5, 5, 11, 5))
	var saved: String = facade.save()
	assert_true(facade.load_save(saved), "reload the saved game")
	var ru = facade.get_state().get_unit(u.id)
	assert_eq(ru.goto_x, 11, "the standing go-to destination survives save/load")

func test_can_stack_move_true_for_open_tile_false_for_water() -> void:
	var facade = setup_facade(136, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(4, 4).terrain_id = "grassland"
	gs.map.get_tile(5, 4).terrain_id = "grassland"
	gs.map.get_tile(4, 5).terrain_id = "ocean"
	make_unit(gs, "warrior", pid, 4, 4)
	assert_true(facade.can_stack_move(4, 4, 5, 4),
		"An adjacent open land tile is a legal destination for a land unit")
	assert_false(facade.can_stack_move(4, 4, 4, 5),
		"Water is not a legal destination for a land unit")

func test_can_stack_move_civilian_only_cannot_attack_wild_city() -> void:
	var facade = setup_facade(138, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(4, 4).terrain_id = "grassland"
	gs.map.get_tile(5, 4).terrain_id = "grassland"
	var worker = make_unit(gs, "worker", pid, 4, 4)
	make_settlement(gs, -2, 5, 4, 1)   # wild camp (owner -2)
	assert_false(facade.can_stack_move(4, 4, 5, 4, [worker.id]),
		"A civilian-only selection cannot attack a wild city (no wasted strength-0 assault)")

func test_can_stack_move_warrior_can_attack_wild_city() -> void:
	var facade = setup_facade(139, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(4, 4).terrain_id = "grassland"
	gs.map.get_tile(5, 4).terrain_id = "grassland"
	var warrior = make_warrior(gs, pid, 4, 4)
	make_settlement(gs, -2, 5, 4, 1)
	assert_true(facade.can_stack_move(4, 4, 5, 4, [warrior.id]),
		"A warrior can attack an adjacent wild city")

func test_attacking_undefended_wild_camp_razes_it_immediately() -> void:
	# Regression (savefile pt-a-7): a warrior right-clicking an undefended barbarian
	# camp used to silently chip its siege HP for many turns ("nothing happens").
	# §4.8 now: an undefended enemy/wild city falls to a single attack. A pop-1 camp
	# is razed (barb captor), the warrior advances onto the now-empty tile, and the
	# raze notification makes the outcome visible.
	var facade = setup_facade(141, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(4, 4).terrain_id = "grassland"
	gs.map.get_tile(5, 4).terrain_id = "grassland"
	var warrior = make_warrior(gs, pid, 4, 4)
	make_settlement(gs, -2, 5, 4, 1)   # wild camp (owner -2)
	var before: int = facade.get_notification_queue().size()
	var ok = facade.apply_command(
		Commands.move_stack(pid, 4, 4, 5, 4, [warrior.id]))
	assert_true(ok, "The assault command is accepted")
	assert_eq(gs.get_settlement_at(5, 4), null, "The undefended camp is razed at once")
	assert_eq([warrior.x, warrior.y], [5, 4], "The warrior advances onto the razed tile")
	var notes: Array = facade.get_notification_queue()
	assert_true(notes.size() > before, "Razing the camp adds a notification")

func test_is_hostile_tile_recognises_wild_city_and_unit() -> void:
	var facade = setup_facade(140, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_settlement(gs, -2, 6, 6, 1)    # wild camp
	make_warrior(gs, -2, 7, 7, true)    # wild raider unit
	gs.map.get_tile(8, 8).terrain_id = "grassland"
	assert_true(facade.is_hostile_tile(6, 6), "A wild city tile is hostile")
	assert_true(facade.is_hostile_tile(7, 7), "A wild unit tile is hostile")
	assert_false(facade.is_hostile_tile(8, 8), "An empty tile is not hostile")

func test_inspect_tile_clears_selection_and_records_tile() -> void:
	var facade = setup_facade(137, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 4, 4)
	facade.select_unit(u.id)
	facade.inspect_tile(7, 7)
	assert_eq(facade.get_selection().head_unit(), -1, "Inspecting a tile clears the unit selection")
	assert_true(facade.get_selection().has_inspected_tile(), "…and records the inspected tile")

func test_tile_info_text_reports_terrain() -> void:
	var facade = setup_facade(138, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.map.get_tile(3, 3).terrain_id = "grassland"
	var text = facade.tile_info_text(3, 3)
	assert_true(text.find("Grassland") >= 0, "Tile info names the terrain")
	assert_true(text.find("Yields") >= 0, "Tile info lists yields")

func test_tile_info_text_reflects_improvement_yield() -> void:
	# A built improvement (mine on hills, +1 production once Mining is known) must
	# raise the readout's yields above the bare-terrain base — the readout computes
	# the full tile output, not just terrain.base_output.
	var facade = setup_facade(140, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	if not ("mining" in gs.players[0].technologies):
		gs.players[0].technologies.append("mining")
	var tile = gs.map.get_tile(3, 3)
	tile.terrain_id = "hills"
	tile.feature_id = ""
	tile.resource_id = ""
	var db = facade._db
	var base = TileOutput.compute(tile, db, gs.players[0].technologies)
	tile.improvement_id = "mine"
	var improved = TileOutput.compute(tile, db, gs.players[0].technologies)
	assert_gt(improved[IDs.Output.PRODUCTION], base[IDs.Output.PRODUCTION],
		"Mine on hills raises sim production over base")
	var text = facade.tile_info_text(3, 3)
	assert_true(text.find("Mine") >= 0, "Readout names the improvement")
	assert_true(text.find(str(improved[IDs.Output.PRODUCTION]) + "P") >= 0,
		"Readout's yields reflect the improved production, not the terrain base")

func test_tile_info_text_shows_foreign_unit() -> void:
	var facade = setup_facade(1500, "small",
		[{"name": "Rome", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "Greece", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var enemy = make_unit(gs, "warrior", gs.players[1].id, 5, 5)
	var text = facade.tile_info_text(5, 5)
	assert_true(text.find("Greece") >= 0, "Foreign unit's owner name appears in tile info")
	assert_true(text.find("HP") >= 0, "Foreign unit's health appears in tile info")

func test_tile_info_text_shows_foreign_city() -> void:
	var facade = setup_facade(1501, "small",
		[{"name": "Rome", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "Greece", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var city = make_settlement(gs, gs.players[1].id, 6, 6)
	city.name = "Athens"
	var text = facade.tile_info_text(6, 6)
	assert_true(text.find("Greece") >= 0, "Foreign city's owner name appears in tile info")
	assert_true(text.find("Athens") >= 0, "Foreign city's name appears in tile info")
	# Information fog (§25.6): a rival city shows its defensive posture; its
	# population stays hidden until investigate_city passive intel is met.
	assert_true(text.find("Defence: +") >= 0, "Foreign city's defence readout appears")
	assert_false(text.find("pop") >= 0, "Foreign city's population is hidden without intel")

func test_tile_info_text_omits_own_subjects() -> void:
	var facade = setup_facade(1502, "small",
		[{"name": "Rome", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 4, 4)
	make_settlement(gs, pid, 4, 4)
	var text = facade.tile_info_text(4, 4)
	assert_eq(text.find("Rome's"), -1, "Own units/cities are not duplicated in tile info")

# Issue 17: wild units (owner -2) show "Bandit <type>" or "Wild <type>" in tile info.
func test_tile_info_text_wild_raider_shows_bandit_label() -> void:
	var facade = setup_facade(1503, "small",
		[{"name": "Rome", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	make_unit(gs, "warrior", -2, 7, 7)
	var text = facade.tile_info_text(7, 7)
	assert_true(text.find("Bandit") >= 0, "Wild raider (warrior) shows 'Bandit' prefix")
	assert_eq(text.find("?"), -1, "No '?' owner placeholder for wild units")

func test_tile_info_text_wild_animal_shows_wild_label() -> void:
	var facade = setup_facade(1504, "small",
		[{"name": "Rome", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	make_unit(gs, "wolf", -2, 8, 8)
	var text = facade.tile_info_text(8, 8)
	assert_true(text.find("Wild") >= 0, "Wild animal (wolf) shows 'Wild' prefix")
	assert_eq(text.find("?"), -1, "No '?' owner placeholder for wild animals")

func test_mission_move_to_is_per_unit() -> void:
	# MISSION_MOVE_TO is a per-unit move command: only the named unit leaves a
	# shared tile, so it can be peeled off a stack.
	var facade = setup_facade(139, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 4, 4)
	var b = make_unit(gs, "scout", pid, 4, 4)
	assert_true(facade.apply_command(Commands.mission_move_to(pid, a.id, 5, 4)),
		"A per-unit move order should succeed")
	assert_eq([gs.get_unit(a.id).x, gs.get_unit(a.id).y], [5, 4], "The ordered unit moves")
	assert_eq([gs.get_unit(b.id).x, gs.get_unit(b.id).y], [4, 4],
		"…the rest of the stack stays behind")

# ── Diplomatic assembly voting (§7.2) ──────────────────────────────────────────

# A bare facade over a religious assembly with an open session: player 1 founds the
# Apostolic Palace in a christian capital, players 1–3 all hold christian cities.
func _assembly_facade():
	var gs = make_gs(3)
	var c1 = make_settlement(gs, 1, 3, 3, 5)
	c1.belief_id = "christianity"
	c1.structures.append("apostolic_palace")
	var c2 = make_settlement(gs, 2, 8, 8, 3); c2.belief_id = "christianity"
	var c3 = make_settlement(gs, 3, 14, 14, 2); c3.belief_id = "christianity"
	var f = bare_facade(gs)
	f._hooks = hooks()
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)   # open the first session
	return f

func test_cast_vote_command_records_a_vote() -> void:
	var facade = _assembly_facade()
	facade.get_state().current_player_id = 1   # a player votes on their own turn
	assert_true(facade.apply_command(Commands.cast_vote(1, "yea")),
		"A member's vote command is accepted")
	assert_true(Assembly.has_voted(facade.get_state(), 1), "…and is recorded")

func test_cast_vote_rejected_for_non_member() -> void:
	var gs = make_gs(2)
	var c1 = make_settlement(gs, 1, 3, 3, 4)
	c1.belief_id = "christianity"
	c1.structures.append("apostolic_palace")
	make_settlement(gs, 2, 8, 8, 4)  # player 2 holds no christian city
	var facade = bare_facade(gs)
	facade._hooks = hooks()
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)
	gs.current_player_id = 2   # it IS player 2's turn — rejection is on membership
	assert_false(facade.apply_command(Commands.cast_vote(2, "yea")),
		"A non-member's vote command is rejected")

func test_get_pending_vote_reports_then_clears() -> void:
	var facade = _assembly_facade()
	facade.get_state().current_player_id = 2
	var ballot = facade.get_pending_vote(2)
	assert_eq(str(ballot.get("resolution_id", "")), "elect_resident",
		"A member sees the open proposal")
	facade.apply_command(Commands.cast_vote(2, "abstain"))
	assert_true(facade.get_pending_vote(2).empty(),
		"Once voted, the member has no pending ballot")

func test_human_turn_raises_election_popup() -> void:
	var facade = _assembly_facade()
	# Player 2 defaults to human (is_ai == false): opening their turn raises the ballot.
	facade._maybe_raise_vote_popup(2)
	var popup = facade.get_pending_popup()
	assert_eq(int(popup.get("type", -1)), IDs.PopupType.CHOOSE_ELECTION,
		"An unvoted human member is shown the election popup")

func test_ai_member_votes_during_its_turn() -> void:
	var facade = _assembly_facade()
	var gs = facade.get_state()
	gs.get_player(2).is_ai = true
	gs.current_player_id = 2
	PlayerAI.manage_assembly(facade, 2)
	assert_true(Assembly.has_voted(gs, 2), "The AI casts its assembly vote")

func test_end_turn_loop_runs_assembly_sessions() -> void:
	# Drive the real end-turn pipeline with a founding wonder present: the world
	# step must establish the body, open a session on the cadence, and resolve it,
	# surfacing an assembly notification — all without error.
	var gs = make_gs(2)
	var c1 = make_settlement(gs, 1, 3, 3, 5); c1.belief_id = "christianity"
	c1.structures.append("united_nations")
	make_settlement(gs, 2, 8, 8, 3)
	var facade = bare_facade(gs)
	facade._hooks = hooks()
	var saw_event = [false]
	facade.connect("assembly_event", self, "_on_assembly_event", [saw_event])
	var interval = gs.db.get_constant("assembly_session_interval", 12)
	run_turns(facade, interval + 3)
	assert_eq(str(gs.assembly.get("kind", "")), "secular",
		"The end-turn loop establishes the secular assembly")
	assert_true(int(gs.assembly.get("last_session_turn", -1)) >= 0,
		"A session opened during the run")
	assert_true(saw_event[0], "An assembly_event signal fired through the drain")

func _on_assembly_event(_e, flag) -> void:
	flag[0] = true

# ── Issue 16: city growth notification ────────────────────────────────────────

func test_facade_growth_notification_appears_in_queue() -> void:
	# Manually push a pending_growth record and drain it; the notification must
	# appear in the queue so the message log shows it.
	var gs = make_gs(1)
	var f = bare_facade(gs)
	f._hooks = hooks()
	gs.pending_growth = [{"player_id": 1, "settlement_name": "Athens", "population": 2}]
	f._drain_growth_events()
	assert_true(gs.pending_growth.empty(), "pending_growth cleared after drain")
	var found = false
	for n in f.get_notification_queue():
		if str(n.get("text", "")).find("Athens") >= 0 and str(n.get("text", "")).find("2") >= 0:
			found = true
	assert_true(found, "Growth notification for Athens reaching pop 2 appears in the queue")

func test_city_growth_notification_via_end_turn() -> void:
	# A city with enough food to grow immediately should produce a notification
	# after end-turn drives the settlement step.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.name = "Corinth"
	s.food_store = 9999  # triggers growth on the first turn
	s.worked_tiles = [[5, 5]]
	gs.current_player_id = 1
	var f = bare_facade(gs)
	f._hooks = hooks()
	f.apply_command(Commands.end_turn(1))
	var found = false
	for n in f.get_notification_queue():
		if str(n.get("text", "")).find("Corinth") >= 0:
			found = true
	assert_true(found, "End-turn growth produces a notification mentioning the city name")

# ── Issue 19: event log for player unit deaths ────────────────────────────────

func test_notification_when_current_player_unit_killed_defending() -> void:
	# Current player's unit is the defender and dies — must appear in the log.
	var gs = make_gs(2)
	var defender = make_warrior(gs, 1, 5, 5)
	defender.health = 1  # will die
	var attacker = make_warrior(gs, 2, 5, 6)
	attacker.base_strength = 50  # guaranteed win
	gs.current_player_id = 1
	var f = bare_facade(gs)
	f._hooks = hooks()
	var result = Combat.resolve(attacker, defender, gs, gs.rng)
	f._apply_combat_result(attacker, defender, result, false)
	f._add_combat_notification(attacker, defender, result)
	if not result.get("defender_survived", true):
		var found = false
		for n in f.get_notification_queue():
			if str(n.get("text", "")).find("killed") >= 0 or str(n.get("text", "")).find("Your") >= 0:
				found = true
		assert_true(found, "Player's unit killed while defending generates a kill notification")

func test_wild_event_drain_notifies_player_unit_death() -> void:
	# A pending wild event flagging a player unit's death should produce a
	# notification when drained.
	var gs = make_gs(2)
	var f = bare_facade(gs)
	f._hooks = hooks()
	gs.get_player(1).name = "Alice"
	gs.pending_wild_events = [{
		"kind": "combat",
		"result": {"attacker_survived": true, "defender_survived": false,
			"attacker_health_after": 80, "defender_health_after": 0,
			"attacker_withdrew": false, "rounds": 3,
			"attacker_xp_gain": 5, "defender_xp_gain": 0,
			"spillover_damage": 0, "flanking_damage": 0},
		"attacker_type_id": "warrior",
		"defender_owner_id": 1,
		"defender_type_id": "warrior",
		"defender_x": 7, "defender_y": 3
	}]
	f._drain_wild_events()
	var found = false
	for n in f.get_notification_queue():
		var txt: String = str(n.get("text", ""))
		if txt.find("killed") >= 0 or txt.find("wild") >= 0 or txt.find("Wild") >= 0:
			found = true
	assert_true(found, "Draining a wild kill event produces a notification for the player")

# ── Specialist assignment & slot ceiling (§14.5) ─────────────────────────────

func test_assign_specialist_respects_slot_ceiling() -> void:
	var facade = setup_facade(640, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 6)
	# Default scientist slots = 1 (no Library), so one is allowed but two are not.
	assert_true(facade.apply_command(Commands.assign_specialist(pid, s.id, "scientist", 1)),
		"One scientist fits the default single slot")
	assert_false(facade.apply_command(Commands.assign_specialist(pid, s.id, "scientist", 2)),
		"A second scientist exceeds the slot ceiling")
	assert_eq(int(s.specialists.get("scientist", 0)), 1, "The over-cap assignment is rejected")

func test_assign_unknown_specialist_type_rejected() -> void:
	var facade = setup_facade(641, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 4)
	assert_false(facade.apply_command(Commands.assign_specialist(pid, s.id, "wizard", 1)),
		"An unknown specialist type is rejected")

# ── Goody huts (§9) ──────────────────────────────────────────────────────────────

func test_entering_goody_hut_consumes_it_and_applies_reward() -> void:
	var facade = setup_facade(77, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 0}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	# Force a single deterministic reward so the effect is checkable.
	gs.db.goodies = {"goodies": [{"id": "gold", "type": "treasury", "weight": 10, "min": 40, "max": 40}]}
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.get_player(pid).treasury = 0
	gs.map.get_tile(3, 2).has_discovery = true
	make_warrior(gs, pid, 2, 2)

	watch_signals(facade)
	assert_true(facade.apply_command(Commands.move_stack(pid, 2, 2, 3, 2)),
		"Moving onto a goody hut succeeds")
	assert_false(gs.map.get_tile(3, 2).has_discovery, "The hut is consumed on entry")
	assert_eq(gs.get_player(pid).treasury, 40, "The goody reward is applied (gold banked)")
	assert_signal_emitted(facade, "goody_received", "entering a hut emits goody_received")

func test_goody_ambush_spawns_wild_raiders_and_surfaces_them() -> void:
	var facade = setup_facade(77, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 0}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	# Lift the ancient quiet phase so raider-spawning bad goodies are eligible
	# (§24), then force a single deterministic ambush reward.
	gs.get_player(pid).technologies.append("alphabet")
	gs.db.goodies = {"goodies": [{"id": "ambush", "type": "ambush", "weight": 10,
		"damage": 50, "bad": true, "spawn_chance": 100, "min_spawn": 1,
		"spawn_unit": "warrior"}]}
	gs.map.get_tile(3, 2).has_discovery = true
	var w = make_warrior(gs, pid, 2, 2)

	watch_signals(facade)
	assert_true(facade.apply_command(Commands.move_stack(pid, 2, 2, 3, 2)),
		"Moving onto the ambush hut succeeds")
	assert_eq(w.health, 50, "the ambush damages the discoverer")
	var wild := 0
	for u in gs.units:
		if u.owner_player_id == -2 and u.is_wild:
			wild += 1
	assert_true(wild >= 1, "the ambush spawns at least one wild raider (owner -2)")
	assert_signal_emitted(facade, "unit_created",
		"each ambush raider is surfaced via unit_created")
	assert_signal_emitted(facade, "goody_received", "the ambush emits goody_received")

# ── Cultural-border vision: player_visible_tiles (border-vision feature) ──────

func test_player_visible_tiles_includes_owned_territory_and_one_ring() -> void:
	# A player with no units/cities still sees every owned tile plus a one-tile
	# fringe just outside it. Owned tile (10,10); the ring adds its 8 neighbours.
	var gs = make_gs(2)
	gs.map.get_tile(10, 10).owner_player_id = 1
	var f = bare_facade(gs)
	var seen = f.player_visible_tiles(1)
	assert_true(seen.has("10,10"), "Own territory tile is visible")
	# All 8 ring-1 neighbours are visible.
	for d in [[-1, -1], [0, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [0, 1], [1, 1]]:
		var k = str(10 + d[0]) + "," + str(10 + d[1])
		assert_true(seen.has(k), "One-ring fringe tile %s is visible" % k)
	# Two rings out, with no unit anywhere, is NOT visible.
	assert_false(seen.has("12,10"), "A tile two rings beyond the border is not visible")
	assert_false(seen.has("10,12"), "…and likewise on the other axis")

func test_player_visible_tiles_unions_with_unit_sight() -> void:
	# Territory vision is additive: a far-off unit's sight still shows up alongside
	# the territory + ring contribution.
	var gs = make_gs(2)
	gs.map.get_tile(2, 2).owner_player_id = 1
	make_unit(gs, "warrior", 1, 15, 15)   # well away from the owned tile
	var f = bare_facade(gs)
	var seen = f.player_visible_tiles(1)
	assert_true(seen.has("2,2"), "Owned territory still contributes")
	assert_true(seen.has("15,15"), "The unit's own tile is in sight")
	assert_true(seen.has("16,15"), "A tile within the unit's sight radius is visible")

func test_player_visible_tiles_excludes_rival_territory() -> void:
	# Player 1 does not see player 2's territory through the territory rule.
	var gs = make_gs(2)
	gs.map.get_tile(15, 15).owner_player_id = 2
	var f = bare_facade(gs)
	var seen = f.player_visible_tiles(1)
	assert_false(seen.has("15,15"), "A rival's owned tile is not visible to player 1")

func test_player_visible_tiles_ring_width_is_data_driven() -> void:
	# Bumping territory_vision_ring widens the fringe.
	var gs = make_gs(2)
	gs.db.constants["territory_vision_ring"] = 2
	gs.map.get_tile(10, 10).owner_player_id = 1
	var f = bare_facade(gs)
	var seen = f.player_visible_tiles(1)
	assert_true(seen.has("12,10"), "With ring=2 a tile two rings out is visible")
	assert_false(seen.has("13,10"), "…but three rings out is still hidden")

# ── Persistent fog memory: get_seen_memory (read API for the scene) ──────────

func test_get_seen_memory_empty_before_any_commit() -> void:
	var gs = make_gs(2)
	make_unit(gs, "warrior", 1, 5, 5)
	var f = bare_facade(gs)
	assert_true(f.get_seen_memory(1).empty(),
		"No memory until a player step commits it")

func test_get_seen_memory_returns_committed_snapshot() -> void:
	# After a player ends their turn, the facade exposes their seen-memory snapshot.
	var gs = make_gs(2)
	make_unit(gs, "warrior", 1, 5, 5)
	gs.map.get_tile(5, 5).owner_player_id = 1
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.end_turn(1))
	var mem = f.get_seen_memory(1)
	assert_true(mem.has("5,5"), "End-of-turn commit records the unit's tile")
	assert_eq(int(mem["5,5"].get("owner_player_id")), 1, "Snapshot carries the border owner")

# ── Gold rate (HUD signed per-turn readout) ───────────────────────────────────

func test_gold_rate_equals_income_minus_upkeep() -> void:
	var f = setup_facade(4242)
	var gs = f.get_state()
	var p = gs.get_player(gs.current_player_id)
	var expected = TurnEngine.gold_income(gs, p) - TurnEngine.gold_upkeep(gs, p)
	assert_eq(f.get_player_gold_rate(p.id), expected,
		"get_player_gold_rate == income - upkeep")

func test_gold_rate_matches_applied_treasury_delta() -> void:
	# The previewed rate must be exactly the delta _update_treasury applies, so the
	# HUD never lies. Unit upkeep makes the rate negative for a fresh player, so
	# stake the treasury first to keep the post-turn value off the insolvency clamp.
	var f = setup_facade(4243)
	var gs = f.get_state()
	var p = gs.get_player(gs.current_player_id)
	p.treasury = 1000
	var rate = f.get_player_gold_rate(p.id)
	var before = p.treasury
	gs.current_player_id = p.id
	f.apply_command(Commands.end_turn(p.id))
	assert_eq(p.treasury - before, rate,
		"Treasury moved by exactly the previewed gold rate")

func test_gold_rate_unknown_player_is_zero() -> void:
	var f = setup_facade(4244)
	assert_eq(f.get_player_gold_rate(999), 0, "Unknown player has a 0 gold rate")

# ── Unit strength display (Issue 4) ─────────────────────────────────────────────

# Net effective strength delegates to Unit.effective_strength (defender role) on
# the unit's current tile, so terrain/fortify/health modifiers are honest.

func test_strength_flat_open_ground_effective_equals_base() -> void:
	# A warrior standing on plain grassland (no defence bonus, full health, no
	# entrenchment) has effective == base.
	var gs = make_gs()
	var f = bare_facade(gs)
	var u = make_warrior(gs, 1, 5, 5)  # base_strength 10 on grassland
	assert_eq(f.unit_effective_strength(u.id), u.base_strength,
		"Flat open ground: effective == base")
	assert_eq(f.unit_strength_text(u.id), "Strength: 10 (10 effective)",
		"Display string for open-ground warrior")

func test_strength_defensive_tile_raises_effective() -> void:
	# Hills grant +25% defence; a defender's effective strength exceeds its base.
	var gs = make_gs()
	var f = bare_facade(gs)
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var u = make_warrior(gs, 1, 5, 5)  # base 10 → 10 * 125 / 100 = 12
	assert_true(f.unit_effective_strength(u.id) > u.base_strength,
		"Defensive tile gives effective > base")
	assert_eq(f.unit_effective_strength(u.id), 12, "10 base on hills (+25%) == 12")
	assert_eq(f.unit_strength_text(u.id), "Strength: 10 (12 effective)",
		"Display string for warrior on hills")

func test_strength_fortify_entrenchment_raises_effective() -> void:
	# Entrenchment (fortify) adds to a defender's effective strength even on flat
	# ground.
	var gs = make_gs()
	var f = bare_facade(gs)
	var u = make_warrior(gs, 1, 5, 5)  # base 10 on grassland
	u.entrenchment = 20  # +20%
	assert_eq(f.unit_effective_strength(u.id), 12, "Entrenched warrior 10 → 12")

func test_strength_injured_unit_reduces_effective() -> void:
	# Health scales effective strength down (mirrors Combat's health fraction).
	var gs = make_gs()
	var f = bare_facade(gs)
	var u = make_warrior(gs, 1, 5, 5)  # base 10
	u.health = 50
	assert_eq(f.unit_effective_strength(u.id), 5,
		"Half-health warrior 10 → 5 effective")
	assert_eq(f.unit_strength_text(u.id), "Strength: 10 (5 effective)",
		"Display string reflects health scaling")

func test_strength_civilian_has_no_strength_line() -> void:
	# A settler (base_strength 0) yields an empty string so the panel omits the line.
	var gs = make_gs()
	var f = bare_facade(gs)
	var u = make_unit(gs, "settler", 1, 5, 5)
	assert_eq(u.base_strength, 0, "Settler has base_strength 0")
	assert_eq(f.unit_effective_strength(u.id), 0, "Civilian effective strength is 0")
	assert_eq(f.unit_strength_text(u.id), "", "Civilian shows no strength line")

func test_strength_unknown_unit_is_empty() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	assert_eq(f.unit_effective_strength(999), 0, "Unknown unit effective strength 0")
	assert_eq(f.unit_strength_text(999), "", "Unknown unit shows no strength line")

# ── Explore mission permitted for all combat units (Issue 6) ──────────────────

# A plain melee combat unit (warrior) can receive the Explore mission, not just
# recon/scout. The facade gate must agree with the selection panel's button.
func test_explore_accepted_for_plain_combat_unit() -> void:
	var gs = make_gs(1)
	gs.current_player_id = gs.players[0].id
	var pid: int = gs.players[0].id
	var f = bare_facade(gs)
	var w = make_warrior(gs, pid, 5, 5)
	assert_true(w.base_strength > 0, "Warrior is a combat unit (base_strength > 0)")
	assert_true(f.apply_command(Commands.mission_explore(pid, w.id)),
		"A plain combat unit (warrior) is allowed to explore")
	assert_true(w.is_exploring, "Warrior is now exploring")

# A siege unit (catapult) is a player combat unit and may explore too.
func test_explore_accepted_for_siege_unit() -> void:
	var gs = make_gs(1)
	gs.current_player_id = gs.players[0].id
	var pid: int = gs.players[0].id
	var f = bare_facade(gs)
	var c = make_unit(gs, "catapult", pid, 6, 6)
	assert_true(f.apply_command(Commands.mission_explore(pid, c.id)),
		"A siege combat unit (catapult) is allowed to explore")
	assert_true(c.is_exploring, "Catapult is now exploring")

# Recon units keep working (the original behaviour).
func test_explore_accepted_for_recon_unit() -> void:
	var gs = make_gs(1)
	gs.current_player_id = gs.players[0].id
	var pid: int = gs.players[0].id
	var f = bare_facade(gs)
	var s = make_unit(gs, "scout", pid, 7, 7)
	assert_true(f.apply_command(Commands.mission_explore(pid, s.id)),
		"A recon/scout unit is still allowed to explore")
	assert_true(s.is_exploring, "Scout is now exploring")

# Civilians (base_strength 0) are still rejected — match existing behaviour.
func test_explore_rejected_for_civilian_units() -> void:
	var gs = make_gs(1)
	gs.current_player_id = gs.players[0].id
	var pid: int = gs.players[0].id
	var f = bare_facade(gs)
	var settler = make_unit(gs, "settler", pid, 8, 8)
	var worker = make_unit(gs, "worker", pid, 9, 9)
	assert_false(f.apply_command(Commands.mission_explore(pid, settler.id)),
		"A settler (civilian) may not explore")
	assert_false(settler.is_exploring, "Settler is not exploring")
	assert_false(f.apply_command(Commands.mission_explore(pid, worker.id)),
		"A worker (civilian) may not explore")
	assert_false(worker.is_exploring, "Worker is not exploring")

# ── Unit upgrades gate on the target's compound prerequisites (§15.12) ───────────

# Connect a resource to `pid`: an owned tile carrying it with its required
# improvement, plus the resource's reveal tech.
func _connect_resource_for(gs, pid, res_id, x, y) -> void:
	var res = gs.db.get_resource(res_id)
	var t = gs.map.get_tile(x, y)
	t.owner_player_id = pid
	t.resource_id = res_id
	t.improvement_id = str(res.get("improvement_required", ""))
	var reveal = str(res.get("tech_required", ""))
	var p = gs.get_player(pid)
	if reveal != "" and not p.has_tech(reveal):
		p.technologies.append(reveal)

func test_upgrade_blocked_without_target_tech() -> void:
	var gs = make_gs(1)
	var pid: int = gs.players[0].id
	gs.current_player_id = pid
	var f = bare_facade(gs)
	var p = gs.get_player(pid)
	p.treasury = 1000
	_connect_resource_for(gs, pid, "copper", 8, 8)   # resource side satisfied
	var vet = make_warrior(gs, pid, 5, 5)            # warrior upgrades_to axeman
	assert_false(f.apply_command(Commands.unit_upgrade(pid, vet.id)),
		"upgrade refused while the target's tech (bronze_working) is missing")
	assert_eq(vet.unit_type_id, "warrior", "unit unchanged after the refusal")
	p.technologies.append("bronze_working")
	assert_true(f.apply_command(Commands.unit_upgrade(pid, vet.id)),
		"upgrade accepted once the target's tech is researched")
	assert_eq(gs.get_unit(vet.id).unit_type_id, "axeman", "unit became the target type")

func test_upgrade_blocked_without_target_resource() -> void:
	# Axeman's compound resource set {"any": ["copper", "iron"]}: the upgrade is
	# refused with neither metal and accepted with either one connected.
	var gs = make_gs(1)
	var pid: int = gs.players[0].id
	gs.current_player_id = pid
	var f = bare_facade(gs)
	var p = gs.get_player(pid)
	p.treasury = 1000
	p.technologies.append("bronze_working")
	var vet = make_warrior(gs, pid, 5, 5)
	assert_false(f.apply_command(Commands.unit_upgrade(pid, vet.id)),
		"upgrade refused with no copper or iron connected")
	_connect_resource_for(gs, pid, "iron", 8, 8)
	assert_true(f.apply_command(Commands.unit_upgrade(pid, vet.id)),
		"upgrade accepted with iron alone (any-of set)")
	assert_eq(gs.get_unit(vet.id).unit_type_id, "axeman", "warrior upgraded to axeman")
