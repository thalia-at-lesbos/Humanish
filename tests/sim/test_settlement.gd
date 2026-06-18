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

func test_growth_queues_pending_growth_record() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.name = "Sparta"
	s.food_store = 9999  # guaranteed growth
	s.worked_tiles = [[5, 5]]
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	assert_true(s.population > 1, "Population grew")
	assert_eq(gs.pending_growth.size(), 1, "One pending_growth record queued on pop increase")
	assert_eq(str(gs.pending_growth[0].get("settlement_name", "")), "Sparta",
		"Growth record names the city")
	assert_eq(int(gs.pending_growth[0].get("population", 0)), s.population,
		"Growth record has the new population")

func test_no_growth_no_pending_record() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.food_store = 0  # not enough to grow
	s.worked_tiles = []
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	assert_eq(gs.pending_growth.size(), 0, "No growth record when city does not grow")

func test_starvation_cannot_increase_pop() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.food_store = 0
	s.worked_tiles = []  # no food production
	var pop_before: int = s.population
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	assert_true(s.population <= pop_before, "Starvation should reduce or hold population")

func test_consumption_uses_food_per_citizen_constant() -> void:
	# Sustenance consumed per turn = population * food_per_citizen (data-driven, §4.2),
	# not a hardcoded 2.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 2)  # pop 2, dry inland, no food tiles
	s.worked_tiles = []
	s.food_store = 10
	TurnEngine._update_wellbeing(gs, s, gs.get_player(1), gs.db)
	var fpc: int = gs.db.get_constant("food_per_citizen", 2)
	var expected: int = 10 + (0 - s.wellbeing_deficit) - (s.population * fpc)
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	assert_eq(s.food_store, expected, "Consumption is population * food_per_citizen")

# ── Food box: angry citizens & unhealthiness (§4.2) ──────────────────────────

func test_angry_citizens_do_not_eat() -> void:
	# Consumption is over non-angry citizens only (population − discontented).
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 5)   # pop 5, dry inland
	s.worked_tiles = []                        # no food produced
	s.discontented = 2                         # two angry citizens this turn
	s.food_store = 20
	TurnEngine._update_wellbeing(gs, s, gs.get_player(1), gs.db)
	var fpc: int = gs.db.get_constant("food_per_citizen", 2)
	var net: int = s.health_rate()
	var drain: int = -net if net < 0 else 0
	var expected: int = 20 - ((5 - 2) * fpc + drain)
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	assert_eq(s.food_store, expected,
		"Only pop−discontented citizens eat (plus the unhealthiness drain)")

func test_unhealthy_city_grows_slower() -> void:
	# Two same-size cities with no food production: the unhealthy one drains more
	# of its food box (net unhealthiness adds to consumption), so it ends lower.
	var gs = make_gs(1)
	var healthy = make_settlement(gs, 1, 2, 2, 4)
	healthy.worked_tiles = []
	healthy.structures = ["hospital"]          # +3 health
	healthy.food_store = 40
	var sick = make_settlement(gs, 1, 8, 8, 4)
	sick.worked_tiles = []
	sick.structures = []                        # no health structures
	sick.food_store = 40
	TurnEngine._settlement_growth(gs, healthy, gs.get_player(1))
	TurnEngine._settlement_growth(gs, sick, gs.get_player(1))
	assert_lt(sick.food_store, healthy.food_store,
		"An unhealthy city drains its food box faster than a healthy one")

func test_carryover_capped_at_max_food_kept_percent() -> void:
	# A granary that would carry over 90% of the threshold is capped at the
	# configured max_food_kept_percent (75%).
	var gs = make_gs(1)
	var player = gs.get_player(1)
	gs.db.structures["granary"]["effects"]["food_carry_over"] = 90
	var s = make_settlement(gs, 1, 5, 5, 2)
	s.structures = ["granary"]
	s.worked_tiles = []
	# Compute the pre-growth threshold the engine will use (pop 2).
	var t_base: int = gs.db.get_constant("growth_threshold_base", 12)
	var t_per: int = gs.db.get_constant("growth_threshold_per_pop", 8)
	var pace_scale: int = int(gs.db.get_pace(gs.pace_id).get("growth_scale", 100))
	var era_scale: int = Eras.growth_threshold_scale(Eras.player_era(player, gs.db), gs.db)
	var threshold: int = Fixed.scale(Fixed.scale(t_base + t_per * 2, pace_scale), era_scale)
	s.food_store = threshold + 1000             # guaranteed growth
	TurnEngine._settlement_growth(gs, s, player)
	var max_kept: int = Fixed.scale(threshold, gs.db.get_constant("max_food_kept_percent", 75))
	assert_eq(s.food_store, max_kept,
		"Carry-over is capped at threshold × max_food_kept_percent/100, not the granary's 90%")

