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

# Intelligence missions (§7): espionage spends accrued intel points and a
# steal-tech mission transfers a tech the thief lacks.

func test_espionage_spends_intel_points() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(2).technologies = ["mining"]
	var cost: int = gs.db.get_constant("intel_mission_cost", 100)
	gs.get_player(1).intel_points = {2: cost + 50}
	assert_true(f._cmd_espionage_mission({"player_id": 1, "target_alliance_id": 2,
		"mission": "steal_tech"}), "Mission runs when points suffice")
	assert_eq(int(gs.get_player(1).intel_points.get(2, 0)), 50,
		"Mission spends its intel cost regardless of interception")

func test_espionage_rejected_without_points() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(1).intel_points = {2: 10}
	assert_false(f._cmd_espionage_mission({"player_id": 1, "target_alliance_id": 2,
		"mission": "steal_tech"}), "Mission fails without enough points")

func test_steal_tech_transfers_unknown_tech() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(2).technologies = ["mining"]
	f._espionage_steal_tech(gs.get_player(1), gs.alliances[1])
	assert_true(gs.get_player(1).has_tech("mining"), "Steal grants a tech the thief lacked")

# ── Accumulation: structures feed espionage points (§7, §15.5 provisional) ─────

func test_building_espionage_accumulates() -> void:
	var gs = make_gs(2)
	gs.alliances[0].contacts = [2]
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_commerce = 0           # isolate the flat building contribution
	s.structures = ["jail"]         # Jail grants +4 flat espionage
	TurnEngine._apply_intelligence(gs, gs.get_player(1))
	assert_eq(int(gs.get_player(1).intel_points.get(2, 0)), 4,
		"A Jail's flat espionage accrues against the one known alliance")

func test_espionage_output_multiplier() -> void:
	var gs = make_gs(2)
	gs.alliances[0].contacts = [2]
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.output_commerce = 0
	# Intelligence Agency: +8 flat espionage, +50% espionage output → 8 + 4 = 12.
	s.structures = ["intelligence_agency"]
	TurnEngine._apply_intelligence(gs, gs.get_player(1))
	assert_eq(int(gs.get_player(1).intel_points.get(2, 0)), 12,
		"espionage_output scales the city's espionage before distribution")

# ── Mission cost scales with the defender's EP advantage (§15.5 provisional) ───

func test_mission_cost_scales_with_defender_ep() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var base: int = gs.db.get_constant("intel_mission_cost", 100)
	gs.get_player(2).technologies = ["mining"]
	# Attacker holds exactly `base`; defender holds far more against the attacker,
	# so the mission costs more than `base` and is refused.
	gs.get_player(1).intel_points = {2: base}
	gs.get_player(2).intel_points = {1: base * 3}
	assert_false(f._cmd_espionage_mission({"player_id": 1, "target_alliance_id": 2,
		"mission": "steal_tech"}), "A well-defended rival costs more than the base")
	assert_eq(f._espionage_mission_cost(gs.get_player(1), gs.alliances[1], base), base * 3,
		"Cost = base × (1 + EP-advantage/100); 200%% advantage trebles it")

func test_mission_cost_floors_at_base_when_attacker_ahead() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var base: int = gs.db.get_constant("intel_mission_cost", 100)
	gs.get_player(1).intel_points = {2: base * 5}
	assert_eq(f._espionage_mission_cost(gs.get_player(1), gs.alliances[1], base * 5), base,
		"No surcharge when the attacker out-spies the defender")

# ── espionage_defense raises interception chance (§15.5 provisional) ───────────

func test_espionage_defense_raises_interception() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var base_chance: int = gs.db.get_constant("intel_interception_chance", 25)
	assert_eq(f._espionage_interception_chance(gs.alliances[1]), base_chance,
		"Undefended alliance keeps the base interception chance")
	var s = make_settlement(gs, 2, 8, 8, 3)
	s.structures = ["security_bureau"]   # +50% espionage defense
	assert_eq(f._espionage_interception_chance(gs.alliances[1]), base_chance + 50,
		"A Security Bureau adds its espionage_defense to interception")

# ── Incite revolt tips the largest enemy city into disorder (§7.1) ─────────────

func test_incite_revolt_puts_largest_city_in_disorder() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	make_settlement(gs, 2, 8, 8, 2)
	var big = make_settlement(gs, 2, 10, 10, 6)
	f._espionage_incite_revolt(gs.alliances[1], 3)
	assert_true(big.in_disorder, "The most populous enemy city falls into disorder")
	assert_eq(big.discontented, big.population, "Its whole population is discontented")
	assert_eq(big.revolt_turns, 3, "The revolt runs for the mission's duration")

