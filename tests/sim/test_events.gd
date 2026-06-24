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

# Random events & exploration (§9, reworked). The catalogue loads, the selection
# framework (grace / per-era chance / per-game roster / weighted pick / mandatory
# choices) behaves, the prereq vocabulary gates correctly, fire-time rolling is
# deterministic, and each effect verb mutates the right state.

# Mark a player tile as owned and stamp the given Tile properties on it.
func _own_tile(gs, pid, x, y, props = {}):
	var t = gs.map.get_tile(x, y)
	t.owner_player_id = pid
	for k in props:
		t.set(k, props[k])
	return t

# ── Catalogue loads ──────────────────────────────────────────────────────────────

func test_events_table_loads() -> void:
	var gs = make_gs()
	assert_true(gs.db.events.has("forest_fire"), "events.json loads into DataDB")
	assert_true(gs.db.get_events().size() > 1, "the catalogue defines multiple events")
	assert_true(gs.db.get_errors().empty(), "DataDB loads cleanly with the reworked events table")

func test_event_triggers_table_is_gone() -> void:
	# The separate trigger table was folded into the events; the loader no longer
	# carries it and nothing should reference it.
	var gs = make_gs()
	assert_false("event_triggers" in gs.db, "DataDB no longer exposes an event_triggers table")

# ── Per-game roster (active inclusion) ───────────────────────────────────────────

func test_roll_active_events_includes_certain_events() -> void:
	var gs = make_gs()
	Events.roll_active_events(gs)
	# marathon is active 100 — always in the roster.
	assert_true("marathon" in gs.active_event_ids, "an active=100 event is always rostered")

func test_roll_active_events_is_deterministic() -> void:
	var a = make_gs(2, 777)
	Events.roll_active_events(a)
	var b = make_gs(2, 777)
	Events.roll_active_events(b)
	assert_eq(a.active_event_ids, b.active_event_ids, "the same seed rolls the same roster")

func test_roster_excludes_event_not_rolled_in() -> void:
	var gs = make_gs()
	gs.active_event_ids = ["breakthrough"]  # only breakthrough is in this game
	var p = gs.get_player(1)
	# breakthrough has no prereq, so within the roster it is eligible.
	assert_true(Events.event_eligible("breakthrough", p, gs),
		"a rostered, prereq-free event is eligible")
	# setback is also prereq-free but is outside the roster.
	assert_false(Events.event_eligible("setback", p, gs),
		"an event outside the roster is never eligible")

# ── Selection: grace & era chance ────────────────────────────────────────────────

func test_grace_period_suppresses_all_events() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	gs.turn_number = 5  # inside the 20-turn grace period
	var fired = Events.process_player_events(p, gs, gs.rng)
	assert_true(fired.empty(), "no event fires during the opening grace period")

func test_grace_period_is_a_fixed_count() -> void:
	# The grace window is a flat turn count regardless of game speed.
	var gs = make_gs()
	assert_eq(int(gs.db.get_constant("event_grace_turns", 0)), 20,
		"grace is a fixed 20 turns, not a pace-scaled value")

func test_era_chance_table_indexes_by_era() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)  # no techs → Ancient era (index 0)
	assert_eq(Events._era_chance(p, gs.db), 1, "Ancient era carries the 1% per-turn chance")

# ── Prereq predicates ────────────────────────────────────────────────────────────

func test_prereq_tech_all_and_any() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	assert_false(Events.prereq_holds({"tech_all": ["writing"]}, p, gs), "tech_all fails without the tech")
	assert_false(Events.prereq_holds({"tech_any": ["writing", "monotheism"]}, p, gs), "tech_any fails without any")
	p.technologies.append("writing")
	assert_true(Events.prereq_holds({"tech_all": ["writing"]}, p, gs), "tech_all holds with the tech")
	assert_true(Events.prereq_holds({"tech_any": ["writing", "monotheism"]}, p, gs), "tech_any holds with one")

