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

# TurnEngine cross-cutting invariants — things that span the per-settlement and
# per-player pipeline and don't belong in a single feature's test file.
# Currently: Phase-A difficulty handicap for AI players (§2.2 ai_bonus).

# ── A1: AI production handicap ───────────────────────────────────────────────

func test_ai_production_bonus_on_deity() -> void:
	var gs = make_gs(2)
	gs.difficulty_id = "deity"  # ai_bonus = 70

	var human = gs.get_player(1)
	var ai    = gs.get_player(2)
	ai.is_ai = true

	# output_production=5: warrior costs 15, so neither city completes it this turn.
	# human: Fixed.scale(5, 100)=5; AI: Fixed.scale(5, 170)=8
	var human_city = make_settlement(gs, 1, 5, 5)
	human_city.output_production = 5
	human_city.production_queue  = [{"type": "unit", "id": "warrior"}]

	var ai_city = make_settlement(gs, 2, 15, 15)
	ai_city.output_production = 5
	ai_city.production_queue  = [{"type": "unit", "id": "warrior"}]

	TurnEngine._settlement_production(gs, human_city, human)
	TurnEngine._settlement_production(gs, ai_city, ai)

	assert_eq(human_city.production_store, 5, "human production unscaled on deity")
	assert_eq(ai_city.production_store, 8,  "AI production is 170% of human on deity")

func test_ai_production_no_bonus_on_noble() -> void:
	var gs = make_gs(2)
	gs.difficulty_id = "noble"  # ai_bonus = 0

	var human = gs.get_player(1)
	var ai    = gs.get_player(2)
	ai.is_ai = true

	var human_city = make_settlement(gs, 1, 5, 5)
	human_city.output_production = 5
	human_city.production_queue  = [{"type": "unit", "id": "warrior"}]

	var ai_city = make_settlement(gs, 2, 15, 15)
	ai_city.output_production = 5
	ai_city.production_queue  = [{"type": "unit", "id": "warrior"}]

	TurnEngine._settlement_production(gs, human_city, human)
	TurnEngine._settlement_production(gs, ai_city, ai)

	assert_eq(human_city.production_store, ai_city.production_store,
		"human and AI production match when ai_bonus is 0")

func test_human_production_unaffected_by_ai_bonus() -> void:
	var gs = make_gs(1)
	gs.difficulty_id = "deity"  # ai_bonus = 70

	var human = gs.get_player(1)  # is_ai = false by default

	var city = make_settlement(gs, 1, 5, 5)
	city.output_production = 5
	city.production_queue  = [{"type": "unit", "id": "warrior"}]

	TurnEngine._settlement_production(gs, city, human)

	assert_eq(city.production_store, 5, "human production is never affected by ai_bonus")

# ── A2: AI research handicap ─────────────────────────────────────────────────

func test_ai_research_bonus_on_deity() -> void:
	var gs = make_gs(2)
	gs.difficulty_id = "deity"  # ai_bonus = 70

	var human = gs.get_player(1)
	var ai    = gs.get_player(2)
	ai.is_ai = true

	# Both need a current research target and a settlement producing commerce.
	human.current_research_id = "mining"
	ai.current_research_id    = "mining"

	var human_city = make_settlement(gs, 1, 5, 5)
	human_city.output_commerce = 10

	var ai_city = make_settlement(gs, 2, 15, 15)
	ai_city.output_commerce = 10

	# Gather baselines before calling _apply_research.
	var human_before: int = human.research_store
	var ai_before: int    = ai.research_store

	TurnEngine._apply_research(gs, human)
	TurnEngine._apply_research(gs, ai)

	# Default slider_research=100, so all commerce → research.
	# human beakers = Fixed.scale(10, 100) = 10
	# AI beakers    = Fixed.scale(10, 170) = 17
	var human_gain: int = human.research_store - human_before
	var ai_gain: int    = ai.research_store    - ai_before

	assert_eq(human_gain, 10, "human research output unscaled on deity")
	assert_eq(ai_gain, 17,    "AI research is 170% of human on deity")

func test_ai_research_no_bonus_on_noble() -> void:
	var gs = make_gs(2)
	gs.difficulty_id = "noble"  # ai_bonus = 0

	var human = gs.get_player(1)
	var ai    = gs.get_player(2)
	ai.is_ai = true

	human.current_research_id = "mining"
	ai.current_research_id    = "mining"

	make_settlement(gs, 1, 5, 5).output_commerce  = 10
	make_settlement(gs, 2, 15, 15).output_commerce = 10

	TurnEngine._apply_research(gs, human)
	TurnEngine._apply_research(gs, ai)

	assert_eq(human.research_store, ai.research_store,
		"human and AI beakers match when ai_bonus is 0")

