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

# Combat resolution (§5): the per-round loop, determinism, XP, and the §5.4
# extras — flanking, withdrawal, war-fatigue accrual, and the Great General
# earned from combat (§14.2).

func _rng(seed_val):
	var r = load("res://src/core/rng.gd").new()
	r.init(seed_val)
	return r

# ── Result contract ────────────────────────────────────────────────────────────

func test_combat_has_required_keys() -> void:
	var gs = make_gs()
	var attacker = make_warrior(gs, 1, 5, 6)
	var defender = make_warrior(gs, 2, 5, 5)
	var result: Dictionary = Combat.resolve(attacker, defender, gs, _rng(42))
	assert_true(result.has("attacker_survived"), "Result has attacker_survived")
	assert_true(result.has("defender_survived"), "Result has defender_survived")
	assert_true(result.has("rounds"), "Result has rounds")

func test_combat_one_side_dies_or_withdraws() -> void:
	var gs = make_gs()
	var attacker = make_warrior(gs, 1, 5, 6)
	var defender = make_warrior(gs, 2, 5, 5)
	var result: Dictionary = Combat.resolve(attacker, defender, gs, _rng(42))
	assert_true(
		not result["attacker_survived"] or not result["defender_survived"] or result["attacker_withdrew"],
		"Combat must end with a winner or withdrawal")

func test_combat_health_non_negative() -> void:
	var gs = make_gs()
	var attacker = make_warrior(gs, 1, 5, 6)
	var defender = make_warrior(gs, 2, 5, 5)
	var result: Dictionary = Combat.resolve(attacker, defender, gs, _rng(9876))
	assert_true(result["attacker_health_after"] >= 0, "Attacker health >= 0")
	assert_true(result["defender_health_after"] >= 0, "Defender health >= 0")

# ── Determinism ──────────────────────────────────────────────────────────────

func test_combat_same_seed_identical_outcome() -> void:
	var gs = make_gs()
	var a1 = make_warrior(gs, 1, 5, 6); a1.id = 100
	var d1 = make_warrior(gs, 2, 5, 5); d1.id = 101
	var r1: Dictionary = Combat.resolve(a1, d1, gs, _rng(999))

	var a2 = make_warrior(gs, 1, 5, 6); a2.id = 102
	var d2 = make_warrior(gs, 2, 5, 5); d2.id = 103
	var r2: Dictionary = Combat.resolve(a2, d2, gs, _rng(999))

	assert_eq(r1["attacker_survived"], r2["attacker_survived"],
		"Same seed: attacker_survived identical")
	assert_eq(r1["defender_survived"], r2["defender_survived"],
		"Same seed: defender_survived identical")
	assert_eq(r1["attacker_health_after"], r2["attacker_health_after"],
		"Same seed: health identical")
	assert_eq(r1["rounds"], r2["rounds"],
		"Same seed: round count identical")

# ── Experience ───────────────────────────────────────────────────────────────

func test_combat_xp_gain_when_killing_weak_enemy() -> void:
	var gs = make_gs()
	var attacker = make_warrior(gs, 1, 5, 6)
	attacker.base_strength = 100  # very strong
	var defender = make_warrior(gs, 2, 5, 5)
	defender.base_strength = 1
	defender.health = 1
	var result: Dictionary = Combat.resolve(attacker, defender, gs, _rng(1234))
	if not result["defender_survived"]:
		assert_gt(result["attacker_xp_gain"], 0, "Attacker gains XP when killing")

# ── Flanking (§5.4) ────────────────────────────────────────────────────────────

func test_flanking_damages_stacked_unit() -> void:
	var gs = make_gs()
	# A "fast"-tagged attacker triggers flanking on a kill (§5.4).
	gs.db.units["raider_horse"] = {
		"id": "raider_horse", "base_strength": 200, "movement": 300,
		"classification": "cavalry", "tags": ["fast"],
		"first_strikes": 0, "combat_limit": 0, "withdrawal_chance": 0,
		"upkeep": 0, "cost": 40
	}
	var atk = load("res://src/sim/unit.gd").new()
	atk.id = gs.next_unit_id(); atk.unit_type_id = "raider_horse"
	atk.owner_player_id = 1; atk.x = 5; atk.y = 6
	atk.base_strength = 200; atk.health = 100
	atk.movement_total = 300; atk.movement_left = 300
	gs.units.append(atk)

	var def1 = make_warrior(gs, 2, 5, 5)   # the unit being attacked
	var def2 = make_warrior(gs, 2, 5, 5)   # stacked behind it

	var result: Dictionary = Combat.resolve(atk, def1, gs, _rng(7))
	assert_false(result["defender_survived"], "Overwhelming attacker kills the defender")
	assert_gt(result["flanking_damage"], 0, "Fast attacker produces flanking damage")

	var before: int = def2.health
	var facade = bare_facade(gs)
	facade._apply_combat_result(atk, def1, result)
	assert_lt(def2.health, before, "Stacked unit takes flanking damage when its defender falls")

