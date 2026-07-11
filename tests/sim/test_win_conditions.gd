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

# ── Diplomatic win is delivered solely by the world assembly ───────────────────
# The old crude population-share tally was removed: governing a momentary 67%
# population majority no longer wins on its own (one early city trivially holds
# 100% of the world's tiny early population). Diplomatic victory now comes
# exclusively from the §7.2 assembly's UN election — covered end-to-end by
# test_assembly.gd (test_diplomatic_victory_elects_a_winner_when_enabled). These
# guard the removal so the regression cannot creep back.

func test_population_majority_is_not_a_diplomatic_win() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["diplomatic"]
	make_settlement(gs, 1, 3, 3, 7)   # the only city → 100% of the population
	assert_eq(WinConditions.check_all(gs), -1,
		"A population majority alone never triggers the diplomatic win")

func test_population_supermajority_does_not_win_over_a_world_step() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["diplomatic"]
	make_settlement(gs, 1, 3, 3, 7)   # 70% of the population…
	make_settlement(gs, 2, 9, 9, 3)   # …but no UN institution exists
	TurnEngine.world_step(gs, _hooks())
	assert_eq(gs.winning_alliance_id, -1,
		"Without the assembly's UN election no one wins diplomatically")

# ── Dominance ──────────────────────────────────────────────────────────────────
# The data condition (data/win_conditions.json) needs 66% of both land and
# population; the helper map is a uniform 20×20 grassland (400 tiles).

func _give_tiles(gs, player_id, fraction_pct) -> void:
	var tiles: Array = gs.map.all_tiles()
	var cutoff: int = (tiles.size() * fraction_pct) / 100
	for i in range(tiles.size()):
		tiles[i].owner_player_id = player_id if i < cutoff else (3 - player_id)

func test_dominance_win_on_land_and_population() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["dominance"]
	_give_tiles(gs, 1, 75)            # player 1 holds 75% of the map
	make_settlement(gs, 1, 1, 1, 8)   # …and 80% of the population (8 vs 2)
	make_settlement(gs, 2, 18, 18, 2)
	assert_eq(WinConditions.check_all(gs), gs.players[0].alliance_id,
		"Holding 66%+ of both land and population wins dominance")

func test_dominance_no_win_when_land_short() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["dominance"]
	_give_tiles(gs, 1, 50)            # only half the land, despite the population edge
	make_settlement(gs, 1, 1, 1, 9)
	make_settlement(gs, 2, 18, 18, 1)
	assert_eq(WinConditions.check_all(gs), -1,
		"A population lead without the land share is not dominance")

func test_dominance_no_win_when_population_short() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["dominance"]
	_give_tiles(gs, 1, 80)            # most of the land, but the population is split
	make_settlement(gs, 1, 1, 1, 5)
	make_settlement(gs, 2, 18, 18, 5)
	assert_eq(WinConditions.check_all(gs), -1,
		"A land lead without the population share is not dominance")

# ── Endgame project (space race) ───────────────────────────────────────────────

func test_endgame_project_win_at_required_stages() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["endgame_project"]
	var req: int = int(gs.db.win_conditions["endgame_project"].get("stages_required", 7))
	gs.endgame_project_stages = {gs.players[0].alliance_id: req}
	assert_eq(WinConditions.check_all(gs), gs.players[0].alliance_id,
		"Completing every endgame-project stage wins")

func test_endgame_project_no_win_before_all_stages() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["endgame_project"]
	var req: int = int(gs.db.win_conditions["endgame_project"].get("stages_required", 7))
	gs.endgame_project_stages = {gs.players[0].alliance_id: req - 1}
	assert_eq(WinConditions.check_all(gs), -1,
		"One stage short of the endgame project is not a win")

func test_projects_carry_a10_reference_counts_and_costs() -> void:
	# A10 data pass (audit §4): pin the reference spaceship part counts
	# (casing x5, thrusters x5, engines x2) and the Apollo/Manhattan costs
	# (1600/1500) so a regression back to the pre-parity numbers fails loudly.
	# (Per-part reference costs are undocumented — the 250-600 costs are
	# unchanged pending a design-doc sitting.)
	var gs = make_gs()
	assert_eq(int(gs.db.projects["ss_casing"].get("count_needed", 0)), 5,
		"SS Casing needs 5 instances (reference)")
	assert_eq(int(gs.db.projects["ss_thrusters"].get("count_needed", 0)), 5,
		"SS Thrusters need 5 instances (reference)")
	assert_eq(int(gs.db.projects["ss_engine"].get("count_needed", 0)), 2,
		"SS Engines need 2 instances (reference)")
	for pid in ["ss_cockpit", "ss_docking_bay", "ss_life_support", "ss_stasis_chamber"]:
		assert_eq(int(gs.db.projects[pid].get("count_needed", 0)), 1,
			"'%s' needs a single instance (reference)" % pid)
	assert_eq(int(gs.db.get_structure("apollo_program").get("cost", 0)), 1600,
		"Apollo Program costs 1600 (reference project cost)")
	assert_eq(int(gs.db.get_structure("manhattan_project").get("cost", 0)), 1500,
		"Manhattan Project costs 1500 (reference project cost)")

