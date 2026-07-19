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

# Civic gameplay effects (§8). Each test isolates one `effects` key by comparing
# a settlement/player with the civic adopted against the same setup without it.
# Policies are written straight onto `player.policies` (bypassing the tech gate
# in SimFacade._cmd_set_policy) so the effect itself is what is under test.

# ── PolicyEffects helper ─────────────────────────────────────────────────────

func test_sum_int_aggregates_active_policies() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	# Representation carries science_per_scientist: 3.
	p.policies = {"government": "representation"}
	assert_eq(PolicyEffects.sum_int(p, gs.db, "science_per_scientist"), 3,
		"sum_int reads a numeric effect from an active civic")
	assert_eq(PolicyEffects.sum_int(p, gs.db, "nonexistent_key"), 0,
		"Absent effect keys sum to zero")

func test_has_flag_reads_bare_and_nested() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.policies = {"labor": "slavery"}            # bare top-level pop_rush
	assert_true(PolicyEffects.has_flag(p, gs.db, "pop_rush"),
		"has_flag reads a bare top-level boolean effect")
	p.policies = {"legal": "nationhood"}         # nested can_draft
	assert_true(PolicyEffects.has_flag(p, gs.db, "can_draft"),
		"has_flag reads a nested effects-dictionary boolean")
	p.policies = {}
	assert_false(PolicyEffects.has_flag(p, gs.db, "pop_rush"),
		"has_flag is false when no active civic carries the flag")

func test_largest_city_ids_orders_by_population() -> void:
	var gs = make_gs(1)
	make_settlement(gs, 1, 1, 1, 2)
	var big = make_settlement(gs, 1, 3, 3, 9)
	make_settlement(gs, 1, 5, 5, 4)
	var top = PolicyEffects.largest_city_ids(gs, 1, 1)
	assert_eq(top, [big.id], "The single largest city is the most populous one")

# ── Happiness / contentment ──────────────────────────────────────────────────

func _content_pos(gs, s, p) -> int:
	TurnEngine._update_contentment(gs, s, p, gs.db)
	return s.positive_sentiment

func test_hereditary_rule_garrison_happiness() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	make_warrior(gs, 1, 5, 5)  # one garrisoned military unit
	var base_pos = _content_pos(gs, s, p)
	p.policies = {"government": "hereditary_rule"}  # happiness_per_garrison: 1
	assert_eq(_content_pos(gs, s, p), base_pos + 1,
		"Hereditary Rule adds happiness per garrisoned unit")

func test_nationhood_barracks_happiness() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.structures.append("barracks")
	var base_pos = _content_pos(gs, s, p)
	p.policies = {"legal": "nationhood"}  # barracks_happiness: 1
	assert_eq(_content_pos(gs, s, p), base_pos + 1,
		"Nationhood adds happiness from a Barracks")

func test_environmentalism_forest_happiness() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	gs.map.get_tile(6, 5).feature_id = "forest"
	gs.map.get_tile(4, 5).feature_id = "jungle"
	s.worked_tiles = [[6, 5], [4, 5]]
	var base_pos = _content_pos(gs, s, p)
	p.policies = {"economic": "environmentalism"}  # happiness_per_forest: 1
	assert_eq(_content_pos(gs, s, p), base_pos + 2,
		"Environmentalism adds happiness per worked forest/jungle tile")

func test_free_religion_per_religion_happiness() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.belief_id = "buddhism"
	var base_pos = _content_pos(gs, s, p)
	p.policies = {"religion": "free_religion"}  # happiness_per_religion: 1
	assert_eq(_content_pos(gs, s, p), base_pos + 1,
		"Free Religion adds happiness for a religion present in the city")

func test_representation_largest_city_happiness() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	var base_pos = _content_pos(gs, s, p)
	p.policies = {"government": "representation"}  # happiness_largest_cities: 1
	assert_eq(_content_pos(gs, s, p), base_pos + 1,
		"Representation adds happiness in the empire's largest cities")

