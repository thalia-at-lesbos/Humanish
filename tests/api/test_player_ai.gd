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

# ── §B-units: worker construction automation ──────────────────────────────────

func test_worker_improves_resource_on_its_tile() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	gs.get_player(1).technologies = ["animal_husbandry"]
	var t = gs.map.get_tile(5, 5)
	t.terrain_id = "grassland"; t.resource_id = "cow"; t.owner_player_id = 1
	var w = make_unit(gs, "worker", 1, 5, 5)
	PlayerAI._manage_worker(f, gs, w, 1)
	assert_eq(w.building_improvement, "pasture",
		"AI worker improves a visible resource on its own tile first (over a road)")

func test_worker_does_not_reissue_an_active_build() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var w = make_unit(gs, "worker", 1, 5, 5)
	w.building_improvement = "pasture"
	w.build_turns_left = 3
	PlayerAI._manage_worker(f, gs, w, 1)
	assert_eq(w.building_improvement, "pasture", "An in-progress build is kept")
	assert_eq(w.build_turns_left, 3,
		"The AI must not restart an active build — that would reset its progress")

func test_worker_moves_toward_nearest_resource() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	gs.get_player(1).technologies = ["animal_husbandry"]
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var rt = gs.map.get_tile(9, 5)
	rt.resource_id = "cow"; rt.owner_player_id = 1
	var w = make_unit(gs, "worker", 1, 5, 5)
	PlayerAI._manage_worker(f, gs, w, 1)
	assert_true(w.has_moved, "Worker heads for a resource it cannot yet reach")
	assert_true(gs.map.distance(w.x, w.y, 9, 5) < gs.map.distance(5, 5, 9, 5),
		"Movement reduces the distance to the resource tile")

func test_worker_roads_territory_when_no_resources() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	gs.map.get_tile(5, 5).owner_player_id = 1   # owned, bare, flat
	var w = make_unit(gs, "worker", 1, 5, 5)
	PlayerAI._manage_worker(f, gs, w, 1)
	assert_eq(w.building_improvement, "road",
		"With no resources left, the worker roads bare tiles inside our territory")

func test_worker_sleeps_when_no_work() -> void:
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	# No owned territory at all → nothing to improve or road.
	var w = make_unit(gs, "worker", 1, 5, 5)
	PlayerAI._manage_worker(f, gs, w, 1)
	assert_true(w.is_sleeping, "An AI worker with no territory to work sleeps")

func test_ai_worker_build_completes_over_turns() -> void:
	# End-to-end: an AI worker on an owned resource tile builds the improvement
	# and — because the AI no longer re-issues the order each turn — it completes.
	var gs = make_gs(1)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	gs.get_player(1).is_ai = true
	gs.get_player(1).technologies = ["animal_husbandry"]
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	make_settlement(gs, 1, 10, 10, 3)             # spreads culture over the resource
	var rt = gs.map.get_tile(11, 10)
	rt.resource_id = "cow"; rt.owner_player_id = 1
	make_unit(gs, "worker", 1, 11, 10)
	var built := false
	for _i in range(12):
		PlayerAI.take_turn(f, 1)
		if gs.map.get_tile(11, 10).improvement_id == "pasture":
			built = true
			break
	assert_true(built,
		"An AI-driven worker's build finishes and places the improvement over turns")

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

# ── §C2 Focus profile ──────────────────────────────────────────────────────────

func test_focus_profile_sums_two_traits() -> void:
	# Washington = expansive (expand 2, economy 1) + charismatic (expand 1,
	# military 1) → an expand-heavy profile.
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.traits = ["expansive", "charismatic"]
	var prof = PlayerAI._focus_profile(p, gs.db)
	assert_eq(int(prof["expand"]), 3, "expand sums across both traits")
	assert_eq(int(prof["military"]), 1, "military comes from charismatic")
	assert_eq(int(prof["economy"]), 1, "economy comes from expansive")
	assert_eq(int(prof["science"]), 0, "neither trait is science")
	# Expand is the strictly dominant axis.
	for axis in ["military", "economy", "science"]:
		assert_true(int(prof["expand"]) > int(prof[axis]),
			"Washington leans expansionist over " + axis)

