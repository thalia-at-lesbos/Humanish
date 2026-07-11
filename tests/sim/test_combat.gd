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

# ── Per-hit damage: firepower blend (§5.4) ───────────────────────────────────────

func test_per_hit_damage_even_match_is_combat_damage() -> void:
	# Evenly-matched firepower removes ≈ combat_damage (20) of 100 max_hp per hit,
	# so a fight runs ≈ 5 hits to a kill (was ≈10 under the old flat model).
	assert_eq(Combat._per_hit_damage(10, 10, 20), 20,
		"Even firepower → one hit removes combat_damage HP")
	assert_eq(Combat._per_hit_damage(50, 50, 20), 20,
		"Magnitude-independent: equal firepower always yields combat_damage")

func test_per_hit_damage_floored_at_one() -> void:
	# A hopelessly weak attacker hitting an overwhelming defender still deals ≥ 1.
	var dmg: int = Combat._per_hit_damage(100000, 1, 20)
	assert_true(dmg >= 1, "Damage is floored at one point")

func test_even_match_combat_runs_about_five_hits() -> void:
	# Drive a real even fight and confirm the loser fell in ~5 hits' worth of damage.
	var gs = make_gs()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
		tile.feature_id = ""
	var atk = make_warrior(gs, 1, 5, 6)   # base_strength 10
	var dfn = make_warrior(gs, 2, 5, 5)   # base_strength 10
	# Per-hit damage between two even warriors on open grassland is combat_damage.
	var a_str: int = atk.effective_strength(gs.db, true, {}, {}, "melee")
	var d_str: int = dfn.effective_strength(gs.db, false,
		gs.db.get_terrain("grassland"), {}, "melee")
	var per_hit: int = Combat._per_hit_damage(a_str, d_str, 20)
	var hits_to_kill: int = (100 + per_hit - 1) / per_hit
	assert_true(hits_to_kill >= 4 and hits_to_kill <= 6,
		"Even matchup kills in ≈5 hits, got %d (per-hit %d)" % [hits_to_kill, per_hit])

func test_odds_clamp_gives_hopeless_attacker_a_chance() -> void:
	# A vastly out-matched attacker would have ~0 natural odds; the 10%/90% clamp
	# keeps it from being mathematically hopeless, so across seeds it lands a hit
	# the old (unclamped) odds would never have allowed.
	var landed_a_hit: bool = false
	for s in range(60):
		var gs = make_gs()
		for tile in gs.map.all_tiles():
			tile.terrain_id = "grassland"
			tile.feature_id = ""
		var atk = make_warrior(gs, 1, 5, 6); atk.base_strength = 1
		var dfn = make_warrior(gs, 2, 5, 5); dfn.base_strength = 1000
		var r: Dictionary = Combat.resolve(atk, dfn, gs, _rng(s))
		if r["defender_health_after"] < 100:
			landed_a_hit = true
			break
	assert_true(landed_a_hit,
		"Odds clamp lets a hopeless attacker land at least one hit across seeds")

# ── Per-unit siege damage caps (§15.6) ────────────────────────────────────────

func test_siege_cap_floors_defender_health() -> void:
	# A sieging attacker cannot reduce the defender below its combat_limit
	# floor — the fight ends with the defender alive at exactly the floor.
	var gs = make_gs()
	gs.db.units["sieger"] = {
		"id": "sieger", "base_strength": 200, "movement": 60,
		"classification": "siege", "tags": ["siege"],
		"first_strikes": 0, "combat_limit": 25, "withdrawal_chance": 0,
		"upkeep": 0, "cost": 50
	}
	var atk = load("res://src/sim/unit.gd").new()
	atk.id = gs.next_unit_id(); atk.unit_type_id = "sieger"
	atk.owner_player_id = 1; atk.x = 5; atk.y = 6
	atk.base_strength = 200; atk.health = 100
	atk.movement_total = 60; atk.movement_left = 60
	gs.units.append(atk)
	var defender = make_warrior(gs, 2, 5, 5)
	var result: Dictionary = Combat.resolve(atk, defender, gs, _rng(11))
	assert_true(result["defender_survived"],
		"A capped attacker can never kill: the defender survives at the floor")
	assert_eq(result["defender_health_after"], 25,
		"The defender is reduced exactly to the unit's combat_limit floor")

