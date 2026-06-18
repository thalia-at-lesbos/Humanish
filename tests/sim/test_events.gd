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

# Events & exploration (§9): the events table loads, scripted events fire once
# after their min-turn, and entering a discovery site consumes it for a reward.

func test_events_table_loads() -> void:
	var gs = make_gs()
	assert_true(gs.db.events.has("ancient_windfall"), "events.json loads into DataDB")
	assert_true(gs.db.get_errors().empty(), "DataDB still loads cleanly with the events table")

func test_scripted_event_fires_once_after_min_turn() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.treasury = 0
	gs.turn_number = 10  # >= min_turn 8
	var fired = Events.process_player_events(p, gs, gs.rng)
	assert_eq(fired.size(), 1, "Event fires when its min_turn is reached")
	assert_eq(p.treasury, 50, "Event treasury effect applied")
	Events.process_player_events(p, gs, gs.rng)
	assert_eq(p.treasury, 50, "A once-fired event does not repeat")

func test_scripted_event_held_before_min_turn() -> void:
	var gs = make_gs()
	gs.turn_number = 2  # < min_turn 8
	var fired = Events.process_player_events(gs.get_player(1), gs, gs.rng)
	assert_true(fired.empty(), "Event does not fire before its min_turn")

func test_entering_discovery_site_yields_reward() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	gs.map.get_tile(6, 5).has_discovery = true
	make_unit(gs, "warrior", 1, 5, 5)
	f._cmd_move_stack({"player_id": 1, "from_x": 5, "from_y": 5, "to_x": 6, "to_y": 5})
	assert_false(gs.map.get_tile(6, 5).has_discovery, "Discovery site is consumed on entry")

# ── Goody-hut reward table (§9) ──────────────────────────────────────────────────

func test_goodies_table_loads() -> void:
	var gs = make_gs()
	assert_true(gs.db.get_goodies().size() > 0, "goodies.json loads a non-empty reward list")
	assert_true(gs.db.get_errors().empty(), "DataDB still loads cleanly with the goodies table")

func test_goody_treasury_adds_gold() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	gs.get_player(1).treasury = 0
	var r = Events._apply_goody({"type": "treasury", "min": 50, "max": 50}, u, gs, gs.rng)
	assert_eq(r["type"], "treasury")
	assert_eq(gs.get_player(1).treasury, 50, "treasury goody banks gold for the owner")

func test_goody_heal_restores_unit() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	u.health = 10
	Events._apply_goody({"type": "heal"}, u, gs, gs.rng)
	assert_eq(u.health, gs.db.get_constant("max_hp", 100), "heal goody restores full health")

func test_goody_experience_adds_xp() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	u.experience = 0
	Events._apply_goody({"type": "experience", "min": 7, "max": 7}, u, gs, gs.rng)
	assert_eq(u.experience, 7, "experience goody adds XP to the discoverer")

func test_goody_unit_spawns_free_unit() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	var before = gs.units.size()
	var r = Events._apply_goody({"type": "unit", "unit_type": "warrior"}, u, gs, gs.rng)
	assert_eq(gs.units.size(), before + 1, "unit goody spawns a free unit")
	assert_true(int(r.get("unit_id", -1)) >= 0, "unit goody returns the new unit id")
	var spawned = gs.get_unit(int(r["unit_id"]))
	assert_eq(spawned.owner_player_id, 1, "the free unit belongs to the discoverer")
	assert_eq([spawned.x, spawned.y], [5, 5], "the free unit appears on the discoverer's tile")

func test_goody_tech_grants_free_tech() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	var p = gs.get_player(1)
	p.technologies = ["agriculture"]
	var before = p.technologies.size()
	var r = Events._apply_goody({"type": "tech"}, u, gs, gs.rng)
	assert_true(str(r.get("tech_id", "")) != "", "tech goody grants a researchable tech")
	assert_eq(p.technologies.size(), before + 1, "the granted tech is added to the player")

func test_goody_ambush_hurts_but_never_kills() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	u.health = 30
	Events._apply_goody({"type": "ambush", "damage": 50}, u, gs, gs.rng)
	assert_eq(u.health, 1, "ambush floors the discoverer at 1 health, never killing it")

func test_exploration_reward_is_rng_deterministic() -> void:
	var a = make_gs(1, 4242)
	var ua = make_unit(a, "warrior", 1, 5, 5)
	var ra = Events.exploration_reward(ua, a, a.rng)
	var b = make_gs(1, 4242)
	var ub = make_unit(b, "warrior", 1, 5, 5)
	var rb = Events.exploration_reward(ub, b, b.rng)
	assert_eq(ra["type"], rb["type"], "the same seed rolls the same goody type")
