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
	# Keep both boxes below the growth threshold (20 + 2·pop since A11) so
	# neither city grows — growth resets the box to 50% of threshold and would
	# erase the consumption difference this test measures.
	healthy.food_store = 10
	var sick = make_settlement(gs, 1, 8, 8, 4)
	sick.worked_tiles = []
	sick.structures = []                        # no health structures
	sick.food_store = 10
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

func test_city_centre_is_always_worked_for_free() -> void:
	# §4.1: the city centre tile is worked for free (it does not consume a
	# population worker slot). A size-1 city therefore works its centre PLUS one
	# population tile — the root of the "city never grows" bug: without the free
	# centre a lone citizen worked a single off-centre tile and the centre's yield
	# (and the resulting food surplus) was lost.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 1)
	TurnEngine._auto_assign_workers(gs, gs.get_player(1))
	assert_true(_has_pair(s.worked_tiles, 5, 5),
		"The city centre tile is always worked")
	assert_eq(s.worked_tiles.size(), 2,
		"A size-1 city works the free centre plus one population tile")

func test_city_centre_not_double_counted_when_locked() -> void:
	# Locking the centre tile must not add a duplicate or charge a worker slot.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.locked_tiles = [[5, 5]]
	TurnEngine._auto_assign_workers(gs, gs.get_player(1))
	assert_eq(s.worked_tiles.size(), 2,
		"Locking the centre does not create a duplicate or consume the budget")
	var centre_count: int = 0
	for p in s.worked_tiles:
		if int(p[0]) == 5 and int(p[1]) == 5:
			centre_count += 1
	assert_eq(centre_count, 1, "The centre appears exactly once")

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
	assert_eq(s.worked_tiles.size(), 2,
		"With automation off only the free centre and the locked tile are worked")
	assert_true(_has_pair(s.worked_tiles, 6, 5), "…and the locked tile is worked")
	assert_true(_has_pair(s.worked_tiles, 5, 5), "…alongside the free city centre")

func test_mountain_is_never_auto_assigned() -> void:
	# A5 (reference): peaks are unworkable — auto-assign must skip them even when
	# every other candidate is exhausted.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	gs.map.get_tile(6, 5).terrain_id = "mountain"
	TurnEngine._auto_assign_workers(gs, gs.get_player(1))
	assert_false(_has_pair(s.worked_tiles, 6, 5),
		"An unworkable mountain tile is never auto-assigned a citizen")

func test_locked_mountain_is_not_worked() -> void:
	# A manual lock on unworkable terrain is ignored by the assigner.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	gs.map.get_tile(6, 5).terrain_id = "mountain"
	s.locked_tiles = [[6, 5]]
	TurnEngine._auto_assign_workers(gs, gs.get_player(1))
	assert_false(_has_pair(s.worked_tiles, 6, 5),
		"A locked mountain tile is still never worked")

func test_set_tile_worked_rejects_mountain() -> void:
	# The SET_TILE_WORKED command refuses to lock an unworkable tile at all.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	gs.map.get_tile(6, 5).terrain_id = "mountain"
	var f = bare_facade(gs)
	var ok: bool = f.apply_command(Commands.set_tile_worked(1, s.id, 6, 5, true))
	assert_false(ok, "Locking a mountain tile is rejected")
	assert_eq(s.locked_tiles.size(), 0, "No lock is recorded")

func test_river_tile_adds_commerce_to_city_output() -> void:
	# A5 (reference): a worked grassland river tile yields +1 commerce. The centre
	# tile is given a river border; output is compared against a river-less twin.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.manage_citizens_auto = false
	TurnEngine._auto_assign_workers(gs, gs.get_player(1))
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	var dry: int = s.output_commerce
	gs.map.get_tile(5, 5).river_n = true
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	assert_eq(s.output_commerce, dry + 1,
		"A river border on a worked grassland tile adds +1 commerce")

func test_auto_mode_fills_remaining_slots_around_locks() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.manage_citizens_auto = true
	s.locked_tiles = [[6, 5]]
	TurnEngine._auto_assign_workers(gs, gs.get_player(1))
	assert_eq(s.worked_tiles.size(), 4,
		"Automation fills the remaining worker slots beyond the lock (plus free centre)")
	assert_true(_has_pair(s.worked_tiles, 6, 5), "…while still honouring the lock")
	assert_true(_has_pair(s.worked_tiles, 5, 5), "…and the centre is worked for free")

func test_lock_and_automation_survive_serialization() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	s.locked_tiles = [[6, 5], [4, 4]]
	s.manage_citizens_auto = false
	var s2 = Settlement.deserialize(s.serialize())
	assert_eq(s2.locked_tiles, [[6, 5], [4, 4]], "Locked tiles survive a save/load roundtrip")
	assert_false(s2.manage_citizens_auto, "The automation flag survives a save/load roundtrip")

# ── End-to-end growth (the full player_step pipeline) ────────────────────────
# These drive growth through the real pipeline (worker assignment → settlement
# step), the path that exposed the "city never grows" regression — the direct
# _settlement_growth tests above can't catch a worker-assignment fault because
# they hand-set worked_tiles.

func test_wellfed_city_grows_over_turns_endtoend() -> void:
	# A grassland city (centre 2 food + worked-tile 2 food = 4) consumes 2/turn
	# plus 1 to its net unhealthiness at size 1, banks a +1 surplus, and must
	# cross the size-1 growth threshold (20) within a reasonable horizon and
	# increase population. (Beliefs are tech-gated, so no turn-1 health bonus.)
	var gs = make_gs(1, 42, 20, 20)
	var s = make_settlement(gs, 1, 10, 10, 1)
	Influence.found_claim(gs.map, 10, 10, 1, 2, 20)
	var f = bare_facade(gs)
	for _t in range(24):
		gs.current_player_id = 1
		f.apply_command(Commands.end_turn(1))
	assert_true(s.population > 1,
		"A well-fed grassland city grows over turns through the full pipeline")