func test_siege_roster_carries_reference_floors() -> void:
	# §15.6 data pass: floor = 100 − reference iCombatLimit.
	var gs = make_gs()
	var floors = {"catapult": 25, "trebuchet": 25, "hwacha": 25,
		"cannon": 20, "artillery": 15, "mobile_artillery": 15}
	for uid in floors:
		assert_eq(int(gs.db.get_unit(uid).get("combat_limit", 0)), floors[uid],
			"'%s' carries its §15.6 damage floor" % uid)

func test_promotion_roster_carries_a8_reference_values() -> void:
	# A8 data pass (audit §9 + game-data §29.3): pin the retuned promotion
	# values so a regression back to the pre-parity numbers fails loudly.
	var db = make_gs().db
	assert_eq(int(db.get_promotion("combat6").get("combat_strength_bonus", 0)), 25,
		"Combat VI is +25% (reference)")
	assert_eq(int(db.get_promotion("flanking2").get("withdrawal_chance_bonus", 0)), 20,
		"Flanking II is +20% withdrawal (reference)")
	assert_eq(int(db.get_promotion("interception1").get("intercept_bonus", 0)), 10,
		"Interception I is +10% (reference)")
	assert_eq(int(db.get_promotion("interception2").get("intercept_bonus", 0)), 20,
		"Interception II is +20% (reference)")
	assert_eq(int(db.get_promotion("guerrilla3").get("withdrawal_chance_bonus", 0)), 50,
		"Guerrilla III regained its +50% withdrawal (reference)")
	assert_eq(int(db.get_promotion("woodsman3").get("first_strikes_bonus", 0)), 2,
		"Woodsman III regained its +2 first strikes (reference)")
	# Drill line per §29.3: I bare, II +1 FS, III protection only, IV +2 FS;
	# II–IV carry +20% collateral-damage protection.
	assert_false(db.get_promotion("drill1").has("first_strikes_bonus"),
		"Drill I carries no first-strike field (§29.3)")
	assert_eq(int(db.get_promotion("drill2").get("first_strikes_bonus", 0)), 1,
		"Drill II is +1 first strike (§29.3)")
	assert_false(db.get_promotion("drill3").has("first_strikes_bonus"),
		"Drill III grants no guaranteed first strike (§29.3)")
	assert_eq(int(db.get_promotion("drill4").get("first_strikes_bonus", 0)), 2,
		"Drill IV is +2 first strikes (§29.3)")
	for tier in ["drill2", "drill3", "drill4"]:
		assert_eq(int(db.get_promotion(tier).get("collateral_damage_protection", 0)), 20,
			"'%s' carries +20%% collateral-damage protection (§29.3)" % tier)

# ── Chance first strikes (§15.5) ──────────────────────────────────────────────

func _make_chance_striker(gs, chance, base_fs = 1):
	# Synthetic attacker type carrying a chance_first_strikes stat.
	gs.db.units["chance_striker"] = {
		"id": "chance_striker", "base_strength": 5, "movement": 60,
		"classification": "ranged", "tags": [],
		"first_strikes": base_fs, "chance_first_strikes": chance,
		"combat_limit": 0, "withdrawal_chance": 0, "upkeep": 0, "cost": 30
	}
	var atk = load("res://src/sim/unit.gd").new()
	atk.id = gs.next_unit_id(); atk.unit_type_id = "chance_striker"
	atk.owner_player_id = 1; atk.x = 5; atk.y = 6
	atk.base_strength = 5; atk.health = 100
	atk.movement_total = 60; atk.movement_left = 60
	gs.units.append(atk)
	return atk

func test_chance_first_strikes_same_seed_identical_outcome() -> void:
	var gs = make_gs()
	var atk = _make_chance_striker(gs, 3)
	var defender = make_warrior(gs, 2, 5, 5)
	var r1: Dictionary = Combat.resolve(atk, defender, gs, _rng(99))
	# Reset healths so the second resolve starts from identical state.
	atk.health = 100; defender.health = 100
	var r2: Dictionary = Combat.resolve(atk, defender, gs, _rng(99))
	for key in r1:
		assert_eq(r2[key], r1[key],
			"Chance-FS combat is seed-deterministic (key '%s')" % key)

func test_chance_first_strikes_rolls_within_bounds() -> void:
	# rolled_first_strikes = guaranteed + uniform 0..chance, never outside.
	var gs = make_gs()
	var atk = _make_chance_striker(gs, 2, 1)
	var seen = {}
	for s in range(60):
		var fs = Combat.rolled_first_strikes(gs.db, atk, _rng(s))
		assert_true(fs >= 1 and fs <= 3,
			"Rolled first strikes stay within guaranteed..guaranteed+chance")
		seen[fs] = true
	assert_eq(seen.size(), 3, "Across seeds the whole 0..chance range is reached")

