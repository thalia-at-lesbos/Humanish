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

# Great People subsystem (§14): specialist-typed birth, the abstract fallback,
# Golden Ages, the full set of GP actions, the Great General earned from combat,
# and one round-trip through the SimFacade command path.

func _city(gs, player_id, x, y):
	return make_settlement(gs, player_id, x, y, 2)

# ── Type mapping & dominant specialist ──────────────────────────────────────────

func test_gp_unit_for_type_maps_specialists() -> void:
	var gs = make_gs()
	assert_eq(GreatPeople.gp_unit_for_type(gs.db, "scientist"), "great_scientist",
		"scientist specialist maps to the Great Scientist unit")
	assert_eq(GreatPeople.gp_unit_for_type(gs.db, "combat_xp"), "great_general",
		"combat XP maps to the Great General unit")
	assert_eq(GreatPeople.gp_unit_for_type(gs.db, "nonsense"), "",
		"an unknown generator maps to no unit")

func test_gp_unit_for_type_reads_the_specialists_table() -> void:
	# The mapping comes from data/specialists.json (great_person_unit), not a unit
	# tag scan — every working specialist's table mapping resolves to its GP unit.
	var gs = make_gs()
	for stype in Specialists.assignable_types(gs.db):
		assert_eq(GreatPeople.gp_unit_for_type(gs.db, stype),
			Specialists.great_person_unit(gs.db, stype),
			"%s births the table's great_person_unit" % stype)

func test_dominant_specialist_picks_the_largest() -> void:
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	s.specialists = {"artist": 2, "merchant": 5, "scientist": 5}
	assert_eq(GreatPeople.dominant_specialist(s), "merchant",
		"ties break on the lexicographically smallest type for determinism")
	s.specialists = {}
	assert_eq(GreatPeople.dominant_specialist(s), "",
		"no specialists means no dominant type")

func test_birth_from_settlement_spawns_typed_unit() -> void:
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	s.specialists = {"engineer": 3}
	var uid: int = GreatPeople.birth_from_settlement(gs, s)
	assert_true(uid > 0, "a Great Person is born")
	var u = gs.get_unit(uid)
	assert_eq(u.unit_type_id, "great_engineer", "engineer specialists birth a Great Engineer")
	assert_eq(u.owner_player_id, 1, "the city owner owns the Great Person")
	assert_eq(u.x, 5, "born at the city tile (x)")
	assert_eq(u.y, 5, "born at the city tile (y)")

# ── Abstract fallback (no typed specialists) ─────────────────────────────────────

func test_abstract_fallback_grants_tech() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.current_research_id = "mining"
	var s = _city(gs, 1, 5, 5)  # no specialists -> abstract path
	TurnEngine._apply_special_person(gs, s)
	assert_true(p.has_tech("mining"), "with no typed specialists the bonus grants the in-progress tech")
	assert_eq(p.current_research_id, "", "research target cleared after the grant")

func test_abstract_fallback_founds_econ_org() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.current_research_id = ""
	var s = _city(gs, 1, 5, 5)
	TurnEngine._apply_special_person(gs, s)
	assert_ne(s.econ_org_id, "", "no research falls through to seeding an economic organization")

# ── Join City ────────────────────────────────────────────────────────────────

func test_join_city_adds_super_specialist() -> void:
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	var u = make_gp(gs, "great_artist", 1, 5, 5)
	assert_true(GreatPeople.perform_action(gs, u, "join_city", {"settlement_id": s.id}),
		"join_city succeeds")
	assert_eq(int(s.specialists.get("artist", 0)), 1, "an artist super-specialist is added")
	assert_eq(gs.get_unit(u.id), null, "the unit is consumed")

func test_join_city_general_settles_as_engineer() -> void:
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	var u = make_gp(gs, "great_general", 1, 5, 5)
	GreatPeople.perform_action(gs, u, "join_city", {"settlement_id": s.id})
	assert_eq(int(s.specialists.get("engineer", 0)), 1,
		"a settled Great General works as a production (engineer) specialist")

# ── Golden Ages ────────────────────────────────────────────────────────────────

func test_two_great_persons_start_a_golden_age() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var u1 = make_gp(gs, "great_artist", 1, 5, 5)
	GreatPeople.perform_action(gs, u1, "start_golden_age", {})
	assert_eq(p.golden_age_turns, 0, "one Great Person is not enough to start")
	var u2 = make_gp(gs, "great_engineer", 1, 5, 5)
	GreatPeople.perform_action(gs, u2, "start_golden_age", {})
	assert_true(p.golden_age_turns > 0, "two Great Persons start a Golden Age")
	assert_eq(p.golden_age_count, 1, "Golden Age count increments")

func test_single_gp_extends_active_golden_age() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.golden_age_turns = 3
	p.golden_age_count = 1
	var u = make_gp(gs, "great_artist", 1, 5, 5)
	GreatPeople.perform_action(gs, u, "start_golden_age", {})
	assert_true(p.golden_age_turns > 3, "a single Great Person extends a running Golden Age")

