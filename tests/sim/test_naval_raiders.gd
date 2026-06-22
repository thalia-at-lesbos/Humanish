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

# Naval raiders (§9.4, provisional): sea-domain wild forces that spawn on open water
# (gated like land raiders, but only once a player can sail) and patrol at random,
# attacking player units they bump into.

# Paint the right half of the map (x >= 10) as ocean.
func _add_ocean(gs) -> void:
	for tile in gs.map.all_tiles():
		if tile.x >= 10:
			tile.terrain_id = "ocean"

# Open the three wild-unit gates and unlock sailing on the leading player.
func _open_naval(gs) -> void:
	gs.difficulty_id = "warlord"
	gs.turn_number = 60
	gs.players[0].technologies.append("alphabet")  # classical era → era gate lifts
	gs.players[0].technologies.append("sailing")   # unlock the Galley
	make_settlement(gs, 1, 2, 2)
	make_settlement(gs, 1, 2, 17)
	make_settlement(gs, 2, 17, 2)

func _count_naval(gs) -> int:
	var n = 0
	for u in gs.units:
		if u.is_wild and gs.db.get_unit(u.unit_type_id).get("domain", "land") == "sea":
			n += 1
	return n

# ── Spawning ────────────────────────────────────────────────────────────────────

func test_no_naval_raiders_until_someone_can_sail() -> void:
	var gs = make_gs(2, 21)
	_add_ocean(gs)
	gs.difficulty_id = "warlord"
	gs.turn_number = 60
	gs.players[0].technologies.append("alphabet")
	make_settlement(gs, 1, 2, 2)
	make_settlement(gs, 1, 2, 17)
	make_settlement(gs, 2, 17, 2)
	# No naval tech anywhere → empty seas regardless of the gates.
	gs.db.difficulties["warlord"]["unowned_water_tiles_per_wild_unit"] = 20
	for _i in range(5):
		WildForces.spawn_naval(gs, gs.rng)
	assert_eq(_count_naval(gs), 0, "the seas stay empty until a player can sail")

func test_naval_raiders_spawn_on_open_water() -> void:
	var gs = make_gs(2, 22)
	_add_ocean(gs)
	_open_naval(gs)
	# Shrink the (very large) water divisor so the small test ocean has a target.
	gs.db.difficulties["warlord"]["unowned_water_tiles_per_wild_unit"] = 20
	for _i in range(10):
		WildForces.spawn_naval(gs, gs.rng)
	assert_true(_count_naval(gs) > 0, "naval raiders appear on open water once sailing exists")
	for u in gs.units:
		if u.is_wild and gs.db.get_unit(u.unit_type_id).get("domain", "land") == "sea":
			assert_eq(u.owner_player_id, -2, "a naval raider belongs to the wild faction")
			assert_false(u.is_animal, "a naval raider is not an animal")
			assert_eq(gs.db.get_terrain(gs.map.get_tile(u.x, u.y).terrain_id).get("domain"),
				"sea", "a naval raider spawns on a sea tile")

# The sailing gate is specifically the `sailing` tech: it is the only tech a player
# needs for the cheapest naval raider stock (the Galley), so granting exactly sailing
# (the era gate already lifted) is what opens the seas, and the raider spawned is the
# Galley — an owner-agnostic, water-domain barbarian unit.
func test_sailing_tech_specifically_opens_the_seas_with_a_galley() -> void:
	var gs = make_gs(2, 25)
	_add_ocean(gs)
	gs.difficulty_id = "warlord"
	gs.turn_number = 60
	gs.players[0].technologies.append("alphabet")  # classical era → era gate lifts
	make_settlement(gs, 1, 2, 2)
	make_settlement(gs, 1, 2, 17)
	make_settlement(gs, 2, 17, 2)
	gs.db.difficulties["warlord"]["unowned_water_tiles_per_wild_unit"] = 20
	# Era + turn + city gates are all clear, but no naval tech yet → still empty.
	for _i in range(5):
		WildForces.spawn_naval(gs, gs.rng)
	assert_eq(_count_naval(gs), 0, "no naval raiders before any player researches sailing")
	# Grant exactly sailing → the seas open, and the raider is the Galley.
	gs.players[0].technologies.append("sailing")
	for _i in range(10):
		WildForces.spawn_naval(gs, gs.rng)
	assert_true(_count_naval(gs) > 0, "sailing alone opens the seas to naval raiders")
	for u in gs.units:
		if u.is_wild and gs.db.get_unit(u.unit_type_id).get("domain", "land") == "sea":
			assert_eq(u.unit_type_id, "galley",
				"the sailing-era naval raider is the Galley")

# Data check: a water-domain barbarian raider unit exists, is owner-agnostic stock
# (no `unique_to`), carries combat strength, and is gated on the sailing tech.
func test_galley_is_water_domain_barbarian_stock() -> void:
	var gs = make_gs()
	var g: Dictionary = gs.db.get_unit("galley")
	assert_false(g.empty(), "the galley unit exists in data")
	assert_eq(str(g.get("domain", "land")), "sea", "the galley is a water-domain unit")
	assert_true(int(g.get("base_strength", 0)) > 0, "the galley has combat strength (raider stock)")
	assert_eq(str(g.get("unique_to", "")), "", "the galley is generic (not a society unique)")
	assert_eq(str(g.get("tech_required", "")), "sailing", "the galley is gated on sailing")

# ── Behaviour ───────────────────────────────────────────────────────────────────

func test_naval_raider_attacks_a_unit_it_lands_on() -> void:
	var gs = make_gs(2, 23)
	# A single sea tile to the east is the raider's only move, and it holds a galley.
	gs.map.get_tile(5, 5).terrain_id = "ocean"
	gs.map.get_tile(6, 5).terrain_id = "ocean"
	var raider = make_unit(gs, "trireme", -2, 5, 5)
	raider.is_wild = true
	make_unit(gs, "galley", 1, 6, 5)
	WildAI.run(gs, gs.rng)
	var attacked = false
	for ev in gs.pending_wild_events:
		if ev.get("kind") == "combat":
			attacked = true
	assert_true(attacked, "a naval raider attacks a player unit it sails into")

func test_naval_raider_patrols_only_over_water() -> void:
	var gs = make_gs(2, 24)
	_add_ocean(gs)  # x >= 10 is sea, the rest is land
	var raider = make_unit(gs, "trireme", -2, 15, 5)
	raider.is_wild = true
	WildAI.run(gs, gs.rng)
	var dom = gs.db.get_terrain(gs.map.get_tile(raider.x, raider.y).terrain_id).get("domain")
	assert_eq(dom, "sea", "a naval raider never sails onto land")
	assert_true(raider.has_moved, "with open water around it, the raider patrols")