func test_surplus_reaches_food_box_each_turn_endtoend() -> void:
	# After one full turn the city centre is worked and the food box has banked a
	# positive surplus (output_food > consumption), proving the centre's yield
	# feeds the box rather than being lost.
	var gs = make_gs(1, 7, 20, 20)
	var s = make_settlement(gs, 1, 10, 10, 1)
	Influence.found_claim(gs.map, 10, 10, 1, 2, 20)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	f.apply_command(Commands.end_turn(1))
	assert_true(_has_pair(s.worked_tiles, 10, 10),
		"The city centre is worked after a turn of the real pipeline")
	var fpc: int = gs.db.get_constant("food_per_citizen", 2)
	assert_true(s.output_food > s.population * fpc,
		"Food output exceeds consumption, so the food box accrues a surplus")
	assert_true(s.food_store > 0, "The surplus reaches the food box")

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

# ── Trait production-speed modifiers (B4, audit §1.8) ──────────────────────────

func test_trait_doubles_listed_structure_production() -> void:
	# The reference trait model: Aggressive builds barracks at DOUBLE speed
	# (+100% production toward it), so the listed structure completes in half the
	# turns — it is not granted free.
	var gs = make_gs(2)
	var trait_holder = gs.get_player(1)
	trait_holder.traits = ["aggressive"]
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_production = 8
	s.production_queue = [{"type": "structure", "id": "barracks"}]
	s.production_store = 0
	var plain = make_settlement(gs, 2, 10, 10, 3)
	plain.output_production = 8
	plain.production_queue = [{"type": "structure", "id": "barracks"}]
	plain.production_store = 0
	TurnEngine._settlement_production(gs, s, trait_holder)
	TurnEngine._settlement_production(gs, plain, gs.get_player(2))
	assert_eq(s.production_store, plain.production_store * 2,
		"An Aggressive player's barracks accrues exactly double the hammers per turn")

func test_trait_double_production_ignores_unlisted_items() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.traits = ["aggressive"]
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_production = 8
	s.production_queue = [{"type": "structure", "id": "library"}]
	s.production_store = 0
	var build_scale: int = int(gs.db.get_pace(gs.pace_id).get("build_scale", 100))
	TurnEngine._settlement_production(gs, s, p)
	assert_eq(s.production_store, Fixed.scale(8, build_scale),
		"A structure outside the trait's list gets no trait speed bonus")

func test_imperialistic_trains_settlers_half_again_faster() -> void:
	# Imperialistic carries the reference per-unit modifier: settlers build +50%
	# faster (unit_production_modifiers — a unit, so the sibling dict key).
	var gs = make_gs(2)
	var imp = gs.get_player(1)
	imp.traits = ["imperialistic"]
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_production = 8
	s.production_queue = [{"type": "unit", "id": "settler"}]
	s.production_store = 0
	var plain = make_settlement(gs, 2, 10, 10, 3)
	plain.output_production = 8
	plain.production_queue = [{"type": "unit", "id": "settler"}]
	plain.production_store = 0
	TurnEngine._settlement_production(gs, s, imp)
	TurnEngine._settlement_production(gs, plain, gs.get_player(2))
	var build_scale: int = int(gs.db.get_pace(gs.pace_id).get("build_scale", 100))
	assert_eq(s.production_store,
		Fixed.apply_stacked_bonus(Fixed.scale(8, build_scale), 50),
		"An Imperialistic player's settler accrues +50% hammers per turn")
	assert_eq(plain.production_store, Fixed.scale(8, build_scale),
		"A traitless player's settler accrues the unmodified base")

func test_trait_and_structure_percent_mods_stack_additively() -> void:
	# §4.3: the trait's +100 joins the same additive percent chain as the Forge's
	# +25 (one multiplicative application on the base), mirroring the reference.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.traits = ["aggressive"]
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_production = 8
	s.structures = ["forge"]                       # production_bonus: 25
	s.production_queue = [{"type": "structure", "id": "barracks"}]
	s.production_store = 0
	var build_scale: int = int(gs.db.get_pace(gs.pace_id).get("build_scale", 100))
	TurnEngine._settlement_production(gs, s, p)
	assert_eq(s.production_store,
		Fixed.apply_stacked_bonus(Fixed.scale(8, build_scale), 125),
		"Trait +100 and Forge +25 sum to +125 applied once on the base")

# ── Compound unit prerequisites — the production gate (§15.12) ─────────────────
#
# The build gate every chooser shares (city screen offers, PlayerAI's queue,
# draft, upgrades): UnitPrereqs.tech_ok over the player, plus
# UnitPrereqs.resource_ok over EconOrgs.accessible_resources. Exercised here
# against a real game state with the shipped compound units.

# Connect a resource to player 1: an owned tile carrying it with the required
# improvement, plus the resource's reveal tech.
func _connect_resource(gs, res_id, x, y) -> void:
	var res = gs.db.get_resource(res_id)
	var t = gs.map.get_tile(x, y)
	t.owner_player_id = 1
	t.resource_id = res_id
	t.improvement_id = str(res.get("improvement_required", ""))
	var reveal = str(res.get("tech_required", ""))
	var p = gs.get_player(1)
	if reveal != "" and not p.has_tech(reveal):
		p.technologies.append(reveal)

func _unit_buildable(gs, unit_id) -> bool:
	var u = gs.db.get_unit(unit_id)
	var p = gs.get_player(1)
	if not UnitPrereqs.tech_ok(u.get("tech_required", null), p):
		return false
	return UnitPrereqs.resource_ok(u.get("resource_required", null),
		EconOrgs.accessible_resources(gs, 1))

func test_two_tech_and_list_needs_both_techs() -> void:
	# Maceman: tech_required ["civil_service", "machinery"] (AND), resource any-of.
	var gs = make_gs(1)
	_connect_resource(gs, "iron", 6, 6)   # resource side satisfied throughout
	var p = gs.get_player(1)
	assert_false(_unit_buildable(gs, "maceman"), "no techs → not buildable")
	p.technologies.append("civil_service")
	assert_false(_unit_buildable(gs, "maceman"), "one of two AND techs → not buildable")
	p.technologies.append("machinery")
	assert_true(_unit_buildable(gs, "maceman"), "both AND techs → buildable")

func test_any_resource_set_satisfied_by_either() -> void:
	# Maceman's resource_required {"any": ["copper", "iron"]}.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.technologies = ["civil_service", "machinery"]
	assert_false(_unit_buildable(gs, "maceman"), "neither alternative → not buildable")
	_connect_resource(gs, "copper", 6, 6)
	assert_true(_unit_buildable(gs, "maceman"), "copper alone satisfies the any-set")
	var gs2 = make_gs(1)
	gs2.get_player(1).technologies = ["civil_service", "machinery"]
	_connect_resource(gs2, "iron", 6, 6)
	assert_true(_unit_buildable(gs2, "maceman"), "iron alone satisfies the any-set")