func test_police_state_reduces_war_anger() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 8)
	var fa = gs.get_player_alliance(1)
	fa.war_fatigue = {"2": 40}  # 40 / divisor(4) = 10 anger points
	TurnEngine._update_contentment(gs, s, p, gs.db)
	var base_neg = s.negative_sentiment
	p.policies = {"government": "police_state"}  # war_anger_reduction: 50
	TurnEngine._update_contentment(gs, s, p, gs.db)
	assert_true(s.negative_sentiment < base_neg,
		"Police State cuts the anger contributed by war fatigue")

# ── Wellbeing / health ───────────────────────────────────────────────────────

func test_environmentalism_empire_health() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	var base = s.wellbeing_positive
	p.policies = {"economic": "environmentalism"}  # health_empire: 6
	TurnEngine._update_wellbeing(gs, s, p, gs.db)
	assert_eq(s.wellbeing_positive, base + 6,
		"Environmentalism adds empire-wide health")

# ── Tile-output bonuses (via _settlement_growth) ─────────────────────────────

func _grow_outputs(gs, s, p) -> Array:
	TurnEngine._settlement_growth(gs, s, p)
	return [s.output_production, s.output_commerce]

func test_universal_suffrage_town_production() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	gs.map.get_tile(6, 5).improvement_id = "town"
	s.worked_tiles = [[6, 5]]
	var base = _grow_outputs(gs, s, p)[0]
	p.policies = {"government": "universal_suffrage"}  # town_production: 1
	assert_eq(_grow_outputs(gs, s, p)[0], base + 1,
		"Universal Suffrage adds production from Town tiles")

func test_free_speech_town_commerce() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	gs.map.get_tile(6, 5).improvement_id = "town"
	s.worked_tiles = [[6, 5]]
	var base = _grow_outputs(gs, s, p)[1]
	p.policies = {"legal": "free_speech"}  # town_commerce: 1
	assert_eq(_grow_outputs(gs, s, p)[1], base + 1,
		"Free Speech adds commerce from Town tiles")

func test_caste_system_workshop_production() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	gs.map.get_tile(6, 5).improvement_id = "workshop"
	s.worked_tiles = [[6, 5]]
	var base = _grow_outputs(gs, s, p)[0]
	p.policies = {"labor": "caste_system"}  # workshop_production: 1
	assert_eq(_grow_outputs(gs, s, p)[0], base + 1,
		"Caste System adds production from Workshop tiles")

func test_state_property_watermill_farm_production() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	gs.map.get_tile(6, 5).improvement_id = "watermill"
	gs.map.get_tile(4, 5).improvement_id = "farm"
	s.worked_tiles = [[6, 5], [4, 5]]
	var base = _grow_outputs(gs, s, p)[0]
	p.policies = {"economic": "state_property"}  # watermill_farm_production: 1
	assert_eq(_grow_outputs(gs, s, p)[0], base + 2,
		"State Property adds production from Watermill and Farm tiles")

func test_environmentalism_windmill_commerce() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 2)
	gs.map.get_tile(6, 5).improvement_id = "windmill"
	s.worked_tiles = [[6, 5]]
	var base = _grow_outputs(gs, s, p)[1]
	p.policies = {"economic": "environmentalism"}  # windmill_commerce: 1
	assert_eq(_grow_outputs(gs, s, p)[1], base + 1,
		"Environmentalism adds commerce from Windmill tiles")

func test_bureaucracy_capital_bonus() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 4)
	s.specialists = {"merchant": 2}  # 2 merchants * 3 commerce (table) = 6 commerce
	var base = _grow_outputs(gs, s, p)[1]
	p.policies = {"legal": "bureaucracy"}  # capital_commerce: 50
	var boosted = _grow_outputs(gs, s, p)[1]
	assert_eq(boosted, base + base * 50 / 100,
		"Bureaucracy boosts the capital's commerce by 50%")

func test_mercantilism_free_specialist_commerce() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 4)
	var base = _grow_outputs(gs, s, p)[1]
	p.policies = {"economic": "mercantilism"}  # free_specialist_per_city: 1
	assert_eq(_grow_outputs(gs, s, p)[1], base + gs.db.get_constant("specialist_commerce", 3),
		"Mercantilism's free specialist yields commerce")

