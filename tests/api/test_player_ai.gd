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

# Exercises the simple computer player (PlayerAI). Covers each decision area —
# research (cheapest), civics (latest), production (cheapest-first rotation),
# units (garrison vs. random) — plus whole-turn determinism through the facade.

# A bare facade armed with a Hooks registry, so end_turn (and thus take_turn) can
# run the turn pipeline against a hand-built state.
func ai_facade(gs):
	var f = bare_facade(gs)
	f._hooks = hooks()
	return f

# ── Economy: research-heavy, but solvency-aware ────────────────────────────────

func test_economy_pours_into_research_when_solvent() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	p.treasury = 1000   # plenty of gold
	PlayerAI.manage_economy(f, 1)
	assert_eq(p.slider_research, 100, "A solvent AI puts everything into research")
	assert_eq(p.slider_finance, 0, "…and nothing into finance")

func test_economy_shifts_to_finance_when_broke() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	p.treasury = 0   # thin reserve
	PlayerAI.manage_economy(f, 1)
	assert_true(p.slider_finance > 0, "A broke AI redirects the economy toward finance")
	assert_eq(p.get_slider_sum(), 100, "Sliders still sum to 100")

# ── Research: cheapest researchable tech ───────────────────────────────────────

func test_research_picks_cheapest_available() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)

	PlayerAI.manage_research(f, 1)

	assert_ne(p.current_research_id, "", "AI should choose something to research")
	# No researchable tech may be cheaper than the one chosen.
	var chosen_cost: int = int(gs.db.technologies[p.current_research_id].get("cost", 0))
	for tech_id in gs.db.technologies:
		if Research.can_research(tech_id, p, gs.db):
			assert_true(int(gs.db.technologies[tech_id].get("cost", 0)) >= chosen_cost,
				"Chosen research must be the cheapest available")

func test_research_only_chooses_researchable() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	PlayerAI.manage_research(f, 1)
	assert_true(Research.can_research(p.current_research_id, p, gs.db),
		"Chosen tech must satisfy its prerequisites")

# ── Civics: latest unlocked policy per category ────────────────────────────────

func test_civics_adopts_latest_with_no_tech() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)

	PlayerAI.manage_civics(f, 1)

	# With no techs, the latest unlocked labor policy is serfdom (tribalism →
	# slavery → serfdom are the tech-free ones, in that order).
	assert_eq(p.policies.get("labor", ""), "serfdom",
		"Latest tech-free labor policy is serfdom")
	assert_eq(p.policies.get("government", ""), "despotism",
		"Only unlocked government policy is despotism")

func test_civics_advances_when_tech_unlocks() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	p.technologies.append("monarchy")

	PlayerAI.manage_civics(f, 1)

	assert_eq(p.policies.get("government", ""), "hereditary_rule",
		"With monarchy known, the latest government policy is hereditary_rule")

# ── Production: every buildable item, cheapest first ───────────────────────────

func test_production_options_role_then_cheapest() -> void:
	# §B3: options are role-ranked first (lower role earlier), then cheapest-first
	# within a role. Verify both invariants on consecutive pairs.
	var gs = make_gs(1)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)

	var opts = PlayerAI._sorted_options(gs, s, p)
	assert_true(opts.size() > 0, "There should be buildable options")
	for i in range(1, opts.size()):
		var prev_role: int = int(opts[i - 1]["role"])
		var role: int = int(opts[i]["role"])
		assert_true(role >= prev_role, "Options must be ordered by ascending role rank")
		if role == prev_role:
			assert_true(int(opts[i]["cost"]) >= int(opts[i - 1]["cost"]),
				"Within a role, options are cheapest-first")

func test_production_fills_empty_queue_cheapest_first() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)

	var opts = PlayerAI._sorted_options(gs, s, p)
	PlayerAI.manage_production(f, 1)

	assert_false(s.production_queue.empty(), "Queue should be populated")
	# The queue is exactly the cheapest-first option list (rotation through all).
	assert_eq(s.production_queue.size(), opts.size(), "Queue lists every possibility")
	for i in range(opts.size()):
		assert_eq(str(s.production_queue[i].get("id", "")), str(opts[i]["id"]),
			"Queue order matches the cheapest-first plan")

