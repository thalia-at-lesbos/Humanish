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

# Victory & scoring (§10): last-standing, the assembly vote that drives the
# diplomatic win, and wonders feeding into the score weighting.

func _hooks():
	return hooks()

# ── Last standing ────────────────────────────────────────────────────────────

func test_last_standing_win() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["last_standing"]
	gs.players[1].is_eliminated = true
	make_settlement(gs, gs.players[0].id, 5, 5)
	make_warrior(gs, gs.players[0].id, 5, 6)
	var winner: int = WinConditions.check_all(gs)
	assert_eq(winner, gs.players[0].alliance_id, "The sole survivor's alliance wins last_standing")

# ── Diplomatic win ─────────────────────────────────────────────────────────────

func test_diplomatic_win_on_supermajority() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["diplomatic"]
	gs.diplomatic_votes = {1: 70, 2: 30}  # 70% >= 67% required
	assert_eq(WinConditions.check_all(gs), 1, "Alliance with the required vote share wins")

func test_diplomatic_no_win_below_threshold() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["diplomatic"]
	gs.diplomatic_votes = {1: 60, 2: 40}  # 60% < 67%
	assert_eq(WinConditions.check_all(gs), -1, "No diplomatic win below the required share")

func test_diplomatic_no_win_without_votes() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["diplomatic"]
	assert_eq(WinConditions.check_all(gs), -1,
		"No diplomatic win when the assembly has cast no votes")

func test_diplomatic_votes_survive_save_load() -> void:
	var gs = make_gs(2)
	gs.diplomatic_votes = {1: 5, 2: 9}
	var restored = load("res://src/sim/game_state.gd").deserialize(gs.serialize(), gs.db)
	assert_eq(int(restored.diplomatic_votes.get(2, 0)), 9,
		"diplomatic_votes round-trips through serialization")

# ── Assembly drives the diplomatic vote (§3.7) ─────────────────────────────────

func test_assembly_tallies_votes_by_population() -> void:
	var gs = make_gs(2)
	make_settlement(gs, 1, 3, 3, 7)
	make_settlement(gs, 2, 9, 9, 3)
	TurnEngine._resolve_assembly(gs)
	assert_eq(int(gs.diplomatic_votes.get(1, 0)), 7, "Alliance 1 polls its population")
	assert_eq(int(gs.diplomatic_votes.get(2, 0)), 3, "Alliance 2 polls its population")

func test_assembly_enables_diplomatic_victory() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["diplomatic"]
	make_settlement(gs, 1, 3, 3, 7)  # 70% of 10 votes
	make_settlement(gs, 2, 9, 9, 3)
	TurnEngine.world_step(gs, _hooks())
	assert_eq(gs.winning_alliance_id, 1, "A population supermajority wins the assembly vote")

func test_no_diplomatic_win_when_split() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["diplomatic"]
	make_settlement(gs, 1, 3, 3, 5)
	make_settlement(gs, 2, 9, 9, 5)
	TurnEngine.world_step(gs, _hooks())
	assert_eq(gs.winning_alliance_id, -1, "An even split elects no one")

# ── Scoring (§10) ────────────────────────────────────────────────────────────

func test_wonder_raises_score() -> void:
	var gs = make_gs(2)
	gs.db.structures["great_wonder"] = {"id": "great_wonder", "is_wonder": true}
	var s = make_settlement(gs, 1, 5, 5)
	Scoring.compute_all(gs)
	var base_score: int = gs.get_player(1).score
	s.structures.append("great_wonder")
	Scoring.compute_all(gs)
	assert_gt(gs.get_player(1).score, base_score, "Owning a wonder increases the player's score")