func test_completing_a_project_advances_the_stage_count() -> void:
	# Drive the real production path: a finished "project" item bumps the
	# alliance's stage tally (turn_engine `_complete_item`), which is exactly what
	# the endgame win condition reads.
	var gs = make_gs(2)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.production_queue = [{"type": "project", "id": "ss_casing"}]
	s.output_production = 100000        # enough store to finish in one step
	TurnEngine._settlement_production(gs, s, gs.get_player(1))
	assert_eq(int(gs.endgame_project_stages.get(gs.players[0].alliance_id, 0)), 1,
		"Finishing a project increments the alliance's endgame-project stage count")

# ── Cultural ───────────────────────────────────────────────────────────────────
# A settlement reaches the top ring when culture_total passes the last threshold;
# the condition (data default) needs 3 such cities in one alliance.

func test_cultural_win_with_enough_legendary_cities() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["cultural"]
	var max_ring: int = gs.db.constants.get("culture_ring_thresholds", []).size()
	var need: int = int(gs.db.win_conditions["cultural"].get("cities_at_max_culture", 3))
	for i in range(need):
		var s = make_settlement(gs, 1, 2 + i, 2, 4)
		s.culture_ring = max_ring
	assert_eq(WinConditions.check_all(gs), gs.players[0].alliance_id,
		"The required number of top-ring cities wins the cultural condition")

func test_cultural_no_win_one_city_short() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["cultural"]
	var max_ring: int = gs.db.constants.get("culture_ring_thresholds", []).size()
	var need: int = int(gs.db.win_conditions["cultural"].get("cities_at_max_culture", 3))
	for i in range(need - 1):         # one shy of the requirement
		var s = make_settlement(gs, 1, 2 + i, 2, 4)
		s.culture_ring = max_ring
	assert_eq(WinConditions.check_all(gs), -1,
		"One city short of the cultural requirement is not a win")

func test_accumulated_culture_reaches_the_top_ring() -> void:
	# Reachability: enough culture pushes a settlement's ring to the maximum that
	# the cultural win reads, via the real `_settlement_culture` path.
	var gs = make_gs(2)
	var s = make_settlement(gs, 1, 5, 5, 4)
	var thresholds: Array = gs.db.constants.get("culture_ring_thresholds", [])
	s.culture_total = int(thresholds[thresholds.size() - 1]) + 1
	s.output_commerce = 0             # already past the last threshold; no new culture needed
	TurnEngine._settlement_culture(gs, s, gs.get_player(1))
	assert_eq(s.culture_ring, thresholds.size(),
		"Passing the final culture threshold lifts the city to the top ring")

# ── Time / score ───────────────────────────────────────────────────────────────

func test_time_win_goes_to_highest_score_at_turn_limit() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["time"]
	gs.turn_number = gs.max_turns     # the final turn has arrived
	# Player 1 simply has more of everything that scores.
	make_settlement(gs, 1, 3, 3, 9)
	make_settlement(gs, 2, 15, 15, 1)
	for tile in gs.map.all_tiles():
		tile.owner_player_id = 1
	assert_eq(WinConditions.check_all(gs), gs.players[0].alliance_id,
		"At the turn limit the highest-scoring alliance wins on time")

func test_no_time_win_before_turn_limit() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["time"]
	gs.turn_number = gs.max_turns - 1
	make_settlement(gs, 1, 3, 3, 9)
	assert_eq(WinConditions.check_all(gs), -1,
		"The time condition does not fire before the final turn")

# ── Scoring (§10) ────────────────────────────────────────────────────────────

# ── Score victory (§10) — the standalone 7th condition ───────────────────────
# Build a clearly-dominant player (all the land, all the population) so the
# threshold can be pinned just at/over their score; the rival sits near 0.

func _make_runaway(gs) -> void:
	make_settlement(gs, 1, 3, 3, 9)
	make_settlement(gs, 2, 15, 15, 1)
	for tile in gs.map.all_tiles():
		tile.owner_player_id = 1

func test_score_win_when_alliance_reaches_threshold() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["score"]
	_make_runaway(gs)
	Scoring.compute_all(gs)
	gs.db.win_conditions["score"]["score_threshold"] = gs.get_player(1).score
	assert_eq(WinConditions.check_all(gs), gs.players[0].alliance_id,
		"An alliance at/over the score threshold wins immediately")

func test_no_score_win_below_threshold() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["score"]
	_make_runaway(gs)
	Scoring.compute_all(gs)
	gs.db.win_conditions["score"]["score_threshold"] = gs.get_player(1).score + 1
	assert_eq(WinConditions.check_all(gs), -1,
		"An alliance just under the score threshold does not win")

func test_score_win_fires_before_the_turn_limit() -> void:
	# Score is independent of Time: it can award mid-game, whereas Time only
	# tiebreaks at the final turn (which has not arrived here).
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["score", "time"]
	gs.turn_number = gs.max_turns - 1
	_make_runaway(gs)
	Scoring.compute_all(gs)
	gs.db.win_conditions["score"]["score_threshold"] = gs.get_player(1).score
	assert_eq(WinConditions.check_all(gs), gs.players[0].alliance_id,
		"Score awards before the turn limit even with Time also enabled")

func test_wonder_raises_score() -> void:
	var gs = make_gs(2)
	gs.db.structures["great_wonder"] = {"id": "great_wonder", "is_wonder": true}
	var s = make_settlement(gs, 1, 5, 5)
	Scoring.compute_all(gs)
	var base_score: int = gs.get_player(1).score
	s.structures.append("great_wonder")
	Scoring.compute_all(gs)
	assert_gt(gs.get_player(1).score, base_score, "Owning a wonder increases the player's score")
