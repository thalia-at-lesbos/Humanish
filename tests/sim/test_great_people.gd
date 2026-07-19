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
	assert_eq(GreatPeople.dominant_specialist(s, gs.db), "merchant",
		"ties break on the lexicographically smallest type for determinism")
	s.specialists = {}
	assert_eq(GreatPeople.dominant_specialist(s, gs.db), "",
		"no specialists means no dominant type")

func test_dominant_specialist_ignores_pointless_types() -> void:
	# §15.19: the auto-filled citizen default specialist (and the settled
	# great_* forms) bank no GP points, so they never direct a birth — a city
	# full of idle citizens still births by its point-banking specialists.
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	s.specialists = {"citizen": 6, "great_artist": 4, "scientist": 1}
	assert_eq(GreatPeople.dominant_specialist(s, gs.db), "scientist",
		"zero-GPP types (citizen, settled greats) never claim dominance")
	s.specialists = {"citizen": 3}
	assert_eq(GreatPeople.dominant_specialist(s, gs.db), "",
		"citizens alone leave the city with no dominant type")

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
	assert_eq(int(s.specialists.get("great_artist", 0)), 1,
		"a settled Great Artist super-specialist is added")
	assert_eq(gs.get_unit(u.id), null, "the unit is consumed")

func test_join_city_general_settles_as_great_general() -> void:
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	var u = make_gp(gs, "great_general", 1, 5, 5)
	GreatPeople.perform_action(gs, u, "join_city", {"settlement_id": s.id})
	assert_eq(int(s.specialists.get("great_general", 0)), 1,
		"a settled Great General uses its own great_general record")

func test_settled_great_yields_flow_into_city_output() -> void:
	# The settled forms carry the reference yields (audit §8): a settled Great
	# Prophet works +2 production / +5 commerce through the normal pipelines.
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	var u = make_gp(gs, "great_prophet", 1, 5, 5)
	assert_true(GreatPeople.perform_action(gs, u, "join_city", {"settlement_id": s.id}),
		"join_city succeeds for a Great Prophet")
	var out: Dictionary = Specialists.settlement_output(gs.db, s)
	assert_eq(int(out["production"]), 2, "a settled Great Prophet yields +2 production")
	assert_eq(int(out["commerce"]), 5, "a settled Great Prophet yields +5 commerce")

func test_settled_greats_bank_no_gp_points() -> void:
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	var u = make_gp(gs, "great_scientist", 1, 5, 5)
	GreatPeople.perform_action(gs, u, "join_city", {"settlement_id": s.id})
	assert_eq(Specialists.settlement_gp_points(gs.db, s), 0,
		"settled Great People bank no further GP points (reference)")

# ── Military instructor (§15.20 / R4) ────────────────────────────────────────

func test_settled_great_general_has_no_yield_standin() -> void:
	# R4 replaced the settled Great General's +2-production stand-in with the
	# military-instructor model: the specialist row carries zero yields and the
	# §15.20 experience value 2 instead.
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	var u = make_gp(gs, "great_general", 1, 5, 5)
	GreatPeople.perform_action(gs, u, "join_city", {"settlement_id": s.id})
	var out: Dictionary = Specialists.settlement_output(gs.db, s)
	for ch in out:
		assert_eq(int(out[ch]), 0,
			"a settled Great General yields nothing (%s) — the +2P stand-in is gone" % ch)
	assert_eq(Specialists.experience(gs.db, "great_general"), 2,
		"the great_general specialist carries the §15.20 experience value 2")

func test_settled_great_general_grants_xp_to_units_built_in_city() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = _city(gs, 1, 5, 5)
	var other = _city(gs, 1, 8, 8)
	var u = make_gp(gs, "great_general", 1, 5, 5)
	GreatPeople.perform_action(gs, u, "join_city", {"settlement_id": s.id})
	TurnEngine._complete_item(gs, s, p, {"type": "unit", "id": "warrior"})
	var trained = gs.units[gs.units.size() - 1]
	assert_eq(trained.experience, 2,
		"a unit completed in the instructor's city starts with +2 XP")
	TurnEngine._complete_item(gs, other, p, {"type": "unit", "id": "warrior"})
	var elsewhere = gs.units[gs.units.size() - 1]
	assert_eq(elsewhere.experience, 0,
		"the instructor teaches only in its own city")