# ── Culture ──────────────────────────────────────────────────────────────────

func test_free_speech_culture_all_cities() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.slider_culture = 100; p.slider_finance = 0
	p.slider_research = 0; p.slider_intel = 0
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_commerce = 10
	TurnEngine._settlement_culture(gs, s, p)
	var base = s.culture_total
	s.culture_total = 0
	p.policies = {"legal": "free_speech"}  # culture_all_cities: 100
	TurnEngine._settlement_culture(gs, s, p)
	assert_eq(s.culture_total, base * 2,
		"Free Speech doubles culture output")

# ── Production-phase effects (via _policy_production_delta) ───────────────────

func test_police_state_military_production() -> void:
	# military_production is now a percentage modifier (§4.3): it stacks in the
	# production percent chain rather than as a flat delta.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	p.policies = {"government": "police_state"}  # military_production: 25
	var item = {"type": "unit", "id": "warrior"}
	assert_eq(TurnEngine._production_percent_mods(gs, s, p, gs.db, item), 25,
		"Police State contributes +25% toward a military unit")
	var civ_item = {"type": "unit", "id": "settler"}
	assert_eq(TurnEngine._production_percent_mods(gs, s, p, gs.db, civ_item), 0,
		"...but not toward a civilian unit")

func test_two_percent_sources_sum_then_apply_once() -> void:
	# A Forge (+25% all production) and Police State (+25% military) sum to +50%
	# applied once on the base — not compounded (×1.25×1.25 ≈ +56%).
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	gs.db.units["test_titan"] = {
		"id": "test_titan", "classification": "melee", "base_strength": 10,
		"movement": 100, "cost": 100000, "upkeep": 0, "tags": []
	}
	s.structures = ["forge"]                       # production_bonus: 25
	p.policies = {"government": "police_state"}    # military_production: 25
	var mil = {"type": "unit", "id": "test_titan"}
	assert_eq(TurnEngine._production_percent_mods(gs, s, p, gs.db, mil), 50,
		"Two +% sources sum to +50% in the chain")
	s.output_production = 100
	s.production_queue = [mil]                     # too costly to finish this turn
	s.production_store = 0
	var base: int = Fixed.scale(100, int(gs.db.get_pace(gs.pace_id).get("build_scale", 100)))
	var sum_once: int = Fixed.apply_stacked_bonus(base, 50)
	var compounded: int = Fixed.apply_stacked_bonus(Fixed.apply_stacked_bonus(base, 25), 25)
	TurnEngine._settlement_production(gs, s, p)
	assert_eq(s.production_store, sum_once,
		"Modifiers are summed and applied once on the base")
	assert_ne(s.production_store, compounded,
		"...not applied multiplicatively in sequence")

func test_organized_religion_building_production() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	p.policies = {"religion": "organized_religion"}  # religious_building_production: 1
	var temple = {"type": "structure", "id": "temple"}
	assert_eq(TurnEngine._policy_production_delta(gs, s, p, gs.db, temple), 1,
		"Organized Religion adds flat production toward a religious building")
	var lib = {"type": "structure", "id": "library"}
	assert_eq(TurnEngine._policy_production_delta(gs, s, p, gs.db, lib), 0,
		"...but not toward a secular building")

func test_pacifism_production_drain() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	make_warrior(gs, 1, 5, 5)
	make_warrior(gs, 1, 5, 5)  # two garrisoned military units
	p.policies = {"religion": "pacifism"}  # production_per_military_unit: -1
	var item = {"type": "structure", "id": "library"}
	assert_eq(TurnEngine._policy_production_delta(gs, s, p, gs.db, item), -2,
		"Pacifism drains 1 production per garrisoned military unit")

# ── Research ─────────────────────────────────────────────────────────────────