func test_golden_age_boosts_worked_tiles() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = _city(gs, 1, 5, 5)
	s.worked_tiles = [[5, 6], [6, 5]]
	TurnEngine._settlement_growth(gs, s, p)
	var base_food: int = s.output_food
	p.golden_age_turns = 5
	TurnEngine._settlement_growth(gs, s, p)
	var bonus: int = gs.db.get_constant("golden_age_tile_bonus", 1)
	assert_eq(s.output_food, base_food + s.worked_tiles.size() * bonus,
		"each worked tile yields +1 food during a Golden Age")

func test_tick_golden_age_counts_down_and_floors_at_zero() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.golden_age_turns = 2
	GreatPeople.tick_golden_age(p)
	assert_eq(p.golden_age_turns, 1, "ticks down one")
	GreatPeople.tick_golden_age(p)
	GreatPeople.tick_golden_age(p)
	assert_eq(p.golden_age_turns, 0, "never goes negative")

# ── Type-specific actions ──────────────────────────────────────────────────────

func test_great_work_adds_culture() -> void:
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	s.culture_total = 100
	var u = make_gp(gs, "great_artist", 1, 5, 5)
	GreatPeople.perform_action(gs, u, "great_work", {"settlement_id": s.id})
	assert_eq(s.culture_total, 100 + gs.db.get_constant("gp_great_work_culture", 4000),
		"Great Work adds a burst of culture to the city")

func test_hurry_production_adds_hammers() -> void:
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	var u = make_gp(gs, "great_engineer", 1, 5, 5)
	GreatPeople.perform_action(gs, u, "hurry_production", {"settlement_id": s.id})
	assert_eq(s.production_store, gs.db.get_constant("gp_hurry_production_hammers", 500),
		"Hurry Production injects hammers into the city's build")

func test_trade_mission_adds_gold() -> void:
	var gs = make_gs()
	var p = gs.get_player(1); p.treasury = 0
	var u = make_gp(gs, "great_merchant", 1, 5, 5)
	GreatPeople.perform_action(gs, u, "trade_mission", {})
	assert_eq(p.treasury, gs.db.get_constant("gp_trade_mission_gold", 2000),
		"Trade Mission yields gold")

func test_discover_technology_completes_research() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.current_research_id = "mining"  # a no-prerequisite tech
	p.research_store = 5
	var u = make_gp(gs, "great_scientist", 1, 5, 5)
	assert_true(GreatPeople.perform_action(gs, u, "discover_technology", {}),
		"Discover Technology succeeds for an available tech")
	assert_true(p.has_tech("mining"), "the technology is learned instantly")
	assert_eq(p.current_research_id, "", "the research target is cleared")

func test_discover_technology_refuses_unmet_prereqs() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var target: String = ""
	for tid in gs.db.technologies:
		if gs.db.technologies[tid].get("prereqs_all", []).size() > 0:
			target = tid
			break
	assert_ne(target, "", "fixture sanity: a tech with prerequisites exists")
	var u = make_gp(gs, "great_scientist", 1, 5, 5)
	assert_false(GreatPeople.perform_action(gs, u, "discover_technology", {"tech_id": target}),
		"a tech whose prerequisites are unmet cannot be discovered")
	assert_false(p.has_tech(target), "the tech is not granted")
	assert_true(gs.get_unit(u.id) != null, "the unit is not consumed on a failed action")

func test_found_corporation() -> void:
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	var u = make_gp(gs, "great_merchant", 1, 5, 5)
	assert_true(GreatPeople.perform_action(gs, u, "found_corporation", {"settlement_id": s.id}),
		"Found Corporation succeeds")
	assert_ne(s.econ_org_id, "", "the city now hosts a corporation")
	assert_true(gs.founded_econ_orgs.has(s.econ_org_id), "the corporation is recorded globally")

func test_found_religion_ignores_tech() -> void:
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	var u = make_gp(gs, "great_prophet", 1, 5, 5)
	assert_true(GreatPeople.perform_action(gs, u, "found_religion", {}),
		"a Great Prophet founds a religion regardless of tech")
	assert_ne(s.belief_id, "", "the holy city adopts the new religion")
	assert_true(gs.founded_beliefs.has(s.belief_id), "the religion is recorded globally")

func test_build_academy_adds_structure() -> void:
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	var u = make_gp(gs, "great_scientist", 1, 5, 5)
	assert_true(GreatPeople.perform_action(gs, u, "build_academy", {"settlement_id": s.id}),
		"Build Academy succeeds")
	assert_true(s.has_structure("academy"), "the academy is built in the city")

func test_national_wonder_is_unique_per_player() -> void:
	var gs = make_gs()
	var s1 = _city(gs, 1, 5, 5)
	var s2 = _city(gs, 1, 8, 8)
	var u1 = make_gp(gs, "great_engineer", 1, 5, 5)
	assert_true(GreatPeople.perform_action(gs, u1, "build_ironworks", {"settlement_id": s1.id}),
		"the first Ironworks is built")
	assert_true(s1.has_structure("ironworks"), "Ironworks present in the first city")
	var u2 = make_gp(gs, "great_engineer", 1, 8, 8)
	assert_false(GreatPeople.perform_action(gs, u2, "build_ironworks", {"settlement_id": s2.id}),
		"a second Ironworks (national wonder) is refused")
	assert_false(s2.has_structure("ironworks"), "the second city does not get it")
	assert_true(gs.get_unit(u2.id) != null, "the engineer is kept when the wonder is refused")