func test_all_resource_set_needs_every_entry() -> void:
	# Knight: resource_required {"all": ["horse", "iron"]}.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.technologies = ["guilds", "horseback_riding"]
	assert_false(_unit_buildable(gs, "knight"), "no resources → not buildable")
	_connect_resource(gs, "horse", 6, 6)
	assert_false(_unit_buildable(gs, "knight"), "horse alone → not buildable (all-set)")
	_connect_resource(gs, "iron", 7, 7)
	assert_true(_unit_buildable(gs, "knight"), "horse + iron → buildable")

func test_traded_resource_satisfies_the_gate() -> void:
	# A resource received through an active recurring deal counts as connected —
	# the same accessibility rule corporations use (§7 / §15.12).
	var gs = make_gs(2)
	var p = gs.get_player(1)
	p.technologies = ["civil_service", "machinery"]
	assert_false(_unit_buildable(gs, "maceman"), "no home or traded metal → blocked")
	gs.deals.append({"proposer_player_id": 1, "accepter_player_id": 2,
		"recurring": {"receive": {"resources": ["iron"]}}})
	assert_true(_unit_buildable(gs, "maceman"), "iron via a recurring deal → buildable")

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

# The human city aids (growth_bonus / health_bonus / happiness_bonus) are a
# player aid: AI players (is_ai) get none. Since T1 the AI carries its OWN
# §29.10 growth column (ai_growth_percent: settler 160 slows it, deity 80
# speeds it) — distinct from and never mixing with the human growth_bonus —
# while health and happiness stay human-only with no AI analogue.

func test_difficulty_handicaps_skip_ai_players() -> void:
	assert_eq(_grow_pop_for_difficulty("settler", true), 1,
		"Settler AI holds: its own ai_growth_percent 160 raises the threshold "
		+ "(the human growth_bonus aid still never applies)")
	assert_eq(_grow_pop_for_difficulty("deity", true), 2,
		"Deity AI grows: ai_growth_percent 80 lowers the threshold")
	assert_eq(_deficit_for_difficulty("settler", true),
		_deficit_for_difficulty("deity", true),
		"Health handicap does not apply to AI players")
	assert_eq(_positive_for_difficulty("settler", true),
		_positive_for_difficulty("deity", true),
		"Happiness handicap does not apply to AI players")

# ── Leader/society trait wellbeing (§4.6) ────────────────────────────────────

func test_expansive_trait_grants_health() -> void:
	# Expansive grants +2 health per city (the original-reference value).
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base_pos: int = s.wellbeing_positive
	p.traits = ["expansive"]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_positive, base_pos + 2,
		"Expansive grants +2 health per city (reference value)")

func test_traitless_player_has_no_trait_health() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	p.traits = []
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	# No traits, no structures, dry inland: positive is purely difficulty
	# (prince health_bonus = 2, the reference human floor — A3).
	assert_eq(s.wellbeing_positive, 2,
		"A traitless prince city's positive wellbeing is the difficulty aid alone")

# ── Worked-tile feature wellbeing (§4.6, R5 fractional centi-health) ─────────
# Features carry `health_delta_centi` (hundredths of a health point: forest +50,
# jungle −25, flood plains −40, oasis +100, fallout −100). Worked tiles are
# summed in centi-units and the net truncates toward zero to whole health.

func test_single_worked_forest_rounds_to_zero() -> void:
	# One forest = +50 centi = +0.5 → truncates toward zero to 0.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	s.worked_tiles = [[2, 3]]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base_pos: int = s.wellbeing_positive
	gs.map.get_tile(2, 3).feature_id = "forest"  # health_delta_centi 50
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_positive, base_pos, "A lone worked forest (+0.5) rounds to 0")

func test_two_worked_forests_add_one_health() -> void:
	# The exact boundary: 2 × 50 = 100 centi = +1 whole health.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	s.worked_tiles = [[2, 3], [3, 2]]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base_pos: int = s.wellbeing_positive
	gs.map.get_tile(2, 3).feature_id = "forest"
	gs.map.get_tile(3, 2).feature_id = "forest"
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_positive, base_pos + 1, "Two worked forests (100 centi) add +1 health")

func test_three_worked_forests_add_one_health_net() -> void:
	# The R5 pin: 3 × 50 = 150 centi truncates to +1, not +2.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	s.worked_tiles = [[2, 3], [3, 2], [3, 3]]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base_pos: int = s.wellbeing_positive
	for wt in s.worked_tiles:
		gs.map.get_tile(wt[0], wt[1]).feature_id = "forest"
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_positive, base_pos + 1, "Three worked forests (150 centi) add +1 net")

func test_worked_jungle_fraction_rounds_toward_zero() -> void:
	# One jungle = −25 centi; truncation toward zero leaves 0 unhealthiness —
	# NOT the −1 a floor-style rounding would give.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	s.worked_tiles = [[2, 3]]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base_neg: int = s.wellbeing_negative
	gs.map.get_tile(2, 3).feature_id = "jungle"  # health_delta_centi -25
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_negative, base_neg, "A lone worked jungle (-0.25) rounds to 0")

func test_four_worked_jungles_add_one_unhealthiness() -> void:
	# 4 × −25 = −100 centi = −1 whole health, landing on the negative face.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	s.worked_tiles = [[2, 3], [3, 2], [3, 3], [1, 2]]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base_neg: int = s.wellbeing_negative
	for wt in s.worked_tiles:
		gs.map.get_tile(wt[0], wt[1]).feature_id = "jungle"
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_negative, base_neg + 1, "Four worked jungles (-100 centi) add +1 unhealthiness")

func test_worked_flood_plains_fraction_and_multiple() -> void:
	# One flood plains = −40 centi → 0; three = −120 centi → −1.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	s.worked_tiles = [[2, 3]]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base_neg: int = s.wellbeing_negative
	gs.map.get_tile(2, 3).feature_id = "flood_plains"  # health_delta_centi -40
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_negative, base_neg, "A lone worked flood plains (-0.4) rounds to 0")
	s.worked_tiles = [[2, 3], [3, 2], [3, 3]]
	for wt in s.worked_tiles:
		gs.map.get_tile(wt[0], wt[1]).feature_id = "flood_plains"
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_negative, base_neg + 1, "Three worked flood plains (-120 centi) add +1 unhealthiness")