func test_human_research_unaffected_by_ai_bonus() -> void:
	var gs = make_gs(1)
	gs.difficulty_id = "deity"  # ai_bonus = 70

	var human = gs.get_player(1)  # is_ai = false
	human.current_research_id = "mining"
	make_settlement(gs, 1, 5, 5).output_commerce = 10

	TurnEngine._apply_research(gs, human)

	assert_eq(human.research_store, 10, "human research is never affected by ai_bonus")

# ── C8: war-weariness peace decay (§15.8) ────────────────────────────────────

func test_war_weariness_decays_in_peace() -> void:
	var gs = make_gs(2)
	gs.alliances[0].war_fatigue = {2: 101}
	TurnEngine._decay_war_fatigue(gs)
	# (101 - 1) * 99 / 100 = 99 — the flat decay rate, then the peace percent.
	assert_eq(int(gs.alliances[0].war_fatigue.get(2, 0)), 99,
		"Peace decay: minus the decay rate, then keep the peace percent")

func test_war_weariness_does_not_decay_while_at_war() -> void:
	var gs = make_gs(2)
	gs.alliances[0].at_war_with = [2]
	gs.alliances[0].war_fatigue = {2: 50}
	TurnEngine._decay_war_fatigue(gs)
	assert_eq(int(gs.alliances[0].war_fatigue.get(2, 0)), 50,
		"A hot war never decays")
	# The asymmetric case: only the OTHER side lists the war — still hot.
	var gs2 = make_gs(2)
	gs2.alliances[1].at_war_with = [1]
	gs2.alliances[0].war_fatigue = {2: 50}
	TurnEngine._decay_war_fatigue(gs2)
	assert_eq(int(gs2.alliances[0].war_fatigue.get(2, 0)), 50,
		"Either side listing the war blocks decay")

func test_war_weariness_entry_erased_at_zero() -> void:
	var gs = make_gs(2)
	gs.alliances[0].war_fatigue = {2: 1}
	TurnEngine._decay_war_fatigue(gs)
	assert_false(gs.alliances[0].war_fatigue.has(2),
		"A fully decayed entry is erased, keeping the dictionary clean")

func test_world_step_runs_the_peace_decay() -> void:
	var gs = make_gs(2)
	gs.alliances[0].war_fatigue = {2: 101}
	TurnEngine.world_step(gs, hooks())
	assert_eq(int(gs.alliances[0].war_fatigue.get(2, 0)), 99,
		"world_step applies the peace decay each turn")

# ── W4: Statue of Zeus enemy_war_weariness (§15) ─────────────────────────────
#
# A standing structure carrying `enemy_war_weariness` (Statue of Zeus, +100%)
# amplifies the war-weariness its owner's enemies accrue against them, at the
# shared per-event accrual site (CombatApply.accrue_war_fatigue).

func test_statue_of_zeus_doubles_enemy_accrual() -> void:
	var gs = make_gs(2)
	var zeus_city = make_settlement(gs, 2, 15, 15)
	zeus_city.structures.append("statue_of_zeus")  # enemy_war_weariness: 100
	# Player 1 loses a unit attacking player 2: base 3 × multiplier 2 = 6,
	# doubled by the enemy's statue → 12.
	CombatApply.accrue_war_fatigue(gs, 1, 2, "war_weariness_unit_killed_attacking")
	assert_eq(int(gs.alliances[0].war_fatigue.get(2, 0)), 12,
		"The statue doubles the fatigue the enemy accrues against its owner")

func test_statue_of_zeus_does_not_boost_owner_accrual() -> void:
	var gs = make_gs(2)
	var zeus_city = make_settlement(gs, 2, 15, 15)
	zeus_city.structures.append("statue_of_zeus")
	# The owner's own accrual against player 1 is unamplified: 3 × 2 = 6.
	CombatApply.accrue_war_fatigue(gs, 2, 1, "war_weariness_unit_killed_attacking")
	assert_eq(int(gs.alliances[1].war_fatigue.get(1, 0)), 6,
		"The owner's own weariness accrues at the normal rate")

func test_accrual_unchanged_without_the_statue() -> void:
	var gs = make_gs(2)
	make_settlement(gs, 2, 15, 15)  # enemy city, no wonder
	CombatApply.accrue_war_fatigue(gs, 1, 2, "war_weariness_unit_killed_attacking")
	assert_eq(int(gs.alliances[0].war_fatigue.get(2, 0)), 6,
		"No enemy_war_weariness structure → the plain 3 × 2 accrual")

func test_statue_of_zeus_stops_counting_after_capture() -> void:
	var gs = make_gs(2)
	var zeus_city = make_settlement(gs, 2, 15, 15)
	zeus_city.structures.append("statue_of_zeus")
	zeus_city.owner_player_id = 1  # captured by the attacker
	CombatApply.accrue_war_fatigue(gs, 1, 2, "war_weariness_unit_killed_attacking")
	assert_eq(int(gs.alliances[0].war_fatigue.get(2, 0)), 6,
		"A captured statue no longer amplifies accrual against its old owner")