func test_prereq_building_and_civic() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	assert_false(Events.prereq_holds({"building": "walls"}, p, gs), "building fails without the structure")
	s.structures.append("walls")
	assert_true(Events.prereq_holds({"building": "walls"}, p, gs), "building holds when owned")
	assert_false(Events.prereq_holds({"civic": "environmentalism"}, p, gs), "civic fails when not adopted")
	p.policies["economy"] = "environmentalism"
	assert_true(Events.prereq_holds({"civic": "environmentalism"}, p, gs), "civic holds when adopted")

func test_prereq_war_and_era_and_pop() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5, 3)
	assert_false(Events.prereq_holds({"at_war": true}, p, gs), "at_war fails at peace")
	gs.get_alliance(1).at_war_with.append(2)
	gs.get_alliance(2).at_war_with.append(1)
	assert_true(Events.prereq_holds({"at_war": true}, p, gs), "at_war holds at war")
	assert_true(Events.prereq_holds({"min_era": 0}, p, gs), "min_era 0 always holds")
	assert_false(Events.prereq_holds({"min_era": 6}, p, gs), "a Future-era prereq fails in the Ancient era")
	assert_true(Events.prereq_holds({"max_pop": 5}, p, gs), "max_pop holds for a small city")
	assert_false(Events.prereq_holds({"min_pop": 6}, p, gs), "min_pop fails when no city is large enough")

func test_prereq_resource_absent_and_state_religion() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	assert_true(Events.prereq_holds({"resource_absent": "spices"}, p, gs), "resource_absent holds with none owned")
	_own_tile(gs, 1, 6, 6, {"resource_id": "spices"})
	assert_false(Events.prereq_holds({"resource_absent": "spices"}, p, gs), "resource_absent fails once owned")
	assert_false(Events.prereq_holds({"state_religion": true}, p, gs), "state_religion fails with none")
	p.state_religion = "buddhism"
	assert_true(Events.prereq_holds({"state_religion": true}, p, gs), "state_religion holds when adopted")

func test_prereq_players_tech_count() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	gs.get_player(1).technologies.append("horseback_riding")
	assert_false(Events.prereq_holds({"players_tech": {"tech": "horseback_riding", "count": 2}}, p, gs),
		"players_tech needs the required count of holders")
	gs.get_player(2).technologies.append("horseback_riding")
	assert_true(Events.prereq_holds({"players_tech": {"tech": "horseback_riding", "count": 2}}, p, gs),
		"players_tech holds once enough players know it")

func test_prereq_tile_terrain_feature_improvement_resource_route() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	# A grassland tile is owned but bare.
	_own_tile(gs, 1, 7, 7, {"terrain_id": "grassland"})
	assert_true(Events.prereq_holds({"tile": {"terrain": "grassland"}}, p, gs), "tile terrain matches")
	assert_false(Events.prereq_holds({"tile": {"improvement": "mine"}}, p, gs), "no mine yet")
	_own_tile(gs, 1, 7, 7, {"feature_id": "forest", "improvement_id": "mine",
		"resource_id": "gold", "transport_id": "road"})
	assert_true(Events.prereq_holds({"tile": {"feature": "forest"}}, p, gs), "tile feature matches")
	assert_true(Events.prereq_holds({"tile": {"improvement": "mine", "resource": "gold"}}, p, gs),
		"tile improvement+resource match together")
	assert_true(Events.prereq_holds({"tile": {"route": true}}, p, gs), "tile route (road) matches")
	# in_city_radius: the tile must sit near an owned city.
	_own_tile(gs, 1, 18, 18, {"feature_id": "jungle"})  # far from the city at (5,5)
	assert_false(Events.prereq_holds({"tile": {"feature": "jungle", "in_city_radius": true}}, p, gs),
		"a far tile is outside the city radius")
	_own_tile(gs, 1, 6, 5, {"feature_id": "jungle"})    # adjacent to the city
	assert_true(Events.prereq_holds({"tile": {"feature": "jungle", "in_city_radius": true}}, p, gs),
		"a tile next to a city is in the radius")

func test_obsolete_tech_blocks_event() -> void:
	var gs = make_gs()
	gs.active_event_ids = ["bowyer"]
	var p = gs.get_player(1)
	p.technologies.append("archery")
	assert_true(Events.event_eligible("bowyer", p, gs), "Bowyer is eligible with Archery")
	p.technologies.append("nationalism")  # an obsolete tech
	assert_false(Events.event_eligible("bowyer", p, gs), "an obsolete tech disqualifies the event")