func test_growth_threshold_rises_with_pop_and_pace() -> void:
	# Guard the affine pop-and-speed curve: more population OR a slower pace both
	# raise the food needed to grow.
	var gs = make_gs(1)
	var t_base: int = gs.db.get_constant("growth_threshold_base", 12)
	var t_per: int = gs.db.get_constant("growth_threshold_per_pop", 8)
	var pop1: int = t_base + t_per * 1
	var pop5: int = t_base + t_per * 5
	assert_gt(pop5, pop1, "Threshold rises with population")
	var quick: int = Fixed.scale(pop5, int(gs.db.get_pace("quick").get("growth_scale", 67)))
	var marathon: int = Fixed.scale(pop5, int(gs.db.get_pace("marathon").get("growth_scale", 300)))
	assert_gt(marathon, quick, "Threshold rises with a slower pace")

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

func test_structure_percent_production_applies_multiplicatively() -> void:
	# A Forge (+25% production) scales the base production multiplicatively through
	# the §4.3 percent chain rather than adding a flat amount.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_production = 8
	s.structures = ["forge"]                       # production_bonus: 25
	s.production_queue = [{"type": "structure", "id": "library"}]  # high-cost, won't finish
	s.production_store = 0
	var build_scale: int = int(gs.db.get_pace(gs.pace_id).get("build_scale", 100))
	var base: int = Fixed.scale(8, build_scale)
	var expected: int = Fixed.apply_stacked_bonus(base, 25)
	TurnEngine._settlement_production(gs, s, p)
	assert_eq(s.production_store, expected,
		"Forge's +25% applies multiplicatively on base production, not as a flat add")

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

func test_river_border_gives_fresh_water() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)  # dry, surrounded by grassland
	TurnEngine._update_wellbeing(gs, s, gs.get_player(1), gs.db)
	var dry_pos: int = s.wellbeing_positive
	# A river running along the city tile's northern border is fresh water (§4.6),
	# even with no adjacent water body.
	gs.map.get_tile(2, 2).river_n = true
	TurnEngine._update_wellbeing(gs, s, gs.get_player(1), gs.db)
	assert_gt(s.wellbeing_positive, dry_pos, "A river border supplies fresh water")

# ── Difficulty handicaps (§2) ────────────────────────────────────────────────
# data/difficulties.json carries per-level growth_bonus, health_bonus and
# happiness_bonus that apply to every city; these assert the wiring.

func test_difficulty_growth_bonus_speeds_growth() -> void:
	# Equalise wellbeing across difficulties (hospital + fresh water so the deficit
	# is 0 even on Deity) so the only difference is the growth threshold itself.
	var grew_settler: int = _grow_pop_for_difficulty("settler")
	var grew_deity: int = _grow_pop_for_difficulty("deity")
	assert_eq(grew_settler, 2, "Easier difficulty lowers the threshold and the city grows")
	assert_eq(grew_deity, 1, "Harder difficulty raises the threshold and the city holds")

func _grow_pop_for_difficulty(diff, is_ai = false) -> int:
	var gs = make_gs(1)
	gs.difficulty_id = diff
	gs.get_player(1).is_ai = is_ai
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.structures = ["hospital"]            # +3 health → deficit 0 on every level
	gs.map.get_tile(6, 5).terrain_id = "coast"  # fresh water → +2 health
	s.worked_tiles = []                    # no food: surplus is a fixed -2
	s.food_store = 20                       # → 18 after consumption; crosses 15 not 24
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	return s.population

func test_ai_cities_receive_no_growth_aid() -> void:
	# The growth handicap is a human-only aid (§2.2): a Settler-difficulty AI city
	# does NOT get the lowered threshold, so it holds where a human city grows.
	assert_eq(_grow_pop_for_difficulty("settler", false), 2,
		"Human Settler city grows (receives the growth aid)")
	assert_eq(_grow_pop_for_difficulty("settler", true), 1,
		"AI Settler city holds (no city aids)")

func test_difficulty_health_bonus_affects_wellbeing() -> void:
	assert_true(_deficit_for_difficulty("deity") > _deficit_for_difficulty("settler"),
		"Harder difficulty worsens city wellbeing (larger deficit)")

func _deficit_for_difficulty(diff, is_ai = false) -> int:
	var gs = make_gs(1)
	gs.difficulty_id = diff
	gs.get_player(1).is_ai = is_ai
	var s = make_settlement(gs, 1, 2, 2, 5)  # dry inland city, no structures
	TurnEngine._update_wellbeing(gs, s, gs.get_player(1), gs.db)
	return s.wellbeing_deficit