func test_production_excludes_great_people() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	# Give the player every tech so Great People would qualify on tech grounds.
	for tech_id in gs.db.technologies:
		p.technologies.append(tech_id)
	var s = make_settlement(gs, 1, 5, 5)
	for opt in PlayerAI._sorted_options(gs, s, p):
		var cls: String = str(gs.db.get_unit(str(opt["id"])).get("classification", ""))
		assert_ne(cls, "great_person", "Great People are never offered as production")

func test_production_leaves_busy_queue_untouched() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var s = make_settlement(gs, 1, 5, 5)
	s.production_queue = [{"type": "unit", "id": "settler"}]

	PlayerAI.manage_production(f, 1)

	assert_eq(s.production_queue.size(), 1, "An in-progress queue is not replanned")
	assert_eq(str(s.production_queue[0]["id"]), "settler", "Existing build is preserved")

func test_production_excludes_already_built_structures() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	s.structures.append("granary")
	for opt in PlayerAI._sorted_options(gs, s, p):
		if str(opt["type"]) == "structure":
			assert_ne(str(opt["id"]), "granary", "Built structures are not re-offered")

# ── Units: garrison vs. random ─────────────────────────────────────────────────

func test_garrison_unit_on_city_fortifies() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 1, 5, 5)
	var u = make_warrior(gs, 1, 5, 5)

	PlayerAI._garrison_unit(f, gs, u, 1)

	assert_true(u.is_fortified, "A unit standing on its own city fortifies in place")

func test_garrison_unit_off_city_moves_toward_it() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 1, 5, 5)
	var u = make_warrior(gs, 1, 9, 9)

	PlayerAI._garrison_unit(f, gs, u, 1)

	assert_true(u.has_moved, "A unit away from its city heads toward it")
	var moved_closer: bool = gs.map.distance(u.x, u.y, 5, 5) < gs.map.distance(9, 9, 5, 5)
	assert_true(moved_closer, "Movement should reduce distance to the city")

func test_nearest_owned_city_picks_closest() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var near = make_settlement(gs, 1, 6, 6)
	make_settlement(gs, 1, 15, 15)
	var u = make_warrior(gs, 1, 5, 5)
	var got = PlayerAI._nearest_owned_city(gs, u, 1)
	assert_eq(got.id, near.id, "Should target the nearest owned settlement")

func test_manage_units_is_deterministic() -> void:
	# Two identical worlds (same seed) must reach an identical state hash after a
	# pass of unit management — proving the AI draws only from the shared gs.rng.
	var hash_a = _run_units_world()
	var hash_b = _run_units_world()
	assert_eq(hash_a, hash_b,
		"Unit management is reproducible for a given seed")

func _run_units_world() -> int:
	var gs = make_gs(1, 31337)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 1, 5, 5)
	make_warrior(gs, 1, 5, 5)
	make_warrior(gs, 1, 7, 7)
	make_unit(gs, "settler", 1, 9, 9)
	make_unit(gs, "worker", 1, 11, 11)
	PlayerAI.manage_units(f, 1)
	return f.state_hash()

# ── Whole turn through the facade ──────────────────────────────────────────────

func test_take_turn_advances_to_next_player() -> void:
	var gs = make_gs(2)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 1, 5, 5)
	make_warrior(gs, 1, 5, 5)

	PlayerAI.take_turn(f, 1)

	assert_eq(gs.current_player_id, 2, "Ending the AI turn passes play to the next player")

func test_take_turn_noop_when_not_active_player() -> void:
	var gs = make_gs(2)
	var f = ai_facade(gs)
	gs.current_player_id = 2          # it is player 2's turn, not player 1's
	make_settlement(gs, 1, 5, 5)

	PlayerAI.take_turn(f, 1)

	assert_eq(gs.current_player_id, 2, "AI does nothing when it is not its turn")