func test_military_instructors_stack_with_buildings_and_each_other() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = _city(gs, 1, 5, 5)
	s.structures.append("barracks")  # land_xp 3
	s.specialists = {"great_general": 2}
	assert_eq(TurnEngine.new_unit_xp(gs, s, p, "warrior"), 3 + 2 * 2,
		"two settled Great Generals add +2 XP each on top of the barracks")

func test_military_instructor_teaches_no_civilians() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = _city(gs, 1, 5, 5)
	s.specialists = {"great_general": 1}
	TurnEngine._complete_item(gs, s, p, {"type": "unit", "id": "worker"})
	var trained = gs.units[gs.units.size() - 1]
	assert_eq(trained.experience, 0, "a non-military unit draws no instructor XP")

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

func test_golden_age_length_scales_with_game_pace() -> void:
	# §15.3 (C3): Golden-Age length uses the pace's own golden_age_scale column
	# (80/100/125/200), not build_scale — base 8 turns becomes 6/8/10/16.
	var gs = make_gs()
	var p = gs.get_player(1)
	var expected := {"quick": 6, "normal": 8, "epic": 10, "marathon": 16}
	for pace_id in expected:
		gs.pace_id = pace_id
		assert_eq(GreatPeople._golden_age_duration(gs, p), expected[pace_id],
			"Golden Age lasts %s turns on %s" % [expected[pace_id], pace_id])

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

func test_great_general_builds_military_academy() -> void:
	# M7: the Military Academy is barred from every city production queue
	# (`not_buildable`), so the Great General's generic build_<structure_id>
	# action is the one way to raise it — and it must keep working.
	var gs = make_gs()
	var s = _city(gs, 1, 5, 5)
	var u = make_gp(gs, "great_general", 1, 5, 5)
	assert_true(GreatPeople.perform_action(gs, u, "build_military_academy",
		{"settlement_id": s.id}), "Build Military Academy succeeds")
	assert_true(s.has_structure("military_academy"),
		"the Military Academy is built in the city")

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
	assert_true(w.has_promotion("leader"),
		"attach also grants the reference Leader marker (gates Tactics/Medic III)")
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
	# 15 XP * (1 + 100%) = 30 == first threshold (A9: reference GG rate +100).
	GreatPeople.award_combat_points(gs, p, 7, 7, 15)
	assert_eq(p.great_generals_produced, 1,
		"Imperialistic leaders reach the threshold with less combat XP")

func test_subsequent_great_general_costs_more() -> void:
	var gs = make_gs()
	var p = gs.get_player(1)
	GreatPeople.award_combat_points(gs, p, 7, 7, gs.db.get_constant("great_general_first_cost", 30))
	assert_true(p.great_general_threshold > gs.db.get_constant("great_general_first_cost", 30),
		"the next Great General costs more than the first")

# ── Special-person production at the city threshold (§6.5/§14.3/§15.18) ──────────

func test_special_person_births_typed_great_person() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5)
	s.special_person_points = 97
	s.specialists = {"scientist": 1}  # +3 points -> 100 == base threshold
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
	s.special_person_points = 60
	s.specialists = {"merchant": 12, "scientist": 3}  # +45 points -> 105
	TurnEngine._special_person_progress(gs, s)
	assert_eq(s.special_persons_produced, 1, "A special person is produced")
	var found := false
	for u in gs.units:
		if u.owner_player_id == 1 and u.unit_type_id == "great_merchant":
			found = true
	assert_true(found, "More merchant than scientist specialists births a Great Merchant")

