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

# Wild forces (§9, provisional BtS port). Ambient wild-unit spawning is gated by a
# pace-scaled turn threshold, the current era, and a city-density check, then tops
# each contiguous land area up toward a per-difficulty unowned-tile density target.
# Wild cities (raider camps) have their own later turn gate, a per-area density cap,
# a creation-probability roll, and a minimum distance from civ culture.

# ── Gate-opening helpers ────────────────────────────────────────────────────────

# Open the three ambient-spawn gates on a fresh make_gs() state: warlord difficulty
# (unit divisor 80, turn gate 40), a turn past that gate, a classical-era tech so
# the era gate lifts, and enough civ cities to clear the 1.5x city-density check.
func _open_unit_gates(gs) -> void:
	gs.difficulty_id = "warlord"
	gs.turn_number = 60
	gs.players[0].technologies.append("alphabet")  # classical → era gate lifts
	make_settlement(gs, 1, 2, 2)
	make_settlement(gs, 1, 2, 17)
	make_settlement(gs, 2, 17, 2)

func _wild_count(gs) -> int:
	var n = 0
	for u in gs.units:
		if u.is_wild:
			n += 1
	return n

func _camp_count(gs) -> int:
	var n = 0
	for s in gs.settlements:
		if s.owner_player_id == -2:
			n += 1
	return n

# ── Ambient unit spawning ───────────────────────────────────────────────────────

func test_no_wild_units_before_creation_turn_gate() -> void:
	var gs = make_gs(2, 7)
	_open_unit_gates(gs)
	gs.turn_number = 39  # warlord gate is 40
	WildForces.spawn_turn(gs, gs.rng)
	assert_eq(_wild_count(gs), 0, "No wild units may spawn before the turn gate")

	gs.turn_number = 40
	WildForces.spawn_turn(gs, gs.rng)
	assert_true(_wild_count(gs) > 0, "Wild units spawn once the turn gate is reached")

func test_creation_turn_gate_scales_with_game_pace() -> void:
	var gs = make_gs(2, 7)
	_open_unit_gates(gs)
	gs.pace_id = "marathon"  # 40-turn gate becomes 40 * 300/100 = 120
	gs.turn_number = 60      # past the normal gate, well short of the marathon one
	WildForces.spawn_turn(gs, gs.rng)
	assert_eq(_wild_count(gs), 0, "Marathon stretches the turn gate; turn 60 is too early")

func test_era_gate_suppresses_wild_units_in_starting_era() -> void:
	var gs = make_gs(2, 7)
	_open_unit_gates(gs)
	gs.players[0].technologies = []  # back to ancient → no_wild_units flag applies
	WildForces.spawn_turn(gs, gs.rng)
	assert_eq(_wild_count(gs), 0, "Ancient-era no_wild_units flag blocks organised raiders")

	gs.players[0].technologies.append("alphabet")  # classical lifts the flag
	WildForces.spawn_turn(gs, gs.rng)
	assert_true(_wild_count(gs) > 0, "Reaching the classical era opens wild-unit spawning")

func test_city_density_gate_holds_until_world_settles() -> void:
	var gs = make_gs(2, 7)
	gs.difficulty_id = "warlord"
	gs.turn_number = 60
	gs.players[0].technologies.append("alphabet")
	# Two living civs need >= 3 civ cities (1.5x); start with only two.
	make_settlement(gs, 1, 2, 2)
	make_settlement(gs, 2, 17, 2)
	WildForces.spawn_turn(gs, gs.rng)
	assert_eq(_wild_count(gs), 0, "Below 1.5x cities-per-civ, wild units stay home")

	make_settlement(gs, 1, 2, 17)  # third city clears the ratio
	WildForces.spawn_turn(gs, gs.rng)
	assert_true(_wild_count(gs) > 0, "Once the world fills in, wild units appear")