func test_zero_chance_first_strikes_consumes_no_rng_draw() -> void:
	# A unit without a chance stat must not draw from the rng, or every seeded
	# combat stream in the game would shift.
	var gs = make_gs()
	var warrior = make_warrior(gs, 1, 5, 6)
	var r_used = _rng(7)
	var fs = Combat.rolled_first_strikes(gs.db, warrior, r_used)
	assert_eq(fs, 0, "A warrior has no first strikes")
	assert_eq(r_used.randi_range(0, 1000000), _rng(7).randi_range(0, 1000000),
		"The rng stream is untouched by a zero-chance first-strike read")

func test_drill_promotions_grant_first_strikes() -> void:
	# A8 reference drill line (game-data §29.3): Drill I carries no combat
	# fields, Drill II a guaranteed +1 first strike — so a base-1 unit with
	# both has exactly 2, with no chance roll drawn.
	var gs = make_gs()
	var atk = _make_chance_striker(gs, 0, 1)
	atk.promotions = ["drill1", "drill2"]
	assert_eq(Combat.rolled_first_strikes(gs.db, atk, _rng(1)), 2,
		"Guaranteed first strikes sum unit base + drill promotion bonuses")
	gs.db.promotions["test_drill_chance"] = {
		"id": "test_drill_chance", "name": "Test Drill",
		"applies_to": "land", "chance_first_strikes_bonus": 2
	}
	atk.promotions = ["test_drill_chance"]
	var seen = {}
	for s in range(60):
		var fs = Combat.rolled_first_strikes(gs.db, atk, _rng(s))
		assert_true(fs >= 1 and fs <= 3,
			"Promotion chance bonus rolls within guaranteed..guaranteed+chance")
		seen[fs] = true
	assert_eq(seen.size(), 3, "Promotion chance bonus spans its whole range")

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

func test_withdrawal_chance_clamped_at_max() -> void:
	# A11: total withdrawal chance (unit + promotions) is clamped at
	# withdrawal_chance_max (reference MAX_WITHDRAWAL_PROBABILITY 90), so even a
	# nominal 200% withdrawer sometimes dies — across fixed seeds at least one
	# fatal hit must land (P(all 60 withdraw) at 90% ≈ 0.2%).
	var died_once: bool = false
	for s in range(60):
		var gs = make_gs()
		gs.db.constants["withdrawal_chance_max"] = 90
		gs.db.units["coward"] = {
			"id": "coward", "base_strength": 1, "movement": 200,
			"classification": "melee", "tags": [],
			"first_strikes": 0, "combat_limit": 0, "withdrawal_chance": 200,
			"upkeep": 0, "cost": 10
		}
		var atk = load("res://src/sim/unit.gd").new()
		atk.id = gs.next_unit_id(); atk.unit_type_id = "coward"
		atk.owner_player_id = 1; atk.x = 5; atk.y = 6
		atk.base_strength = 1; atk.health = 100
		atk.movement_total = 200; atk.movement_left = 200
		gs.units.append(atk)
		var defender = make_warrior(gs, 2, 5, 5)
		defender.base_strength = 100
		var r: Dictionary = Combat.resolve(atk, defender, gs, _rng(s))
		if not r["attacker_survived"]:
			died_once = true
			break
	assert_true(died_once,
		"The 90% withdrawal clamp lets a fatal hit land across seeds (A11)")

func test_xp_per_combat_capped_at_ten() -> void:
	# A11: no single fight awards more than experience_per_combat_cap
	# (reference MAX_EXPERIENCE_PER_COMBAT 10). Killing a 1.5×-stronger,
	# full-health defender earns 15 raw XP (150·10/100); the cap trims it to 10.
	# 100 guaranteed first strikes make the kill certain and damage-free, so the
	# outcome is seed-independent.
	var gs = make_gs()
	gs.db.units["xp_probe"] = {
		"id": "xp_probe", "base_strength": 100, "movement": 60,
		"classification": "melee", "tags": [],
		"first_strikes": 100, "combat_limit": 0, "withdrawal_chance": 0,
		"upkeep": 0, "cost": 30
	}
	var atk = load("res://src/sim/unit.gd").new()
	atk.id = gs.next_unit_id(); atk.unit_type_id = "xp_probe"
	atk.owner_player_id = 1; atk.x = 5; atk.y = 6
	atk.base_strength = 100; atk.health = 100
	atk.movement_total = 60; atk.movement_left = 60
	gs.units.append(atk)
	var defender = make_warrior(gs, 2, 5, 5)
	defender.base_strength = 150
	var result: Dictionary = Combat.resolve(atk, defender, gs, _rng(11))
	assert_false(result["defender_survived"], "First strikes kill the defender")
	assert_eq(int(result["attacker_xp_gain"]), 10,
		"XP per combat is capped at 10 (reference, A11)")

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