func test_threshold_escalates_after_own_birth() -> void:
	# §15.18: a birth adds gp_threshold_increase_percent twice (own 50 + own-team
	# 50) to the player's threshold modifier — +100% of base per birth.
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	assert_eq(GreatPeople.special_person_threshold(gs, p), 100,
		"the first Great Person costs the base threshold")
	s.special_person_points = 100
	s.specialists = {"artist": 1}
	TurnEngine._special_person_progress(gs, s)
	assert_eq(p.special_persons_born, 1, "the birth counts on the player")
	assert_eq(GreatPeople.special_person_threshold(gs, p), 200,
		"the next special person costs +100% of base (50 own + 50 same-team)")

func test_threshold_follows_reference_progression() -> void:
	# §15.18 progression: base 100, each birth adds 100 (50 own + 50 same-team)
	# to the modifier, and the increment is multiplied by (births/10 + 1) using
	# the post-birth count — so the 11th GP is the first to cost a doubled step:
	# 100, 200, ..., 1000, then 1200, 1400, ...
	var gs = make_gs()
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.specialists = {"scientist": 1}
	var expected: int = 100
	for n in range(1, 12):
		s.special_person_points = GreatPeople.special_person_threshold(gs, p)
		TurnEngine._special_person_progress(gs, s)
		expected += 100 * (n / 10 + 1)
		assert_eq(GreatPeople.special_person_threshold(gs, p), expected,
			"threshold after birth %d follows the reference progression" % n)
	assert_eq(GreatPeople.special_person_threshold(gs, p), 1400,
		"births 1-9 add +100 each, the 10th and 11th add +200 (acceleration)")

func test_same_team_birth_escalates_teammates_threshold() -> void:
	# §15.18: every living same-team player takes the team share (+50 x its own
	# (births/10 + 1)) when a teammate births a GP; unrelated players are
	# untouched. Humanish teams are alliances.
	var gs = make_gs(3)
	var p1 = gs.get_player(1)
	var p2 = gs.get_player(2)
	var p3 = gs.get_player(3)
	p2.alliance_id = p1.alliance_id  # p2 joins p1's team; p3 stays apart
	var s = make_settlement(gs, 1, 5, 5)
	s.special_person_points = 100
	s.specialists = {"scientist": 1}
	TurnEngine._special_person_progress(gs, s)
	assert_eq(GreatPeople.special_person_threshold(gs, p1), 200,
		"the owner takes the own share and its own team share (+100)")
	assert_eq(GreatPeople.special_person_threshold(gs, p2), 150,
		"a teammate takes only the team share (+50)")
	assert_eq(p2.special_persons_born, 0, "a teammate's own birth count is untouched")
	assert_eq(GreatPeople.special_person_threshold(gs, p3), 100,
		"a player outside the team is unaffected")

func test_per_city_pools_stay_independent() -> void:
	# §15.18 reference split: the pool is per-city — one city's birth never
	# drains another's pool, but the escalated player threshold applies to all.
	var gs = make_gs()
	var sa = make_settlement(gs, 1, 5, 5)
	var sb = make_settlement(gs, 1, 8, 8)
	sa.special_person_points = 100
	sa.specialists = {"scientist": 1}
	sb.special_person_points = 90
	TurnEngine._special_person_progress(gs, sa)
	assert_eq(sa.special_persons_produced, 1, "city A births at the base threshold")
	assert_eq(sb.special_person_points, 90, "city B's pool is untouched by A's birth")
	sb.special_person_points = 150
	sb.specialists = {"scientist": 1}
	TurnEngine._special_person_progress(gs, sb)
	assert_eq(sb.special_persons_produced, 0,
		"city B now needs the escalated player-wide threshold (200)")
	sb.special_person_points = 200
	TurnEngine._special_person_progress(gs, sb)
	assert_eq(sb.special_persons_produced, 1, "city B births once its pool reaches 200")

func test_pool_keeps_remainder_after_birth() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5)
	s.special_person_points = 130
	s.specialists = {"scientist": 1}  # +3 -> 133
	TurnEngine._special_person_progress(gs, s)
	assert_eq(s.special_persons_produced, 1, "one birth per crossing")
	assert_eq(s.special_person_points, 33, "the pool keeps the remainder past the threshold")