func test_density_converges_to_unowned_tile_target() -> void:
	# 20x20 all-land map, warlord divisor 80 → target = unowned/80 = 5; the /4+1
	# top-up converges there and the global cap (target+1) is never exceeded.
	var gs = make_gs(2, 7)
	_open_unit_gates(gs)
	var divisor = gs.db.get_difficulty("warlord").get("unowned_tiles_per_wild_unit")
	var unowned = 0
	for t in gs.map.all_tiles():
		if t.owner_player_id < 0:
			unowned += 1
	var target = unowned / int(divisor)
	for _i in range(10):
		WildForces.spawn_turn(gs, gs.rng)
	assert_eq(_wild_count(gs), target,
		"Wild density converges to one unit per %d unowned tiles" % divisor)
	assert_true(_wild_count(gs) <= target + 1, "Global cap is target + 1")

# ── Wild-city (raider camp) spawning ────────────────────────────────────────────

func test_wild_city_respects_its_turn_gate() -> void:
	var gs = make_gs(2, 7)
	gs.difficulty_id = "warlord"   # city gate is 45
	gs.turn_number = 44
	for _i in range(50):           # many rolls; none should land before the gate
		WildForces.spawn_raider_settlement(gs, gs.rng)
	assert_eq(_camp_count(gs), 0, "No raider camp before the city turn gate")

func test_wild_city_density_cap_and_distance_from_culture() -> void:
	var gs = make_gs(2, 7)
	gs.difficulty_id = "warlord"   # city divisor 140, prob 5%
	gs.turn_number = 60
	var civ = make_settlement(gs, 1, 5, 5)
	var unowned = 0
	for t in gs.map.all_tiles():
		if t.owner_player_id < 0:
			unowned += 1
	var cap = unowned / int(gs.db.get_difficulty("warlord").get("unowned_tiles_per_wild_city"))
	for _i in range(400):          # enough rolls to hit the 5% chance repeatedly
		WildForces.spawn_raider_settlement(gs, gs.rng)
	var camps = _camp_count(gs)
	assert_true(camps > 0, "Raider camps do eventually spawn past the gate")
	assert_true(camps <= cap, "Camp count (%d) stays within the density cap (%d)" % [camps, cap])
	var min_dist = gs.db.get_constant("wild_city_min_distance", 6)
	for s in gs.settlements:
		if s.owner_player_id == -2:
			assert_true(gs.map.distance(s.x, s.y, civ.x, civ.y) >= min_dist,
				"Camp keeps >= %d tiles from civ culture" % min_dist)

func test_raider_camp_claims_cultural_border() -> void:
	# A spawned Raider Camp owns its own tile and an immediate ring of tiles as the
	# wild owner (-2), so it shows cultural borders like any civ city (§4.7). Wild
	# forces have no turn slot, so this founding claim is their whole border.
	var gs = make_gs(2, 7)
	gs.difficulty_id = "warlord"
	gs.turn_number = 60
	# Found a camp far from anything; place it directly so the claim is deterministic.
	WildForces._spawn_raider_settlement(10, 10, gs)
	var camp = null
	for s in gs.settlements:
		if s.owner_player_id == -2:
			camp = s
			break
	assert_not_null(camp, "A raider camp was placed")
	# Its own tile is owned by the wild owner.
	assert_eq(gs.map.get_tile(camp.x, camp.y).owner_player_id, -2,
		"Camp centre tile is owned by the wild owner (-2)")
	# The immediate ring (radius 1) is claimed too — a visible border region.
	var radius = gs.db.get_constant("wild_camp_claim_radius", 1)
	var wild_owned = 0
	for t in gs.map.tiles_in_range(camp.x, camp.y, radius):
		if t.owner_player_id == -2:
			wild_owned += 1
	assert_true(wild_owned > 1,
		"Camp claims a ring of tiles, not just its centre (got %d)" % wild_owned)
	# Tiles well outside the claim radius stay unowned.
	assert_eq(gs.map.get_tile(camp.x, camp.y + radius + 2).owner_player_id, -1,
		"Tiles outside the wild claim radius stay unowned (-1)")

# ── Camp garrison (WildAI keeps a defender home) ────────────────────────────────

