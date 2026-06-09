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