func test_representation_science_per_scientist() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.current_research_id = "bronze_working"  # a costly tech that will not complete
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.specialists = {"scientist": 2}
	TurnEngine._apply_research(gs, p)
	var base = p.research_store
	p.research_store = 0
	p.policies = {"government": "representation"}  # science_per_scientist: 3
	TurnEngine._apply_research(gs, p)
	assert_eq(p.research_store, base + 6,
		"Representation grants +3 science per scientist specialist")

func test_free_religion_science_output() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.slider_research = 100; p.slider_finance = 0
	p.slider_culture = 0; p.slider_intel = 0
	p.current_research_id = "bronze_working"
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_commerce = 100  # 100 research income at a 100% research slider
	TurnEngine._apply_research(gs, p)
	var base = p.research_store
	p.research_store = 0
	p.policies = {"religion": "free_religion"}  # science_output: 10
	TurnEngine._apply_research(gs, p)
	assert_eq(p.research_store, base + base * 10 / 100,
		"Free Religion boosts science output by 10%")

# ── Treasury ─────────────────────────────────────────────────────────────────

func test_vassalage_free_unit_upkeep() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5, 1)
	make_unit(gs, "warrior", 1, 5, 5)  # upkeep 1
	make_unit(gs, "warrior", 1, 5, 5)
	make_unit(gs, "warrior", 1, 5, 5)
	p.treasury = 100  # buffer so insolvency does not zero the result
	TurnEngine._update_treasury(gs, p)
	var base_treasury = p.treasury
	p.treasury = 100
	p.policies = {"legal": "vassalage"}  # free_units_per_city: 2 → 2 of 3 free
	TurnEngine._update_treasury(gs, p)
	assert_eq(p.treasury - base_treasury, 2,
		"Vassalage waives upkeep for 2 units per city (2 of 1-gold each)")

func test_state_property_no_distance_maintenance() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	make_settlement(gs, 1, 1, 1, 1)     # capital (lowest id)
	make_settlement(gs, 1, 15, 15, 1)   # distant city
	p.treasury = 1000  # buffer so insolvency does not zero the result
	TurnEngine._update_treasury(gs, p)
	var base_treasury = p.treasury
	p.treasury = 1000
	p.policies = {"economic": "state_property"}  # no_distance_maintenance
	TurnEngine._update_treasury(gs, p)
	assert_true(p.treasury > base_treasury,
		"State Property removes the distance-maintenance penalty")

# ── Rushing (facade gate) ────────────────────────────────────────────────────

func _rush_setup():
	var gs = make_gs(1)
	gs.current_player_id = 1
	var f = bare_facade(gs)
	var s = make_settlement(gs, 1, 5, 5, 5)
	s.production_queue = [{"type": "unit", "id": "warrior"}]
	gs.get_player(1).treasury = 100000
	return [gs, f, s]

func test_gold_rush_needs_no_permitting_civic() -> void:
	# M5 (§15.2/§29.8): the Universal Suffrage `can_rush_with_gold` gate is
	# retired — the gold hurry is available under every government.
	var setup = _rush_setup()
	var gs = setup[0]; var f = setup[1]
	assert_true(f.apply_command(Commands.rush_production(1, gs.settlements[0].id, "treasury")),
		"Gold rush accepted with no civics adopted at all")

func test_pop_rush_requires_slavery() -> void:
	var setup = _rush_setup()
	var gs = setup[0]; var f = setup[1]
	assert_false(f.apply_command(Commands.rush_population(1, gs.settlements[0].id)),
		"Population rush is rejected without a permitting civic")
	gs.get_player(1).policies = {"labor": "slavery"}
	assert_true(f.apply_command(Commands.rush_population(1, gs.settlements[0].id)),
		"Slavery permits a population rush")

func test_pop_rush_legacy_method_string_still_routes() -> void:
	var setup = _rush_setup()
	var gs = setup[0]; var f = setup[1]
	gs.get_player(1).policies = {"labor": "slavery"}
	assert_true(f.apply_command(Commands.rush_production(1, gs.settlements[0].id, "population")),
		"The legacy RUSH_PRODUCTION method=population still whips")

# ── Worker speed ─────────────────────────────────────────────────────────────