# ── Public query helpers for the espionage menu (§15.5 provisional) ─────────────

func test_get_espionage_mission_cost_matches_private() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var base: int = gs.db.get_constant("intel_mission_cost", 100)
	gs.get_player(1).intel_points = {2: base * 5}
	gs.current_player_id = 1
	assert_eq(f.get_espionage_mission_cost(2),
		f._espionage_mission_cost(gs.get_player(1), gs.alliances[1], base * 5),
		"Public cost query matches private helper for the same attacker/target")

func test_get_espionage_interception_chance_matches_private() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_eq(f.get_espionage_interception_chance(2),
		f._espionage_interception_chance(gs.alliances[1]),
		"Public interception query matches private helper")

func test_get_espionage_mission_cost_returns_zero_for_invalid_target() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	assert_eq(f.get_espionage_mission_cost(999), 0,
		"Cost query returns 0 for a non-existent alliance")

# ── Data-driven mission catalogue (§7.1, Phase 6) ──────────────────────────────

func test_unknown_mission_id_rejected() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(2).technologies = ["mining"]
	gs.get_player(1).intel_points = {2: 100000}
	assert_false(f._cmd_espionage_mission({"player_id": 1, "target_alliance_id": 2,
		"mission": "not_a_real_mission"}), "A mission absent from the table is rejected")

func test_per_mission_cost_multiplier_applies() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var base: int = gs.db.get_constant("intel_mission_cost", 100)
	gs.current_player_id = 1
	gs.get_player(1).intel_points = {2: base * 5}   # attacker ahead → base curve
	# sabotage carries cost_multiplier 80 in the table → 80% of the base cost.
	var sab: int = int(gs.db.get_espionage_mission("sabotage").get("cost_multiplier", 100))
	assert_eq(f.get_espionage_mission_cost(2, "sabotage"), base * sab / 100,
		"Per-mission cost scales by the mission's cost_multiplier")
	assert_eq(f.get_espionage_mission_cost(2, "steal_tech"), base,
		"steal_tech (multiplier 100) equals the base curve")

func test_steal_tech_gate_rejects_when_no_unknown_tech() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	# Target knows nothing the attacker lacks → the steal_tech gate fails.
	gs.get_player(1).technologies = ["mining"]
	gs.get_player(2).technologies = ["mining"]
	gs.get_player(1).intel_points = {2: 100000}
	assert_false(f._cmd_espionage_mission({"player_id": 1, "target_alliance_id": 2,
		"mission": "steal_tech"}), "steal_tech is refused with no stealable tech, EP untouched")
	assert_eq(int(gs.get_player(1).intel_points.get(2, 0)), 100000,
		"A gate-failed mission spends no EP")

func test_steal_gold_transfers_treasury() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var amount: int = int(gs.db.get_espionage_mission("steal_gold").get("amount", 0))
	gs.get_player(1).treasury = 0
	gs.get_player(2).treasury = amount + 500
	f._espionage_steal_gold(gs.get_player(1), gs.alliances[1], amount)
	assert_eq(gs.get_player(1).treasury, amount, "Thief gains the stolen gold")
	assert_eq(gs.get_player(2).treasury, 500, "Victim loses exactly the stolen amount")

func test_steal_gold_caps_at_victim_treasury() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(1).treasury = 0
	gs.get_player(2).treasury = 30
	f._espionage_steal_gold(gs.get_player(1), gs.alliances[1], 100)
	assert_eq(gs.get_player(1).treasury, 30, "Steal is capped at the victim's treasury")
	assert_eq(gs.get_player(2).treasury, 0, "A broke victim is left at zero, not negative")

func test_poison_water_removes_population_from_largest_city() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	make_settlement(gs, 2, 8, 8, 2)
	var big = make_settlement(gs, 2, 10, 10, 6)
	var before: int = big.population
	f._espionage_poison_water(gs.alliances[1])
	assert_eq(big.population, before - 1, "Poison removes one population from the largest city")

func test_mission_interception_modifier_raises_chance() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	var base_chance: int = gs.db.get_constant("intel_interception_chance", 25)
	var modifier: int = int(gs.db.get_espionage_mission("poison_water").get("interception_modifier", 0))
	assert_true(modifier > 0, "poison_water carries a positive interception modifier")
	assert_eq(f.get_espionage_interception_chance(2, "poison_water"), base_chance + modifier,
		"The mission's interception_modifier adds to the base chance")

