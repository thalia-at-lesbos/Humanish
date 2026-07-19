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

# ── Endgame project (space race, §15.16 / M4) ─────────────────────────────────
# Parts tally per type (Projects.count_needed); one of every type launches the
# ship, the arrival countdown ticks per check, at 0 the arrival roll fires.

# Fill alliance `aid`'s tally: every part type at `frac_full` (true = full
# count, false = the minimum one of each).
func _fill_parts(gs, aid, full = true) -> void:
	var tally := {}
	for pid in Projects.endgame_ids(gs.db):
		tally[pid] = Projects.count_needed(gs.db.projects[pid]) if full else 1
	gs.endgame_project_parts[aid] = tally

func test_one_of_every_part_type_launches_the_countdown() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["endgame_project"]
	var aid: int = gs.players[0].alliance_id
	_fill_parts(gs, aid, true)
	assert_eq(WinConditions.check_all(gs), -1,
		"Completing the parts does not win instantly — the ship must travel")
	assert_eq(int(gs.spaceship_countdown.get(aid, -1)), 10,
		"A full ship at normal pace launches with the base 10-turn countdown")

func test_no_launch_while_a_part_type_is_missing() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["endgame_project"]
	var aid: int = gs.players[0].alliance_id
	_fill_parts(gs, aid, true)
	gs.endgame_project_parts[aid].erase("ss_thrusters")
	assert_eq(WinConditions.check_all(gs), -1, "No win with a part type missing")
	assert_false(gs.spaceship_countdown.has(aid),
		"The ship cannot launch while any part type has zero instances")

func test_arrival_countdown_ticks_down_to_victory() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["endgame_project"]
	var aid: int = gs.players[0].alliance_id
	_fill_parts(gs, aid, true)
	assert_eq(WinConditions.check_all(gs), -1, "launch turn: no win yet")
	var rng_before: String = JSON.print(gs.rng.get_state())
	for i in range(9):
		assert_eq(WinConditions.check_all(gs), -1,
			"still travelling %d turns after launch" % (i + 1))
	assert_eq(int(gs.spaceship_countdown.get(aid, -1)), 1,
		"one travel turn left after nine ticks")
	assert_eq(WinConditions.check_all(gs), gs.players[0].alliance_id,
		"The ship arrives when the countdown expires — full casings always succeed")
	assert_eq(JSON.print(gs.rng.get_state()), rng_before,
		"a certain (chance-100) arrival consumes no rng draw")

func test_missing_optional_parts_stretch_the_delay() -> void:
	# Minimum launch (1 of each): 1 engine missing of 2 → 50×1/2 = +25%;
	# 4 thrusters missing of 5 → 100×4/5 = +80%. 10 × 205 / 100 = 20 turns.
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["endgame_project"]
	var aid: int = gs.players[0].alliance_id
	_fill_parts(gs, aid, false)
	WinConditions.check_all(gs)
	assert_eq(int(gs.spaceship_countdown.get(aid, -1)), 20,
		"Missing engines/thrusters stretch the countdown (+25% and +80%)")

func test_pace_scales_the_arrival_delay() -> void:
	# The long-dead victory_delay_scale column finally read: 67/100/150/300.
	var cases := {"quick": 6, "epic": 15, "marathon": 30}
	for pace_id in cases:
		var gs = make_gs(2)
		gs.enabled_win_conditions = ["endgame_project"]
		gs.pace_id = pace_id
		var aid: int = gs.players[0].alliance_id
		_fill_parts(gs, aid, true)
		WinConditions.check_all(gs)
		assert_eq(int(gs.spaceship_countdown.get(aid, -1)), int(cases[pace_id]),
			"victory_delay_scale stretches the countdown on %s" % pace_id)

func test_failed_arrival_loses_the_launch_but_keeps_the_parts() -> void:
	# Missing casings risk the roll: 4 missing × an (injected) 100% penalty
	# clamps the chance to 0, so the arrival fails without an rng draw.
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["endgame_project"]
	var aid: int = gs.players[0].alliance_id
	_fill_parts(gs, aid, true)
	gs.endgame_project_parts[aid]["ss_casing"] = 1
	gs.db.projects["ss_casing"]["success_rate"] = 100
	gs.spaceship_countdown[aid] = 1
	assert_eq(WinConditions.check_all(gs), -1, "A doomed arrival roll is not a win")
	assert_false(gs.spaceship_countdown.has(aid),
		"A failed arrival spends the launch — the countdown is cleared")
	assert_eq(int(gs.endgame_project_parts[aid].get("ss_thrusters", 0)), 5,
		"Built parts survive a failed arrival")
	# The next check auto-relaunches from scratch (a re-launch is possible).
	WinConditions.check_all(gs)
	assert_true(gs.spaceship_countdown.has(aid),
		"With every part type still present the ship re-launches")