# ── Withdrawal (§5.4) ────────────────────────────────────────────────────────────

func test_withdrawal_saves_attacker_from_fatal_hit() -> void:
	var gs = make_gs()
	gs.db.units["coward"] = {
		"id": "coward", "base_strength": 1, "movement": 200,
		"classification": "melee", "tags": [],
		"first_strikes": 0, "combat_limit": 0, "withdrawal_chance": 100,
		"upkeep": 0, "cost": 10
	}
	var atk = load("res://src/sim/unit.gd").new()
	atk.id = gs.next_unit_id(); atk.unit_type_id = "coward"
	atk.owner_player_id = 1; atk.x = 5; atk.y = 6
	atk.base_strength = 1; atk.health = 100
	atk.movement_total = 200; atk.movement_left = 200
	gs.units.append(atk)

	var defender = make_warrior(gs, 2, 5, 5)
	defender.base_strength = 100  # all but guaranteed to win each round

	var result: Dictionary = Combat.resolve(atk, defender, gs, _rng(3))
	assert_true(result["attacker_withdrew"], "Guaranteed-withdrawal attacker retreats")
	assert_true(result["attacker_survived"], "A withdrawing attacker survives the fatal hit")
	assert_eq(result["attacker_health_after"], 100,
		"Withdrawn attacker reports its pre-combat health, not a mangled value")

# ── War fatigue (§3.8/§7) ────────────────────────────────────────────────────────

func test_combat_loss_accrues_war_fatigue() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	var atk = make_unit(gs, "warrior", 1, 5, 6)
	var def = make_unit(gs, "warrior", 2, 5, 5)
	var result = {
		"attacker_survived": true, "defender_survived": false,
		"attacker_health_after": 100, "defender_health_after": 0,
		"attacker_withdrew": false, "rounds": 1,
		"attacker_xp_gain": 0, "defender_xp_gain": 0,
		"spillover_damage": 0, "flanking_damage": 0
	}
	f._apply_combat_result(atk, def, result)
	var amt: int = gs.db.get_constant("war_fatigue_per_loss", 5)
	assert_eq(int(gs.alliances[1].war_fatigue.get(1, 0)), amt,
		"Loser's alliance accrues war-fatigue against the victor")

# ── Auto-promotion on XP (§5.5) ──────────────────────────────────────────────────

func test_unit_auto_promotes_on_xp_threshold() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	var atk = make_warrior(gs, 1, 5, 6)
	var def = make_warrior(gs, 2, 5, 5)
	# Hand the survivor enough XP to clear the first non-zero threshold (10).
	var result = {
		"attacker_survived": true, "defender_survived": false,
		"attacker_health_after": 100, "defender_health_after": 0,
		"attacker_withdrew": false, "rounds": 1,
		"attacker_xp_gain": 15, "defender_xp_gain": 0,
		"spillover_damage": 0, "flanking_damage": 0
	}
	f._apply_combat_result(atk, def, result)
	assert_eq(atk.experience_level, 1, "Crossing the XP threshold raises the level")
	assert_eq(atk.promotions.size(), 1, "A promotion is awarded on level up")

func test_no_promotion_below_threshold() -> void:
	var gs = make_gs()
	var f = bare_facade(gs)
	var atk = make_warrior(gs, 1, 5, 6)
	var def = make_warrior(gs, 2, 5, 5)
	var result = {
		"attacker_survived": true, "defender_survived": false,
		"attacker_health_after": 100, "defender_health_after": 0,
		"attacker_withdrew": false, "rounds": 1,
		"attacker_xp_gain": 5, "defender_xp_gain": 0,
		"spillover_damage": 0, "flanking_damage": 0
	}
	f._apply_combat_result(atk, def, result)
	assert_eq(atk.experience_level, 0, "Below the threshold no level is gained")
	assert_eq(atk.promotions.size(), 0, "No promotion below the threshold")

# ── Attack-move through the facade ───────────────────────────────────────────────