func test_espionage_mission_options_lists_catalogue() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	gs.get_player(2).technologies = ["mining"]
	gs.get_player(1).intel_points = {2: 100000}
	var opts = f.espionage_mission_options(2)
	assert_eq(opts.size(), gs.db.get_espionage_missions().size(),
		"Options cover every catalogue mission")
	var steal = null
	for o in opts:
		if o["id"] == "steal_tech":
			steal = o
	assert_not_null(steal, "steal_tech appears in the options")
	assert_true(bool(steal["available"]) and bool(steal["affordable"]),
		"With a stealable tech and ample EP, steal_tech is available and affordable")

# ── Expanded mission catalogue (§7.1) ─────────────────────────────────────────

func test_destroy_building_razes_costliest_non_palace() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var s = make_settlement(gs, 2, 8, 8, 4)
	# market (150) is costlier than walls (50); the Palace is never targetable.
	s.structures = ["palace", "walls", "market"]
	f._espionage_destroy_building(gs.alliances[1])
	assert_false(s.structures.has("market"), "The costliest non-Palace structure is razed")
	assert_true(s.structures.has("walls"), "Cheaper structures are left standing")
	assert_true(s.structures.has("palace"), "The Palace is never targetable")

func test_destroy_building_gate_rejects_palace_only_city() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var s = make_settlement(gs, 2, 8, 8, 4)
	s.structures = ["palace"]
	var m = gs.db.get_espionage_mission("destroy_building")
	assert_false(f._mission_target_valid(gs.get_player(1), gs.alliances[1], m),
		"destroy_building is refused when only the un-targetable Palace remains")

func test_destroy_project_wipes_in_progress_project() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var s = make_settlement(gs, 2, 8, 8, 4)
	s.production_queue = [{"type": "project", "id": "ss_casing"}]
	s.production_store = 200
	f._espionage_destroy_project(gs.alliances[1])
	assert_true(s.production_queue.empty(), "The project is dequeued")
	assert_eq(s.production_store, 0, "Its stored production is wiped")

func test_destroy_project_gate_ignores_non_project_builds() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var s = make_settlement(gs, 2, 8, 8, 4)
	s.production_queue = [{"type": "structure", "id": "market"}]
	var m = gs.db.get_espionage_mission("destroy_project")
	assert_false(f._mission_target_valid(gs.get_player(1), gs.alliances[1], m),
		"destroy_project does not fire against a city building a mere structure")

func test_destroy_improvement_clears_worked_tile() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var s = make_settlement(gs, 2, 8, 8, 4)
	var tile = gs.map.get_tile(9, 8)
	tile.improvement_id = "farm"
	s.worked_tiles = [[9, 8]]
	f._espionage_destroy_improvement(gs.alliances[1])
	assert_eq(tile.improvement_id, "", "The worked tile's improvement is razed")

func test_insert_culture_adds_attacker_influence() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var s = make_settlement(gs, 2, 8, 8, 4)
	var amount = int(gs.db.get_espionage_mission("insert_culture").get("amount", 0))
	f._espionage_insert_culture(gs.get_player(1), gs.alliances[1], amount)
	var tile = gs.map.get_tile(s.x, s.y)
	assert_eq(int(tile.influence.get(1, 0)), amount,
		"The attacker's cultural influence is added to the target city tile")

func test_incite_unhappiness_adds_timed_anger() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var s = make_settlement(gs, 2, 8, 8, 4)
	f._espionage_incite_unhappiness(gs.alliances[1], 3, 5)
	assert_eq(s.timed_happiness.size(), 1, "A timed unhappiness modifier is queued")
	assert_eq(int(s.timed_happiness[0]["amount"]), -3, "It adds the mission's angry faces")
	assert_eq(int(s.timed_happiness[0]["turns_left"]), 5, "...for the mission's duration")

func test_switch_civic_forces_anarchy() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	make_settlement(gs, 2, 8, 8, 4)
	f._espionage_force_anarchy(gs.alliances[1], 2, false)
	assert_eq(gs.get_player(2).transition_turns, 2,
		"The victim is thrown into anarchy for the mission's duration")

func test_switch_religion_strips_state_religion_and_anarchy() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	make_settlement(gs, 2, 8, 8, 4)
	gs.get_player(2).state_religion = "the_path"
	f._espionage_force_anarchy(gs.alliances[1], 2, true)
	assert_eq(gs.get_player(2).state_religion, "", "The victim loses its state religion")
	assert_eq(gs.get_player(2).transition_turns, 2, "...and falls into anarchy")