func test_serfdom_speeds_worker_builds() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	# Mine requires "mining" tech and hills landform — provide both.
	gs.get_player(1).technologies = ["mining"]
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var f = bare_facade(gs)
	var w = make_unit(gs, "worker", 1, 5, 5)
	f.apply_command(Commands.build_improvement(1, w.id, "mine"))  # build_turns 5
	assert_eq(w.build_turns_left, 5, "Unmodified mine build takes the base 5 turns")
	w.movement_left = w.movement_total
	w.has_moved = false
	gs.get_player(1).policies = {"labor": "serfdom"}  # worker_speed_modifier: 50
	f.apply_command(Commands.build_improvement(1, w.id, "mine"))
	assert_eq(w.build_turns_left, 3,
		"Serfdom +50%% scales the 5-turn mine to 5×100/150 = 3 (truncating)")

func test_unit_work_rate_scales_build_turns() -> void:
	# §15.9: a unit `work_rate` above the default 100 shortens builds — synthetic
	# db override (no shipped unit carries a bonus rate; the reference Fast
	# Worker is 100 too, its edge is movement).
	var gs = make_gs(1)
	gs.current_player_id = 1
	gs.get_player(1).technologies = ["mining"]
	gs.map.get_tile(5, 5).terrain_id = "hills"
	gs.db.units["worker"]["work_rate"] = 150
	var f = bare_facade(gs)
	var w = make_unit(gs, "worker", 1, 5, 5)
	f.apply_command(Commands.build_improvement(1, w.id, "mine"))
	assert_eq(w.build_turns_left, 3,
		"work_rate 150 scales the 5-turn mine to 5×100/150 = 3 (truncating)")

func test_hagia_sophia_speeds_worker_builds() -> void:
	# §15.9: a standing structure carrying effects.worker_speed_modifier (Hagia
	# Sophia +50) speeds every worker of the owning player, empire-wide.
	var gs = make_gs(1)
	gs.current_player_id = 1
	gs.get_player(1).technologies = ["mining"]
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var s = make_settlement(gs, 1, 10, 10, 2)
	s.structures.append("hagia_sophia")
	var f = bare_facade(gs)
	var w = make_unit(gs, "worker", 1, 5, 5)
	f.apply_command(Commands.build_improvement(1, w.id, "mine"))
	assert_eq(w.build_turns_left, 3,
		"Hagia Sophia +50%% scales the 5-turn mine to 3, even far from the city")

func test_worker_speed_sources_stack_additively() -> void:
	# Serfdom 50 + Hagia Sophia 50 → 5×100/200 = 2.
	var gs = make_gs(1)
	gs.current_player_id = 1
	gs.get_player(1).technologies = ["mining"]
	gs.get_player(1).policies = {"labor": "serfdom"}
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var s = make_settlement(gs, 1, 10, 10, 2)
	s.structures.append("hagia_sophia")
	var f = bare_facade(gs)
	var w = make_unit(gs, "worker", 1, 5, 5)
	f.apply_command(Commands.build_improvement(1, w.id, "mine"))
	assert_eq(w.build_turns_left, 2,
		"Serfdom and Hagia Sophia stack additively: 5×100/(100+50+50) = 2")

func test_worker_build_turns_never_below_one() -> void:
	var gs = make_gs(1)
	gs.db.units["worker"]["work_rate"] = 600  # 5×100/600 = 0 → clamped
	var w = make_unit(gs, "worker", 1, 5, 5)
	assert_eq(TurnEngine.worker_build_turns(gs, w, 5), 1,
		"A scaled build never drops below 1 turn")