func test_losing_the_capital_cancels_the_countdown() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["endgame_project"]
	var aid: int = gs.players[0].alliance_id
	_fill_parts(gs, aid, true)
	WinConditions.check_all(gs)
	assert_true(gs.spaceship_countdown.has(aid), "launched")
	var cap = make_settlement(gs, 1, 4, 4, 3)
	cap.structures.append("palace")
	assert_true(WinConditions.spaceship_capital_lost(gs, cap),
		"Losing the palace city cancels the arrival countdown")
	assert_false(gs.spaceship_countdown.has(aid), "the spaceship is lost")
	assert_false(WinConditions.spaceship_capital_lost(gs, cap),
		"No countdown in flight: nothing further to cancel")

func test_non_capital_loss_keeps_the_countdown() -> void:
	var gs = make_gs(2)
	var aid: int = gs.players[0].alliance_id
	_fill_parts(gs, aid, true)
	gs.spaceship_countdown[aid] = 5
	var town = make_settlement(gs, 1, 8, 8, 2)
	assert_false(WinConditions.spaceship_capital_lost(gs, town),
		"A non-palace city falling never cancels the launch")
	assert_eq(int(gs.spaceship_countdown.get(aid, -1)), 5, "countdown intact")

func test_spaceship_state_roundtrips_with_int_keys() -> void:
	# JSON returns dict keys as strings and numbers as floats; deserialize must
	# coerce the alliance keys and counts back to int (the recurring gotcha).
	var gs = make_gs(2)
	var aid: int = gs.players[0].alliance_id
	_fill_parts(gs, aid, false)
	gs.spaceship_countdown[aid] = 7
	var text: String = JSON.print(gs.serialize())
	var gs2 = GameState.deserialize(JSON.parse(text).result, gs.db)
	assert_true(gs2.endgame_project_parts.has(aid),
		"per-type tallies come back keyed by INT alliance id")
	assert_true(gs2.spaceship_countdown.has(aid),
		"countdowns come back keyed by INT alliance id")
	assert_eq(int(gs2.spaceship_countdown[aid]), 7, "countdown value survives")
	assert_eq(gs2.endgame_project_parts[aid].get("ss_engine", -1), 1,
		"per-type counts come back as ints")
	assert_eq(JSON.print(gs2.serialize()), text,
		"a load/save roundtrip reproduces the identical save")

func test_old_flat_stage_save_migrates_to_per_type() -> void:
	# A pre-M4 save carried alliance_id -> flat stage count; k stages migrate to
	# one part each of the first k types in `stage` order.
	var gs = make_gs(2)
	var aid: int = gs.players[0].alliance_id
	var d: Dictionary = JSON.parse(JSON.print(gs.serialize())).result
	d.erase("endgame_project_parts")
	d.erase("spaceship_countdown")
	d["endgame_project_stages"] = {str(aid): 3}
	var gs2 = GameState.deserialize(d, gs.db)
	var tally: Dictionary = gs2.endgame_project_parts.get(aid, {})
	assert_eq(int(tally.get("ss_casing", 0)), 1, "stage 1 migrates to a casing")
	assert_eq(int(tally.get("ss_cockpit", 0)), 1, "stage 2 migrates to a cockpit")
	assert_eq(int(tally.get("ss_docking_bay", 0)), 1, "stage 3 migrates to a docking bay")
	assert_eq(int(tally.get("ss_engine", 0)), 0, "later stages stay unbuilt")

func test_projects_carry_a10_reference_counts_and_costs() -> void:
	# A10 data pass (audit §4): pin the reference spaceship part counts
	# (casing x5, thrusters x5, engines x2), the per-part costs (verified against
	# the reference 2026-07-11), and the Apollo/Manhattan costs (1600/1500) so a
	# regression back to the pre-parity numbers fails loudly.
	var gs = make_gs()
	var part_costs := {"ss_casing": 1200, "ss_cockpit": 1000, "ss_docking_bay": 2000,
		"ss_engine": 1600, "ss_life_support": 1000, "ss_stasis_chamber": 1200,
		"ss_thrusters": 1200}
	for pid in part_costs:
		assert_eq(int(gs.db.projects[pid].get("cost", 0)), int(part_costs[pid]),
			"'%s' carries the reference per-part cost" % pid)
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

func test_completing_a_project_advances_the_part_tally() -> void:
	# Drive the real production path: a finished "project" item bumps the
	# alliance's PER-TYPE part tally (turn_engine `_complete_item`), which is
	# exactly what the endgame win condition reads (§15.16 / M4).
	var gs = make_gs(2)
	var s = make_settlement(gs, 1, 5, 5, 3)
	s.production_queue = [{"type": "project", "id": "ss_casing"}]
	s.output_production = 100000        # enough store to finish in one step
	TurnEngine._settlement_production(gs, s, gs.get_player(1))
	var tally: Dictionary = gs.endgame_project_parts.get(gs.players[0].alliance_id, {})
	assert_eq(int(tally.get("ss_casing", 0)), 1,
		"Finishing a part increments the alliance's tally for that type")