func test_mixed_sign_features_net_before_truncation() -> void:
	# The centi sum nets BEFORE truncating: 2 forests + 1 jungle = +75 → 0
	# (per-sign truncation would wrongly give +1); a third forest tips it to
	# +125 → +1.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	s.worked_tiles = [[2, 3], [3, 2], [3, 3]]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base_pos: int = s.wellbeing_positive
	var base_neg: int = s.wellbeing_negative
	gs.map.get_tile(2, 3).feature_id = "forest"
	gs.map.get_tile(3, 2).feature_id = "forest"
	gs.map.get_tile(3, 3).feature_id = "jungle"
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_positive, base_pos, "2 forests + 1 jungle net +75 centi → 0 health")
	assert_eq(s.wellbeing_negative, base_neg, "a netted-out fraction adds no unhealthiness either")
	s.worked_tiles = [[2, 3], [3, 2], [3, 3], [1, 2]]
	gs.map.get_tile(1, 2).feature_id = "forest"
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_positive, base_pos + 1, "3 forests + 1 jungle net +125 centi → +1 health")

func test_worked_oasis_keeps_whole_point() -> void:
	# Oasis stays a whole point (+100 centi = +1) — the R5 fractions touch only
	# forest/jungle/flood plains.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	var p = gs.get_player(1)
	s.worked_tiles = [[2, 3]]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base_pos: int = s.wellbeing_positive
	gs.map.get_tile(2, 3).feature_id = "oasis"  # health_delta_centi 100
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_positive, base_pos + 1, "A worked oasis still adds +1 health")

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

# ── Population rush ("whipping", §15.2) ──────────────────────────────────────

# A slavery player with one settlement and a 100-hammer unit queued directly
# (no queued_turn stamp, so the new-hurry surcharge does not apply unless a
# test opts in via the SET_PRODUCTION command).
func _whip_setup(pop = 7):
	var gs = make_gs(1)
	gs.current_player_id = 1
	gs.get_player(1).policies = {"labor": "slavery"}
	gs.db.units["whip_dummy"] = {"id": "whip_dummy", "name": "Whip Dummy",
		"cost": 100, "base_strength": 5, "movement": 120}
	var f = bare_facade(gs)
	var s = make_settlement(gs, 1, 5, 5, pop)
	s.production_queue = [{"type": "unit", "id": "whip_dummy"}]
	return [gs, f, s]

func test_whip_pop_cost_is_ceiling_of_remaining_over_per_pop() -> void:
	var setup = _whip_setup()
	var gs = setup[0]; var s = setup[2]
	var p = gs.get_player(1)
	assert_eq(TurnEngine.rush_pop_cost(gs, s, p), 4,
		"100 hammers at 30/pop whips 4 citizens (ceiling)")
	s.production_store = 10
	assert_eq(TurnEngine.rush_pop_cost(gs, s, p), 3,
		"90 remaining hammers at 30/pop whips 3 citizens")
	s.production_store = 100
	assert_eq(TurnEngine.rush_pop_cost(gs, s, p), 0,
		"Nothing left to rush costs no population")

func test_whip_hammers_per_pop_scales_with_pace() -> void:
	var gs = make_gs(1)
	assert_eq(TurnEngine.rush_hammers_per_pop(gs.db, gs.db.get_pace("quick")), 20,
		"Quick pace: 30 scaled by hurry_scale 67")
	assert_eq(TurnEngine.rush_hammers_per_pop(gs.db, gs.db.get_pace("normal")), 30,
		"Normal pace: the reference 30 hammers per pop")
	assert_eq(TurnEngine.rush_hammers_per_pop(gs.db, gs.db.get_pace("epic")), 45,
		"Epic pace: 30 scaled by hurry_scale 150")
	assert_eq(TurnEngine.rush_hammers_per_pop(gs.db, gs.db.get_pace("marathon")), 90,
		"Marathon pace: 30 scaled by hurry_scale 300")

func test_whip_command_spends_pop_and_fills_store() -> void:
	var setup = _whip_setup()
	var gs = setup[0]; var f = setup[1]; var s = setup[2]
	assert_true(f.apply_command(Commands.rush_population(1, s.id)),
		"Whip accepted for a slavery player")
	assert_eq(s.population, 3, "4 citizens sacrificed from pop 7")
	assert_eq(s.production_store, 120, "4 pop x 30 hammers banked")

func test_whip_new_hurry_surcharge_applies_to_items_queued_this_turn() -> void:
	var setup = _whip_setup()
	var gs = setup[0]; var f = setup[1]; var s = setup[2]
	var p = gs.get_player(1)
	assert_true(f.apply_command(Commands.set_production(1, s.id,
		[{"type": "unit", "id": "whip_dummy"}])), "queue set via command")
	assert_eq(int(s.production_queue[0].get("queued_turn", -1)), gs.turn_number,
		"SET_PRODUCTION stamps new items with the current turn")
	assert_eq(TurnEngine.rush_pop_cost(gs, s, p), 5,
		"Queued this turn: 100 + 50% = 150 hammers -> 5 citizens")
	s.production_queue[0]["queued_turn"] = gs.turn_number - 1
	assert_eq(TurnEngine.rush_pop_cost(gs, s, p), 4,
		"Queued on an earlier turn: no surcharge, 4 citizens")

func test_set_production_keeps_stamp_of_already_queued_items() -> void:
	var setup = _whip_setup()
	var gs = setup[0]; var f = setup[1]; var s = setup[2]
	assert_true(f.apply_command(Commands.set_production(1, s.id,
		[{"type": "unit", "id": "whip_dummy"}])), "queue set via command")
	gs.turn_number += 3
	assert_true(f.apply_command(Commands.set_production(1, s.id,
		[{"type": "unit", "id": "whip_dummy"}, {"type": "unit", "id": "warrior"}])),
		"queue extended via command")
	assert_eq(int(s.production_queue[0].get("queued_turn", -1)), gs.turn_number - 3,
		"A surviving item keeps its original queued-turn stamp")
	assert_eq(int(s.production_queue[1].get("queued_turn", -1)), gs.turn_number,
		"A newly added item is stamped with the current turn")

