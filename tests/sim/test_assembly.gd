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

# §7.2 Diplomatic assemblies, elections & resolutions (provisional). Exercises the
# founding-wonder gate, membership/vote weight, the session→vote→resolve lifecycle,
# resolution effects, and serialization. The facade voting path lives in
# tests/api/test_sim_facade.gd-adjacent suites; here we drive the Assembly module
# and GameState directly.

const APOSTOLIC := "apostolic_palace"
const UN := "united_nations"

# Build a 3-player state where player 1 founds the religious assembly via the
# Apostolic Palace in a christian capital. Players 2/3 also hold christian cities so
# they are eligible religious members.
func _religious_gs(seed_val = 7):
	var gs = make_gs(3, seed_val)
	var c1 = make_settlement(gs, 1, 3, 3, 5)
	c1.belief_id = "christianity"
	c1.structures.append(APOSTOLIC)
	var c2 = make_settlement(gs, 2, 8, 8, 3)
	c2.belief_id = "christianity"
	var c3 = make_settlement(gs, 3, 14, 14, 2)
	c3.belief_id = "christianity"
	return gs

# Build a 3-player state where player 1 founds the secular United Nations. Weights are
# total population: 5 / 3 / 2. Diplomatic victory is enabled.
func _secular_gs(seed_val = 11):
	var gs = make_gs(3, seed_val)
	make_settlement(gs, 1, 3, 3, 5).structures.append(UN)
	make_settlement(gs, 2, 8, 8, 3)
	make_settlement(gs, 3, 14, 14, 2)
	gs.enabled_win_conditions = ["diplomatic"]
	return gs

# ── Founding-wonder gate ───────────────────────────────────────────────────────

func test_no_assembly_without_a_founding_wonder() -> void:
	var gs = make_gs(2)
	make_settlement(gs, 1, 3, 3, 4)
	assert_eq(Assembly.active_body(gs), "", "No wonder, no assembly")
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)
	assert_true(gs.assembly.empty(), "world_tick founds nothing without a wonder")

func test_apostolic_palace_founds_religious_body() -> void:
	var gs = _religious_gs()
	assert_eq(Assembly.active_body(gs), "religious", "Apostolic Palace founds the religious body")

func test_united_nations_supersedes_religious_body() -> void:
	var gs = _religious_gs()
	gs.get_settlement(1).structures.append(UN)
	assert_eq(Assembly.active_body(gs), "secular", "The UN supersedes the Apostolic Palace")

func test_assembly_torn_down_when_wonder_lost() -> void:
	var gs = _religious_gs()
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)
	assert_false(gs.assembly.empty(), "Assembly established")
	gs.get_settlement(1).structures.erase(APOSTOLIC)
	Assembly.world_tick(gs, gs.rng)
	assert_true(gs.assembly.empty(), "Losing the founding wonder dissolves the assembly")

# ── Membership & vote weight ───────────────────────────────────────────────────

func test_religious_weight_counts_only_believing_cities() -> void:
	var gs = _religious_gs()
	# Player 1 also has a non-believing city: it must not add weight.
	var extra = make_settlement(gs, 1, 5, 5, 9)
	extra.belief_id = ""
	assert_eq(Assembly.vote_weight(gs, gs.get_player(1), "religious"), 5,
		"Only the christian capital (pop 5) counts toward religious weight")

func test_secular_weight_counts_all_population() -> void:
	var gs = _religious_gs()
	var extra = make_settlement(gs, 1, 5, 5, 9)
	extra.belief_id = ""
	assert_eq(Assembly.vote_weight(gs, gs.get_player(1), "secular"), 14,
		"Secular weight is total population (5 + 9)")

func test_nonbelievers_are_not_religious_members() -> void:
	var gs = make_gs(2)
	var c1 = make_settlement(gs, 1, 3, 3, 4)
	c1.belief_id = "christianity"
	c1.structures.append(APOSTOLIC)
	make_settlement(gs, 2, 8, 8, 4)  # no belief
	assert_true(Assembly.is_member(gs, gs.get_player(1), "religious"), "Believer is a member")
	assert_false(Assembly.is_member(gs, gs.get_player(2), "religious"),
		"A player with no believing city is not a religious member")

