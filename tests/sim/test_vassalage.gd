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

# §7 Team/vassalage parity (Phase 8): a crushed alliance capitulates, a recovered
# vassal is liberated, and a vassal shares its overlord's wars and peace. Pure
# Vassalage helpers + the world-step tick + the FREE_VASSAL command.

# Give player `pid` `count` warriors so its alliance has military power. Tiles are
# spread so they never stack illegally (placement is irrelevant to power).
func _arm(gs, pid, count) -> void:
	for i in range(count):
		make_warrior(gs, pid, 2 + i, pid)

# ── alliance_power ──────────────────────────────────────────────────────────────

func test_alliance_power_counts_military_only() -> void:
	var gs = make_gs(2)
	_arm(gs, 1, 2)                 # two warriors
	make_unit(gs, "settler", 1, 8, 8)  # civilian — must not count
	var with_civ: int = Vassalage.alliance_power(gs, gs.get_alliance(1))
	var empty: int = Vassalage.alliance_power(gs, gs.get_alliance(2))
	assert_true(with_civ > 0, "An armed alliance has positive power")
	assert_eq(empty, 0, "An alliance with no military has zero power")
	# Removing one warrior roughly halves power; the settler never contributed.
	assert_true(Vassalage.alliance_power(gs, gs.get_alliance(1)) == with_civ,
		"Civilian units add no military power")

# ── Capitulation gate ───────────────────────────────────────────────────────────

func test_is_crushed_by_when_at_war_and_far_weaker() -> void:
	var gs = make_gs(2)
	_arm(gs, 1, 4)   # overlord: four warriors
	_arm(gs, 2, 1)   # sub: one warrior (25% — below the 40% threshold)
	gs.get_alliance(1).at_war_with = [2]
	gs.get_alliance(2).at_war_with = [1]
	assert_true(Vassalage.is_crushed_by(gs, gs.db, gs.get_alliance(2), gs.get_alliance(1)),
		"A far weaker alliance at war is crushed")

func test_not_crushed_when_not_at_war() -> void:
	var gs = make_gs(2)
	_arm(gs, 1, 4)
	_arm(gs, 2, 1)
	assert_false(Vassalage.is_crushed_by(gs, gs.db, gs.get_alliance(2), gs.get_alliance(1)),
		"Without a war there is no capitulation, however lopsided the forces")

func test_not_crushed_when_strong_enough() -> void:
	var gs = make_gs(2)
	_arm(gs, 1, 3)
	_arm(gs, 2, 2)   # ~66% — above the 40% capitulation threshold
	gs.get_alliance(1).at_war_with = [2]
	gs.get_alliance(2).at_war_with = [1]
	assert_false(Vassalage.is_crushed_by(gs, gs.db, gs.get_alliance(2), gs.get_alliance(1)),
		"A merely-losing alliance is not crushed")

func test_crushing_overlord_picks_strongest_enemy() -> void:
	var gs = make_gs(3)
	_arm(gs, 1, 4)   # alliance 1: strong
	_arm(gs, 2, 6)   # alliance 2: stronger
	_arm(gs, 3, 1)   # alliance 3 (sub): crushed by both
	gs.get_alliance(3).at_war_with = [1, 2]
	gs.get_alliance(1).at_war_with = [3]
	gs.get_alliance(2).at_war_with = [3]
	var overlord = Vassalage.crushing_overlord(gs, gs.db, gs.get_alliance(3))
	assert_not_null(overlord, "A crushed alliance finds a conqueror")
	assert_eq(overlord.id, 2, "It capitulates to the strongest crushing enemy")

# ── Liberation ──────────────────────────────────────────────────────────────────

func test_vassal_liberates_when_recovered() -> void:
	var gs = make_gs(2)
	_arm(gs, 1, 1)
	_arm(gs, 2, 1)   # equal power — at/above the 70% liberation threshold
	gs.get_alliance(2).is_subordinate_to = 1
	gs.get_alliance(1).tributaries = [2]
	assert_true(Vassalage.can_liberate(gs, gs.db, gs.get_alliance(2)),
		"A recovered vassal can break free")
	Vassalage.world_tick(gs, gs.db)
	assert_eq(gs.get_alliance(2).is_subordinate_to, -1, "It is freed")
	assert_false(2 in gs.get_alliance(1).tributaries, "And dropped from the overlord's list")
	# A liberation notice is queued for the facade to surface.
	var found: bool = false
	for e in gs.pending_deal_events:
		if str(e.get("kind", "")) == "vassal_liberated":
			found = true
	assert_true(found, "A liberation event is queued")