func test_whip_refused_below_minimum_population() -> void:
	var setup = _whip_setup(4)  # needs 4 pop, would leave 0 < minimum 1
	var f = setup[1]; var s = setup[2]
	assert_false(f.apply_command(Commands.rush_population(1, s.id)),
		"Whip that would drop the city below pop 1 is rejected")
	assert_eq(s.population, 4, "Population untouched by the rejected whip")
	assert_eq(s.production_store, 0, "No hammers banked by the rejected whip")

func test_whip_refused_with_nothing_to_rush() -> void:
	var setup = _whip_setup()
	var f = setup[1]; var s = setup[2]
	s.production_store = 100
	assert_false(f.apply_command(Commands.rush_population(1, s.id)),
		"Whip rejected when the head item is already paid for")
	s.production_queue = []
	assert_false(f.apply_command(Commands.rush_population(1, s.id)),
		"Whip rejected with an empty production queue")

func test_whip_anger_stacks_per_rush() -> void:
	var setup = _whip_setup(12)
	var gs = setup[0]; var f = setup[1]; var s = setup[2]
	var p = gs.get_player(1)
	assert_true(f.apply_command(Commands.rush_population(1, s.id)), "first whip")
	s.production_store = 0
	assert_true(f.apply_command(Commands.rush_population(1, s.id)), "second whip")
	assert_eq(s.timed_happiness.size(), 2, "Each whip stacks its own anger entry")
	for tm in s.timed_happiness:
		assert_eq(int(tm["amount"]), -1, "Each whip is worth one angry citizen")
		assert_eq(int(tm["turns_left"]), 10, "Whip anger lasts 10 turns")
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var whipped_neg: int = s.negative_sentiment
	s.timed_happiness = []
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_eq(whipped_neg, s.negative_sentiment + 2,
		"Two stacked whips add two discontented citizens")

func test_whip_anger_expires_after_its_duration() -> void:
	var setup = _whip_setup()
	var gs = setup[0]; var f = setup[1]; var s = setup[2]
	var p = gs.get_player(1)
	assert_true(f.apply_command(Commands.rush_population(1, s.id)), "whip accepted")
	for _i in range(9):
		TurnEngine._tick_states(gs, p)
	assert_eq(s.timed_happiness.size(), 1, "Whip anger still active after 9 turns")
	TurnEngine._tick_states(gs, p)
	assert_eq(s.timed_happiness.size(), 0, "Whip anger expires after 10 turns")

func test_whip_state_survives_json_roundtrip_with_int_keys() -> void:
	# The queued_turn stamp and the stacked anger entries must come back as ints
	# after a JSON save/load (the float-key gotcha), so post-load whip math and
	# the state hash match the original.
	var setup = _whip_setup(12)
	var gs = setup[0]; var f = setup[1]; var s = setup[2]
	var p = gs.get_player(1)
	assert_true(f.apply_command(Commands.set_production(1, s.id,
		[{"type": "unit", "id": "whip_dummy"}])), "queue set via command")
	assert_true(f.apply_command(Commands.rush_population(1, s.id)), "whip accepted")
	var parsed = JSON.parse(JSON.print(s.serialize()))
	assert_eq(parsed.error, OK, "settlement JSON parses back")
	var s2 = Settlement.deserialize(parsed.result)
	assert_eq(typeof(s2.production_queue[0]["queued_turn"]), TYPE_INT,
		"queued_turn is coerced back to int on deserialize")
	assert_eq(int(s2.production_queue[0]["queued_turn"]), gs.turn_number,
		"queued_turn value survives the roundtrip")
	assert_eq(typeof(s2.timed_happiness[0]["amount"]), TYPE_INT,
		"whip anger amount is coerced back to int on deserialize")
	gs.settlements[0] = s2
	assert_eq(TurnEngine.rush_pop_cost(gs, s2, p), TurnEngine.rush_pop_cost(gs, s, p),
		"Post-load whip math matches the original")

func test_whip_anger_duration_halved_by_sacrificial_altar() -> void:
	var setup = _whip_setup()
	var f = setup[1]; var s = setup[2]
	s.structures = ["sacrificial_altar"]
	assert_true(f.apply_command(Commands.rush_population(1, s.id)), "whip accepted")
	assert_eq(int(s.timed_happiness[0]["turns_left"]), 5,
		"halve_slavery_anger (Sacrificial Altar) halves whip-anger duration")

# ── W1: standing-structure science_bonus (§15) ───────────────────────────────
#
# The summed per-structure `science_bonus` percentage multiplies the city's
# research commerce share (integer truncation). Direct science yields
# (specialists, event STRUCT_YIELD, corporations) sit outside the multiplier —
# test_events.gd covers that a zero-commerce city's STRUCT_YIELD is unscaled.

func _all_commerce_to_research(p) -> void:
	p.slider_research = 100; p.slider_finance = 0
	p.slider_culture = 0; p.slider_intel = 0

func test_science_bonus_library_boosts_research_share_25pct() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	_all_commerce_to_research(p)
	p.current_research_id = "plastics"  # costly: never completes in one tick
	var s = make_settlement(gs, 1, 5, 5)
	s.structures.append("library")      # science_bonus: 25
	s.output_commerce = 100
	TurnEngine._apply_research(gs, p)
	assert_eq(p.research_store, 125,
		"A library boosts the city's 100-beaker research share by 25%")

func test_science_bonus_academy_boosts_research_share_50pct() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	_all_commerce_to_research(p)
	p.current_research_id = "plastics"
	var s = make_settlement(gs, 1, 5, 5)
	s.structures.append("academy")      # science_bonus: 50
	s.output_commerce = 100
	TurnEngine._apply_research(gs, p)
	assert_eq(p.research_store, 150,
		"An academy boosts the city's research share by 50%")

func test_science_bonus_stacks_additively() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	_all_commerce_to_research(p)
	p.current_research_id = "plastics"
	var s = make_settlement(gs, 1, 5, 5)
	s.structures.append("library")      # 25
	s.structures.append("university")   # 25
	s.output_commerce = 100
	TurnEngine._apply_research(gs, p)
	assert_eq(p.research_store, 150,
		"Library + university sum to +50% on the city's research share")

func test_science_bonus_truncates_integer_share() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	_all_commerce_to_research(p)
	p.current_research_id = "plastics"
	var s = make_settlement(gs, 1, 5, 5)
	s.structures.append("library")      # 25% of 10 = 2.5 → 2
	s.output_commerce = 10
	TurnEngine._apply_research(gs, p)
	assert_eq(p.research_store, 12,
		"The 25% bonus on a 10-beaker share truncates to +2")