func test_charismatic_lowers_promotion_xp_needed() -> void:
	# A9: the reference Charismatic model — 25% less XP needed per level. The
	# first non-zero threshold (10) becomes 10*75/100 = 7 for a charismatic
	# leader's unit, while a traitless owner still needs the full 10.
	var gs = make_gs()
	var plain = make_warrior(gs, 1, 5, 6)
	plain.experience = 8
	CombatApply.award_promotions(gs, plain)
	assert_eq(plain.experience_level, 0,
		"A traitless owner's unit still needs the full threshold")
	gs.get_player(1).traits = ["charismatic"]
	var charmed = make_warrior(gs, 1, 6, 6)
	charmed.experience = 8
	CombatApply.award_promotions(gs, charmed)
	assert_eq(charmed.experience_level, 1,
		"Charismatic lowers the XP needed for a level by 25% (reference)")
	assert_eq(charmed.promotions.size(), 1, "The reduced threshold awards a promotion")

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
	assert_eq(Combat.settlement_defence(s, gs.db), 60,
		"Settlement defence = structure defence_bonus + cultural_defence_bonus")
	assert_eq(Combat.settlement_defence(null, gs.db), 0, "No settlement → no bonus")

func test_defender_in_settlement_is_stronger() -> void:
	var gs = make_gs()
	var d = make_warrior(gs, 2, 5, 5)   # base_strength 10
	var s = make_settlement(gs, 2, 5, 5)
	s.structures = ["walls"]
	var def_bonus: int = Combat.settlement_defence(s, gs.db)
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

# ── Panther vs Warrior investigation (pinned numbers) ───────────────────────────
#
# A player reported a Panther killing two hill-defending Warriors and asked whether
# combat is broken. It is working as designed: the Panther (data base_strength 2,
# the reference value since the A1 parity pass) matches a Warrior (data
# base_strength 2). The hill terrain's +25% defence bonus IS applied to the defender
# in resolve(), but at integer strengths it rounds away for a strength-2 unit
# (2 * 125 / 100 = 2), so a hill barely helps a lone unfortified Warrior. These
# tests pin the actual numbers so a future balance/data change can't silently
# shift them.

func test_panther_outpowers_warrior_by_data() -> void:
	# Pin the raw data stats the investigation reasoned from.
	assert_eq(int(gs_db_strength("panther")), 2, "Panther base_strength is 2 (reference value, A1)")
	assert_eq(int(gs_db_strength("warrior")), 2, "Warrior base_strength is 2")

func gs_db_strength(uid):
	var gs = make_gs()
	return int(gs.db.get_unit(uid).get("base_strength", 0))

func test_hill_defence_bonus_reaches_resolve() -> void:
	# The hills terrain grants +25% defence; effective_strength reads it for the
	# defender (and only the defender). Use a high-strength unit so the +25% survives
	# integer truncation and the bonus is unambiguously visible.
	var gs = make_gs()
	var hills: Dictionary = gs.db.get_terrain("hills")
	var d = make_warrior(gs, 2, 5, 5)  # base_strength 10
	var on_hill: int = d.effective_strength(gs.db, false, hills, {}, "")
	var on_flat: int = d.effective_strength(gs.db, false, {}, {}, "")
	assert_eq(on_hill, 12, "a strength-10 defender on a hill is 10 * 1.25 = 12")
	assert_eq(on_flat, 10, "a strength-10 defender on flat ground is unboosted")
	assert_true(on_hill > on_flat, "the hill defence bonus reaches the defender")
	# The same hill bonus does NOT help an attacker (defender-only terrain defence).
	var as_attacker: int = d.effective_strength(gs.db, true, hills, {}, "")
	assert_eq(as_attacker, 10, "terrain defence never helps the attacker")