func test_vassal_stays_when_still_weak() -> void:
	var gs = make_gs(2)
	_arm(gs, 1, 5)
	_arm(gs, 2, 1)   # 20% — below the 70% liberation threshold
	gs.get_alliance(2).is_subordinate_to = 1
	gs.get_alliance(1).tributaries = [2]
	assert_false(Vassalage.can_liberate(gs, gs.db, gs.get_alliance(2)),
		"A weak vassal cannot break free")
	Vassalage.world_tick(gs, gs.db)
	assert_eq(gs.get_alliance(2).is_subordinate_to, 1, "It stays subordinate")

# ── Shared war & peace ──────────────────────────────────────────────────────────

func test_vassal_inherits_overlord_war() -> void:
	var gs = make_gs(3)
	gs.get_alliance(2).is_subordinate_to = 1
	gs.get_alliance(1).tributaries = [2]
	gs.get_alliance(1).at_war_with = [3]   # overlord at war with alliance 3
	gs.get_alliance(3).at_war_with = [1]
	Vassalage.world_tick(gs, gs.db)
	assert_true(gs.get_alliance(2).is_at_war_with(3), "The vassal is dragged into the overlord's war")
	assert_true(gs.get_alliance(3).is_at_war_with(2), "And the enemy is at war with the vassal")

func test_vassal_shares_overlord_peace() -> void:
	var gs = make_gs(3)
	gs.get_alliance(2).is_subordinate_to = 1
	gs.get_alliance(1).tributaries = [2]
	# The vassal carries a war with alliance 3 the overlord is not in.
	gs.get_alliance(2).at_war_with = [3]
	gs.get_alliance(3).at_war_with = [2]
	Vassalage.world_tick(gs, gs.db)
	assert_false(gs.get_alliance(2).is_at_war_with(3),
		"A vassal cannot keep a war its overlord has left (shared peace)")
	assert_false(gs.get_alliance(3).is_at_war_with(2), "The drop is mutual")

# ── FREE_VASSAL command ─────────────────────────────────────────────────────────

func test_free_vassal_command_releases() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.get_alliance(2).is_subordinate_to = 1
	gs.get_alliance(1).tributaries = [2]
	assert_true(f._cmd_free_vassal({"player_id": 1, "vassal_alliance_id": 2}),
		"An overlord may free its vassal")
	assert_eq(gs.get_alliance(2).is_subordinate_to, -1, "The vassal is independent again")
	assert_false(2 in gs.get_alliance(1).tributaries, "And dropped from the tributary list")

func test_free_vassal_rejects_non_overlord() -> void:
	var gs = make_gs(3)
	var f = bare_facade(gs)
	gs.get_alliance(2).is_subordinate_to = 1
	gs.get_alliance(1).tributaries = [2]
	# Player 3 is not the overlord — it cannot free alliance 2.
	assert_false(f._cmd_free_vassal({"player_id": 3, "vassal_alliance_id": 2}),
		"A non-overlord cannot release the vassal")
	assert_eq(gs.get_alliance(2).is_subordinate_to, 1, "The relationship stands")

func test_free_vassal_rejects_non_vassal() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	assert_false(f._cmd_free_vassal({"player_id": 1, "vassal_alliance_id": 2}),
		"Freeing an alliance that is not your vassal is rejected")

# ── Save/load discipline (no new serialized state, but verify the relation survives) ──

func test_subordination_survives_save_load() -> void:
	var gs = make_gs(2)
	gs.get_alliance(2).is_subordinate_to = 1
	gs.get_alliance(1).tributaries = [2]
	var data = gs.get_alliance(1).serialize()
	var restored = Alliance.deserialize(JSON.parse(JSON.print(data)).result)
	assert_eq(typeof(restored.tributaries[0]), TYPE_INT, "Tributary ids deserialize as ints")
	assert_true(2 in restored.tributaries, "The tributary list survives a JSON roundtrip")
