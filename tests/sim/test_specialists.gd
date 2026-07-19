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

# Specialists subsystem (§6.5 / §15.19 / R3): free settled specialists that sit
# on top of population, and the citizen default specialist the engine auto-fills
# with every citizen that has no tile to work and no specialist post.

# ── Table readers ────────────────────────────────────────────────────────────

func test_default_type_is_the_citizen() -> void:
	var db = make_db()
	assert_eq(Specialists.default_type(db), "citizen",
		"the citizen row carries the is_default flag (§15.19)")

func test_settled_greats_are_free() -> void:
	var db = make_db()
	assert_true(Specialists.is_free(db, "great_artist"),
		"a settled great is a free specialist (§15.19)")
	assert_false(Specialists.is_free(db, "scientist"),
		"a working specialist consumes a population slot")
	assert_false(Specialists.is_free(db, "citizen"),
		"the citizen default specialist is population, not a free specialist")

func test_population_used_counts_only_working_posts() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5, 6)
	s.specialists = {"scientist": 2, "priest": 1, "great_engineer": 3, "citizen": 2}
	assert_eq(Specialists.population_used(gs.db, s), 3,
		"free settled greats and auto-filled citizens consume no worker slot")

func test_settlement_unit_xp_sums_instructor_experience() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5, 2)
	s.specialists = {"great_general": 2, "scientist": 1, "citizen": 3}
	assert_eq(Specialists.settlement_unit_xp(gs.db, s), 4,
		"only the experience-carrying instructors contribute (+2 each, §15.20)")

# ── Free settled specialists (§15.19 / R3) ───────────────────────────────────

func test_free_settled_specialist_does_not_consume_a_worker_slot() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	s.specialists = {"great_artist": 1}
	TurnEngine._auto_assign_workers(gs, p)
	assert_eq(s.worked_tiles.size(), 3,
		"both citizens still work tiles (plus the free centre) — the settled great is free")
	assert_false(s.specialists.has("citizen"),
		"with tiles for everyone no citizen specialist is auto-filled")

func test_working_specialist_still_consumes_a_worker_slot() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	s.specialists = {"scientist": 1}
	TurnEngine._auto_assign_workers(gs, p)
	assert_eq(s.worked_tiles.size(), 2,
		"an assigned working specialist takes one citizen off the tiles")

# ── Citizen auto-assignment (§15.19 / R3) ────────────────────────────────────

func test_excess_citizens_become_citizen_specialists() -> void:
	# A 2x2 map leaves a corner city only 3 workable non-centre tiles: the two
	# leftover citizens of a size-5 city land as citizen default specialists.
	var gs = make_gs(1, 42, 2, 2)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 0, 0, 5)
	TurnEngine._auto_assign_workers(gs, p)
	assert_eq(s.worked_tiles.size(), 4, "centre plus the three reachable tiles")
	assert_eq(int(s.specialists.get("citizen", 0)), 2,
		"the two citizens with no tile to work become citizen specialists")

func test_unassigned_citizens_under_manual_management_become_citizens() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.manage_citizens_auto = false
	TurnEngine._auto_assign_workers(gs, p)
	assert_eq(s.worked_tiles.size(), 1, "manual mode works only the centre and locks")
	assert_eq(int(s.specialists.get("citizen", 0)), 3,
		"every unassigned citizen lands as a citizen specialist")

func test_citizens_reassigned_when_tiles_open_up() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.manage_citizens_auto = false
	TurnEngine._auto_assign_workers(gs, p)
	assert_eq(int(s.specialists.get("citizen", 0)), 3, "all idle under manual management")
	s.locked_tiles.append([5, 6])
	TurnEngine._auto_assign_workers(gs, p)
	assert_eq(int(s.specialists.get("citizen", 0)), 2,
		"locking a tile pulls one citizen back onto the land")
	s.manage_citizens_auto = true
	TurnEngine._auto_assign_workers(gs, p)
	assert_false(s.specialists.has("citizen"),
		"re-enabling automation re-employs every citizen (tiles abound)")

func test_citizen_specialists_yield_one_production_each() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.manage_citizens_auto = false
	TurnEngine._auto_assign_workers(gs, p)
	TurnEngine._settlement_growth(gs, s, p)
	var with_citizens: int = s.output_production
	s.specialists = {}
	TurnEngine._settlement_growth(gs, s, p)
	assert_eq(with_citizens, s.output_production + 3,
		"three auto-filled citizens add +1 production each (the shipped citizen row)")

func test_citizen_specialists_bank_no_gp_points() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5, 4)
	s.specialists = {"citizen": 4}
	assert_eq(Specialists.settlement_gp_points(gs.db, s), 0,
		"the citizen default specialist banks no GP points (§15.19)")

# ── Facade assignment cap (§15.19) ───────────────────────────────────────────

func test_free_specialist_does_not_block_assignment() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.specialists = {"great_engineer": 1}
	var f = bare_facade(gs)
	assert_true(f.apply_command(Commands.assign_specialist(1, s.id, "scientist", 1)),
		"a free settled great leaves the lone citizen assignable (§15.19)")
	assert_eq(int(s.specialists.get("scientist", 0)), 1, "the scientist post is filled")

func test_population_still_caps_working_specialists() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.specialists = {"scientist": 1}
	var f = bare_facade(gs)
	assert_false(f.apply_command(Commands.assign_specialist(1, s.id, "priest", 1)),
		"working posts beyond the population are refused")

func test_assigning_a_working_post_displaces_a_citizen() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	s.manage_citizens_auto = false
	TurnEngine._auto_assign_workers(gs, p)
	assert_eq(int(s.specialists.get("citizen", 0)), 2, "both citizens idle")
	var f = bare_facade(gs)
	assert_true(f.apply_command(Commands.assign_specialist(1, s.id, "scientist", 1)),
		"a citizen specialist never blocks a working post")
	assert_eq(int(s.specialists.get("citizen", 0)), 1,
		"the new post displaced one auto-filled citizen at once")

# ── Save/load: citizen counts survive and stay engine-managed ────────────────

func test_citizen_specialists_survive_a_save_roundtrip() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.manage_citizens_auto = false
	TurnEngine._auto_assign_workers(gs, p)
	var gs2 = GameState.deserialize(JSON.parse(JSON.print(gs.serialize())).result, gs.db)
	var s2 = gs2.settlements[0]
	assert_eq(int(s2.specialists.get("citizen", 0)), 3,
		"the auto-filled citizen count survives the roundtrip")
	assert_eq(JSON.print(gs2.serialize()), JSON.print(gs.serialize()),
		"a re-save of the loaded state is identical")