func test_difficulty_happiness_bonus_affects_contentment() -> void:
	assert_true(_positive_for_difficulty("settler") > _positive_for_difficulty("deity"),
		"Easier difficulty grants more comfort (higher positive sentiment)")

func _positive_for_difficulty(diff, is_ai = false) -> int:
	var gs = make_gs(1)
	gs.difficulty_id = diff
	gs.get_player(1).is_ai = is_ai
	var s = make_settlement(gs, 1, 2, 2, 1)
	TurnEngine._update_contentment(gs, s, gs.get_player(1), gs.db)
	return s.positive_sentiment

# Handicaps are a player aid: AI players (is_ai) get none, so difficulty makes no
# difference to their cities (their handicap is the separate ai_bonus).

func test_difficulty_handicaps_skip_ai_players() -> void:
	assert_eq(_grow_pop_for_difficulty("settler", true),
		_grow_pop_for_difficulty("deity", true),
		"Growth handicap does not apply to AI players")
	assert_eq(_deficit_for_difficulty("settler", true),
		_deficit_for_difficulty("deity", true),
		"Health handicap does not apply to AI players")
	assert_eq(_positive_for_difficulty("settler", true),
		_positive_for_difficulty("deity", true),
		"Happiness handicap does not apply to AI players")

# ── Leader/society trait wellbeing (§4.6) ────────────────────────────────────

func test_expansive_trait_grants_health() -> void:
	# Expansive grants +2 health per city (the Beyond the Sword value).
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base_pos: int = s.wellbeing_positive
	p.traits = ["expansive"]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_positive, base_pos + 2,
		"Expansive grants +2 health per city (BtS value)")

func test_traitless_player_has_no_trait_health() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	p.traits = []
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	# No traits, no structures, dry inland: positive is purely difficulty (prince=0).
	assert_eq(s.wellbeing_positive, 0, "A traitless prince city has no positive wellbeing")

# ── Worked-tile feature wellbeing (§4.6) ─────────────────────────────────────

func test_worked_forest_improves_wellbeing() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	s.worked_tiles = [[2, 3]]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base_pos: int = s.wellbeing_positive
	gs.map.get_tile(2, 3).feature_id = "forest"  # health_bonus 1
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_positive, base_pos + 1, "A worked forest adds +1 health")

func test_worked_jungle_worsens_wellbeing() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	s.worked_tiles = [[2, 3]]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base_neg: int = s.wellbeing_negative
	gs.map.get_tile(2, 3).feature_id = "jungle"  # health_penalty 1
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_negative, base_neg + 1, "A worked jungle adds +1 unhealthiness")

func test_unworked_feature_does_not_affect_wellbeing() -> void:
	# Only worked tiles count; an unworked jungle in the wild is harmless.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	s.worked_tiles = []
	gs.map.get_tile(2, 3).feature_id = "jungle"
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_negative, s.population,
		"An unworked jungle contributes no unhealthiness")

# ── Specialist output (§6.5, data-table driven) ──────────────────────────────

func test_merchant_specialists_add_table_commerce() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	var p = gs.get_player(1)
	s.worked_tiles = []
	TurnEngine._settlement_growth(gs, s, p)
	var base_commerce: int = s.output_commerce
	s.specialists = {"merchant": 2}
	TurnEngine._settlement_growth(gs, s, p)
	var per: int = int(gs.db.get_specialist("merchant")["output"]["commerce"])
	assert_eq(s.output_commerce, base_commerce + 2 * per,
		"Each merchant adds the table's commerce output")

func test_engineer_specialists_add_table_production() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	var p = gs.get_player(1)
	s.worked_tiles = []
	TurnEngine._settlement_growth(gs, s, p)
	var base_prod: int = s.output_production
	s.specialists = {"engineer": 3}
	TurnEngine._settlement_growth(gs, s, p)
	var per: int = int(gs.db.get_specialist("engineer")["output"]["production"])
	assert_eq(s.output_production, base_prod + 3 * per,
		"Each engineer adds the table's production output (not commerce)")

func test_scientist_specialists_add_science_not_commerce() -> void:
	# A scientist's output is science, routed to research — not raw city commerce.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 5)
	var p = gs.get_player(1)
	s.worked_tiles = []
	TurnEngine._settlement_growth(gs, s, p)
	var base_commerce: int = s.output_commerce
	s.specialists = {"scientist": 2}
	TurnEngine._settlement_growth(gs, s, p)
	assert_eq(s.output_commerce, base_commerce,
		"Scientists yield science, not city commerce")
	assert_eq(Specialists.settlement_channel(gs.db, s, "science"),
		2 * int(gs.db.get_specialist("scientist")["output"]["science"]),
		"Scientist science is exposed on the science channel")