func test_switch_religion_gate_requires_a_believer() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	make_settlement(gs, 2, 8, 8, 4)
	gs.get_player(2).state_religion = ""
	var m = gs.db.get_espionage_mission("switch_religion")
	assert_false(f._mission_target_valid(gs.get_player(1), gs.alliances[1], m),
		"switch_religion is refused when no target member has a state religion")

func test_counterespionage_records_cover_and_raises_interception() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	make_settlement(gs, 1, 5, 5, 4)   # the caster needs a city only for the gate
	# Player 1 (alliance 1) runs counterespionage against player 2's alliance (2).
	f._espionage_counterespionage(gs.get_player(1), gs.alliances[1], 5)
	assert_eq(int(gs.get_player(1).counter_espionage.get(2, 0)), 5,
		"Counterespionage cover is recorded against the target alliance")
	# Now player 2 (alliance 2) attacks player 1's alliance (1): player 1's cover
	# against alliance 2 raises the interception protecting alliance 1.
	var base_chance = gs.db.get_constant("intel_interception_chance", 25)
	var bonus = gs.db.get_constant("intel_counterespionage_bonus", 25)
	assert_eq(f._espionage_interception_chance(gs.alliances[0], 0, 2), base_chance + bonus,
		"Active counterespionage cover raises interception against that attacker")
	assert_eq(f._espionage_interception_chance(gs.alliances[0], 0, -1), base_chance,
		"The UI preview (no attacker) ignores the counterespionage term")

func test_counter_espionage_ticks_down_and_roundtrips() -> void:
	var gs = make_gs(2)
	gs.get_player(1).counter_espionage = {2: 2}
	TurnEngine._tick_states(gs, gs.get_player(1))
	assert_eq(int(gs.get_player(1).counter_espionage.get(2, 0)), 1,
		"Counterespionage cover ticks down one per turn")
	# Survives save/load with the key coerced back to int (JSON key-type gotcha).
	var json = gs.serialize()
	var gs2 = GameState.deserialize(JSON.parse(JSON.print(json)).result, gs.db)
	assert_true(gs2.get_player(1).counter_espionage.has(2),
		"The cover ledger key is coerced back to int on load")
	assert_eq(int(gs2.get_player(1).counter_espionage.get(2, 0)), 1,
		"The cover value roundtrips through save/load")

# ── Spies cannot be attacked (§7.1) ───────────────────────────────────────────

func test_spy_is_not_a_combat_defender() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	make_unit(gs, "spy", 2, 5, 5)   # a lone enemy spy
	assert_null(Stack.get_defender(gs.units, 5, 5, 1, gs),
		"A tile holding only a spy has no defender — spies cannot be attacked")
	assert_false(f.is_hostile_tile(5, 5),
		"A lone enemy spy's tile is not a hostile (attackable) target")

func test_spy_shares_tile_with_garrison_safely() -> void:
	# A spy stacked under a real defender does not become the target, and the real
	# defender is still found.
	var gs = make_gs(2)
	make_unit(gs, "spy", 2, 5, 5)
	var warrior = make_warrior(gs, 2, 5, 5)
	assert_eq(Stack.get_defender(gs.units, 5, 5, 1, gs).id, warrior.id,
		"The military unit defends; the stacked spy is never chosen")

# ── Spy infiltration movement (§7.1) ──────────────────────────────────────────

func test_spy_infiltrates_peaceful_foreign_city() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	var city = make_settlement(gs, 2, 8, 8, 5)
	gs.map.get_tile(8, 8).owner_player_id = 2   # the city sits in foreign territory
	var spy = make_unit(gs, "spy", 1, 7, 8)
	assert_true(f.can_stack_move(7, 8, 8, 8, [spy.id]),
		"A spy may move onto a foreign city tile, crossing the border")
	assert_true(f._cmd_move_stack(Commands.move_stack(1, 7, 8, 8, 8, [spy.id])),
		"The infiltration move succeeds")
	assert_eq([spy.x, spy.y], [8, 8], "The spy now stands on the foreign city tile")
	assert_eq(city.owner_player_id, 2, "Infiltration does not capture the city")

func test_spy_infiltrates_garrisoned_enemy_city_without_combat() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	# At war, with a garrison sitting in the enemy city.
	gs.alliances[0].at_war_with = [2]
	gs.alliances[1].at_war_with = [1]
	var city = make_settlement(gs, 2, 8, 8, 5)
	var garrison = make_warrior(gs, 2, 8, 8)
	var spy = make_unit(gs, "spy", 1, 7, 8)
	assert_true(f.can_stack_move(7, 8, 8, 8, [spy.id]),
		"A spy may infiltrate even a garrisoned enemy city")
	assert_true(f._cmd_move_stack(Commands.move_stack(1, 7, 8, 8, 8, [spy.id])),
		"The infiltration move succeeds with no combat")
	assert_eq([spy.x, spy.y], [8, 8], "The spy walks onto the garrisoned tile")
	assert_not_null(gs.get_unit(garrison.id), "The garrison is untouched (no battle)")
	assert_not_null(gs.get_unit(spy.id), "The spy survives — it was never in combat")
	assert_eq(city.owner_player_id, 2, "The enemy city is not captured")

