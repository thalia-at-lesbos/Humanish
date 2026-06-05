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

# Exercises the simple computer player (PlayerAI). Covers each decision area —
# research (cheapest), civics (latest), production (cheapest-first rotation),
# units (garrison vs. random) — plus whole-turn determinism through the facade.

# A bare facade armed with a Hooks registry, so end_turn (and thus take_turn) can
# run the turn pipeline against a hand-built state.
func ai_facade(gs):
	var f = bare_facade(gs)
	f._hooks = hooks()
	return f

# ── Research: cheapest researchable tech ───────────────────────────────────────

func test_research_picks_cheapest_available() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)

	PlayerAI.manage_research(f, 1)

	assert_ne(p.current_research_id, "", "AI should choose something to research")
	# No researchable tech may be cheaper than the one chosen.
	var chosen_cost: int = int(gs.db.technologies[p.current_research_id].get("cost", 0))
	for tech_id in gs.db.technologies:
		if Research.can_research(tech_id, p, gs.db):
			assert_true(int(gs.db.technologies[tech_id].get("cost", 0)) >= chosen_cost,
				"Chosen research must be the cheapest available")

func test_research_only_chooses_researchable() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	PlayerAI.manage_research(f, 1)
	assert_true(Research.can_research(p.current_research_id, p, gs.db),
		"Chosen tech must satisfy its prerequisites")

# ── Civics: latest unlocked policy per category ────────────────────────────────

func test_civics_adopts_latest_with_no_tech() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)

	PlayerAI.manage_civics(f, 1)

	# With no techs, the latest unlocked labor policy is serfdom (tribalism →
	# slavery → serfdom are the tech-free ones, in that order).
	assert_eq(p.policies.get("labor", ""), "serfdom",
		"Latest tech-free labor policy is serfdom")
	assert_eq(p.policies.get("government", ""), "despotism",
		"Only unlocked government policy is despotism")

func test_civics_advances_when_tech_unlocks() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	p.technologies.append("monarchy")

	PlayerAI.manage_civics(f, 1)

	assert_eq(p.policies.get("government", ""), "hereditary_rule",
		"With monarchy known, the latest government policy is hereditary_rule")

# ── Production: every buildable item, cheapest first ───────────────────────────

func test_production_options_sorted_ascending() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)

	var opts = PlayerAI._sorted_options(gs, s, p)
	assert_true(opts.size() > 0, "There should be buildable options")
	for i in range(1, opts.size()):
		assert_true(int(opts[i]["cost"]) >= int(opts[i - 1]["cost"]),
			"Options must be ordered cheapest-first")

func test_production_fills_empty_queue_cheapest_first() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)

	var opts = PlayerAI._sorted_options(gs, s, p)
	PlayerAI.manage_production(f, 1)

	assert_false(s.production_queue.empty(), "Queue should be populated")
	# The queue is exactly the cheapest-first option list (rotation through all).
	assert_eq(s.production_queue.size(), opts.size(), "Queue lists every possibility")
	for i in range(opts.size()):
		assert_eq(str(s.production_queue[i].get("id", "")), str(opts[i]["id"]),
			"Queue order matches the cheapest-first plan")

func test_production_excludes_great_people() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	# Give the player every tech so Great People would qualify on tech grounds.
	for tech_id in gs.db.technologies:
		p.technologies.append(tech_id)
	var s = make_settlement(gs, 1, 5, 5)
	for opt in PlayerAI._sorted_options(gs, s, p):
		var cls: String = str(gs.db.get_unit(str(opt["id"])).get("classification", ""))
		assert_ne(cls, "great_person", "Great People are never offered as production")

func test_production_leaves_busy_queue_untouched() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var s = make_settlement(gs, 1, 5, 5)
	s.production_queue = [{"type": "unit", "id": "settler"}]

	PlayerAI.manage_production(f, 1)

	assert_eq(s.production_queue.size(), 1, "An in-progress queue is not replanned")
	assert_eq(str(s.production_queue[0]["id"]), "settler", "Existing build is preserved")

func test_production_excludes_already_built_structures() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.structures.append("granary")
	for opt in PlayerAI._sorted_options(gs, s, p):
		if str(opt["type"]) == "structure":
			assert_ne(str(opt["id"]), "granary", "Built structures are not re-offered")

# ── Units: garrison vs. random ─────────────────────────────────────────────────

func test_garrison_unit_on_city_fortifies() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 1, 5, 5)
	var u = make_warrior(gs, 1, 5, 5)

	PlayerAI._garrison_unit(f, gs, u, 1)

	assert_true(u.is_fortified, "A unit standing on its own city fortifies in place")

func test_garrison_unit_off_city_moves_toward_it() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 1, 5, 5)
	var u = make_warrior(gs, 1, 9, 9)

	PlayerAI._garrison_unit(f, gs, u, 1)

	assert_true(u.has_moved, "A unit away from its city heads toward it")
	var moved_closer: bool = gs.map.distance(u.x, u.y, 5, 5) < gs.map.distance(9, 9, 5, 5)
	assert_true(moved_closer, "Movement should reduce distance to the city")

func test_nearest_owned_city_picks_closest() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var near = make_settlement(gs, 1, 6, 6)
	make_settlement(gs, 1, 15, 15)
	var u = make_warrior(gs, 1, 5, 5)
	var got = PlayerAI._nearest_owned_city(gs, u, 1)
	assert_eq(got.id, near.id, "Should target the nearest owned settlement")

func test_manage_units_is_deterministic() -> void:
	# Two identical worlds (same seed) must reach an identical state hash after a
	# pass of unit management — proving the AI draws only from the shared gs.rng.
	var hash_a = _run_units_world()
	var hash_b = _run_units_world()
	assert_eq(hash_a, hash_b,
		"Unit management is reproducible for a given seed")

func _run_units_world() -> int:
	var gs = make_gs(1, 31337)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 1, 5, 5)
	make_warrior(gs, 1, 5, 5)
	make_warrior(gs, 1, 7, 7)
	make_unit(gs, "settler", 1, 9, 9)
	make_unit(gs, "worker", 1, 11, 11)
	PlayerAI.manage_units(f, 1)
	return f.state_hash()

# ── Whole turn through the facade ──────────────────────────────────────────────

func test_take_turn_advances_to_next_player() -> void:
	var gs = make_gs(2)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 1, 5, 5)
	make_warrior(gs, 1, 5, 5)

	PlayerAI.take_turn(f, 1)

	assert_eq(gs.current_player_id, 2, "Ending the AI turn passes play to the next player")

func test_take_turn_noop_when_not_active_player() -> void:
	var gs = make_gs(2)
	var f = ai_facade(gs)
	gs.current_player_id = 2          # it is player 2's turn, not player 1's
	make_settlement(gs, 1, 5, 5)

	PlayerAI.take_turn(f, 1)

	assert_eq(gs.current_player_id, 2, "AI does nothing when it is not its turn")

func test_take_turn_is_deterministic() -> void:
	var h1 = _run_full_turn_hash()
	var h2 = _run_full_turn_hash()
	assert_eq(h1, h2, "A full AI turn yields the same state hash for the same seed")

func _run_full_turn_hash() -> int:
	var gs = make_gs(2, 24680)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 1, 5, 5)
	make_warrior(gs, 1, 5, 5)
	make_unit(gs, "settler", 1, 8, 8)
	PlayerAI.take_turn(f, 1)
	return f.state_hash()
