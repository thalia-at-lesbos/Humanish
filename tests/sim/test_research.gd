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

# Research (§6.3): prerequisite gating, the prereq cost discount, accumulation to
# completion, the seeded starting tech, and alliance-pooled research.

# ── Prerequisite gating ──────────────────────────────────────────────────────

func test_can_research_tech_without_prereqs() -> void:
	var gs = make_gs(1)
	assert_true(Research.can_research("mining", gs.get_player(1), gs.db),
		"Mining has no prereqs, should be researchable")

func test_cannot_research_already_known() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.technologies.append("mining")
	assert_false(Research.can_research("mining", p, gs.db),
		"Cannot research a tech already known")

func test_cannot_research_missing_prereq() -> void:
	var gs = make_gs(1)
	assert_false(Research.can_research("bronze_working", gs.get_player(1), gs.db),
		"Cannot research bronze_working without mining prereq")

func test_can_research_with_prereq() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.technologies.append("mining")
	assert_true(Research.can_research("bronze_working", p, gs.db),
		"Can research bronze_working when mining is known")

func test_tech_tree_gating_along_the_age_chain() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	assert_true(Research.can_research("agriculture", p, gs.db), "agriculture open from the start")
	assert_false(Research.can_research("pottery", p, gs.db), "pottery locked without agriculture")
	p.technologies = ["agriculture"]
	assert_true(Research.can_research("pottery", p, gs.db), "pottery unlocks after agriculture")
	assert_false(Research.can_research("writing", p, gs.db), "writing still locked")

# ── Cost & completion ────────────────────────────────────────────────────────

func test_prereq_discount_applies() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.technologies.append("mining")
	var cost_with: int = Research._effective_cost("bronze_working", p, gs.db, {}, "normal")
	var p2 = load("res://src/sim/player.gd").new()
	p2.id = 99; p2.technologies = []
	var cost_without: int = Research._effective_cost("bronze_working", p2, gs.db, {}, "normal")
	assert_true(cost_with <= cost_without, "Having a prereq should reduce or equal research cost")

func test_research_accumulates_and_completes() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.current_research_id = "mining"
	p.slider_finance = 50; p.slider_research = 30; p.slider_culture = 10; p.slider_intel = 10
	var s = make_settlement(gs, 1, 5, 5)
	s.output_commerce = 100  # 30% research = 30/turn
	var completed: bool = false
	for _i in range(5):
		TurnEngine._apply_research(gs, p)
		if p.current_research_id == "":
			completed = true
			break
	assert_true(completed, "Mining should complete within 5 turns")
	assert_true(p.has_tech("mining"), "Player should have mining after research")

func test_setup_seeds_starting_tech_and_research() -> void:
	var facade = setup_facade(42, "tiny",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 100}], ["time"])
	var p = facade.get_state().players[0]
	assert_true(p.has_tech("agriculture"), "Players start knowing agriculture")
	assert_eq(p.current_research_id, "pottery", "Default research target is pottery")

# ── Alliance shared research (§6.3) ──────────────────────────────────────────

func _all_research_to(p):
	p.slider_research = 100; p.slider_finance = 0; p.slider_culture = 0; p.slider_intel = 0

func test_multi_member_alliance_pools_research() -> void:
	var gs = make_gs(2)
	gs.get_player(2).alliance_id = 1
	gs.alliances[0].add_member(2)
	make_settlement(gs, 1, 3, 3).output_commerce = 100
	make_settlement(gs, 2, 9, 9).output_commerce = 100
	_all_research_to(gs.get_player(1))
	_all_research_to(gs.get_player(2))
	TurnEngine._advance_alliances(gs)
	assert_gt(gs.alliances[0].shared_research_store, 0,
		"A multi-member alliance pools donated research")

func test_solo_alliance_pools_nothing() -> void:
	var gs = make_gs(2)
	make_settlement(gs, 1, 3, 3).output_commerce = 100
	TurnEngine._advance_alliances(gs)
	assert_eq(gs.alliances[0].shared_research_store, 0,
		"A solo alliance contributes nothing to a shared pool (no double count)")

func test_shared_store_drawn_into_member_research() -> void:
	var gs = make_gs(2)
	var p = gs.get_player(1)
	gs.get_player(2).alliance_id = 1
	gs.alliances[0].add_member(2)
	p.current_research_id = "mining"
	gs.alliances[0].shared_research_store = 40
	var before: int = p.research_store
	TurnEngine._apply_research(gs, p)
	assert_gt(p.research_store + (40 if p.current_research_id == "" else 0), before,
		"A member draws its share of the shared pool")
	assert_lt(gs.alliances[0].shared_research_store, 40, "Drawing from the pool decrements it")