func test_unit_can_attack_adjacent_enemy() -> void:
	var facade = setup_facade(5, "small")
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var p0 = gs.players[0].id
	var p1 = gs.players[1].id
	gs.current_player_id = p0

	var a = load("res://src/sim/unit.gd").new()
	a.id = gs.next_unit_id(); a.unit_type_id = "warrior"; a.owner_player_id = p0
	a.x = 5; a.y = 5; a.base_strength = 100; a.health = 100
	a.movement_total = 200; a.movement_left = 200
	gs.units.append(a)
	var d = load("res://src/sim/unit.gd").new()
	d.id = gs.next_unit_id(); d.unit_type_id = "warrior"; d.owner_player_id = p1
	d.x = 6; d.y = 5; d.base_strength = 1; d.health = 100
	gs.units.append(d)

	watch_signals(facade)
	var ok = facade.apply_command(Commands.move_stack(p0, 5, 5, 6, 5))
	assert_true(ok, "Attack-move onto an adjacent enemy should be accepted")
	assert_signal_emitted(facade, "combat_resolved",
		"Moving onto an enemy must resolve combat")
	assert_null(gs.get_unit(d.id), "The weak defender should be destroyed")
	var av = gs.get_unit(a.id)
	assert_not_null(av, "The strong attacker should survive")
	assert_eq([av.x, av.y], [6, 5], "The victorious attacker advances onto the captured tile")

# ── Class-versus-class modifiers (§5.3) ─────────────────────────────────────────

func test_vs_class_promotion_applies_only_against_mapped_class() -> void:
	var gs = make_gs()
	var u = make_warrior(gs, 1, 5, 5)   # melee, base_strength 10
	u.promotions = ["formation"]        # vs_mounted +25, applies_to melee
	var vs_mounted: int = u.effective_strength(gs.db, false, {}, {}, "mounted")
	var vs_melee: int = u.effective_strength(gs.db, false, {}, {}, "melee")
	assert_gt(vs_mounted, vs_melee,
		"formation's vs_mounted bonus applies against a mounted opponent")
	assert_eq(vs_melee, 10,
		"...and not against a non-mounted opponent (base strength unchanged)")

func test_vs_fortified_promotion_applies_against_entrenched_opponent() -> void:
	var gs = make_gs()
	gs.db.units["test_catapult"] = {
		"id": "test_catapult", "base_strength": 10, "movement": 100,
		"classification": "siege", "tags": [], "upkeep": 0, "cost": 40
	}
	var u = make_unit(gs, "test_catapult", 1, 5, 5)
	u.base_strength = 10
	u.promotions = ["barrage1"]          # vs_fortified +25, applies_to siege
	var vs_fort: int = u.effective_strength(gs.db, true, {}, {}, "", false, 0, true)
	var vs_open: int = u.effective_strength(gs.db, true, {}, {}, "", false, 0, false)
	assert_gt(vs_fort, vs_open, "barrage's vs_fortified bonus applies vs an entrenched unit")

# ── Settlement attack / defence modifiers (§5.3) ────────────────────────────────

func test_attack_vs_settlement_bonus_only_at_a_city() -> void:
	var gs = make_gs()
	var u = make_warrior(gs, 1, 5, 5)   # melee
	u.promotions = ["city_raider1"]     # attack_vs_settlement +20, melee
	var at_city: int = u.effective_strength(gs.db, true, {}, {}, "", true)
	var in_open: int = u.effective_strength(gs.db, true, {}, {}, "", false)
	assert_gt(at_city, in_open, "city_raider boosts an attack into a settlement")
	assert_eq(in_open, 10, "...and not in the open field")

func test_settlement_defence_helper_sums_structure_and_cultural() -> void:
	var gs = make_gs()
	var s = make_settlement(gs, 2, 5, 5)
	s.structures = ["walls"]            # defence_bonus 50 + cultural_defence_bonus 10
	assert_eq(Combat._settlement_defence(s, gs.db), 60,
		"Settlement defence = structure defence_bonus + cultural_defence_bonus")
	assert_eq(Combat._settlement_defence(null, gs.db), 0, "No settlement → no bonus")

func test_defender_in_settlement_is_stronger() -> void:
	var gs = make_gs()
	var d = make_warrior(gs, 2, 5, 5)   # base_strength 10
	var s = make_settlement(gs, 2, 5, 5)
	s.structures = ["walls"]
	var def_bonus: int = Combat._settlement_defence(s, gs.db)
	var defending: int = d.effective_strength(gs.db, false, {}, {}, "", true, def_bonus)
	var in_open: int = d.effective_strength(gs.db, false, {}, {}, "", false, 0)
	assert_gt(defending, in_open, "A garrison inside a walled city defends harder")

func test_settlement_defence_flows_through_combat_resolve() -> void:
	var gs = make_gs()
	# An impregnable bastion: settlement defence so high the attacker can never win.
	gs.db.structures["test_bastion"] = {"id": "test_bastion", "defence_bonus": 100000}
	var atk = make_warrior(gs, 1, 5, 6)
	var dfn = make_warrior(gs, 2, 5, 5)
	var s = make_settlement(gs, 2, 5, 5)
	s.structures = ["test_bastion"]
	var r: Dictionary = Combat.resolve(atk, dfn, gs, _rng(42))
	assert_true(r["defender_survived"],
		"Combat.resolve reads the defender's settlement defence (garrison survives)")
