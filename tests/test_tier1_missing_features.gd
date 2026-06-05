# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://addons/gut/test.gd"

# Tier 1 fixes from docs/missing-engine-features.md:
#   1. per-turn healing                (§5.6)
#   2. auto-promotion on XP threshold  (§5.5)
#   3. alliance shared research        (§6.3)
#   4. belief founding + bonuses       (§8)
#   5. special-person production       (§6.5)

func _make_db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

func _make_gs():
	var db = _make_db()
	var gs = load("res://src/sim/game_state.gd").new()
	gs.db = db
	gs.rng = load("res://src/core/rng.gd").new()
	gs.rng.init(42)
	gs.map = load("res://src/world/world_map.gd").new()
	gs.map.init(20, 20, false, false)
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var p1 = load("res://src/sim/player.gd").new()
	p1.id = 1; p1.alliance_id = 1
	var p2 = load("res://src/sim/player.gd").new()
	p2.id = 2; p2.alliance_id = 2
	gs.players.append(p1); gs.players.append(p2)
	var a1 = load("res://src/sim/alliance.gd").new(); a1.id = 1; a1.add_member(1)
	var a2 = load("res://src/sim/alliance.gd").new(); a2.id = 2; a2.add_member(2)
	gs.alliances.append(a1); gs.alliances.append(a2)
	return gs

func _hooks():
	return load("res://src/sim/hooks.gd").new()

func _warrior(gs, player_id, x, y):
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id()
	u.unit_type_id = "warrior"
	u.owner_player_id = player_id
	u.x = x; u.y = y
	u.base_strength = 10; u.health = 100
	u.movement_total = 200; u.movement_left = 200
	gs.units.append(u)
	return u

func _settlement(gs, player_id, x, y):
	var s = load("res://src/sim/settlement.gd").new()
	s.id = gs.next_settlement_id(); s.owner_player_id = player_id
	s.x = x; s.y = y; s.population = 1
	gs.settlements.append(s)
	return s

# ── 1. Healing ─────────────────────────────────────────────────────────────────

func test_stationary_unit_heals_in_neutral_territory() -> void:
	var gs = _make_gs()
	var u = _warrior(gs, 1, 5, 5)
	u.health = 50
	var rate: int = gs.db.get_constant("healing_neutral_territory", 5)
	TurnEngine.player_step(gs, 1, _hooks())
	assert_eq(u.health, 50 + rate, "Stationary unit heals at the neutral-territory rate")

func test_unit_heals_faster_in_own_settlement() -> void:
	var gs = _make_gs()
	_settlement(gs, 1, 5, 5)
	var u = _warrior(gs, 1, 5, 5)
	u.health = 40
	var rate: int = gs.db.get_constant("healing_in_settlement", 30)
	TurnEngine.player_step(gs, 1, _hooks())
	assert_eq(u.health, 40 + rate, "Garrisoned unit heals at the settlement rate")

func test_moving_unit_does_not_heal() -> void:
	var gs = _make_gs()
	var u = _warrior(gs, 1, 5, 5)
	u.health = 50; u.has_moved = true
	TurnEngine.player_step(gs, 1, _hooks())
	assert_eq(u.health, 50, "A unit that moved this turn does not heal")

func test_healing_caps_at_full() -> void:
	var gs = _make_gs()
	var u = _warrior(gs, 1, 5, 5)
	u.health = 95
	TurnEngine.player_step(gs, 1, _hooks())
	assert_eq(u.health, 100, "Healing never exceeds full health")

# ── 2. Auto-promotion ──────────────────────────────────────────────────────────

func test_unit_auto_promotes_on_xp_threshold() -> void:
	var gs = _make_gs()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade._gs = gs
	facade._db = gs.db
	var atk = _warrior(gs, 1, 5, 6)
	var def = _warrior(gs, 2, 5, 5)
	# Hand the survivor enough XP to clear the first non-zero threshold (10).
	var result = {
		"attacker_survived": true, "defender_survived": false,
		"attacker_health_after": 100, "defender_health_after": 0,
		"attacker_withdrew": false, "rounds": 1,
		"attacker_xp_gain": 15, "defender_xp_gain": 0,
		"spillover_damage": 0, "flanking_damage": 0
	}
	facade._apply_combat_result(atk, def, result)
	assert_eq(atk.experience_level, 1, "Crossing the XP threshold raises the level")
	assert_eq(atk.promotions.size(), 1, "A promotion is awarded on level up")

func test_no_promotion_below_threshold() -> void:
	var gs = _make_gs()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade._gs = gs
	facade._db = gs.db
	var atk = _warrior(gs, 1, 5, 6)
	var def = _warrior(gs, 2, 5, 5)
	var result = {
		"attacker_survived": true, "defender_survived": false,
		"attacker_health_after": 100, "defender_health_after": 0,
		"attacker_withdrew": false, "rounds": 1,
		"attacker_xp_gain": 5, "defender_xp_gain": 0,
		"spillover_damage": 0, "flanking_damage": 0
	}
	facade._apply_combat_result(atk, def, result)
	assert_eq(atk.experience_level, 0, "Below the threshold no level is gained")
	assert_eq(atk.promotions.size(), 0, "No promotion below the threshold")