func test_focus_profile_single_trait_matches_block() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.traits = ["financial"]
	var prof = PlayerAI._focus_profile(p, gs.db)
	var block: Dictionary = gs.db.get_trait("financial").get("ai_focus", {})
	for axis in ["expand", "military", "economy", "science"]:
		assert_eq(int(prof[axis]), int(block.get(axis, 0)),
			"A single-trait profile equals that trait's ai_focus on " + axis)

func test_focus_profile_traitless_is_zero() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.traits = []
	var prof = PlayerAI._focus_profile(p, gs.db)
	for axis in ["expand", "military", "economy", "science"]:
		assert_eq(int(prof[axis]), 0,
			"A traitless leader has a flat (Phase-B baseline) profile on " + axis)

# ── §C3 Production order biased by focus ───────────────────────────────────────

# The first economy structure a defended city queues: index of the leading
# `structure` option (role ECONOMY) in the focus-ordered plan.
func _first_structure_axis(gs, s, p) -> String:
	for opt in PlayerAI._sorted_options(gs, s, p):
		if str(opt["type"]) == "structure":
			return PlayerAI._structure_axis(gs.db.get_structure(str(opt["id"])))
	return ""

func test_production_order_differs_by_focus() -> void:
	# Same defended city; a science leader leads its structures with a research
	# building, a military leader with a defensive/training one. Give every tech so
	# the full structure menu is on the table for both.
	var gs = make_gs(2)
	gs.current_player_id = 1
	var sci = gs.get_player(1)
	var mil = gs.get_player(2)
	for tech_id in gs.db.technologies:
		sci.technologies.append(tech_id)
		mil.technologies.append(tech_id)
	sci.traits = ["philosophical"]   # science 3
	mil.traits = ["aggressive"]      # military 3
	var ss = make_settlement(gs, 1, 5, 5)
	make_warrior(gs, 1, 5, 5)        # meets the defender floor → economy role leads
	var ms = make_settlement(gs, 2, 15, 15)
	make_warrior(gs, 2, 15, 15)

	assert_eq(_first_structure_axis(gs, ss, sci), "science",
		"A philosophical leader fronts its build list with a science building")
	assert_eq(_first_structure_axis(gs, ms, mil), "military",
		"An aggressive leader fronts its build list with a military building")

func test_focus_bias_respects_defender_floor() -> void:
	# Even a science-heavy leader still queues the garrison defender first in an
	# undefended city — focus sits below the role floor.
	var gs = make_gs(1)
	gs.current_player_id = 1
	var p = gs.get_player(1)
	p.traits = ["philosophical"]
	var s = make_settlement(gs, 1, 5, 5)   # undefended
	var opts = PlayerAI._sorted_options(gs, s, p)
	assert_eq(int(opts[0]["role"]), PlayerAI.ROLE_DEFENDER,
		"The defender floor outranks personality focus")
	assert_eq(str(opts[0]["type"]), "unit", "The first item is the garrison unit")

# ── §C4 Sliders / target / floor / margin biased by focus ──────────────────────

func test_science_leader_runs_higher_research_than_economy_leader() -> void:
	# Both solvent. The economy leader runs a standing finance share; the science
	# leader stays at full research. Compare the resulting research sliders.
	var gs = make_gs(2)
	var f = ai_facade(gs)
	gs.current_player_id = 1
	var eco = gs.get_player(1)
	eco.traits = ["financial"]     # economy 3
	eco.treasury = 1000
	PlayerAI.manage_economy(f, 1)

	gs.current_player_id = 2
	var sci = gs.get_player(2)
	sci.traits = ["philosophical"] # science 3
	sci.treasury = 1000
	PlayerAI.manage_economy(f, 2)

	assert_true(sci.slider_research > eco.slider_research,
		"A science leader runs a higher research slider than an economy leader")
	assert_eq(sci.slider_research, 100, "A science leader pours everything into research")
	assert_true(eco.slider_finance > 0, "An economy leader keeps a standing finance share")
	assert_eq(eco.get_slider_sum(), 100, "Sliders still sum to 100")