# ── Session lifecycle: first session elects a resident ─────────────────────────

func test_first_session_opens_a_resident_election() -> void:
	var gs = _religious_gs()
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)
	assert_true(Assembly.has_open_session(gs), "A session opens on the cadence")
	var pending = Assembly.pending_proposal(gs)
	assert_eq(str(pending["resolution_id"]), "elect_resident",
		"With no resident, the chamber first elects one")
	# Front-runner is the highest-weight member (player 1, pop 5).
	assert_eq(int(pending["candidate_player_id"]), 1, "Highest-weight member is the candidate")
	assert_true(str(pending["text"]).find("P1") >= 0, "Proposal text names the candidate")

func test_resident_elected_when_members_vote_yea() -> void:
	var gs = _religious_gs()
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)   # open
	for pid in [1, 2, 3]:
		assert_true(Assembly.cast_vote(gs, pid, Assembly.VOTE_YEA), "Member %d votes" % pid)
	Assembly.world_tick(gs, gs.rng)   # resolve
	assert_false(Assembly.has_open_session(gs), "Proposal resolved, session closed")
	assert_eq(int(gs.assembly["resident_player_id"]), 1, "The candidate becomes resident")

func test_proposal_fails_below_pass_share() -> void:
	var gs = _religious_gs()
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)
	# Yea weight 3 of 10 total (30%) is below the 50% pass share, so the motion fails.
	Assembly.cast_vote(gs, 1, Assembly.VOTE_NAY)   # weight 5
	Assembly.cast_vote(gs, 2, Assembly.VOTE_YEA)   # weight 3
	Assembly.cast_vote(gs, 3, Assembly.VOTE_NAY)   # weight 2
	Assembly.world_tick(gs, gs.rng)
	assert_eq(int(gs.assembly["resident_player_id"]), -1, "A defeated election seats no resident")

func test_non_member_cannot_vote() -> void:
	var gs = make_gs(2)
	var c1 = make_settlement(gs, 1, 3, 3, 4)
	c1.belief_id = "christianity"
	c1.structures.append(APOSTOLIC)
	make_settlement(gs, 2, 8, 8, 4)
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)
	assert_false(Assembly.cast_vote(gs, 2, Assembly.VOTE_YEA),
		"A non-member's vote is rejected")

# ── Resolution effects ─────────────────────────────────────────────────────────

func test_force_peace_ends_all_wars() -> void:
	var gs = _religious_gs()
	gs.get_alliance(1).at_war_with = [2]
	gs.get_alliance(2).at_war_with = [1]
	Assembly._establish(gs, "religious")
	gs.assembly["resident_player_id"] = 1
	Assembly.apply_effect(gs, "force_peace", {})
	assert_true(gs.get_alliance(1).at_war_with.empty(), "Aggressor's wars cleared")
	assert_true(gs.get_alliance(2).at_war_with.empty(), "Defender's wars cleared")

func test_diplomatic_victory_elects_a_winner_when_enabled() -> void:
	var gs = _religious_gs()
	gs.enabled_win_conditions = ["diplomatic"]
	Assembly._establish(gs, "religious")
	Assembly.apply_effect(gs, "diplomatic_victory", {"candidate_player_id": 2})
	assert_eq(gs.winning_alliance_id, 2, "Passing the supreme-leadership motion wins the game")

func test_diplomatic_victory_inert_when_condition_disabled() -> void:
	var gs = _religious_gs()
	gs.enabled_win_conditions = ["time"]
	Assembly._establish(gs, "religious")
	Assembly.apply_effect(gs, "diplomatic_victory", {"candidate_player_id": 2})
	assert_eq(gs.winning_alliance_id, -1, "No diplomatic win when the condition is off")

func test_religion_mandate_sets_state_religion() -> void:
	var gs = _religious_gs()
	Assembly._establish(gs, "religious")
	Assembly.apply_effect(gs, "religion_mandate", {"belief_id": "christianity"})
	assert_eq(gs.get_player(2).state_religion, "christianity",
		"Members harbouring the faith adopt it as state religion")