# ── 3. Alliance shared research ────────────────────────────────────────────────

func test_alliance_pools_research_for_multi_member() -> void:
	var gs = _make_gs()
	# Put players 1 and 2 in one alliance, each with a producing settlement.
	gs.get_player(2).alliance_id = 1
	gs.alliances[0].add_member(2)
	var s1 = _settlement(gs, 1, 3, 3); s1.output_commerce = 100
	var s2 = _settlement(gs, 2, 9, 9); s2.output_commerce = 100
	gs.get_player(1).slider_research = 100; gs.get_player(1).slider_finance = 0
	gs.get_player(1).slider_culture = 0; gs.get_player(1).slider_intel = 0
	gs.get_player(2).slider_research = 100; gs.get_player(2).slider_finance = 0
	gs.get_player(2).slider_culture = 0; gs.get_player(2).slider_intel = 0
	TurnEngine._advance_alliances(gs)
	assert_gt(gs.alliances[0].shared_research_store, 0,
		"A multi-member alliance pools donated research")

func test_solo_alliance_pools_nothing() -> void:
	var gs = _make_gs()
	var s1 = _settlement(gs, 1, 3, 3); s1.output_commerce = 100
	TurnEngine._advance_alliances(gs)
	assert_eq(gs.alliances[0].shared_research_store, 0,
		"A solo alliance contributes nothing to a shared pool (no double count)")

func test_shared_store_drawn_into_member_research() -> void:
	var gs = _make_gs()
	var p = gs.get_player(1)
	gs.get_player(2).alliance_id = 1
	gs.alliances[0].add_member(2)
	p.current_research_id = "mining"
	gs.alliances[0].shared_research_store = 40
	var before: int = p.research_store
	TurnEngine._apply_research(gs, p)
	assert_gt(p.research_store + (40 if p.current_research_id == "" else 0), before,
		"A member draws its share of the shared pool")
	assert_lt(gs.alliances[0].shared_research_store, 40,
		"Drawing from the pool decrements it")

# ── 4. Belief founding ─────────────────────────────────────────────────────────

func test_player_founds_belief_when_eligible() -> void:
	var gs = _make_gs()
	_settlement(gs, 1, 5, 5)
	var founded = Beliefs.try_found(1, gs, gs.rng)
	assert_ne(founded, "", "A player with a settlement founds an eligible belief")
	assert_eq(gs.founded_beliefs.get(founded, -1), 1, "Founder recorded")
	assert_eq(gs.get_settlement_at(5, 5).belief_id, founded, "Settlement becomes the holy site")

func test_no_belief_founded_without_settlement() -> void:
	var gs = _make_gs()
	var founded = Beliefs.try_found(1, gs, gs.rng)
	assert_eq(founded, "", "No belief is founded without a settlement to host it")
	assert_true(gs.founded_beliefs.empty(), "No belief recorded as founded")

func test_belief_adds_happiness() -> void:
	var gs = _make_gs()
	var s = _settlement(gs, 1, 5, 5)
	s.population = 5
	TurnEngine._update_contentment(gs, s, gs.get_player(1), gs.db)
	var base_pos: int = s.positive_sentiment
	s.belief_id = "sun_faith"  # happiness_bonus: 1
	TurnEngine._update_contentment(gs, s, gs.get_player(1), gs.db)
	assert_gt(s.positive_sentiment, base_pos, "An adopted belief raises positive sentiment")

# ── 5. Special-person production ───────────────────────────────────────────────

func test_special_person_births_typed_great_person() -> void:
	# Typed specialists now yield an actual Great Person unit of that type (§14.3),
	# which the player then directs via a GP action.
	var gs = _make_gs()
	var s = _settlement(gs, 1, 5, 5)
	s.special_person_threshold = 10
	s.specialists = {"scientist": 12}  # 12 points >= threshold 10
	TurnEngine._special_person_progress(gs, s)
	assert_eq(s.special_persons_produced, 1, "A special person is produced")
	var found := false
	for u in gs.units:
		if u.owner_player_id == 1 and u.unit_type_id == "great_scientist" \
				and u.x == 5 and u.y == 5:
			found = true
	assert_true(found, "Dominant scientist specialists birth a Great Scientist at the city")

func test_special_person_births_match_dominant_specialist() -> void:
	# The dominant specialist type decides which Great Person is born.
	var gs = _make_gs()
	var s = _settlement(gs, 1, 5, 5)
	s.special_person_threshold = 10
	s.specialists = {"merchant": 12, "scientist": 3}
	TurnEngine._special_person_progress(gs, s)
	assert_eq(s.special_persons_produced, 1, "A special person is produced")
	var found := false
	for u in gs.units:
		if u.owner_player_id == 1 and u.unit_type_id == "great_merchant":
			found = true
	assert_true(found, "More merchant than scientist specialists births a Great Merchant")

func test_special_person_threshold_rises() -> void:
	var gs = _make_gs()
	var s = _settlement(gs, 1, 5, 5)
	s.special_person_threshold = 100
	s.specialists = {"artist": 100}
	TurnEngine._special_person_progress(gs, s)
	assert_gt(s.special_person_threshold, 100, "The next special person costs more")