func test_expand_focus_raises_city_target() -> void:
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var base: int = gs.db.get_constant("ai_city_target", 6)
	p.traits = []
	assert_eq(PlayerAI._city_target(p, gs.db), base, "A traitless leader holds the base target")
	p.traits = ["imperialistic"]   # expand 3
	assert_true(PlayerAI._city_target(p, gs.db) > base,
		"An expansionist leader targets more cities than the baseline")

func test_military_focus_raises_defender_floor() -> void:
	var gs = make_gs(2)
	var sa = make_settlement(gs, 1, 5, 5)
	var sb = make_settlement(gs, 2, 15, 15)
	gs.get_player(1).traits = []                # baseline
	gs.get_player(2).traits = ["aggressive"]    # military 3
	var base: int = PlayerAI._defender_target(gs, sa, 1)
	assert_eq(base, gs.db.get_constant("ai_min_defenders", 1),
		"A peaceful leader holds the base garrison floor")
	assert_true(PlayerAI._defender_target(gs, sb, 2) > base,
		"A military leader holds a higher garrison floor")

func test_military_focus_lowers_attack_margin() -> void:
	var gs = make_gs(2)
	var peaceful = gs.get_player(1)
	peaceful.traits = []
	var warlike = gs.get_player(2)
	warlike.traits = ["aggressive"]   # military 3
	var base: int = gs.db.get_constant("ai_attack_margin", 20)
	assert_eq(PlayerAI._attack_margin(peaceful, gs.db), base,
		"A peaceful leader needs the full power edge to attack")
	assert_true(PlayerAI._attack_margin(warlike, gs.db) < base,
		"A military leader attacks on a slimmer power edge")
	assert_true(PlayerAI._attack_margin(warlike, gs.db) >= 0,
		"The attack margin never goes negative")

# ── §C5 Personality regression gate ────────────────────────────────────────────

func _owned_cities(gs, pid: int) -> int:
	var n: int = 0
	for s in gs.settlements:
		if s.owner_player_id == pid:
			n += 1
	return n

func _has_garrison(gs, pid: int) -> bool:
	for s in gs.settlements:
		if s.owner_player_id != pid:
			continue
		for u in gs.units:
			if u.owner_player_id == pid and u.x == s.x and u.y == s.y \
					and PlayerAI._is_military_unit(gs.db.get_unit(u.unit_type_id)):
				return true
	return false

# Two contrasting leaders — a peaceful science empire and a militaristic
# expansionist — play side by side for an opening stretch. The "soft bias, not
# gates" guarantee: neither self-destructs, and even the peaceful leader still
# founds a city and keeps a garrison (focus tilts emphasis above the Phase-B
# floor; it never zeroes a role). The *full* all-AI win gate is the manual
# `tests/manual/ai_full_game_smoke.gd`, which already pits distinct societies —
# this fast CI test only guards the personality spot-checks.
const PERSONALITY_TURNS: int = 16