func test_take_turn_is_deterministic() -> void:
	var h1 = _run_full_turn_hash()
	var h2 = _run_full_turn_hash()
	assert_eq(h1, h2, "A full AI turn yields the same state hash for the same seed")

func _run_full_turn_hash() -> int:
	var gs = make_gs(2, 24680)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 1, 5, 5)
	make_warrior(gs, 1, 5, 5)
	make_unit(gs, "settler", 1, 8, 8)
	PlayerAI.take_turn(f, 1)
	return f.state_hash()

# ── §B1 Expansion: settlers seek the best site and found ───────────────────────

func test_best_city_site_avoids_low_yield_region() -> void:
	# West half desert (zero yield), east half grassland. A settler between them
	# should pick a site on the productive (east) side.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	for t in gs.map.all_tiles():
		if t.x <= 10:
			t.terrain_id = "desert"
	var u = make_unit(gs, "settler", 1, 10, 10)

	var site = PlayerAI._best_city_site(gs, u, p)
	assert_not_null(site, "A legal productive site exists to the east")
	assert_true(int(site["x"]) > 10, "Settler favours the grassland (east) side over desert")

func test_best_city_site_never_too_close_to_a_city() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	var u = make_unit(gs, "settler", 1, 6, 6)   # right next to the city
	var min_dist: int = gs.db.get_constant("min_settlement_distance", 3)

	var site = PlayerAI._best_city_site(gs, u, p)
	assert_not_null(site, "There is open land beyond the spacing ring")
	assert_true(gs.map.distance(int(site["x"]), int(site["y"]), 5, 5) >= min_dist,
		"A chosen site always respects minimum settlement spacing")

func test_best_city_site_is_deterministic() -> void:
	var gs = make_gs(1, 777)
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	var u = make_unit(gs, "settler", 1, 11, 11)
	var a = PlayerAI._best_city_site(gs, u, p)
	var b = PlayerAI._best_city_site(gs, u, p)
	assert_not_null(a, "A site is found")
	assert_true(int(a["x"]) == int(b["x"]) and int(a["y"]) == int(b["y"]),
		"Site selection is fully deterministic (no RNG)")

func test_manage_settler_founds_on_arrival() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	# No existing city: the settler's own tile is the best (distance penalty wins),
	# so it founds in place.
	var u = make_unit(gs, "settler", 1, 10, 10)
	var before: int = gs.settlements.size()

	PlayerAI._manage_settler(f, gs, u, p)

	assert_eq(gs.settlements.size(), before + 1, "Settler founds a city on a good site")
	assert_null(gs.get_unit(u.id), "The founding settler is consumed")

# ── §B2 City-count target ──────────────────────────────────────────────────────

func test_wants_settler_below_target_with_open_land() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	make_settlement(gs, 1, 5, 5)
	assert_true(PlayerAI._wants_settler(gs, p),
		"Below the city target with open land, the AI wants a settler")

func test_no_settler_at_city_target() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var target: int = gs.db.get_constant("ai_city_target", 6)
	for i in range(target):
		make_settlement(gs, 1, i * 3, 0)
	assert_false(PlayerAI._wants_settler(gs, p),
		"At the city target the AI stops wanting settlers")

func test_no_settler_when_no_good_land() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	for t in gs.map.all_tiles():
		t.terrain_id = "desert"   # zero-yield everywhere → no positive site
	make_settlement(gs, 1, 5, 5)
	assert_false(PlayerAI._wants_settler(gs, p),
		"With no productive land the AI does not spam settlers")

# ── §B3 Directed production priority ───────────────────────────────────────────

func test_production_defender_first_when_undefended() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)   # no garrison
	var opts = PlayerAI._sorted_options(gs, s, p)
	assert_eq(int(opts[0]["role"]), PlayerAI.ROLE_DEFENDER,
		"An undefended city queues a defender first")
	assert_eq(str(opts[0]["type"]), "unit", "The defender is a unit")
	assert_ne(str(gs.db.get_unit(str(opts[0]["id"])).get("classification", "")), "civilian",
		"The defender is a military unit, not a civilian")