func test_resident_aid_grants_gold() -> void:
	var gs = _religious_gs()
	Assembly._establish(gs, "religious")
	gs.assembly["resident_player_id"] = 1
	var before = gs.get_player(1).treasury
	Assembly.apply_effect(gs, "resident_aid", {})
	assert_eq(gs.get_player(1).treasury, before + gs.db.get_constant("resident_aid_gold", 100),
		"The resident receives the aid grant")

func test_civic_mandate_aligns_members() -> void:
	var gs = _religious_gs()
	Assembly._establish(gs, "religious")
	gs.assembly["resident_player_id"] = 1
	gs.get_player(1).policies["government"] = "despotism"
	Assembly.apply_effect(gs, "civic_mandate", {})
	assert_eq(str(gs.get_player(2).policies.get("government", "")), "despotism",
		"Members align to the resident's government civic")

func test_trade_embargo_recorded_as_standing_effect() -> void:
	var gs = _religious_gs()
	Assembly._establish(gs, "religious")
	Assembly.apply_effect(gs, "trade_embargo", {"target_alliance_id": 2})
	assert_eq(int(gs.assembly["standing"]["trade_embargo"]), 2,
		"The embargo target is recorded as a standing effect")

# ── Diplomatic victory: thresholds, gates & the "too big" rule (§7.3) ───────────

func test_state_religion_doubles_religious_vote_weight() -> void:
	var gs = _religious_gs()
	gs.get_player(1).state_religion = "christianity"
	assert_eq(Assembly.vote_weight(gs, gs.get_player(1), "religious"), 10,
		"Running the assembly belief as state religion doubles weight (5 -> 10)")
	assert_eq(Assembly.vote_weight(gs, gs.get_player(2), "religious"), 3,
		"A non-adherent member keeps its base weight")

func test_ap_victory_motion_appears_on_its_cadence() -> void:
	var gs = _religious_gs()
	gs.enabled_win_conditions = ["diplomatic"]
	gs.turn_number = gs.db.get_constant("ap_diplo_victory_interval", 50)
	Assembly.world_tick(gs, gs.rng)
	assert_true(Assembly.has_open_session(gs), "AP victory motion opens on its cadence")
	assert_eq(str(Assembly.pending_proposal(gs)["resolution_id"]), "diplomatic_victory",
		"The dedicated cadence proposes the supreme-leadership motion")

func test_ap_victory_motion_suppressed_when_a_civ_lacks_the_belief() -> void:
	var gs = _religious_gs()
	gs.enabled_win_conditions = ["diplomatic"]
	gs.get_settlement(3).belief_id = ""   # player 3 no longer follows the faith anywhere
	gs.turn_number = gs.db.get_constant("ap_diplo_victory_interval", 50)  # not a session-interval turn
	Assembly.world_tick(gs, gs.rng)
	assert_false(Assembly.has_open_session(gs),
		"With an unfaithful civ the AP victory motion is not put forward")

# Open the diplomatic-victory motion through the AP cadence (so its candidate slate
# is built) and return the pending proposal. Player 1 owns the Apostolic Palace.
func _open_ap_victory(gs):
	gs.enabled_win_conditions = ["diplomatic"]
	gs.turn_number = gs.db.get_constant("ap_diplo_victory_interval", 50)
	Assembly.world_tick(gs, gs.rng)
	return Assembly.pending_proposal(gs)

func test_ap_victory_needs_three_quarters() -> void:
	# Religious chamber, weights 5/3/2 (total 10). Player 1 is the sole candidate
	# (owner and front-runner), so members vote for "1" or abstain.
	var gs = _religious_gs()
	_open_ap_victory(gs)
	Assembly.cast_vote(gs, 1, "1")   # 5
	Assembly.cast_vote(gs, 2, "1")   # 3  -> 8/10 = 80%
	Assembly.cast_vote(gs, 3, Assembly.VOTE_ABSTAIN)   # 2
	Assembly.world_tick(gs, gs.rng)  # resolves the pending motion
	assert_eq(gs.winning_alliance_id, 1, "80% clears the 75% Apostolic bar")

func test_ap_victory_fails_below_three_quarters() -> void:
	var gs = _religious_gs()
	_open_ap_victory(gs)
	Assembly.cast_vote(gs, 1, "1")   # 5
	Assembly.cast_vote(gs, 3, "1")   # 2  -> 7/10 = 70%
	Assembly.cast_vote(gs, 2, Assembly.VOTE_ABSTAIN)   # 3
	Assembly.world_tick(gs, gs.rng)
	assert_eq(gs.winning_alliance_id, -1, "70% misses the 75% Apostolic bar")