func test_infiltration_adds_espionage() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var u = make_gp(gs, "great_spy", 1, 5, 5)
	assert_true(GreatPeople.perform_action(gs, u, "infiltration", {"target_alliance_id": 2}),
		"a Great Spy infiltrates a foreign alliance")
	assert_eq(int(p.intel_points.get(2, 0)),
		gs.db.get_constant("gp_infiltration_espionage", 3000),
		"espionage points accrue against the target")

func test_spy_cannot_start_golden_age() -> void:
	var gs = make_gs()
	var u = make_gp(gs, "great_spy", 1, 5, 5)
	assert_false(GreatPeople.perform_action(gs, u, "start_golden_age", {}),
		"a Great Spy has no Golden Age action")
	assert_true(gs.get_unit(u.id) != null, "the rejected unit is not consumed")

func test_attach_to_unit_grants_leadership() -> void:
	var gs = make_gs()
	var w = make_warrior(gs, 1, 5, 5)
	var g = make_gp(gs, "great_general", 1, 5, 5)
	assert_true(GreatPeople.perform_action(gs, g, "attach_to_unit", {}),
		"Attach to Unit succeeds when a friendly military unit shares the tile")
	assert_true(w.has_promotion("leadership"), "co-located military units gain Leadership")
	assert_eq(gs.get_unit(g.id), null, "the Great General is consumed into the stack")

# ── Great General from combat (§14.2) ────────────────────────────────────────────

func test_great_general_born_from_combat_xp() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var first_cost: int = gs.db.get_constant("great_general_first_cost", 30)
	GreatPeople.award_combat_points(gs, p, 7, 7, first_cost)
	assert_eq(p.great_generals_produced, 1, "crossing the first threshold births a Great General")
	var found := false
	for u in gs.units:
		if u.unit_type_id == "great_general" and u.x == 7 and u.y == 7:
			found = true
	assert_true(found, "the Great General appears in the field at the victory site")

func test_imperialistic_accelerates_great_general() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	p.traits = ["imperialistic"]
	# 20 XP * (1 + 50%) = 30 == first threshold.
	GreatPeople.award_combat_points(gs, p, 7, 7, 20)
	assert_eq(p.great_generals_produced, 1,
		"Imperialistic leaders reach the threshold with less combat XP")

func test_subsequent_great_general_costs_more() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	GreatPeople.award_combat_points(gs, p, 7, 7, gs.db.get_constant("great_general_first_cost", 30))
	assert_true(p.great_general_threshold > gs.db.get_constant("great_general_first_cost", 30),
		"the next Great General costs more than the first")

# ── Special-person production at the city threshold (§6.5/§14.3) ──────────────────

func test_special_person_births_typed_great_person() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5)
	s.special_person_threshold = 10
	s.specialists = {"scientist": 12}  # 12 points >= threshold 10
	TurnEngine._special_person_progress(gs, s)
	assert_eq(s.special_persons_produced, 1, "A special person is produced")
	var found := false
	for u in gs.units:
		if u.owner_player_id == 1 and u.unit_type_id == "great_scientist" \
				and u.x == 5 and u.y == 5:
			found = true
	assert_true(found, "Dominant scientist specialists birth a Great Scientist at the city")

func test_special_person_birth_matches_dominant_specialist() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5)
	s.special_person_threshold = 10
	s.specialists = {"merchant": 12, "scientist": 3}
	TurnEngine._special_person_progress(gs, s)
	assert_eq(s.special_persons_produced, 1, "A special person is produced")
	var found := false
	for u in gs.units:
		if u.owner_player_id == 1 and u.unit_type_id == "great_merchant":
			found = true
	assert_true(found, "More merchant than scientist specialists births a Great Merchant")

func test_special_person_threshold_rises() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5)
	s.special_person_threshold = 100
	s.specialists = {"artist": 100}
	TurnEngine._special_person_progress(gs, s)
	assert_gt(s.special_person_threshold, 100, "The next special person costs more")

# ── Facade command path ──────────────────────────────────────────────────────

func test_gp_action_through_facade_command() -> void:
	var facade = setup_facade(7, "tiny",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 0}], ["time"])
	var gs = facade.get_state()
	var pid: int = gs.players[0].id
	var s = make_settlement(gs, pid, 2, 2, 2)
	var u = GreatPeople.spawn_unit(gs, "great_artist", pid, 2, 2)
	assert_true(facade.apply_command(Commands.gp_action(pid, u.id, "join_city", {"settlement_id": s.id})),
		"the GP_ACTION command is accepted")
	assert_eq(int(s.specialists.get("artist", 0)), 1, "the action ran through the facade")
	assert_eq(gs.get_unit(u.id), null, "the unit was consumed via the command path")