# ── Firing & fire-time rolling ───────────────────────────────────────────────────

func test_begin_event_applies_ranged_gold_within_bounds() -> void:
	var gs = make_gs(2, 999)
	var p = gs.get_player(1)
	p.treasury = 0
	make_settlement(gs, 1, 5, 5)
	var d = Events.fire_event("motherload", p, gs)
	assert_eq(str(d.get("kind", "")), "event_fired", "a no-choice event fires immediately")
	assert_true(p.treasury >= 20 and p.treasury <= 40,
		"the rolled gold (range 20..40) lands within bounds (got %d)" % p.treasury)

func test_fire_time_roll_is_deterministic() -> void:
	# The same seed bakes the same magnitude / chance outcome.
	var a = make_gs(2, 4242); make_settlement(a, 1, 5, 5)
	a.get_player(1).treasury = 0
	Events.fire_event("motherload", a.get_player(1), a)
	var b = make_gs(2, 4242); make_settlement(b, 1, 5, 5)
	b.get_player(1).treasury = 0
	Events.fire_event("motherload", b.get_player(1), b)
	assert_eq(a.get_player(1).treasury, b.get_player(1).treasury,
		"the same seed rolls the same ranged outcome")

func test_human_choice_parks_pre_rolled_branches() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.is_ai = false
	make_settlement(gs, 1, 5, 5)
	_own_tile(gs, 1, 6, 5, {"feature_id": "forest"})  # forest in the city radius
	var d = Events.fire_event("forest_fire", p, gs)
	assert_eq(str(d.get("kind", "")), "event_choice_pending", "a human choice event parks a decision")
	assert_eq(gs.pending_event_choices.size(), 1, "one pending choice is queued")
	var parked = gs.pending_event_choices[0]
	assert_eq(parked.get("resolved_choices", []).size(), 3, "all three branches are pre-rolled and parked")

func test_ai_auto_resolves_first_branch() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.is_ai = true
	p.treasury = 0
	make_settlement(gs, 1, 5, 5)
	_own_tile(gs, 1, 6, 5, {"feature_id": "forest"})
	var d = Events.fire_event("forest_fire", p, gs)
	assert_eq(str(d.get("kind", "")), "event_fired", "an AI resolves the choice in-pipeline")
	assert_true(gs.pending_event_choices.empty(), "no human choice is queued for an AI")
	assert_eq(p.treasury, -10, "the AI takes the first branch (pay 10 gold to douse)")

func test_apply_choice_applies_exactly_the_named_branch() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.is_ai = false
	p.treasury = 0
	make_settlement(gs, 1, 5, 5)
	var forest = _own_tile(gs, 1, 6, 5, {"feature_id": "forest"})
	Events.fire_event("forest_fire", p, gs)
	assert_true(Events.apply_choice("forest_fire", "let_burn", p, gs), "resolving the named branch succeeds")
	assert_eq(forest.feature_id, "", "the 'let it burn' branch removes the forest")
	assert_eq(p.treasury, 0, "the 'let it burn' branch costs no gold")
	var cap = Events.capital_of(1, gs)
	assert_eq(cap.timed_happiness.size(), 1, "the angry-face modifier is applied to the capital")
	assert_eq(int(cap.timed_happiness[0].get("amount", 0)), -1, "it is a negative (angry) modifier")

# ── Mandatory-choice end-turn gate (facade) ──────────────────────────────────────

func test_pending_event_blocks_end_turn_until_resolved() -> void:
	var f = setup_facade()
	var gs = f.get_state()
	var p = gs.get_player(1)
	p.is_ai = false
	p.treasury = 100
	gs.current_player_id = 1
	# Park a pre-rolled human choice directly (no map fuss).
	gs.pending_event_choices.append({
		"event_id": "forest_fire", "player_id": 1, "trigger_id": "",
		"resolved_choices": [{"id": "douse", "text": "Pay", "effects": [{"verb": "gold", "amount": -10}]}]
	})
	assert_false(f.apply_command(Commands.end_turn(1)), "End Turn is refused while a choice is pending")
	assert_true(f.apply_command(Commands.resolve_event(1, "forest_fire", "douse")), "the choice resolves")
	assert_eq(p.treasury, 90, "the resolved branch applied (paid 10 gold)")
	assert_true(gs.pending_event_choices.empty(), "the pending choice is cleared")
	assert_true(f.apply_command(Commands.end_turn(1)), "End Turn proceeds once the choice is answered")