func test_worker_speed_applies_to_road_and_clear_missions() -> void:
	# §15.9: the modifier covers every worker order — roads (build_turns 2) and
	# feature clearing (forest clear_turns 4), not just improvements.
	var gs = make_gs(1)
	gs.current_player_id = 1
	gs.get_player(1).policies = {"labor": "serfdom"}
	var f = bare_facade(gs)
	var w = make_unit(gs, "worker", 1, 5, 5)
	f.apply_command(Commands.mission_build_road(1, w.id))
	assert_eq(w.build_turns_left, 1,
		"Serfdom scales the 2-turn road to 2×100/150 = 1")
	var w2 = make_unit(gs, "worker", 1, 6, 6)
	gs.map.get_tile(6, 6).feature_id = "forest"
	f.apply_command(Commands.mission_clear_feature(1, w2.id))
	assert_eq(w2.build_turns_left, 2,
		"Serfdom scales the 4-turn forest clear to 4×100/150 = 2")

# ── Emancipation pressure (§15.9) ────────────────────────────────────────────

func test_civic_pressure_zero_without_adopters() -> void:
	var gs = make_gs(3)
	assert_eq(PolicyEffects.civic_pressure_anger(gs, gs.get_player(1), gs.db), 0,
		"No rival on Emancipation means no pressure anger")

func test_civic_pressure_scales_with_adopter_share() -> void:
	var gs = make_gs(4)
	gs.get_player(2).policies = {"labor": "emancipation"}
	assert_eq(PolicyEffects.civic_pressure_anger(gs, gs.get_player(1), gs.db), 13,
		"1 of 3 rivals adopted: 400×1×100/(3×1000) = 13 anger points (truncating)")
	gs.get_player(3).policies = {"labor": "emancipation"}
	gs.get_player(4).policies = {"labor": "emancipation"}
	assert_eq(PolicyEffects.civic_pressure_anger(gs, gs.get_player(1), gs.db), 40,
		"All 3 rivals adopted: 400×3×100/(3×1000) = 40 anger points")

func test_civic_pressure_adopter_is_exempt() -> void:
	var gs = make_gs(3)
	gs.get_player(1).policies = {"labor": "emancipation"}
	gs.get_player(2).policies = {"labor": "emancipation"}
	gs.get_player(3).policies = {"labor": "emancipation"}
	assert_eq(PolicyEffects.civic_pressure_anger(gs, gs.get_player(1), gs.db), 0,
		"A player running Emancipation feels no pressure from it")

func test_civic_pressure_ignores_teammates_and_eliminated() -> void:
	var gs = make_gs(4)
	gs.get_player(2).policies = {"labor": "emancipation"}
	gs.get_player(3).policies = {"labor": "emancipation"}
	# Player 2 shares player 1's alliance; player 3 is eliminated. Only player 4
	# (a living, unallied non-adopter) remains countable.
	gs.get_player(1).alliance_id = 7
	gs.get_player(2).alliance_id = 7
	gs.get_player(3).is_eliminated = true
	assert_eq(PolicyEffects.civic_pressure_anger(gs, gs.get_player(1), gs.db), 0,
		"Teammates and eliminated players are excluded from both counts")

func test_emancipation_pressure_raises_city_anger() -> void:
	# End-to-end through the contentment phase: 3 rivals all on Emancipation add
	# 40 anger points, so a pop-10 city gains 10×40/100 = 4 unhappy citizens.
	var gs = make_gs(4)
	for pid in [2, 3, 4]:
		gs.get_player(pid).policies = {"labor": "emancipation"}
	var s = make_settlement(gs, 1, 5, 5, 10)
	TurnEngine._update_contentment(gs, s, gs.get_player(1), gs.db)
	var without = s.negative_sentiment
	assert_eq(without, 5, "Pop 10: overcrowding 12%% + pressure 40%% → 5 unhappy")
	gs.get_player(1).policies = {"labor": "emancipation"}
	TurnEngine._update_contentment(gs, s, gs.get_player(1), gs.db)
	assert_eq(s.negative_sentiment, 1,
		"Adopting Emancipation drops the pressure share (overcrowding 12%% stays)")

# ── New-unit experience ──────────────────────────────────────────────────────

func test_vassalage_new_unit_xp() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	p.policies = {"legal": "vassalage"}  # new_unit_xp: 2
	TurnEngine._complete_item(gs, s, p, {"type": "unit", "id": "warrior"})
	var built = gs.units[gs.units.size() - 1]
	assert_eq(built.experience, 2, "Vassalage grants new military units +2 XP")