func test_ap_victory_blocked_when_alliance_too_big() -> void:
	# Player 1's alliance casts 9 of 10 votes (90% >= the 75% too-big share).
	var gs = make_gs(2)
	var c1 = make_settlement(gs, 1, 3, 3, 9)
	c1.belief_id = "christianity"
	c1.structures.append(APOSTOLIC)
	var c2 = make_settlement(gs, 2, 8, 8, 1)
	c2.belief_id = "christianity"
	gs.enabled_win_conditions = ["diplomatic"]
	Assembly._establish(gs, "religious")
	Assembly.apply_effect(gs, "diplomatic_victory", {"candidate_player_id": 1})
	assert_eq(gs.winning_alliance_id, -1, "A too-big candidate cannot win the diplomatic game")
	var blocked = false
	for e in gs.pending_assembly_events:
		if str(e.get("kind", "")) == "victory_blocked":
			blocked = true
	assert_true(blocked, "The barred win is surfaced as a victory_blocked event")

func test_un_candidate_must_hold_mass_media() -> void:
	var gs = _secular_gs()
	var members = [gs.get_player(1), gs.get_player(2), gs.get_player(3)]
	assert_eq(Assembly._diplo_candidate(gs, "secular", members), -1,
		"No Mass-Media holder, no UN candidate")
	gs.get_player(2).technologies.append("mass_media")
	assert_eq(Assembly._diplo_candidate(gs, "secular", members), 2,
		"The Mass-Media holder stands even when not the population leader")

func test_un_victory_passes_above_sixty_below_apostolic_bar() -> void:
	var gs = _secular_gs()
	Assembly._establish(gs, "secular")
	gs.get_player(1).technologies.append("mass_media")
	gs.assembly["pending"] = Assembly._make_proposal(gs, "diplomatic_victory", 1, -1)
	Assembly.cast_vote(gs, 1, "1")   # 5
	Assembly.cast_vote(gs, 3, "1")   # 2  -> 7/10 = 70%
	Assembly.cast_vote(gs, 2, Assembly.VOTE_ABSTAIN)   # 3
	Assembly.world_tick(gs, gs.rng)
	assert_eq(gs.winning_alliance_id, 1,
		"70% clears the UN's 60% bar (which the 75% Apostolic bar would reject)")

func test_un_victory_blocked_without_mass_media() -> void:
	var gs = _secular_gs()
	Assembly._establish(gs, "secular")
	Assembly.apply_effect(gs, "diplomatic_victory", {"candidate_player_id": 1})
	assert_eq(gs.winning_alliance_id, -1, "A UN candidate without Mass Media cannot win")

func test_vassal_backs_overlord_candidate() -> void:
	var gs = _religious_gs()
	Assembly._establish(gs, "religious")
	gs.assembly["pending"] = Assembly._make_proposal(gs, "diplomatic_victory", 1, -1)
	gs.get_alliance(2).is_subordinate_to = 1
	assert_eq(Assembly.ai_vote(gs, 2), "1",
		"A vassal casts its weight for its overlord's candidacy")
	gs.get_alliance(2).is_subordinate_to = -1
	assert_eq(Assembly.ai_vote(gs, 2), Assembly.VOTE_ABSTAIN,
		"An independent rival abstains rather than hand a rival the game")

# ── Apostolic Palace two-candidate runoff (§7.3) ────────────────────────────────

# Religious state for a two-candidate runoff: the wonder owner (player 1, weight 3)
# is not the strongest full member. Player 2 runs the faith as state religion, so it
# is a "full member" and — with weight doubled to 8 — the rival candidate. Player 3
# holds the faith (a voting member, weight 3) but does not run it as state religion,
# so it cannot stand. Total chamber weight 14.
func _runoff_gs(seed_val = 5):
	var gs = make_gs(3, seed_val)
	var c1 = make_settlement(gs, 1, 3, 3, 3)
	c1.belief_id = "christianity"
	c1.structures.append(APOSTOLIC)
	var c2 = make_settlement(gs, 2, 8, 8, 4)
	c2.belief_id = "christianity"
	gs.get_player(2).state_religion = "christianity"
	var c3 = make_settlement(gs, 3, 14, 14, 3)
	c3.belief_id = "christianity"
	gs.enabled_win_conditions = ["diplomatic"]
	return gs