# ── Effect verbs: economy / research ─────────────────────────────────────────────

func test_research_pct_remaining_and_loss() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.current_research_id = "writing"
	var cost = int(gs.db.get_technology("writing").get("cost", 0))
	assert_true(cost > 0, "writing has a positive cost to test against")
	p.research_store = 0
	Events.apply_effects([{"verb": "research_pct_remaining", "percent": 10}], p, gs)
	assert_eq(p.research_store, Fixed.scale(cost, 10), "banks 10% of the remaining tech cost")
	p.research_store = cost
	Events.apply_effects([{"verb": "research_pct_loss", "percent": 8}], p, gs)
	assert_eq(p.research_store, cost - Fixed.scale(cost, 8), "loses 8% of the tech cost")

func test_research_pct_no_current_research_is_noop() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.current_research_id = ""
	p.research_store = 5
	Events.apply_effects([{"verb": "research_pct_remaining", "percent": 50}], p, gs)
	assert_eq(p.research_store, 5, "with no current research the store is untouched")

# ── Effect verbs: golden age, attitude ───────────────────────────────────────────

func test_golden_age_verb_starts_a_golden_age() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	assert_false(GreatPeople.is_in_golden_age(p), "no Golden Age before the event")
	Events.fire_event("marathon", p, gs)
	assert_true(GreatPeople.is_in_golden_age(p), "the Marathon event triggers a Golden Age")
	assert_eq(p.golden_age_count, 1, "the Golden Age is counted")

func test_attitude_verb_adjusts_memory_toward_a_rival() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	Events.fire_event("faux_pas", p, gs)
	# faux_pas applies -30 toward the lowest-id rival (player 2).
	assert_eq(Diplomacy.memory_total(p, 2), -30, "the faux pas worsens memory toward a rival")

# ── Effect verbs: promotions, tile yields, resources, routes ─────────────────────

func test_grant_promotion_targets_matching_classification() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	var archer = make_unit(gs, "archer", 1, 5, 5)      # classification ranged
	var warrior = make_warrior(gs, 1, 5, 5)            # melee
	Events.fire_event("bowyer", p, gs)
	assert_true(archer.has_promotion("combat1"), "the archer gains the granted promotion")
	assert_false(warrior.has_promotion("combat1"), "a non-ranged unit is unaffected")

func test_tile_yield_verb_raises_tile_output() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	var t = _own_tile(gs, 1, 7, 7, {"terrain_id": "grassland"})
	Events.fire_event("truffles", p, gs)
	assert_eq(t.event_food, 1, "Truffles adds +1 food to the tile")
	assert_eq(t.event_commerce, 1, "Truffles adds +1 commerce to the tile")
	var out = TileOutput.compute(t, gs.db, p.technologies)
	assert_eq(out[IDs.Output.FOOD], 3, "grassland base 2 food + event 1 = 3")
	assert_eq(out[IDs.Output.COMMERCE], 1, "grassland base 0 commerce + event 1 = 1")

func test_place_resource_gather_branch() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.is_ai = true  # AI takes the first branch (gather)
	make_settlement(gs, 1, 5, 5)
	var t = _own_tile(gs, 1, 6, 5, {"feature_id": "forest"})
	Events.fire_event("spicy", p, gs)
	assert_eq(t.resource_id, "spices", "the gather branch seeds spices on the forest tile")

func test_remove_route_clears_a_road() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.is_ai = true  # first branch (abandon) removes the road
	make_settlement(gs, 1, 5, 5)
	var t = _own_tile(gs, 1, 7, 7, {"transport_id": "road"})
	Events.fire_event("washed_out", p, gs)
	assert_eq(t.transport_id, "", "the abandon branch tears up the road")