# Place a raider camp at (cx, cy) with its claimed border, returning the Settlement.
func _make_camp(gs, cx, cy):
	WildForces._spawn_raider_settlement(cx, cy, gs)
	for s in gs.settlements:
		if s.owner_player_id == -2 and s.x == cx and s.y == cy:
			return s
	return null

# Count the wild (non-animal) units currently standing on (x, y).
func _wild_on_tile(gs, x, y) -> int:
	var n = 0
	for u in gs.units:
		if u.is_wild and not u.is_animal and u.x == x and u.y == y:
			n += 1
	return n

func test_camp_with_two_units_keeps_one_garrisoned() -> void:
	# A camp holding two wild units, both ordered to march out, must keep at least
	# one on the camp tile after a WildAI.run — the camp is never left undefended.
	var gs = make_gs(2, 7)
	var camp = _make_camp(gs, 10, 10)
	var a = make_warrior(gs, -2, camp.x, camp.y, true)
	var b = make_warrior(gs, -2, camp.x, camp.y, true)
	# Order both toward a far corner so, absent the garrison rule, both would leave.
	a.goto_x = 0; a.goto_y = 0
	b.goto_x = 0; b.goto_y = 0
	WildAI.run(gs, gs.rng)
	assert_true(_wild_on_tile(gs, camp.x, camp.y) >= 1,
		"A camp with 2+ units keeps at least one defender on the camp tile")

func test_camp_garrison_lets_the_others_sortie() -> void:
	# Of three units in a camp (min_garrison 1), exactly one stays and two march out.
	var gs = make_gs(2, 7)
	var camp = _make_camp(gs, 10, 10)
	for _i in range(3):
		var u = make_warrior(gs, -2, camp.x, camp.y, true)
		u.goto_x = 0; u.goto_y = 0
	var min_garrison = gs.db.get_constant("wild_camp_min_garrison", 1)
	WildAI.run(gs, gs.rng)
	assert_eq(_wild_on_tile(gs, camp.x, camp.y), min_garrison,
		"Exactly the garrison floor stays; the rest sortie")

func test_lone_camp_unit_may_sortie() -> void:
	# A camp with only one unit (the garrison floor) lets it leave — holding the last
	# unit home would starve the raiding a freshly-mustered wave exists to launch.
	var gs = make_gs(2, 7)
	var camp = _make_camp(gs, 10, 10)
	var only = make_warrior(gs, -2, camp.x, camp.y, true)
	only.goto_x = 0; only.goto_y = 0
	WildAI.run(gs, gs.rng)
	assert_eq(_wild_on_tile(gs, camp.x, camp.y), 0,
		"A camp with a single unit may send it out to raid")

func test_camp_garrison_is_deterministic() -> void:
	# Same seed and setup → the same unit is held and the same units move.
	var positions = []
	for _run in range(2):
		var gs = make_gs(2, 7)
		var camp = _make_camp(gs, 10, 10)
		for _i in range(3):
			var u = make_warrior(gs, -2, camp.x, camp.y, true)
			u.goto_x = 0; u.goto_y = 0
		WildAI.run(gs, gs.rng)
		var snap = []
		for u in gs.units:
			if u.is_wild and not u.is_animal:
				snap.append([u.id, u.x, u.y])
		snap.sort()
		positions.append(snap)
	assert_eq(positions[0], positions[1],
		"Same seed → identical garrison/sortie outcome")

func test_wild_units_are_capped_over_many_turns() -> void:
	var facade = setup_facade(4242, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}],
		["time"])
	var gs = facade.get_state()
	for _t in range(20):
		for p in gs.players:
			gs.current_player_id = p.id
			facade.apply_command(Commands.end_turn(p.id))

	var land = 0
	for tile in gs.map.all_tiles():
		if gs.db.get_terrain(tile.terrain_id).get("domain", "land") == "land":
			land += 1
	var wild = 0
	for u in gs.units:
		if u.is_wild and not u.is_animal:  # raiders only; animals have their own cap (§9.3)
			wild += 1
	var cap = land / int(gs.db.constants.get("wild_land_per_unit", 80))
	assert_true(wild <= cap + 1,
		"Wild raiders (%d) must stay near the land-based cap (%d), not flood" % [wild, cap])