func test_ap_runoff_fields_owner_and_front_runner() -> void:
	var gs = _runoff_gs()
	var pending = _open_ap_victory(gs)
	assert_eq(str(pending["resolution_id"]), "diplomatic_victory", "Victory motion opens")
	assert_eq(pending["candidates"].size(), 2, "Owner and front-runner both stand")
	assert_eq(int(pending["candidates"][0]), 1, "The wonder owner is the primary candidate")
	assert_eq(int(pending["candidates"][1]), 2, "The strongest member is the rival candidate")

func test_ap_runoff_collapses_when_no_other_full_member() -> void:
	var gs = _religious_gs()   # no player runs christianity as state religion
	var pending = _open_ap_victory(gs)
	assert_eq(pending["candidates"].size(), 1,
		"With no rival full member (adherent), only the owner stands")
	assert_eq(int(pending["candidates"][0]), 1, "The lone candidate is the wonder owner")

func test_ap_runoff_second_candidate_must_be_a_full_member() -> void:
	# Player 2 is the strongest member by far but does NOT run the faith as state
	# religion, so it is passed over for the weaker adherent, player 3.
	var gs = make_gs(3)
	var c1 = make_settlement(gs, 1, 3, 3, 3)
	c1.belief_id = "christianity"
	c1.structures.append(APOSTOLIC)
	var c2 = make_settlement(gs, 2, 8, 8, 10)   # huge, but not an adherent
	c2.belief_id = "christianity"
	var c3 = make_settlement(gs, 3, 14, 14, 3)
	c3.belief_id = "christianity"
	gs.get_player(3).state_religion = "christianity"
	gs.enabled_win_conditions = ["diplomatic"]
	var pending = _open_ap_victory(gs)
	assert_eq(pending["candidates"].size(), 2, "Owner plus the strongest full member stand")
	assert_eq(int(pending["candidates"][1]), 3,
		"The adherent, not the larger non-adherent, is the rival candidate")

func test_ap_runoff_excludes_a_defiant_adherent() -> void:
	# Two adherents; the stronger (player 2) is in defiance, so the next adherent
	# (player 3) takes the rival candidacy.
	var gs = make_gs(3)
	var c1 = make_settlement(gs, 1, 3, 3, 3)
	c1.belief_id = "christianity"
	c1.structures.append(APOSTOLIC)
	var c2 = make_settlement(gs, 2, 8, 8, 8)
	c2.belief_id = "christianity"
	gs.get_player(2).state_religion = "christianity"
	var c3 = make_settlement(gs, 3, 14, 14, 4)
	c3.belief_id = "christianity"
	gs.get_player(3).state_religion = "christianity"
	gs.enabled_win_conditions = ["diplomatic"]
	Assembly._establish(gs, "religious")
	gs.assembly["defiant"] = [2]
	gs.turn_number = gs.db.get_constant("ap_diplo_victory_interval", 50)
	Assembly.world_tick(gs, gs.rng)
	var slate = Assembly.pending_proposal(gs)["candidates"]
	assert_eq(slate.size(), 2, "Owner plus the strongest non-defiant adherent stand")
	assert_eq(int(slate[1]), 3, "The defiant stronger adherent is passed over")

func test_nay_vote_on_a_passed_mandate_marks_defiance() -> void:
	var gs = _religious_gs()   # weights 5 / 3 / 2
	Assembly._establish(gs, "religious")
	gs.assembly["resident_player_id"] = 1
	gs.get_player(1).policies["government"] = "despotism"
	gs.assembly["pending"] = Assembly._make_proposal(gs, "civic_mandate", 1, -1)
	Assembly.cast_vote(gs, 1, Assembly.VOTE_YEA)   # 5
	Assembly.cast_vote(gs, 2, Assembly.VOTE_NAY)   # 3 (defies)
	Assembly.cast_vote(gs, 3, Assembly.VOTE_YEA)   # 2 -> 7/10 = 70% passes
	Assembly.world_tick(gs, gs.rng)
	assert_true(Assembly._is_defiant(gs, 2),
		"A member that voted Nay on a passed mandate is recorded in defiance")
	assert_false(Assembly._is_defiant(gs, 3), "A Yea voter is not in defiance")