func test_panther_vs_hill_warrior_odds_are_plausible() -> void:
	# Pin the per-round odds: a full-health Panther (str 2) attacking a full-health,
	# unfortified Warrior (str 2) on a hill. The hill's +25% truncates away at str 2
	# (2 * 125 / 100 = 2), so odds = 2*1000/(2+2) = 500/1000 — a coin flip per
	# round. Winning two such fights in a row is plausible variance, not a bug.
	var gs = make_gs()
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var panther = make_unit(gs, "panther", -2, 5, 6)  # str 2, attacker
	panther.is_wild = true
	panther.is_animal = true
	var warrior = make_unit(gs, "warrior", 1, 5, 5)   # str 2, defender on hill
	var hills: Dictionary = gs.db.get_terrain("hills")
	var d_str: int = warrior.effective_strength(gs.db, false, hills, {}, "")
	var a_str: int = panther.effective_strength(gs.db, true, {}, {}, "")
	assert_eq(a_str, 2, "Panther attacks at strength 2 (reference value, A1)")
	assert_eq(d_str, 2, "Warrior on a hill defends at strength 2 (hill +25% truncates at str 2)")
	# Odds the panther wins a round (out of 1000), as resolve() computes them.
	var a_odds: int = (a_str * 1000) / (a_str + d_str)
	assert_eq(a_odds, 500, "Panther wins ~50% of rounds — an even fight, working as designed")

# ── §9 wild combat modifier (A3, reference semantics) ────────────────────────
# `wild_combat_modifier` (difficulties.json) is a percentage modifier applied to
# the WILD side's strength when it fights a human player's unit — the reference
# model puts the discount on the barbarian's side, never as a bonus on the
# player's own unit — and it skips AI opponents (their handicap is ai_bonus).
# The shipped value is 0 at every level; these inject one to pin the semantics.

func _resolve_wild_fight(seed_val, wild_mod, wild_attacks = false, human_is_ai = false):
	var gs = make_gs(1, seed_val)
	gs.db.difficulties[gs.difficulty_id]["wild_combat_modifier"] = wild_mod
	gs.get_player(1).is_ai = human_is_ai
	var human = make_warrior(gs, 1, 5, 6)
	var raider = make_warrior(gs, -2, 5, 5, true)
	if wild_attacks:
		return Combat.resolve(raider, human, gs, gs.rng)
	return Combat.resolve(human, raider, gs, gs.rng)

func test_wild_combat_modifier_weakens_a_wild_defender() -> void:
	# −90% turns the str-10 raider into a str-1 defender: the human attacker's
	# odds hit the 900/1000 ceiling and its per-hit damage grows, so with the
	# same seed the fight is a rout where the baseline is a coin flip.
	var base: Dictionary = _resolve_wild_fight(42, 0)
	var nerfed: Dictionary = _resolve_wild_fight(42, -90)
	assert_false(nerfed["defender_survived"], "a −90% wild defender loses the fight")
	assert_true(nerfed["attacker_survived"], "the human attacker survives the rout")
	assert_true(int(nerfed["defender_health_after"]) <= int(base["defender_health_after"]),
		"the modifier hurts the wild side, not the player's")

func test_wild_combat_modifier_weakens_a_wild_attacker() -> void:
	# The same modifier applies when the wild unit is the ATTACKER: its own
	# strength is cut, so it dies against the defending human warrior.
	var res: Dictionary = _resolve_wild_fight(42, -90, true)
	assert_false(res["attacker_survived"], "a −90% wild attacker loses the fight")
	assert_true(res["defender_survived"], "the defending human unit survives")

func test_wild_combat_modifier_skips_ai_opponents() -> void:
	# Vs an AI player the modifier is inert (the AI's aid is folded into
	# ai_bonus), so the same seed replays the unmodified fight exactly.
	var base: Dictionary = _resolve_wild_fight(42, 0)
	var vs_ai: Dictionary = _resolve_wild_fight(42, -90, false, true)
	assert_eq(vs_ai["defender_health_after"], base["defender_health_after"],
		"an AI opponent gets no wild-side modifier (defender health identical)")
	assert_eq(vs_ai["attacker_health_after"], base["attacker_health_after"],
		"an AI opponent gets no wild-side modifier (attacker health identical)")
	assert_eq(vs_ai["rounds"], base["rounds"], "the fight replays round-for-round")