func test_contrasting_leaders_play_rounded_game() -> void:
	var players = [
		{"name": "Gandhi", "leader_id": "gandhi", "traits": ["philosophical", "spiritual"],
			"starting_gold": 100, "starting_units": ["settler", "warrior"], "is_ai": true},
		{"name": "Genghis", "leader_id": "genghis_khan", "traits": ["aggressive", "imperialistic"],
			"starting_gold": 100, "starting_units": ["settler", "warrior"], "is_ai": true},
	]
	var f = setup_facade(20260612, "small", players, ["last_standing", "time"], "warlord")

	var peak_cities := {1: 0, 2: 0}
	var ever_garrison := {1: false, 2: false}
	var first_elim := {1: -1, 2: -1}
	var gs = f.get_state()
	while gs.winning_alliance_id < 0 and gs.turn_number < PERSONALITY_TURNS:
		for pid in [1, 2]:
			if gs.get_player(pid).is_eliminated and first_elim[pid] < 0:
				first_elim[pid] = gs.turn_number
			peak_cities[pid] = max(peak_cities[pid], _owned_cities(gs, pid))
			if _has_garrison(gs, pid):
				ever_garrison[pid] = true
		PlayerAI.take_turn(f, gs.current_player_id)
		gs = f.get_state()

	# Nobody self-destructs in the opening — any elimination is a real conquest.
	for pid in [1, 2]:
		assert_true(int(first_elim[pid]) < 0 or int(first_elim[pid]) >= 5,
			"Player %d survives past the opening (no early self-destruct)" % pid)
	# Both leaders settle; even the peaceful (science) leader founds and garrisons.
	assert_true(int(peak_cities[1]) >= 1, "A peaceful (science) leader founds a city")
	assert_true(int(peak_cities[2]) >= 1, "A militaristic leader founds a city")
	assert_true(bool(ever_garrison[1]),
		"Even a peaceful leader keeps at least one garrison (soft bias, not a gate)")

# ── §7 Diplomacy: attitude-driven deals & war (Phase 7) ───────────────────────
#
# manage_diplomacy answers standing trade offers and picks wars by attitude. Player
# 1 is the deciding AI (alliance 1); player 2 is the proposer/rival (alliance 2).

# Seed a trade offer from alliance 2 to alliance 1 and return its id.
func _seed_offer(gs, give, receive, peace = false):
	var t = {
		"id": gs.next_trade_id(), "proposer_player_id": 2,
		"from_alliance": 2, "to_alliance": 1,
		"give": give, "receive": receive, "peace": peace,
		"expires_turn": gs.turn_number + 20
	}
	gs.get_alliance(2).pending_trades.append(t)
	return int(t["id"])

func test_ai_accepts_a_net_positive_offer() -> void:
	var gs = make_gs(2)
	gs.get_player(2).treasury = 100
	var f = ai_facade(gs)
	gs.current_player_id = 1
	_seed_offer(gs, {"gold": 50}, {})  # AI gets 50 for nothing
	PlayerAI.manage_diplomacy(f, 1)
	assert_eq(gs.get_alliance(2).pending_trades.size(), 0, "the offer is answered")
	assert_eq(gs.get_player(1).treasury, 50, "AI accepted the free gold")

func test_ai_rejects_a_net_negative_offer() -> void:
	var gs = make_gs(2)
	gs.get_player(1).treasury = 100
	var f = ai_facade(gs)
	gs.current_player_id = 1
	_seed_offer(gs, {}, {"gold": 40})  # AI gives 40 for nothing
	PlayerAI.manage_diplomacy(f, 1)
	assert_eq(gs.get_alliance(2).pending_trades.size(), 0, "the offer is cleared")
	assert_eq(gs.get_player(1).treasury, 100, "AI kept its gold (rejected)")

func test_ai_refuses_a_good_offer_from_a_loathed_rival() -> void:
	var gs = make_gs(2)
	gs.get_player(2).treasury = 100
	# Sour the AI's attitude toward player 2 to Furious (a razed city, -40).
	Diplomacy.record(gs, gs.db, 1, 2, "razed_city")
	assert_eq(Diplomacy.attitude_level(gs, gs.db, 1, 2), Diplomacy.FURIOUS,
		"precondition: the AI loathes player 2")
	var f = ai_facade(gs)
	gs.current_player_id = 1
	_seed_offer(gs, {"gold": 50}, {})  # objectively great, but from a hated rival
	PlayerAI.manage_diplomacy(f, 1)
	assert_eq(gs.get_player(1).treasury, 0, "AI refuses to deal with a loathed rival")