func test_ap_runoff_won_when_a_candidate_clears_the_bar() -> void:
	var gs = _runoff_gs()
	_open_ap_victory(gs)
	# Candidate 2 takes 11 of 14 weight (~78%) — past the 75% bar.
	Assembly.cast_vote(gs, 1, "1")   # weight 3 -> candidate 1
	Assembly.cast_vote(gs, 2, "2")   # weight 8 -> candidate 2
	Assembly.cast_vote(gs, 3, "2")   # weight 3 -> candidate 2
	Assembly.world_tick(gs, gs.rng)
	assert_eq(gs.winning_alliance_id, 2, "The candidate clearing 75% wins for its alliance")

func test_ap_runoff_split_below_bar_elects_no_one() -> void:
	var gs = _runoff_gs()
	_open_ap_victory(gs)
	# 8 for candidate 2 (~57%), 6 for candidate 1 — neither reaches 75%.
	Assembly.cast_vote(gs, 2, "2")   # weight 8 -> candidate 2
	Assembly.cast_vote(gs, 1, "1")   # weight 3 -> candidate 1
	Assembly.cast_vote(gs, 3, "1")   # weight 3 -> candidate 1
	Assembly.world_tick(gs, gs.rng)
	assert_eq(gs.winning_alliance_id, -1, "A 57/43 split runoff elects no World Leader")

func test_ai_runoff_backs_self_bloc_then_overlord() -> void:
	var gs = _runoff_gs()
	_open_ap_victory(gs)
	assert_eq(Assembly.ai_vote(gs, 2), "2", "A candidate backs itself")
	assert_eq(Assembly.ai_vote(gs, 3), Assembly.VOTE_ABSTAIN,
		"A rival of both candidates abstains")
	gs.get_alliance(3).is_subordinate_to = 1
	assert_eq(Assembly.ai_vote(gs, 3), "1",
		"A vassal backs its overlord's candidacy even in a runoff")

func test_runoff_rejects_a_vote_for_a_non_candidate() -> void:
	var gs = _runoff_gs()
	_open_ap_victory(gs)
	assert_false(Assembly.cast_vote(gs, 1, "3"), "A vote for a non-candidate is rejected")
	assert_false(Assembly.cast_vote(gs, 1, Assembly.VOTE_YEA), "Yea/Nay are not valid in a runoff")
	assert_true(Assembly.cast_vote(gs, 1, "2"), "A vote for a listed candidate is accepted")
	assert_true(Assembly.cast_vote(gs, 1, Assembly.VOTE_ABSTAIN), "Abstain is always valid")

func test_runoff_state_round_trips_through_save_load() -> void:
	var gs = _runoff_gs()
	_open_ap_victory(gs)
	Assembly.cast_vote(gs, 2, "2")
	var restored = load("res://src/sim/game_state.gd").deserialize(gs.serialize(), gs.db)
	var pending = restored.assembly["pending"]
	assert_eq(int(pending["candidates"][0]), 1, "The candidate slate survives save/load")
	assert_eq(int(pending["candidates"][1]), 2, "Both candidates survive save/load")
	assert_eq(str(pending["votes"]["2"]), "2", "A cast runoff vote survives save/load")

# ── Determinism / persistence ──────────────────────────────────────────────────

func test_assembly_state_round_trips_through_save_load() -> void:
	var gs = _religious_gs()
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)         # open a session
	Assembly.cast_vote(gs, 1, Assembly.VOTE_YEA)
	var restored = load("res://src/sim/game_state.gd").deserialize(gs.serialize(), gs.db)
	assert_eq(str(restored.assembly["kind"]), "religious", "Body survives save/load")
	assert_eq(str(restored.assembly["pending"]["resolution_id"]), "elect_resident",
		"An in-progress proposal survives save/load")
	assert_eq(str(restored.assembly["pending"]["votes"]["1"]), Assembly.VOTE_YEA,
		"Cast votes survive save/load")
