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

# Building-conferred starting experience and free promotions (§5.5), plus the
# heals_units garrison heal. These data keys were previously inert (carried in
# structures.json but read by no sim site).

func _build(gs, s, p, unit_id):
	TurnEngine._complete_item(gs, s, p, {"type": "unit", "id": unit_id})
	return gs.units[gs.units.size() - 1]

func test_barracks_grants_land_xp():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.structures.append("barracks")  # land_xp: 3
	var u = _build(gs, s, p, "warrior")
	assert_eq(u.experience, 3, "barracks grants land units +3 XP")

func test_stable_grants_mounted_xp_only_to_mounted():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.structures.append("stable")  # mounted_xp: 2
	var horse = _build(gs, s, p, "chariot")
	var foot = _build(gs, s, p, "warrior")
	assert_eq(horse.experience, 2, "stable grants mounted units +2 XP")
	assert_eq(foot.experience, 0, "stable does not help a non-mounted unit")

func test_drydock_grants_naval_xp():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.structures.append("drydock")  # naval_xp: 4
	var ship = _build(gs, s, p, "galley")
	assert_eq(ship.experience, 4, "drydock grants naval units +4 XP")

func test_airport_grants_air_xp():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.structures.append("airport")  # air_xp: 3
	var plane = _build(gs, s, p, "fighter")
	assert_eq(plane.experience, 3, "airport grants air units +3 XP")

func test_xp_keys_stack_and_pentagon_is_empire_wide():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var cap = make_settlement(gs, 1, 1, 1, 3)
	cap.structures.append("pentagon")  # unit_xp_all_cities: 2 (empire-wide)
	var s = make_settlement(gs, 1, 9, 9, 3)
	s.structures.append("barracks")    # land_xp: 3
	s.structures.append("west_point")  # military_xp_city: 4
	var u = _build(gs, s, p, "warrior")
	assert_eq(u.experience, 3 + 4 + 2,
		"barracks + West Point + (empire-wide) Pentagon stack")

func test_structure_xp_can_auto_promote():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	# 3 + 4 + 2 + 2(Vassalage) = 11 XP, past the level-1 threshold (10).
	cap_structures(s)
	p.policies = {"legal": "vassalage"}
	var u = _build(gs, s, p, "warrior")
	assert_true(u.experience >= 10, "enough XP to cross the first threshold")
	assert_eq(u.promotions.size(), 1, "crossing a threshold grants a promotion")

func cap_structures(s):
	s.structures.append("barracks")
	s.structures.append("west_point")
	s.structures.append("pentagon")

func test_civilian_gets_no_building_xp():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.structures.append("barracks")
	var w = _build(gs, s, p, "worker")  # civilian
	assert_eq(w.experience, 0, "civilians get no building XP")
	assert_eq(w.promotions.size(), 0, "civilians get no promotions")

func test_dun_grants_named_free_promotion():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.structures.append("dun")  # free_promotion: guerrilla1 (applies_to land)
	var u = _build(gs, s, p, "warrior")
	assert_true("guerrilla1" in u.promotions, "Dun confers guerrilla1 to land units")

func test_ikhanda_grants_free_promotion_all():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.structures.append("ikhanda")  # free_promotion_all
	var u = _build(gs, s, p, "warrior")
	assert_eq(u.promotions.size(), 1, "Ikhanda grants one free promotion")

func test_heals_units_fully_heals_garrison():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.structures.append("ikhanda")  # heals_units
	var u = make_warrior(gs, 1, 5, 5)
	u.health = 40
	TurnEngine._heal_unit(gs, u, p)
	assert_eq(u.health, 100, "a heals_units structure fully restores its garrison")

# ── M1: structure obsolescence (§15.17) ──────────────────────────────────────

func test_obsolete_stable_grants_no_mounted_xp():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.structures.append("stable")        # mounted_xp 2; obsoleted_by advanced_flight
	p.technologies.append("advanced_flight")
	var horse = _build(gs, s, p, "chariot")
	assert_eq(horse.experience, 0,
		"An obsolete stable trains no one (§15.17: Stable → Advanced Flight)")