func test_production_economy_first_when_defended() -> void:
	var gs = make_gs(1)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5)
	make_warrior(gs, 1, 5, 5)   # meets the defender floor
	var opts = PlayerAI._sorted_options(gs, s, p)
	assert_eq(int(opts[0]["role"]), PlayerAI.ROLE_ECONOMY,
		"A defended city builds an economy structure before more units")
	assert_eq(str(opts[0]["type"]), "structure", "The first item is a structure")

# ── §B4 Military floor: garrison nearest-first ─────────────────────────────────

func test_garrison_assignment_is_nearest_first() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 1, 5, 5)
	make_settlement(gs, 1, 15, 15)
	var wa = make_warrior(gs, 1, 6, 5)     # adjacent to the first city
	var wb = make_warrior(gs, 1, 15, 14)   # adjacent to the second

	PlayerAI.manage_units(f, 1)

	assert_true(gs.map.distance(wa.x, wa.y, 5, 5) == 0,
		"The unit nearest city A garrisons city A")
	assert_true(gs.map.distance(wb.x, wb.y, 15, 15) == 0,
		"The unit nearest city B garrisons city B")

func test_scarce_garrison_goes_to_nearest_city() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	make_settlement(gs, 1, 5, 5)
	make_settlement(gs, 1, 15, 15)
	var u = make_warrior(gs, 1, 7, 7)   # closer to city A
	var before: int = gs.map.distance(7, 7, 5, 5)

	PlayerAI.manage_units(f, 1)

	assert_true(gs.map.distance(u.x, u.y, 5, 5) < before,
		"A single defender heads for the nearer city")

# ── §B5 Threat response ────────────────────────────────────────────────────────

func test_threat_raises_defender_target() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5)
	assert_eq(PlayerAI._defender_target(gs, s, 1), gs.db.get_constant("ai_min_defenders", 1),
		"No threat → base defender floor")
	make_warrior(gs, -2, 6, 6, true)   # wild stack one tile away
	assert_eq(PlayerAI._defender_target(gs, s, 1),
		gs.db.get_constant("ai_min_defenders", 1) + 1,
		"A nearby hostile stack raises the city's defender target")

func test_no_false_alarm_from_friendly_or_distant() -> void:
	var gs = make_gs(1)
	var s = make_settlement(gs, 1, 5, 5)
	make_warrior(gs, 1, 6, 6)            # friendly, adjacent
	make_warrior(gs, -2, 19, 19, true)   # wild, far outside the radius
	assert_false(PlayerAI._threats_near(gs, s, 1),
		"Neither a friendly neighbour nor a distant stack is a threat")

# ── §B6 Opportunistic offense ──────────────────────────────────────────────────

func test_attacks_weak_adjacent_enemy() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	f._hooks = hooks()
	gs.current_player_id = 1
	var attacker = make_warrior(gs, 1, 5, 5)        # strength 10
	var weak = make_unit(gs, "wolf", -2, 6, 5)      # wild, strength 2

	PlayerAI.manage_units(f, 1)

	var a = gs.get_unit(attacker.id)
	assert_not_null(a, "The strong attacker survives")
	assert_true(a.has_attacked, "A unit that clearly out-powers a neighbour attacks it")
	assert_null(gs.get_unit(weak.id), "The weak defender is destroyed")

func test_holds_against_strong_adjacent_enemy() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	f._hooks = hooks()
	gs.current_player_id = 1
	var attacker = make_warrior(gs, 1, 5, 5)         # strength 10
	var strong = make_unit(gs, "knight", -2, 6, 5)   # wild, strength 10 (no clear edge)

	PlayerAI.manage_units(f, 1)

	var a = gs.get_unit(attacker.id)
	assert_not_null(a, "The attacker is intact")
	assert_false(a.has_attacked, "Without a clear power edge the unit holds")
	assert_not_null(gs.get_unit(strong.id), "The strong enemy is left alone")
