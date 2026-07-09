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

# ── §6.3 cost chain (game-data §15.4) ────────────────────────────────────────

func test_research_cost_scales_with_pace_marathon_3x() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	# mining has no prereqs → no discounts interfere with the raw chain.
	var normal: int = Research._effective_cost("mining", p, gs.db, {}, "normal")
	var marathon: int = Research._effective_cost("mining", p, gs.db, {}, "marathon")
	assert_eq(marathon, normal * 3, "Marathon tech cost is 3× Normal")

func test_research_cost_scales_with_difficulty_handicap() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var noble: int = Research._effective_cost("mining", p, gs.db, {}, "normal", "noble")
	var deity: int = Research._effective_cost("mining", p, gs.db, {}, "normal", "deity")
	assert_eq(noble, Fixed.scale(50, 130), "Noble pays base × the standard-world 130%")
	assert_eq(deity, Fixed.scale(Fixed.scale(50, 135), 130), "Deity pays the 135% handicap on top")
	assert_gt(deity, noble, "A higher difficulty raises the human research cost")

func test_research_cost_scales_with_world_size() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var standard: int = Research._effective_cost("mining", p, gs.db, {}, "normal", "noble", "standard")
	var huge: int = Research._effective_cost("mining", p, gs.db, {}, "normal", "noble", "huge")
	assert_eq(huge, Fixed.scale(50, 150), "A Huge map is 150% of base (reference floor 100 at Duel)")
	assert_gt(huge, standard, "A larger map raises research cost")

func test_research_cost_scales_with_team_size() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var solo: int = Research._effective_cost("mining", p, gs.db, {}, "normal", "noble", "standard", 1)
	var pair: int = Research._effective_cost("mining", p, gs.db, {}, "normal", "noble", "standard", 2)
	var mod: int = gs.db.get_constant("tech_cost_extra_team_member_modifier", 30)
	assert_eq(solo, Fixed.scale(50, 130), "A solo player pays the chained cost (team factor is a no-op)")
	assert_eq(pair, Fixed.scale(Fixed.scale(50, 130), 100 + mod), "A two-member team pays (100+modifier)%")
	assert_gt(pair, solo, "Each extra team member raises the shared-research cost")

# ── §2.2 difficulty research handicaps ───────────────────────────────────────

func test_human_pays_handicap_but_ai_does_not() -> void:
	var gs = make_gs(2)
	var human = gs.get_player(1); human.is_ai = false
	var ai = gs.get_player(2); ai.is_ai = true
	ai.technologies = ["mining"]  # ancient → era 0, so no per-era modifier yet
	var human_cost: int = Research._effective_cost("agriculture", human, gs.db, {}, "normal", "deity")
	var ai_cost: int = Research._effective_cost("agriculture", ai, gs.db, {}, "normal", "deity")
	assert_eq(human_cost, Fixed.scale(Fixed.scale(60, 135), 130),
		"Human pays the Deity 135% research handicap (× standard-world 130%)")
	assert_lt(ai_cost, human_cost, "The AI does not pay the human handicap")

func test_ai_research_per_era_compounds() -> void:
	var gs = make_gs(1)
	var ai = gs.get_player(1); ai.is_ai = true
	# agriculture has no prereqs, so no discount masks the per-era modifier.
	ai.technologies = ["mining"]                      # ancient → era 0
	var era0: int = Research._effective_cost("agriculture", ai, gs.db, {}, "normal", "deity")
	assert_eq(era0, Fixed.scale(60, 130),
		"At era 0 the per-era modifier is a no-op (only the standard-world 130% applies)")
	ai.technologies = ["mining", "metal_casting"]     # classical → a later era
	var later: int = Research._effective_cost("agriculture", ai, gs.db, {}, "normal", "deity")
	assert_lt(later, era0, "A later-era Deity AI pays less per tech (per-era discount compounds)")

func test_ai_research_per_era_reference_sign_negative_is_cheaper() -> void:
	# A3 reference semantics: `ai_research_per_era` keeps the reference sign — a
	# NEGATIVE value makes AI techs CHEAPER, compounding ×(100+per_era)% per era
	# (the old engine read was 100−per_era with flipped data signs).
	var gs = make_gs(1)
	var ai = gs.get_player(1); ai.is_ai = true
	gs.db.difficulties["deity"]["ai_research_per_era"] = -10
	ai.technologies = ["mining", "metal_casting"]     # classical → era ≥ 1
	var eras: int = Eras.player_era(ai, gs.db)
	assert_gt(eras, 0, "precondition: the AI is past the starting era")
	var expected: int = 60                            # agriculture base; the AI pays no handicap
	for _i in range(eras):
		expected = Fixed.scale(expected, 90)          # 100 + (−10) each era
	expected = Fixed.scale(expected,
		int(gs.db.get_world_size("standard").get("research_percent", 100)))
	var cost: int = Research._effective_cost("agriculture", ai, gs.db, {}, "normal", "deity")
	assert_eq(cost, expected,
		"a negative per-era modifier compounds as (100+per_era)% — cheaper each era")

func test_discount_applies_after_the_chain() -> void:
	# The 10% prereq discount comes off the post-chain (marathon-scaled) cost.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.technologies = ["mining"]  # holds bronze_working's prereq
	var cost: int = Research._effective_cost("bronze_working", p, gs.db, {}, "marathon", "noble")
	var post_chain: int = Fixed.scale(Fixed.scale(120, 130), 300)  # base 120 × standard world 130% × marathon 300%
	assert_eq(cost, post_chain - Fixed.scale(post_chain, 10),
		"The prereq discount is taken off the chained cost, not the base")

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

# ── Finance supplementing research (§6.3) ────────────────────────────────────

func test_finance_supplements_research_when_unfunded() -> void:
	# Research slider at 0, all commerce to finance: a fraction of finance income
	# still feeds the current project so a commerce-funded empire advances.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.current_research_id = "mining"
	p.slider_finance = 100; p.slider_research = 0; p.slider_culture = 0; p.slider_intel = 0
	make_settlement(gs, 1, 5, 5).output_commerce = 10  # too little to complete mining
	var before: int = p.research_store
	TurnEngine._apply_research(gs, p)
	assert_gt(p.research_store, before,
		"net finance supplements research when the research channel is unfunded")

func test_no_finance_supplement_when_research_funded() -> void:
	# With the research slider above 0 the supplement does not apply: progress
	# comes only from the research slice of commerce.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.current_research_id = "mining"
	p.slider_finance = 50; p.slider_research = 50; p.slider_culture = 0; p.slider_intel = 0
	make_settlement(gs, 1, 5, 5).output_commerce = 10
	TurnEngine._apply_research(gs, p)
	assert_eq(p.research_store, 5,
		"only the 50% research slice accrues; finance is not double-counted")

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