func test_threshold_scales_with_pace() -> void:
	# §15.18: the threshold is scaled by the pace great_people_scale
	# (67/100/150/300), applied after the escalation modifier.
	var gs = make_gs()
	var p = gs.get_player(1)
	gs.pace_id = "marathon"
	assert_eq(GreatPeople.special_person_threshold(gs, p), 300,
		"marathon triples the base threshold")
	p.special_person_threshold_mod = 100  # one birth
	assert_eq(GreatPeople.special_person_threshold(gs, p), 600,
		"the modifier applies before the pace scale")
	gs.pace_id = "quick"
	assert_eq(GreatPeople.special_person_threshold(gs, p), 134,
		"quick scales to 67% (200 x 67 / 100, truncating)")

func test_gp_threshold_state_save_roundtrip() -> void:
	# The new Player fields survive a JSON roundtrip as ints (the float gotcha).
	var gs = make_gs()
	var p = gs.get_player(1)
	p.special_persons_born = 3
	p.special_person_threshold_mod = 300
	var s = make_settlement(gs, 1, 5, 5)
	s.special_person_points = 42
	s.special_persons_produced = 3
	var gs2 = GameState.deserialize(JSON.parse(JSON.print(gs.serialize())).result, gs.db)
	var p2 = gs2.get_player(1)
	assert_eq(p2.special_persons_born, 3, "births counter survives the roundtrip")
	assert_eq(p2.special_person_threshold_mod, 300, "threshold modifier survives")
	assert_true(typeof(p2.special_persons_born) == TYPE_INT
		and typeof(p2.special_person_threshold_mod) == TYPE_INT,
		"both fields are int-coerced on load")
	var s2 = gs2.settlements[0]
	assert_eq(s2.special_person_points, 42, "the per-city pool survives")
	assert_eq(s2.special_persons_produced, 3, "the per-city produced tally survives")
	assert_eq(JSON.print(gs2.serialize()), JSON.print(gs.serialize()),
		"a re-save of the loaded state is identical")

func test_pre_r2_save_migrates_player_threshold() -> void:
	# A pre-R2 save has no per-player fields and a per-settlement threshold:
	# the migration rebuilds the birth count from the owned cities' produced
	# tallies and re-derives the escalation (2 x 50 x (k/10 + 1) per birth k),
	# ignoring the obsolete settlement field.
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5)
	s.special_persons_produced = 12
	var d = JSON.parse(JSON.print(gs.serialize())).result
	for pd in d["players"]:
		pd.erase("special_persons_born")
		pd.erase("special_person_threshold_mod")
	for sd in d["settlements"]:
		sd["special_person_threshold"] = 750  # obsolete pre-R2 field
	var gs2 = GameState.deserialize(d, gs.db)
	var p2 = gs2.get_player(1)
	assert_eq(p2.special_persons_born, 12, "births reconstructed from owned cities")
	assert_eq(p2.special_person_threshold_mod, 1500,
		"escalation re-derived: 9 x 100 + 3 x 200 (acceleration from the 10th)")
	assert_eq(GreatPeople.special_person_threshold(gs2, p2), 1600,
		"the migrated player's next GP costs 1600")
	assert_eq(gs2.get_player(2).special_person_threshold_mod, 0,
		"a cityless player migrates to zero births")

func test_working_specialists_bank_three_gp_points_each() -> void:
	# Reference GPP rate (A7): every working specialist banks 3 points per turn.
	var gs = make_gs()
	var s = make_settlement(gs, 1, 5, 5)
	s.specialists = {"scientist": 2, "priest": 1}
	assert_eq(Specialists.settlement_gp_points(gs.db, s), 9,
		"three working specialists bank 3 GP points each")

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
	assert_eq(int(s.specialists.get("great_artist", 0)), 1, "the action ran through the facade")
	assert_eq(gs.get_unit(u.id), null, "the unit was consumed via the command path")
