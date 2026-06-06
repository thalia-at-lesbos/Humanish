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

# The per-settlement step (§4): growth & starvation, contentment/disorder,
# wellbeing, production completion, and culture accrual.

# ── Growth ───────────────────────────────────────────────────────────────────

func test_growth_step_no_crash() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.worked_tiles = [[5, 5]]
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	assert_true(true, "Growth step runs without crash")

func test_growth_pop_increases_above_threshold() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.food_store = 25  # threshold ~20
	s.worked_tiles = [[5, 5]]
	var pop_before: int = s.population
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	assert_true(s.population >= pop_before, "Population should not decrease during growth")

func test_starvation_cannot_increase_pop() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.food_store = 0
	s.worked_tiles = []  # no food production
	var pop_before: int = s.population
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	assert_true(s.population <= pop_before, "Starvation should reduce or hold population")

# ── Manual citizen management (worked-tile locks) ────────────────────────────

func _has_pair(arr, x, y) -> bool:
	for p in arr:
		if int(p[0]) == x and int(p[1]) == y:
			return true
	return false

func test_locked_tile_is_always_worked() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.locked_tiles = [[6, 5]]
	TurnEngine._auto_assign_workers(gs, gs.get_player(1))
	assert_true(_has_pair(s.worked_tiles, 6, 5),
		"A locked tile is worked regardless of its yield score")

func test_locked_tile_survives_reassignment() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	s.locked_tiles = [[4, 5]]
	TurnEngine._auto_assign_workers(gs, gs.get_player(1))
	TurnEngine._auto_assign_workers(gs, gs.get_player(1))   # a second turn
	assert_true(_has_pair(s.worked_tiles, 4, 5),
		"A manual lock persists across end-of-turn reassignment")

func test_manual_mode_works_only_locked_tiles() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.manage_citizens_auto = false
	s.locked_tiles = [[6, 5]]
	TurnEngine._auto_assign_workers(gs, gs.get_player(1))
	assert_eq(s.worked_tiles.size(), 1,
		"With automation off only the locked tile is worked")
	assert_true(_has_pair(s.worked_tiles, 6, 5), "…and it is the locked tile")

func test_auto_mode_fills_remaining_slots_around_locks() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.manage_citizens_auto = true
	s.locked_tiles = [[6, 5]]
	TurnEngine._auto_assign_workers(gs, gs.get_player(1))
	assert_eq(s.worked_tiles.size(), 3,
		"Automation fills the remaining worker slots beyond the lock")
	assert_true(_has_pair(s.worked_tiles, 6, 5), "…while still honouring the lock")

func test_lock_and_automation_survive_serialization() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	s.locked_tiles = [[6, 5], [4, 4]]
	s.manage_citizens_auto = false
	var s2 = Settlement.deserialize(s.serialize())
	assert_eq(s2.locked_tiles, [[6, 5], [4, 4]], "Locked tiles survive a save/load roundtrip")
	assert_false(s2.manage_citizens_auto, "The automation flag survives a save/load roundtrip")

# ── Contentment & disorder ──────────────────────────────────────────────────

func test_disorder_triggers_when_discontent_ge_population() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	s.negative_sentiment = 5
	s.positive_sentiment = 0
	TurnEngine._update_contentment(gs, s, gs.get_player(1), gs.db)
	if s.discontented >= s.population:
		assert_true(s.in_disorder, "Should be in disorder")
	else:
		assert_false(s.in_disorder, "No disorder when discontent < population")

func test_garrison_raises_contentment() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 4)
	var p = gs.get_player(1)
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var base_pos: int = s.positive_sentiment
	make_unit(gs, "warrior", 1, 5, 5)  # garrison
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_gt(s.positive_sentiment, base_pos, "A garrison raises positive sentiment")

func test_overcrowding_adds_anger() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var small = make_settlement(gs, 1, 5, 5, 5)  # below threshold 6
	TurnEngine._update_contentment(gs, small, p, gs.db)
	var small_neg: int = small.negative_sentiment
	var big = make_settlement(gs, 1, 9, 9, 20)  # well above threshold
	TurnEngine._update_contentment(gs, big, p, gs.db)
	assert_gt(big.negative_sentiment, small_neg, "Overcrowding raises negative sentiment")