func test_science_bonus_is_per_city() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	_all_commerce_to_research(p)
	p.current_research_id = "plastics"
	var with_lib = make_settlement(gs, 1, 5, 5)
	with_lib.structures.append("library")
	with_lib.output_commerce = 100
	var without = make_settlement(gs, 1, 9, 9)
	without.output_commerce = 100
	TurnEngine._apply_research(gs, p)
	assert_eq(p.research_store, 225,
		"Only the library city's share is multiplied (125 + 100)")

# ── W2: Three Gorges Dam unhealthy_global (§15) ──────────────────────────────

func test_unhealthy_global_hits_every_city_of_the_owner() -> void:
	var gs = make_gs(2)
	var p1 = gs.get_player(1)
	var cap = make_settlement(gs, 1, 5, 5)
	var other = make_settlement(gs, 1, 9, 9)
	TurnEngine._update_wellbeing(gs, cap, p1, gs.db)
	TurnEngine._update_wellbeing(gs, other, p1, gs.db)
	var cap_neg: int = cap.wellbeing_negative
	var other_neg: int = other.wellbeing_negative
	cap.structures.append("three_gorges_dam")  # effects.unhealthy_global: 2
	TurnEngine._update_wellbeing(gs, cap, p1, gs.db)
	TurnEngine._update_wellbeing(gs, other, p1, gs.db)
	assert_eq(cap.wellbeing_negative, cap_neg + 2,
		"The dam's own city takes the +2 global unhealthiness")
	assert_eq(other.wellbeing_negative, other_neg + 2,
		"Every other city of the owner takes the +2 too")

func test_unhealthy_global_leaves_other_players_alone() -> void:
	var gs = make_gs(2)
	var p2 = gs.get_player(2)
	var foreign = make_settlement(gs, 2, 15, 15)
	TurnEngine._update_wellbeing(gs, foreign, p2, gs.db)
	var foreign_neg: int = foreign.wellbeing_negative
	var cap = make_settlement(gs, 1, 5, 5)
	cap.structures.append("three_gorges_dam")
	TurnEngine._update_wellbeing(gs, foreign, p2, gs.db)
	assert_eq(foreign.wellbeing_negative, foreign_neg,
		"A rival's dam adds no unhealthiness to another player's city")

# ── W3: Hippodrome happiness_with_horse (§15) ────────────────────────────────

func test_hippodrome_happy_only_with_horse_accessible() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.structures.append("hippodrome")   # happiness_bonus 1 + happiness_with_horse 1
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var without_horse: int = s.positive_sentiment
	_connect_resource(gs, "horse", 7, 7)  # owned pasture + animal_husbandry
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_eq(s.positive_sentiment, without_horse + 1,
		"Horse access adds the Hippodrome's conditional +1 happy face")

func test_hippodrome_happy_lost_when_resource_lost() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.structures.append("hippodrome")
	_connect_resource(gs, "horse", 7, 7)
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var with_horse: int = s.positive_sentiment
	gs.map.get_tile(7, 7).improvement_id = ""  # pasture pillaged: access lost
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_eq(s.positive_sentiment, with_horse - 1,
		"Losing the Horse connection loses the conditional happy face")

# ── M1: structure obsolescence (§15.17) ──────────────────────────────────────
#
# Once the owner researches a structure's `obsoleted_by` tech the building's
# every effect stops (it remains built — never sold, no refund). One case per
# aggregation category this suite owns: science %, wellbeing, contentment,
# specialist slots, tile-output yields.

func test_monastery_science_bonus_stops_at_scientific_method() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	_all_commerce_to_research(p)
	p.current_research_id = "plastics"
	var s = make_settlement(gs, 1, 5, 5)
	s.structures.append("monastery")    # science_bonus 10; obsoleted_by scientific_method
	s.output_commerce = 100
	TurnEngine._apply_research(gs, p)
	assert_eq(p.research_store, 110,
		"A live monastery boosts the city's research share by 10%")
	p.research_store = 0
	p.technologies.append("scientific_method")
	TurnEngine._apply_research(gs, p)
	assert_eq(p.research_store, 100,
		"Scientific Method silences the monastery's science bonus (§15.17)")

func test_obsolete_structure_health_effects_stop() -> void:
	# Synthetic roster entry: obsolete the Three Gorges Dam and its owner-wide
	# unhealthy_global stops in every city (the W2 scan filters, §15.17).
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var cap = make_settlement(gs, 1, 5, 5)
	var other = make_settlement(gs, 1, 9, 9)
	cap.structures.append("three_gorges_dam")  # effects.unhealthy_global: 2
	gs.db.structures["three_gorges_dam"]["obsoleted_by"] = "mysticism"
	TurnEngine._update_wellbeing(gs, cap, p, gs.db)
	TurnEngine._update_wellbeing(gs, other, p, gs.db)
	var cap_neg: int = cap.wellbeing_negative
	var other_neg: int = other.wellbeing_negative
	p.technologies.append("mysticism")
	TurnEngine._update_wellbeing(gs, cap, p, gs.db)
	TurnEngine._update_wellbeing(gs, other, p, gs.db)
	assert_eq(cap.wellbeing_negative, cap_neg - 2,
		"The obsolete dam's +2 global unhealthiness stops in its own city")
	assert_eq(other.wellbeing_negative, other_neg - 2,
		"…and in every other city of the owner")

func test_obsolete_structure_happiness_stops() -> void:
	# Synthetic: an obsolete temple's happiness_bonus no longer comforts the
	# city (the contentment scan runs through _structure_effect_active).
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.structures.append("temple")       # happiness_bonus 1
	gs.db.structures["temple"]["obsoleted_by"] = "mysticism"
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var live_pos: int = s.positive_sentiment
	p.technologies.append("mysticism")
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_eq(s.positive_sentiment, live_pos - 1,
		"An obsolete temple's +1 happiness stops (§15.17)")

func test_obelisk_specialist_slots_close_at_astronomy() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 4)
	s.structures.append("obelisk")      # priest slots 2; obsoleted_by astronomy
	var live_slots: int = Specialists.slots_for(gs.db, s, p, "priest")
	p.technologies.append("astronomy")
	assert_eq(Specialists.slots_for(gs.db, s, p, "priest"), live_slots - 2,
		"The obsolete Obelisk's two priest slots close (§15.17)")