# ── Effect verbs: timed happiness, population, wild spawn, chance ─────────────────

func test_city_happy_timed_applies_to_all_cities() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.is_ai = true  # first branch (observe) — no gold cost
	p.policies["economy"] = "environmentalism"
	make_settlement(gs, 1, 5, 5)
	make_settlement(gs, 1, 9, 9)
	Events.fire_event("earth_day", p, gs)
	for s in gs.settlements:
		assert_eq(s.timed_happiness.size(), 1, "every city gains a timed happy face")
		assert_eq(int(s.timed_happiness[0].get("turns_left", 0)), 10, "for 10 turns")

func test_timed_happiness_folds_into_contentment() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 4)
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var base_pos = s.positive_sentiment
	var base_neg = s.negative_sentiment
	s.timed_happiness.append({"amount": 2, "turns_left": 5})
	s.timed_happiness.append({"amount": -1, "turns_left": 5})
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_eq(s.positive_sentiment, base_pos + 2, "a positive modifier raises positive sentiment")
	assert_eq(s.negative_sentiment, base_neg + 1, "a negative modifier adds a flat angry citizen")

func test_timed_happiness_ticks_down_and_expires() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.timed_happiness.append({"amount": 1, "turns_left": 2})
	TurnEngine._tick_states(gs, p)
	assert_eq(int(s.timed_happiness[0].get("turns_left", 0)), 1, "the modifier counts down")
	TurnEngine._tick_states(gs, p)
	assert_true(s.timed_happiness.empty(), "the modifier expires and is dropped")

func test_capital_pop_growth_branch() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.is_ai = true  # first branch (let_settle) → +1 pop
	var cap = make_settlement(gs, 1, 5, 5, 3)
	Events.fire_event("gold_rush", p, gs)
	assert_eq(cap.population, 4, "the gold rush grows the city by one")

func test_spawn_wild_drops_raiders_near_the_capital() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	Events.fire_event("the_huns", p, gs)
	var wild = 0
	for u in gs.units:
		if u.owner_player_id == -2:
			wild += 1
	assert_eq(wild, 4, "The Huns spawns four wild raiders")

func test_chance_branch_pre_rolls_and_may_loop() -> void:
	# dust_bowl 'ride_out' destroys one farm and MAY (50%) destroy a second via a
	# pre-rolled chance. Across several seeds we should see both the 1-farm and the
	# 2-farm outcomes, and every outcome removes at least one farm.
	var saw_one = false
	var saw_two = false
	for seed_val in range(24):
		var gs = make_gs(2, seed_val)
		var p = gs.get_player(1)
		make_settlement(gs, 1, 5, 5)
		_own_tile(gs, 1, 6, 6, {"terrain_id": "plains", "improvement_id": "farm"})
		_own_tile(gs, 1, 7, 7, {"terrain_id": "plains", "improvement_id": "farm"})
		Events.fire_event("dust_bowl", p, gs)
		Events.apply_choice("dust_bowl", "ride_out", p, gs)
		var farms = 0
		for t in gs.map.all_tiles():
			if t.owner_player_id == 1 and t.improvement_id == "farm":
				farms += 1
		assert_true(farms <= 1, "ride_out destroys at least one farm")
		if farms == 1:
			saw_one = true
		elif farms == 0:
			saw_two = true
	assert_true(saw_one, "some seeds destroy exactly one farm")
	assert_true(saw_two, "some seeds trigger the chance and destroy a second farm")

# ── Timed-event lifecycle (synthetic) ────────────────────────────────────────────

func test_timed_event_expires_on_schedule() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var cap = make_settlement(gs, 1, 5, 5)
	cap.health = 100
	register_test_timed_event(gs.db)
	Events.apply_event_begin(gs.db.get_event("test_sickness"), p, gs)
	assert_eq(cap.health, 96, "the timed event's begin effect lowers capital health")
	assert_eq(gs.active_events.size(), 1, "a timed event is registered as active")
	for i in range(4):
		var produced = Events.tick_active_events(p, gs)
		assert_true(produced.empty(), "still active on tick %d" % (i + 1))
		assert_eq(cap.health, 96, "health unchanged while the event persists")
	var last = Events.tick_active_events(p, gs)
	assert_eq(last.size(), 1, "the event expires on its scheduled tick")
	assert_eq(str(last[0].get("kind", "")), "event_expired", "an expiry descriptor is produced")
	assert_eq(cap.health, 100, "the expire effect restores capital health")
	assert_true(gs.active_events.empty(), "the expired event is removed from the active list")