func test_duplicate_part_of_a_filled_type_is_a_noop() -> void:
	# ss_cockpit needs a single instance; a second cockpit no longer advances
	# the race (the hammers are lost, as in the reference).
	var gs = make_gs(2)
	var p1 = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	TurnEngine._complete_item(gs, s, p1, {"type": "project", "id": "ss_cockpit"})
	TurnEngine._complete_item(gs, s, p1, {"type": "project", "id": "ss_cockpit"})
	assert_eq(int(gs.endgame_project_parts[p1.alliance_id].get("ss_cockpit", 0)), 1,
		"A duplicate of an already-filled part type does not advance the race")
	TurnEngine._complete_item(gs, s, p1, {"type": "project", "id": "ss_engine"})
	TurnEngine._complete_item(gs, s, p1, {"type": "project", "id": "ss_engine"})
	TurnEngine._complete_item(gs, s, p1, {"type": "project", "id": "ss_engine"})
	assert_eq(int(gs.endgame_project_parts[p1.alliance_id].get("ss_engine", 0)), 2,
		"Engines cap at their count_needed of 2")

# ── Cultural ───────────────────────────────────────────────────────────────────
# A settlement reaches the top ring when culture_total passes the last threshold;
# the condition (data default) needs 3 such cities in one alliance.

func test_cultural_win_with_enough_legendary_cities() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["cultural"]
	var legendary: int = CultureLevels.legendary_threshold(gs.db, gs.pace_id)
	var need: int = int(gs.db.win_conditions["cultural"].get("cities_at_max_culture", 3))
	for i in range(need):
		var s = make_settlement(gs, 1, 2 + i, 2, 4)
		s.culture_total = legendary   # the pace's top culture-level threshold
	assert_eq(WinConditions.check_all(gs), gs.players[0].alliance_id,
		"The required number of legendary-culture cities wins the cultural condition")

func test_cultural_no_win_one_city_short() -> void:
	var gs = make_gs(2)
	gs.enabled_win_conditions = ["cultural"]
	var legendary: int = CultureLevels.legendary_threshold(gs.db, gs.pace_id)
	var need: int = int(gs.db.win_conditions["cultural"].get("cities_at_max_culture", 3))
	for i in range(need - 1):         # one shy of the requirement
		var s = make_settlement(gs, 1, 2 + i, 2, 4)
		s.culture_total = legendary
	assert_eq(WinConditions.check_all(gs), -1,
		"One city short of the cultural requirement is not a win")

func test_cultural_threshold_scales_with_game_pace() -> void:
	# §15.4 (D2): the legendary-culture requirement is the pace's own top
	# culture-level threshold — 25000/50000/75000/150000 on quick/normal/epic/
	# marathon (the reference per-speed table; no victory_delay_scale stretch).
	var cases := {"quick": 25000, "normal": 50000, "epic": 75000, "marathon": 150000}
	for pace_id in cases:
		var gs = make_gs(2)
		gs.enabled_win_conditions = ["cultural"]
		gs.pace_id = pace_id
		var need: int = int(gs.db.win_conditions["cultural"].get("cities_at_max_culture", 3))
		for i in range(need):
			var s = make_settlement(gs, 1, 2 + i, 2, 4)
			s.culture_total = cases[pace_id] - 1
		assert_eq(WinConditions.check_all(gs), -1,
			"%s culture is one short of legendary on %s" % [cases[pace_id] - 1, pace_id])
		for s2 in gs.settlements:
			s2.culture_total = cases[pace_id]
		assert_eq(WinConditions.check_all(gs), gs.players[0].alliance_id,
			"%s culture per city wins the cultural condition on %s" % [cases[pace_id], pace_id])

func test_accumulated_culture_reaches_the_top_ring() -> void:
	# Reachability: enough culture pushes a settlement's ring to the maximum that
	# the cultural win reads, via the real `_settlement_culture` path. On the D2
	# curve the top (legendary) ring is level 5 + 1 = 6.
	var gs = make_gs(2)
	var s = make_settlement(gs, 1, 5, 5, 4)
	var thresholds: Array = CultureLevels.thresholds(gs.db, gs.pace_id)
	s.culture_total = CultureLevels.legendary_threshold(gs.db, gs.pace_id) + 1
	s.output_commerce = 0             # already past the last threshold; no new culture needed
	TurnEngine._settlement_culture(gs, s, gs.get_player(1))
	assert_eq(s.culture_ring, thresholds.size() + 1,
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