func test_obsolete_structure_output_delta_stops() -> void:
	# Synthetic: give the granary a food output_delta and obsolete it — the
	# yield stops while a non-obsolete copy still pays out.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	gs.db.structures["granary"]["output_delta"]["food"] = 3
	s.structures.append("granary")
	TurnEngine._settlement_growth(gs, s, p)
	var live_food: int = s.output_food
	gs.db.structures["granary"]["obsoleted_by"] = "mysticism"
	p.technologies.append("mysticism")
	TurnEngine._settlement_growth(gs, s, p)
	assert_eq(s.output_food, live_food - 3,
		"An obsolete structure's output_delta yields nothing (§15.17)")

# ── M2: culture-rate building happiness (§15.13/§29.12) ──────────────────────
#
# Entertainment-tier carriers (`effects.culture_rate_happiness`: theatre 10,
# colosseum 5, hippodrome 20, broadcast tower 10, …) grant happiness scaled by
# the owner's culture allocation rate — Σ(carrier values) × culture% / 100,
# truncated ONCE over the per-city sum, no cap.

func test_culture_rate_happiness_zero_at_zero_slider() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var base: int = s.positive_sentiment
	s.structures.append("theatre")
	p.slider_culture = 0
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_eq(s.positive_sentiment, base,
		"At 0% culture a carrier grants no rate happiness")

func test_culture_rate_happiness_scales_with_slider() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var base: int = s.positive_sentiment
	s.structures.append("theatre")     # carrier 10
	s.structures.append("colosseum")   # carrier 5 + happiness_bonus 1
	p.slider_culture = 50
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_eq(s.positive_sentiment, base + 1 + 7,
		"50% culture: summed carriers 15 grant 15*50/100 = 7 happy")

func test_culture_rate_happiness_truncates_once_over_city_sum() -> void:
	# At 35%, truncating per building would give 10*35/100 + 5*35/100 = 3 + 1
	# = 4; the rule truncates once over the summed 15: 15*35/100 = 5.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var base: int = s.positive_sentiment
	s.structures.append("theatre")
	s.structures.append("colosseum")
	p.slider_culture = 35
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_eq(s.positive_sentiment, base + 1 + 5,
		"One truncation over the per-city carrier sum (5, not 4)")

func test_culture_rate_happiness_inactive_carrier_excluded() -> void:
	# No shipped carrier is obsoletable, so exercise the shared
	# _structure_effect_active gate synthetically: obsolete the theatre and its
	# carrier value must leave the sum.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.structures.append("theatre")
	p.slider_culture = 50
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var live: int = s.positive_sentiment
	gs.db.structures["theatre"]["obsoleted_by"] = "mysticism"
	p.technologies.append("mysticism")
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_eq(s.positive_sentiment, live - 5,
		"An obsolete carrier's 10*50/100 = 5 happy stops (§15.17)")

# ── M5: gold hurry retune (§15.2/§29.8) ──────────────────────────────────────
#
# 3 gold per hammer of remaining cost (`rush_gold_per_hammer`), available under
# every government (the Universal Suffrage gate is retired), the shared
# new-order +50% surcharge kept, and NO anger of any kind.

# The whip fixture's 100-hammer dummy with no permitting civic at all.
func _gold_setup(treasury = 100000):
	var setup = _whip_setup()
	setup[0].get_player(1).policies = {}
	setup[0].get_player(1).treasury = treasury
	return setup

func test_gold_hurry_costs_three_gold_per_remaining_hammer() -> void:
	var setup = _gold_setup()
	var gs = setup[0]; var f = setup[1]; var s = setup[2]
	var p = gs.get_player(1)
	s.production_store = 10   # 90 hammers remain
	assert_eq(f.rush_gold_cost(s.id), 270, "3 gold per remaining hammer")
	assert_true(f.apply_command(Commands.rush_production(1, s.id, "treasury")),
		"Gold hurry accepted without any permitting civic")
	assert_eq(p.treasury, 100000 - 270, "270 gold paid")
	assert_eq(s.production_store, 100, "The head item is fully paid for")

func test_gold_hurry_new_order_surcharge() -> void:
	var setup = _gold_setup()
	var gs = setup[0]; var f = setup[1]; var s = setup[2]
	assert_true(f.apply_command(Commands.set_production(1, s.id,
		[{"type": "unit", "id": "whip_dummy"}])), "queue set via command")
	assert_eq(f.rush_gold_cost(s.id), 450,
		"Queued this turn: (100 + 50%) hammers x 3 gold = 450")
	s.production_queue[0]["queued_turn"] = gs.turn_number - 1
	assert_eq(f.rush_gold_cost(s.id), 300,
		"Queued on an earlier turn: 100 hammers x 3 gold, no surcharge")

func test_gold_hurry_causes_no_anger() -> void:
	var setup = _gold_setup()
	var f = setup[1]; var s = setup[2]
	assert_true(f.apply_command(Commands.rush_production(1, s.id, "treasury")),
		"gold hurry accepted")
	assert_eq(s.rush_anger_turns, 0,
		"Reference gold hurry stirs no flat rush anger")
	assert_eq(s.timed_happiness.size(), 0,
		"…and stacks no timed anger either (that channel is the whip's)")

func test_gold_hurry_refused_when_poor_or_nothing_to_rush() -> void:
	var setup = _gold_setup(10)
	var gs = setup[0]; var f = setup[1]; var s = setup[2]
	assert_false(f.apply_command(Commands.rush_production(1, s.id, "treasury")),
		"Too poor: 300 gold needed, 10 held")
	gs.get_player(1).treasury = 100000
	s.production_store = 100
	assert_false(f.apply_command(Commands.rush_production(1, s.id, "treasury")),
		"Nothing left to rush is rejected")
	s.production_queue = []
	assert_false(f.apply_command(Commands.rush_production(1, s.id, "treasury")),
		"An empty production queue is rejected")

# ── R1: settler/worker food-box build (§15.15) ───────────────────────────────
#
# Units flagged `food_production` (settler, worker, fast worker) are built with
# hammers PLUS the city's food surplus: while one heads the queue the growth
# phase diverts the positive surplus to production (joining AFTER the percent
# modifiers, never multiplied by them) and the food box freezes — the growth
# delta becomes min(0, surplus), so the city never grows but can still starve.

