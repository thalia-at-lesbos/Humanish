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
	assert_true(text.find("pop") >= 0, "Foreign city's population appears in tile info")

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