func test_theocracy_state_religion_unit_xp() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.belief_id = "buddhism"
	p.state_religion = "buddhism"  # the city follows the player's state religion
	p.policies = {"religion": "theocracy"}  # state_religion_unit_xp: 2
	TurnEngine._complete_item(gs, s, p, {"type": "unit", "id": "warrior"})
	var built = gs.units[gs.units.size() - 1]
	assert_eq(built.experience, 2,
		"Theocracy grants +2 XP to units built in a state-religion city")

func test_theocracy_no_xp_without_state_religion() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.belief_id = "buddhism"  # present, but not adopted as the state religion
	p.policies = {"religion": "theocracy"}
	TurnEngine._complete_item(gs, s, p, {"type": "unit", "id": "warrior"})
	var built = gs.units[gs.units.size() - 1]
	assert_eq(built.experience, 0,
		"Theocracy grants no XP when the city's religion is not the state religion")

# ── Great Person rate ────────────────────────────────────────────────────────

func test_pacifism_great_person_rate() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 4)
	s.specialists = {"scientist": 3}
	s.special_person_threshold = 100000  # never births during the test
	TurnEngine._special_person_progress(gs, s)
	var base_points = s.special_person_points
	s.special_person_points = 0
	p.policies = {"religion": "pacifism"}  # great_person_rate: 100
	TurnEngine._special_person_progress(gs, s)
	assert_eq(s.special_person_points, base_points * 2,
		"Pacifism doubles Great Person point accumulation")

# ── M1: structure obsolescence × worker speed (§15.17, §15.9) ────────────────
#
# Steam Power carries worker_speed_modifier 50 on the TECH entry, and it is
# also Hagia Sophia's obsoleting tech — so across the transition the two
# sources swap and the net worker speed is unchanged (never double-stacked).

func test_steam_power_tech_speeds_workers() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	gs.get_player(1).technologies = ["mining", "steam_power"]
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var f = bare_facade(gs)
	var w = make_unit(gs, "worker", 1, 5, 5)
	f.apply_command(Commands.build_improvement(1, w.id, "mine"))
	assert_eq(w.build_turns_left, 3,
		"Steam Power's +50%% (tech source, no wonder) scales the 5-turn mine to 3")

func test_hagia_sophia_worker_speed_stops_at_steam_power() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	gs.get_player(1).technologies = ["mining", "steam_power"]
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var s = make_settlement(gs, 1, 10, 10, 2)
	s.structures.append("hagia_sophia")  # worker_speed_modifier 50; obsoleted_by steam_power
	var f = bare_facade(gs)
	var w = make_unit(gs, "worker", 1, 5, 5)
	f.apply_command(Commands.build_improvement(1, w.id, "mine"))
	assert_eq(w.build_turns_left, 3,
		"Obsolete Hagia Sophia adds nothing on top of the tech's +50%%: "
		+ "5×100/150 = 3, not the double-stacked 5×100/200 = 2")

func test_net_worker_speed_unchanged_across_steam_power_transition() -> void:
	# A Hagia Sophia empire researches Steam Power: the wonder's +50 stops, the
	# tech's +50 starts — identical build turns before and after.
	var gs = make_gs(1)
	gs.current_player_id = 1
	gs.get_player(1).technologies = ["mining"]
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var s = make_settlement(gs, 1, 10, 10, 2)
	s.structures.append("hagia_sophia")
	var f = bare_facade(gs)
	var w = make_unit(gs, "worker", 1, 5, 5)
	f.apply_command(Commands.build_improvement(1, w.id, "mine"))
	var before: int = w.build_turns_left
	gs.get_player(1).technologies.append("steam_power")
	w.movement_left = w.movement_total
	w.has_moved = false
	f.apply_command(Commands.build_improvement(1, w.id, "mine"))
	assert_eq(w.build_turns_left, before,
		"Net worker speed is unchanged across the Steam Power transition")
	assert_eq(before, 3, "Both sides of the transition sit at the single +50%% rate")