func test_non_spy_civilian_still_cannot_enter_foreign_city() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 2, 8, 8, 5)
	gs.map.get_tile(8, 8).owner_player_id = 2   # foreign territory blocks non-spies
	var worker = make_unit(gs, "worker", 1, 7, 8)
	assert_false(f.can_stack_move(7, 8, 8, 8, [worker.id]),
		"Only spies infiltrate — an ordinary civilian cannot enter a foreign city")

# ── Spy-on-tile missions (§7.1) ───────────────────────────────────────────────

func test_spy_mission_runs_and_spends_movement() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	make_settlement(gs, 2, 8, 8, 5)
	gs.get_player(2).treasury = 500
	gs.get_player(1).intel_points = {2: 100000}
	var spy = make_unit(gs, "spy", 1, 8, 8)
	assert_eq(spy.movement_left, spy.movement_total, "A fresh spy has full movement")
	assert_true(f._cmd_spy_mission({"player_id": 1, "unit_id": spy.id, "mission": "steal_gold"}),
		"A spy on a foreign city with full movement and EP runs the mission")
	assert_eq(spy.movement_left, 0, "Running a mission spends the spy's whole turn")

func test_spy_mission_requires_full_movement() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	make_settlement(gs, 2, 8, 8, 5)
	gs.get_player(2).treasury = 500
	gs.get_player(1).intel_points = {2: 100000}
	var spy = make_unit(gs, "spy", 1, 8, 8)
	spy.movement_left = spy.movement_total - 1   # spent even one point
	assert_false(f._cmd_spy_mission({"player_id": 1, "unit_id": spy.id, "mission": "steal_gold"}),
		"A spy without full movement cannot perform a mission")
	assert_true(f.spy_mission_options(spy.id).empty(),
		"No spy actions are offered without full movement")

func test_spy_mission_only_on_foreign_city() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_player(2).treasury = 500
	gs.get_player(1).intel_points = {2: 100000}
	# On the spy's own city: no offensive actions.
	make_settlement(gs, 1, 5, 5, 4)
	var own_spy = make_unit(gs, "spy", 1, 5, 5)
	assert_false(f._cmd_spy_mission({"player_id": 1, "unit_id": own_spy.id, "mission": "steal_gold"}),
		"A spy on its own city has no offensive missions")
	assert_true(f.spy_mission_options(own_spy.id).empty(), "...and no actions are offered")
	# On open ground (no city): cannot act.
	var field_spy = make_unit(gs, "spy", 1, 12, 12)
	assert_false(f._cmd_spy_mission({"player_id": 1, "unit_id": field_spy.id, "mission": "steal_gold"}),
		"A spy not standing on a city tile cannot act")

func test_spy_mission_targets_the_spys_city() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	var small = make_settlement(gs, 2, 8, 8, 3)    # the city the spy stands on
	var big = make_settlement(gs, 2, 10, 10, 8)    # a larger city elsewhere
	# Poison water aimed at the specific (smaller) city, not the alliance's largest.
	f._espionage_poison_water(gs.alliances[1], small)
	assert_eq(small.population, 2, "The spy's own city loses the population")
	assert_eq(big.population, 8, "The alliance's largest city is untouched")

func test_spy_mission_options_only_valid_and_usable() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	# A size-1 city: poison_water (needs pop >= 2) is invalid; steal_tech is valid.
	make_settlement(gs, 2, 8, 8, 1)
	gs.get_player(2).technologies = ["mining"]
	gs.get_player(1).intel_points = {2: 100000}
	var spy = make_unit(gs, "spy", 1, 8, 8)
	var ids := []
	for o in f.spy_mission_options(spy.id):
		ids.append(o["id"])
	assert_true("steal_tech" in ids, "A valid, affordable mission is offered")
	assert_false("poison_water" in ids, "An invalid mission (pop 1) is not offered")
	# With no espionage points, nothing is usable.
	gs.get_player(1).intel_points = {2: 0}
	assert_true(f.spy_mission_options(spy.id).empty(),
		"With no EP, no usable spy actions are shown")