func test_ai_declares_war_on_loathed_weaker_rival() -> void:
	var gs = make_gs(2)
	make_warrior(gs, 1, 5, 5)   # AI has an army; the rival has none
	gs.get_alliance(1).contacts.append(2)
	Diplomacy.record(gs, gs.db, 1, 2, "razed_city")  # Furious
	var f = ai_facade(gs)
	gs.current_player_id = 1
	PlayerAI.manage_diplomacy(f, 1)
	assert_true(gs.are_at_war(1, 2),
		"a Furious AI with a military edge declares war")

func test_ai_holds_peace_with_neutral_rival() -> void:
	var gs = make_gs(2)
	make_warrior(gs, 1, 5, 5)
	gs.get_alliance(1).contacts.append(2)
	# No grievance: attitude is neutral (Cautious), so no war.
	var f = ai_facade(gs)
	gs.current_player_id = 1
	PlayerAI.manage_diplomacy(f, 1)
	assert_false(gs.are_at_war(1, 2),
		"a neutral AI does not start a war even when stronger")

func test_ai_capitulates_when_crushed() -> void:
	# Player 2's AI alliance is at war with a far stronger player 1 and capitulates.
	var gs = make_gs(2)
	for i in range(4):
		make_warrior(gs, 1, 2 + i, 1)   # overlord: four warriors
	make_warrior(gs, 2, 5, 5)            # sub: one warrior (crushed)
	gs.get_alliance(1).at_war_with = [2]
	gs.get_alliance(2).at_war_with = [1]
	gs.get_alliance(1).contacts.append(2)
	gs.get_alliance(2).contacts.append(1)
	var f = ai_facade(gs)
	gs.current_player_id = 2
	PlayerAI.manage_diplomacy(f, 2)
	assert_eq(gs.get_alliance(2).is_subordinate_to, 1,
		"a crushed AI alliance capitulates to its conqueror")
	assert_false(gs.are_at_war(1, 2), "capitulation ends the war")

func test_ai_does_not_capitulate_when_holding() -> void:
	var gs = make_gs(2)
	for i in range(2):
		make_warrior(gs, 1, 2 + i, 1)
	make_warrior(gs, 2, 5, 5)
	make_warrior(gs, 2, 6, 5)            # ~50% — not crushed
	gs.get_alliance(1).at_war_with = [2]
	gs.get_alliance(2).at_war_with = [1]
	gs.get_alliance(2).contacts.append(1)
	var f = ai_facade(gs)
	gs.current_player_id = 2
	PlayerAI.manage_diplomacy(f, 2)
	assert_eq(gs.get_alliance(2).is_subordinate_to, -1,
		"an AI that is merely losing does not capitulate")

func test_assembly_vote_backs_a_liked_candidate() -> void:
	# elect_resident with a rival candidate: a Pleased+ attitude flips Nay → Yea.
	var gs = make_gs(3)
	gs.assembly = {
		"kind": "religious", "resident_player_id": -1,
		"pending": {
			"resolution_id": "elect_pope", "candidate_player_id": 2,
			"votes": {}
		}
	}
	# Make elect_pope an elect_resident motion in this db.
	gs.db.resolutions["elect_pope"] = {"id": "elect_pope", "effect": "elect_resident"}
	# Disliked first: a fresh grievance keeps player 1 below Pleased toward 2.
	Diplomacy.record(gs, gs.db, 1, 2, "declared_war")
	assert_eq(Assembly.ai_vote(gs, 1), Assembly.VOTE_NAY,
		"a soured member votes the rival candidate down")
	# Now warm the relationship past Pleased and re-vote.
	gs.get_player(1).diplo_memory.clear()
	for _i in range(6):
		Diplomacy.record(gs, gs.db, 1, 2, "gave_gift")  # +10 each → Friendly
	assert_eq(Assembly.ai_vote(gs, 1), Assembly.VOTE_YEA,
		"a member that likes the candidate backs it")
