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

# Wild animals (§9.3, provisional): the quiet-phase population. They spawn in the
# dark (outside player sight) on unowned land, hunt weak/unfortified units while
# shunning cities and borders, give only capped lifetime XP, and earn no promotions.

func _make_animal(gs, type_id, x, y):
	var u = make_unit(gs, type_id, -2, x, y)
	u.is_wild = true
	u.is_animal = true
	return u

func _count_animals(gs) -> int:
	var n = 0
	for u in gs.units:
		if u.is_animal:
			n += 1
	return n

# ── Spawning ────────────────────────────────────────────────────────────────────

func test_animals_spawn_in_the_dark_and_on_unowned_land() -> void:
	var gs = make_gs(2, 11)
	gs.difficulty_id = "warlord"        # quiet phase: turn 0, ancient era, no cities
	var seer = make_warrior(gs, 1, 10, 10)  # casts a sight bubble
	gs.map.get_tile(3, 3).owner_player_id = 1  # a patch of borders
	for _i in range(15):
		WildForces.spawn_animals(gs, gs.rng)

	assert_true(_count_animals(gs) > 0, "animals appear during the quiet phase")
	var su = gs.db.get_constant("unit_sight", 2)
	for u in gs.units:
		if not u.is_animal:
			continue
		assert_true(u.is_wild, "an animal is a wild unit")
		assert_eq(u.owner_player_id, -2, "animals belong to the wild faction")
		assert_true(gs.map.manhattan(u.x, u.y, seer.x, seer.y) > su,
			"animals spawn outside the player's sight radius")
		assert_eq(gs.map.get_tile(u.x, u.y).owner_player_id, -1,
			"animals spawn only on unowned land")

func test_lion_is_in_the_animal_spawn_roster() -> void:
	# C7 (§29.1): the Lion joins the wild-animal roster. The spawn picker draws
	# uniformly (through the shared gs.rng) from every classification-"animal"
	# unit, so enough seeded spawns surface all four species and nothing else.
	var gs = make_gs(2, 18)
	for _i in range(40):
		WildForces._spawn_animal_unit(5, 5, gs, gs.rng)
	var seen = {}
	for u in gs.units:
		if not u.is_animal:
			continue
		seen[u.unit_type_id] = true
		assert_eq(u.owner_player_id, -2, "a spawned animal belongs to the wild faction")
		assert_true(u.is_wild, "a spawned animal is a wild unit")
	assert_true(seen.has("lion"), "the lion spawns from the animal roster")
	assert_true(seen.has("wolf") and seen.has("panther") and seen.has("bear"),
		"the existing three animals still spawn")
	assert_eq(seen.size(), 4, "the roster is exactly the four animal species")

func test_animals_yield_to_raiders_once_gates_open() -> void:
	var gs = make_gs(2, 12)
	_make_animal(gs, "wolf", 4, 4)
	_make_animal(gs, "panther", 6, 6)
	_make_animal(gs, "bear", 8, 8)
	# Open the three wild-unit gates so organised raiders take over.
	gs.difficulty_id = "warlord"
	gs.turn_number = 60
	gs.players[0].technologies.append("alphabet")
	make_settlement(gs, 1, 2, 2)
	make_settlement(gs, 1, 2, 17)
	make_settlement(gs, 2, 17, 2)

	var before = _count_animals(gs)
	WildForces.spawn_animals(gs, gs.rng)
	assert_eq(_count_animals(gs), before - 1,
		"once raiders take over, animals are culled one per step and none are added")

# ── Combat limits ───────────────────────────────────────────────────────────────

func test_player_unit_caps_lifetime_xp_from_animals() -> void:
	var gs = make_gs(2, 13)
	var hero = make_warrior(gs, 1, 5, 5)
	var cap = gs.db.get_constant("animal_xp_lifetime_cap", 5)
	# Four animal kills worth 6 XP each: the first grants are clamped to the
	# remaining headroom (cap 5 → granted 5, 0, 0, 0), saturating at the cap.
	for _i in range(4):
		var beast = _make_animal(gs, "wolf", 6, 6)
		var result = {
			"attacker_survived": true, "defender_survived": false,
			"attacker_health_after": 100, "defender_health_after": 0,
			"attacker_withdrew": false, "rounds": 1,
			"attacker_xp_gain": 6, "defender_xp_gain": 0,
			"spillover_damage": 0, "flanking_damage": 0
		}
		CombatApply.apply_unit_result(gs, hero, beast, result, false)
	assert_eq(hero.xp_from_animals, cap, "lifetime animal XP saturates at the cap")
	assert_true(hero.experience <= cap, "no experience is granted past the animal cap")

func test_animals_never_earn_promotions() -> void:
	var gs = make_gs(2, 14)
	var beast = _make_animal(gs, "bear", 5, 5)
	beast.experience = 1000  # far past every threshold
	CombatApply.award_promotions(gs, beast)
	assert_eq(beast.promotions.size(), 0, "animals gain no promotions from combat")
	assert_eq(beast.experience_level, 0, "animals do not advance experience levels")

# ── Behaviour ───────────────────────────────────────────────────────────────────

func test_animal_hunts_an_exposed_weak_unit() -> void:
	var gs = make_gs(2, 15)
	_make_animal(gs, "bear", 5, 5)
	make_unit(gs, "worker", 1, 6, 5)  # adjacent civilian on neutral ground
	WildAI.run(gs, gs.rng)
	var attacked = false
	for ev in gs.pending_wild_events:
		if ev.get("kind") == "combat":
			attacked = true
	assert_true(attacked, "an animal attacks an exposed, weak unit it can reach")

func test_animal_leaves_a_garrisoned_city_alone() -> void:
	var gs = make_gs(2, 16)
	make_settlement(gs, 1, 5, 5)
	var guard = make_warrior(gs, 1, 5, 5)  # standing inside the city
	guard.is_fortified = false
	_make_animal(gs, "bear", 6, 5)
	WildAI.run(gs, gs.rng)
	assert_eq(guard.health, 100, "an animal does not attack a unit inside a city")
	for ev in gs.pending_wild_events:
		assert_ne(ev.get("kind"), "combat", "no combat against a city garrison")

func test_animal_will_not_cross_borders_to_reach_prey() -> void:
	var gs = make_gs(2, 17)
	gs.difficulty_id = "noble"  # animals_enter_borders = false
	_make_animal(gs, "bear", 5, 5)
	# A worker just across a one-tile border the animal cannot enter.
	gs.map.get_tile(6, 5).owner_player_id = 1
	var worker = make_unit(gs, "worker", 1, 6, 5)
	WildAI.run(gs, gs.rng)
	var attacked = false
	for ev in gs.pending_wild_events:
		if ev.get("kind") == "combat":
			attacked = true
	assert_false(attacked,
		"an animal cannot enter borders to reach prey on low difficulty")
	assert_eq(worker.health, 100, "the bordered worker is untouched")