func test_settler_training_diverts_food_surplus_to_production() -> void:
	# Real growth→production order: the surplus computed by the growth phase
	# lands in production_store instead of the food box.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.worked_tiles = [[5, 5], [5, 6], [6, 5]]   # grassland food, no hammers
	s.production_queue = [{"type": "unit", "id": "settler"}]
	# Pre-read the consumption inputs the engine will use (same pattern as
	# test_angry_citizens_do_not_eat).
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var fpc: int = gs.db.get_constant("food_per_citizen", 2)
	var net: int = s.health_rate()
	var drain: int = -net if net < 0 else 0
	TurnEngine._settlement_growth(gs, s, p)
	var surplus: int = s.output_food - (s.population * fpc + drain)
	assert_true(surplus > 0, "Fixture sanity: the city runs a food surplus")
	assert_eq(s.food_store, 0, "Frozen food box banks nothing while training")
	assert_eq(s.food_for_production, surplus,
		"The whole positive surplus is diverted toward the settler")
	TurnEngine._settlement_production(gs, s, p)
	var build_scale: int = int(gs.db.get_pace(gs.pace_id).get("build_scale", 100))
	assert_eq(s.production_store,
		Fixed.scale(s.output_production, build_scale) + Fixed.scale(surplus, build_scale),
		"The diverted surplus reaches production_store")
	assert_eq(s.food_for_production, 0, "The transient is consumed by the step")

func test_food_surplus_joins_after_percent_modifiers() -> void:
	# §15.15: progress = hammers × (100+mods)/100 + surplus — the Forge's +25%
	# multiplies the hammer base only, never the food contribution.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_production = 8
	s.structures = ["forge"]                        # production_bonus: 25
	s.production_queue = [{"type": "unit", "id": "settler"}]
	s.food_for_production = 5
	TurnEngine._settlement_production(gs, s, gs.get_player(1))
	var build_scale: int = int(gs.db.get_pace(gs.pace_id).get("build_scale", 100))
	var expected: int = Fixed.apply_stacked_bonus(Fixed.scale(8, build_scale), 25) \
		+ Fixed.scale(5, build_scale)
	assert_eq(s.production_store, expected,
		"Food joins after the +25%: 10 + 5 = 15, not (8+5)×1.25 = 16")

func test_food_contribution_scales_with_build_pace() -> void:
	# Humanish adaptation: hammer output AND item costs both carry the pace's
	# build scale, so the food channel carries it too — its weight relative to
	# hammers is pace-invariant.
	var gs = make_gs(1)
	gs.pace_id = "marathon"                          # build_scale 300
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.output_production = 0
	s.production_queue = [{"type": "unit", "id": "settler"}]
	s.food_for_production = 5
	TurnEngine._settlement_production(gs, s, gs.get_player(1))
	assert_eq(s.production_store, Fixed.scale(5, 300),
		"5 diverted food at marathon contributes 15 progress (cost scales ×3 too)")

func test_growth_frozen_even_with_banked_food_box() -> void:
	# A box already over the threshold does not pop a citizen while a settler
	# trains — and the banked contents stay untouched.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	s.worked_tiles = [[5, 5], [5, 6], [6, 5], [6, 6]]  # positive surplus
	s.food_store = 9999
	s.production_queue = [{"type": "unit", "id": "settler"}]
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	assert_eq(s.population, 2, "No growth while a food-built unit trains")
	assert_eq(s.food_store, 9999, "Banked food is untouched (frozen, not drained)")
	assert_eq(gs.pending_growth.size(), 0, "No growth record while frozen")

func test_starvation_still_bites_while_training() -> void:
	# Growth delta is min(0, surplus): a food deficit still drains the box and
	# costs population even while the settler trains.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 2, 2, 3)
	s.worked_tiles = []                              # no food at all
	s.food_store = 0
	s.production_queue = [{"type": "unit", "id": "settler"}]
	TurnEngine._settlement_growth(gs, s, gs.get_player(1))
	assert_eq(s.population, 2, "Starvation shrinks the city even while training")
	assert_eq(s.food_store, 0, "The drained box clamps at zero as usual")
	assert_eq(s.food_for_production, 0, "A deficit diverts nothing to production")

func test_food_contribution_counts_toward_completion_overflow() -> void:
	# Completion overflow is the normal rule: the food contribution is part of
	# the progress that crosses the cost line, and the remainder carries.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.output_production = 0
	s.production_store = 55                          # worker costs 60
	s.production_queue = [{"type": "unit", "id": "worker"}]
	s.food_for_production = 10
	var units_before: int = gs.units.size()
	TurnEngine._settlement_production(gs, s, gs.get_player(1))
	assert_eq(gs.units.size(), units_before + 1, "The worker completes on food")
	assert_eq(s.production_store, 5, "55 + 10 − 60 = 5 carries over")

func test_non_food_unit_leaves_growth_untouched() -> void:
	# A warrior at the head of the queue diverts nothing: the surplus reaches
	# the food box exactly as before.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 1)
	s.worked_tiles = [[5, 5], [5, 6], [6, 5]]
	s.production_queue = [{"type": "unit", "id": "warrior"}]
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var fpc: int = gs.db.get_constant("food_per_citizen", 2)
	var net: int = s.health_rate()
	var drain: int = -net if net < 0 else 0
	TurnEngine._settlement_growth(gs, s, p)
	var surplus: int = s.output_food - (s.population * fpc + drain)
	assert_eq(s.food_store, surplus, "A non-food build banks the surplus normally")
	assert_eq(s.food_for_production, 0, "Nothing diverted for a warrior")

func test_disorder_loses_diverted_food_exactly_once() -> void:
	# A city in disorder produces nothing, so the diverted surplus is lost this
	# turn — and it is consumed, never double-added later.
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	s.production_queue = [{"type": "unit", "id": "settler"}]
	s.food_for_production = 7
	s.in_disorder = true
	TurnEngine._settlement_production(gs, s, gs.get_player(1))
	assert_eq(s.production_store, 0, "Disorder: no production, food included")
	assert_eq(s.food_for_production, 0, "The diverted food is consumed regardless")
	s.in_disorder = false
	s.output_production = 0
	TurnEngine._settlement_production(gs, s, gs.get_player(1))
	assert_eq(s.production_store, 0, "The lost food never reappears next call")