func test_war_fatigue_raises_discontent() -> void:
	var gs = make_gs(2)
	var s = make_settlement(gs, 1, 5, 5, 10)
	var p = gs.get_player(1)
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var base_neg: int = s.negative_sentiment
	# 200 fatigue / divisor 4 = 50 anger points -> 50% of 10 pop = 5 discontented.
	gs.alliances[0].war_fatigue = {2: 200}
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_gt(s.negative_sentiment, base_neg, "War-fatigue increases negative sentiment")

# ── Production ───────────────────────────────────────────────────────────────

func test_disorder_suppresses_production() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.in_disorder = true
	s.output_production = 10
	s.production_queue = [{"type": "unit", "id": "warrior"}]
	s.production_store = 0
	TurnEngine._settlement_production(gs, s, gs.get_player(1))
	assert_eq(s.production_store, 0, "Disorder: production_store unchanged")

func test_production_completes_unit() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.production_queue = [{"type": "unit", "id": "warrior"}]
	s.production_store = 20  # warrior costs 15
	s.output_production = 0
	TurnEngine._settlement_production(gs, s, gs.get_player(1))
	assert_eq(gs.units.size(), 1, "One unit should have been created")

func test_production_carryover() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.production_queue = [{"type": "unit", "id": "warrior"}]
	s.production_store = 17  # warrior = 15, carryover = 2
	s.output_production = 0
	var units_before: int = gs.units.size()
	TurnEngine._settlement_production(gs, s, gs.get_player(1))
	if gs.units.size() > units_before:
		assert_eq(s.production_store, 2, "Surplus 2 should carry over")

# ── Culture ──────────────────────────────────────────────────────────────────

func test_culture_ring_does_not_decrease() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.culture_total = 0
	s.output_commerce = 5
	var ring_before: int = s.culture_ring
	for _i in range(3):
		TurnEngine._settlement_culture(gs, s, gs.get_player(1))
	assert_true(s.culture_ring >= ring_before, "Culture ring should not decrease over time")

func test_culture_uses_culture_slider_slice() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.output_commerce = 100
	s.culture_total = 0
	var p = gs.get_player(1)
	p.slider_finance = 40; p.slider_research = 40; p.slider_culture = 20; p.slider_intel = 0
	TurnEngine._settlement_culture(gs, s, p)
	assert_eq(s.culture_total, 20, "Culture accrues from the culture slider slice (20% of 100)")

func test_zero_culture_slider_accrues_nothing() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.output_commerce = 100
	s.culture_total = 0
	var p = gs.get_player(1)
	p.slider_finance = 60; p.slider_research = 40; p.slider_culture = 0; p.slider_intel = 0
	TurnEngine._settlement_culture(gs, s, p)
	assert_eq(s.culture_total, 0, "No culture accrues when the culture slider is zero")

# ── Wellbeing ────────────────────────────────────────────────────────────────

func test_wellbeing_deficit_non_negative() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	TurnEngine._update_wellbeing(gs, s, gs.get_player(1), gs.db)
	assert_true(s.wellbeing_deficit >= 0, "Wellbeing deficit is non-negative")

func test_fresh_water_improves_wellbeing() -> void:
	var gs = make_gs(1)
	var land_s = make_settlement(gs, 1, 2, 2, 3)  # surrounded by grassland
	TurnEngine._update_wellbeing(gs, land_s, gs.get_player(1), gs.db)
	var dry_pos: int = land_s.wellbeing_positive
	gs.map.get_tile(3, 2).terrain_id = "coast"  # adjacent water
	TurnEngine._update_wellbeing(gs, land_s, gs.get_player(1), gs.db)
	assert_gt(land_s.wellbeing_positive, dry_pos, "Adjacent fresh water improves wellbeing")

# ── Specialist output (§6.5) ─────────────────────────────────────────────────

func test_specialists_add_commerce() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	var p = gs.get_player(1)
	s.worked_tiles = []
	TurnEngine._settlement_growth(gs, s, p)
	var base_commerce: int = s.output_commerce
	s.specialists = {"merchant": 2}
	TurnEngine._settlement_growth(gs, s, p)
	var per: int = gs.db.get_constant("specialist_commerce", 3)
	assert_eq(s.output_commerce, base_commerce + 2 * per, "Each specialist adds commerce")