func test_active_timed_event_blocks_refire() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5).health = 100
	register_test_timed_event(gs.db)
	Events.apply_event_begin(gs.db.get_event("test_sickness"), p, gs)
	assert_false(Events.event_eligible("test_sickness", p, gs),
		"a still-running timed event is not eligible to re-fire")

# ── Save / load of the reworked state ────────────────────────────────────────────

func test_event_state_survives_save_load() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var cap = make_settlement(gs, 1, 5, 5)
	cap.health = 100
	cap.timed_happiness.append({"amount": 1, "turns_left": 6})
	_own_tile(gs, 1, 7, 7, {"terrain_id": "grassland"}).event_commerce = 2
	gs.active_event_ids = ["marathon", "breakthrough"]
	register_test_timed_event(gs.db)
	Events.apply_event_begin(gs.db.get_event("test_sickness"), p, gs)
	gs.pending_event_choices.append({
		"event_id": "forest_fire", "player_id": 1, "trigger_id": "",
		"resolved_choices": [{"id": "douse", "text": "Pay", "effects": [{"verb": "gold", "amount": -10}]}]
	})
	var gs2 = GameState.deserialize(gs.serialize(), gs.db)
	assert_eq(gs2.active_event_ids, ["marathon", "breakthrough"], "the per-game roster roundtrips")
	assert_eq(gs2.active_events.size(), 1, "an active timed event roundtrips")
	assert_eq(int(gs2.active_events[0]["player_id"]), 1, "active-event player_id coerced to int")
	var cap2 = gs2.get_settlement(cap.id)
	assert_eq(cap2.timed_happiness.size(), 1, "a timed happiness modifier roundtrips")
	assert_eq(int(cap2.timed_happiness[0]["turns_left"]), 6, "its turns_left coerced to int")
	assert_eq(gs2.map.get_tile(7, 7).event_commerce, 2, "a tile yield delta roundtrips")
	assert_eq(gs2.pending_event_choices.size(), 1, "a parked human choice roundtrips")
	assert_eq(gs2.pending_event_choices[0].get("resolved_choices", []).size(), 1,
		"its pre-rolled branches roundtrip")

# ── Exploration / goody-hut reward table (§9, unchanged) ─────────────────────────

func test_entering_discovery_site_yields_reward() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	gs.map.get_tile(6, 5).has_discovery = true
	make_unit(gs, "warrior", 1, 5, 5)
	f._cmd_move_stack({"player_id": 1, "from_x": 5, "from_y": 5, "to_x": 6, "to_y": 5})
	assert_false(gs.map.get_tile(6, 5).has_discovery, "Discovery site is consumed on entry")

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

func test_goody_unit_spawns_free_unit() -> void:
	var gs = make_gs()
	var u = make_unit(gs, "warrior", 1, 5, 5)
	var before = gs.units.size()
	var r = Events._apply_goody({"type": "unit", "unit_type": "warrior"}, u, gs, gs.rng)
	assert_eq(gs.units.size(), before + 1, "unit goody spawns a free unit")
	assert_true(int(r.get("unit_id", -1)) >= 0, "unit goody returns the new unit id")

func test_exploration_reward_is_rng_deterministic() -> void:
	var a = make_gs(1, 4242)
	var ua = make_unit(a, "warrior", 1, 5, 5)
	var ra = Events.exploration_reward(ua, a, a.rng)
	var b = make_gs(1, 4242)
	var ub = make_unit(b, "warrior", 1, 5, 5)
	var rb = Events.exploration_reward(ub, b, b.rng)
	assert_eq(ra["type"], rb["type"], "the same seed rolls the same goody type")
